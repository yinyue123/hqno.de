#!/bin/sh
# app-setup: 1
# id: mongodb
# name: MongoDB
# name.zh: MongoDB
# category: db
# order: 13
# summary: Document database. Comes from MongoDB's own repository — it is not in any distro.
# summary.zh: 文档数据库。要用官方源装，各发行版自己的仓库里都没有。
# includes: mongod, mongosh, the official repository
# includes.zh: mongod 服务、mongosh 客户端、官方软件源
# disk: 500M
# memory: 1G
# ports: 27017
# service: mongod
# param: backup | default | Backup | 备份 | default,dump,files
# action: backup | backup | ▶ Back up now | ▶ 立即备份
. /usr/lib/app-setup/common.sh

MONGO_VER=8.0
# mongodb-org is a metapackage and pulls mongodb-org-tools, which is where
# mongodump and mongorestore live — named here anyway, because the whole
# backup story depends on them and a metapackage quietly changing what it
# depends on is not something to find out about on the night it matters.
PKGS="mongodb-org mongodb-database-tools"
SERVICE="mongod"
CHECK_BIN="mongod"

version_line() {
	_v="$(mongod --version 2>/dev/null | sed -n 's/.*db version v//p' | head -1)"
	printf 'MongoDB %s' "$_v"
}

# MongoDB builds against glibc and publishes no musl binaries, so there is
# nothing to install on Alpine. Saying so is better than a failed compile.
refuse_musl() {
	[ "$PMF" = apk ] || return 0
	err "MongoDB does not publish builds for Alpine — it needs glibc and Alpine is musl."
	err "Options: reinstall this container on Debian or AlmaLinux, or use PostgreSQL,"
	err "which has JSONB and covers most of what people want MongoDB for."
	exit 1
}

# MongoDB 5.0 and later are compiled with AVX and there is no build without it.
# On a CPU that has no AVX — an older Xeon, a budget VPS, some of the cheaper
# cloud instances — mongod installs perfectly, starts, and is killed by the
# kernel with SIGILL a second later. Measured on this very host: `Main PID
# (code=killed, signal=ILL)`.
#
# Checking costs nothing and saves a 190MB download onto a machine that can
# never run it. Without the check the failure is unreadable: the service is
# simply "stopped" and nothing says why.
refuse_no_avx() {
	grep -qm1 -E '^flags.* avx( |$)' /proc/cpuinfo 2>/dev/null && return 0
	err "This machine's CPU has no AVX, and MongoDB $MONGO_VER needs it — every"
	err "build from 5.0 onwards is compiled with it. mongod would install, start,"
	err "and be killed with SIGILL (illegal instruction) a moment later."
	err "Options: MongoDB 4.4 is the last version without AVX but is long out of"
	err "support, so the better answer is PostgreSQL — it has JSONB and covers"
	err "most of what people want MongoDB for. Or move to a host with a newer CPU."
	exit 1
}

deb_codename() {
	# MongoDB publishes per-codename. A release they have not built for yet —
	# a brand new Debian, say — falls back to the previous one, which works
	# because the packages only depend on glibc and libssl.
	case "$OS_ID:$OS_CODENAME" in
		ubuntu:noble|ubuntu:jammy|ubuntu:focal) printf '%s' "$OS_CODENAME" ;;
		ubuntu:*)   printf 'jammy' ;;
		debian:bookworm|debian:bullseye) printf '%s' "$OS_CODENAME" ;;
		debian:*)   printf 'bookworm' ;;
		*)          printf 'bookworm' ;;
	esac
}

MARK='# --- app-setup sizing ---'

# WiredTiger's cache defaults to half of RAM minus 1GB, or 256MB, whichever is
# larger — so on any machine under about 2.5G the default *is* 256MB, and that
# is already a floor MongoDB will not go below: cacheSizeGB has a documented
# minimum of 0.25. There is no configuration that makes MongoDB small.
#
# What this can do is stop it reading the *host's* RAM and sizing the cache
# for a machine it is not running on — inside a container without lxcfs,
# "half of RAM" is half of the host's, which is how mongod ends up asking for
# 8GB on a box that has 512MB. Pinning the number is the whole fix.
# Where the collections live. /var/lib/mongo is on the root filesystem, which
# a reinstall replaces while keeping /data — so with a data disk, that is where
# they go.
MONGO_DIR_DEFAULT=/var/lib/mongo
mongo_data_dir() { data_path mongodb "$MONGO_DIR_DEFAULT"; }

# dbPath is a plain `  dbPath: <x>` line under `storage:` in mongod.conf, which
# is YAML — so it is edited in place rather than appended to. Appending would
# put a second top-level key in the file and mongod refuses to start on a
# duplicate, with a message about the YAML and not about us.
mongo_set_dbpath() {   # mongo_set_dbpath <conf>
	local _d
	_d="$(mongo_data_dir)"
	if [ "$_d" = "$MONGO_DIR_DEFAULT" ]; then
		data_warn "$MONGO_DIR_DEFAULT" "collection"
		return 0
	fi
	[ -f "$1" ] || { warn "no $1 to point at $_d"; return 0; }
	if [ -d "$MONGO_DIR_DEFAULT" ] && [ ! -L "$MONGO_DIR_DEFAULT" ] &&
	   [ -n "$(ls -A "$MONGO_DIR_DEFAULT" 2>/dev/null)" ] && [ ! -d "$_d/journal" ]; then
		svc_running "$(svc)" && { step "stopping $(svc) to move its data"; svc_stop "$(svc)"; }
		data_relocate "$MONGO_DIR_DEFAULT" "$_d" || return 0
	fi
	mkdir -p "$_d"
	chown -R mongod:mongod "$_d" 2>/dev/null || chown -R mongodb:mongodb "$_d" 2>/dev/null || true
	step "keeping the collections on the data disk"
	if grep -qE '^[[:space:]]*dbPath:' "$1"; then
		sed -i "s#^\\([[:space:]]*\\)dbPath:.*#\\1dbPath: $_d#" "$1"
		ok "dbPath: $_d"
	else
		warn "no dbPath: line in $1 — left alone rather than guessed at"
	fi
}

do_movedata() {
	local _d _was
	_d="$(mongo_data_dir)"
	[ "$_d" = "$MONGO_DIR_DEFAULT" ] &&
		die "this container has no data disk, so there is nowhere durable to move to."
	_was=no
	if svc_running "$(svc)"; then _was=yes; step "stopping $(svc)"; svc_stop "$(svc)"; fi
	mongo_set_dbpath /etc/mongod.conf
	if [ "$_was" = yes ]; then step "starting $(svc)"; svc_start "$(svc)" || die "mongod will not start on $_d"; fi
	ok "the collections are on the data disk now, and survive a reinstall."
}

mongo_tune() {
	local _conf _gb
	_conf=/etc/mongod.conf
	[ -f "$_conf" ] || return 0
	backup_once "$_conf"

	if grep -qF "$MARK" "$_conf" 2>/dev/null; then
		if awk -v m="$MARK" 'index($0, m) { exit } { print }' "$_conf" > "$_conf.new"; then
			mv -f "$_conf.new" "$_conf"
		else
			rm -f "$_conf.new"
			warn "could not rewrite $_conf; leaving MongoDB's own settings alone"
			return 0
		fi
	fi
	[ "$(mem_profile)" = normal ] && return 0

	# A quarter of the machine, but never under the 0.25GB MongoDB enforces.
	# Below about 1G that floor is larger than the share, and MongoDB is
	# simply the wrong database for the box — which the recipe's declared
	# `memory: 1G` already says, and the panel warns about before we get here.
	_gb="$(awk -v m="$(mem_total_mb)" 'BEGIN{ v = m/4/1024; if (v < 0.25) v = 0.25; printf "%.2f", v }')"

	step "pinning WiredTiger's cache to ${_gb}G for a $(mem_total_mb)MB machine"
	cat >> "$_conf" <<EOF
$MARK
$(tuning_header)
# Written as an explicit number because the default is computed from what
# MongoDB believes the machine's RAM to be, and in a container without lxcfs
# that is the host's RAM rather than this container's limit.
storage:
  wiredTiger:
    engineConfig:
      cacheSizeGB: $_gb
EOF
	info "MongoDB: wiredTiger cache ${_gb}G"
	if [ "$(mem_total_mb)" -lt 1024 ]; then
		warn "MongoDB will not go below a 0.25G cache no matter what is set here."
		warn "On a ${_gb}G cache and $(mem_total_mb)MB of RAM it will start and then be killed"
		warn "under any real load. There is no configuration that fixes that."
	fi
}

do_install() {
	refuse_musl
	refuse_no_avx
	ensure_downloader

	case "$PMF" in
	deb)
		_repo_os=debian
		case "$OS_ID" in ubuntu) _repo_os=ubuntu ;; esac
		_cn="$(deb_codename)"
		step "adding MongoDB's $MONGO_VER repository ($_repo_os $_cn)"
		pkg_install gnupg ca-certificates
		mkdir -p /usr/share/keyrings
		fetch_stdout "https://www.mongodb.org/static/pgp/server-${MONGO_VER}.asc" |
			gpg --dearmor -o "/usr/share/keyrings/mongodb-server-${MONGO_VER}.gpg" ||
			die "could not fetch MongoDB's signing key — is this machine online?"
		_comp=main
		[ "$_repo_os" = ubuntu ] && _comp=multiverse
		echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-${MONGO_VER}.gpg ] https://repo.mongodb.org/apt/${_repo_os} ${_cn}/mongodb-org/${MONGO_VER} ${_comp}" \
			> /etc/apt/sources.list.d/mongodb-org.list
		rm -f "$APP_SETUP_STATE/pm-refreshed"
		pkg_install mongodb-org
		;;
	rpm)
		step "adding MongoDB's $MONGO_VER repository"
		cat > /etc/yum.repos.d/mongodb-org.repo <<EOF
[mongodb-org-${MONGO_VER}]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/${MONGO_VER}/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-${MONGO_VER}.asc
EOF
		rm -f "$APP_SETUP_STATE/pm-refreshed"
		pkg_install mongodb-org
		;;
	*)
		die "no MongoDB packages for this system"
		;;
	esac

	mkdir -p "$(mongo_data_dir)" /var/log/mongodb
	chown -R mongod:mongod "$(mongo_data_dir)" /var/log/mongodb 2>/dev/null ||
		chown -R mongodb:mongodb "$(mongo_data_dir)" /var/log/mongodb 2>/dev/null || true

	mongo_set_dbpath /etc/mongod.conf
	mongo_tune

	svc_enable "$(svc)"
	svc_start "$(svc)" || die "mongod started and then stopped. Check /var/log/mongodb/mongod.log and \`journalctl -u mongod\` — on a small container this is usually memory, and \`signal=ILL\` there means the CPU is too old for this MongoDB."

	ok "MongoDB is running on 127.0.0.1:27017 with no authentication."
	warn "Turn authentication on before anything else can reach it — the docs button says how."
	dump_tool_check mongodump "app-setup dump mongodb writes one archive file"
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove mongodb-org mongodb-org-server mongodb-org-mongos mongodb-org-tools mongodb-mongosh
	rm -f /etc/apt/sources.list.d/mongodb-org.list /etc/yum.repos.d/mongodb-org.repo
	rm -f /usr/share/keyrings/mongodb-server-*.gpg
	warn "$(mongo_data_dir) was NOT deleted — your data is still there."
}

# -------------------------------------------------------- dump/load/backup --
# `--archive` rather than `--out`: one file instead of a directory of BSON, so
# a dump is something you can scp, and the backup and the dump are the same
# call with a different destination.
mongo_dump_to() {   # mongo_dump_to <file>
	have mongodump || die "mongodump is not installed — it ships in mongodb-database-tools"
	mongodump --quiet --archive="$1" ||
		die "mongodump failed — if authentication is on it needs credentials this recipe does not store"
	[ -s "$1" ] || die "mongodump wrote nothing; that is not a backup"
}

mongo_load_from() { # mongo_load_from <file>
	have mongorestore || die "mongorestore is not installed — it ships in mongodb-database-tools"
	svc_running "$(svc)" || { step "starting $(svc)"; svc_start "$(svc)"; }
	mongorestore --quiet --drop --archive="$1" || die "mongorestore failed"
}

do_dump() {
	local _f
	_f="$(dump_target mongodb archive "${1-}")"
	step "dumping every database"
	mongo_dump_to "$_f"
	chmod 600 "$_f"
	ok "$_f  ($(du -h "$_f" 2>/dev/null | awk '{print $1}'))"
	info "put it back with:  app-setup load mongodb"
}

do_load() {
	local _f
	_f="$(dump_source mongodb archive "${1-}")"
	step "loading $_f"
	warn "collections of the same name are dropped first"
	mongo_load_from "$_f"
	ok "loaded"
}

# ------------------------------------------------------------------ backup --
do_backup() {
	bk_begin mongodb
	bk_quiesce
	if [ "$(bk_method)" = files ]; then
		bk_add "$(mongo_data_dir)"
	else
		step "dumping every database"
		mongo_dump_to "$(bk_path dump.archive)"
	fi
	bk_add /etc/mongod.conf
	bk_finish
}

do_restore() {
	local _d
	bk_open mongodb "${1-}"
	_d="$BK_UNPACKED"
	if [ -f "$_d/dump.archive" ]; then
		step "restoring — existing collections of the same name are dropped"
		mongo_load_from "$_d/dump.archive"
		ok "databases restored"
	elif [ -d "$_d/files$(mongo_data_dir)" ] || [ -d "$_d/files$MONGO_DIR_DEFAULT" ]; then
		step "stopping $(svc) to put the data directory back"
		svc_stop "$(svc)"
		rm -rf "$(mongo_data_dir)" "$MONGO_DIR_DEFAULT"
		bk_restore_files "$_d"
		chown -R mongod:mongod "$(mongo_data_dir)" 2>/dev/null ||
			chown -R mongodb:mongodb "$(mongo_data_dir)" 2>/dev/null || true
		svc_start "$(svc)" || die "mongod will not start on the restored data directory"
		ok "data directory restored"
	else
		die "that archive has neither a dump nor a data directory in it"
	fi
	bk_close
}

do_help() { cat <<'EOF'
MongoDB

  Connect
    mongosh

  Turn on authentication — do this now, not later
    The package ships with no users and no authentication, which is fine
    only because it listens on 127.0.0.1. Before you change bindIp, do this:

      mongosh
      > use admin
      > db.createUser({user:"admin", pwd:"a-good-password",
                       roles:[{role:"root", db:"admin"}]})
      > exit

      In /etc/mongod.conf add:
        security:
          authorization: enabled

      systemctl restart mongod

    After that: mongosh -u admin -p --authenticationDatabase admin

  The basics
    show dbs                      list databases
    use myapp                     switch (it is created on first write)
    db.things.insertOne({a: 1})
    db.things.find({a: 1})
    db.things.createIndex({a: 1})
    show collections

  Backup
    mongodump --out /data/mongo-backup
    mongorestore /data/mongo-backup
    /data survives a reinstall of this container. The root filesystem does
    not, which is why this recipe keeps the collections on /data/mongodb
    when the container has a data disk.

  Memory
    MongoDB reserves half of available RAM for its cache and does not cope
    well with small containers. Under about 1GB it will start and then be
    killed under load. To cap it, in /etc/mongod.conf:
      storage:
        wiredTiger:
          engineConfig:
            cacheSizeGB: 0.25

  Alpine
    There is nothing to install. MongoDB publishes glibc builds only and
    Alpine is musl. Use PostgreSQL with JSONB columns instead — it does
    most of what people want MongoDB for and is in every repository.

  Licence
    MongoDB moved to the SSPL in 2018, which is why no distribution ships
    it any more and why this installs from repo.mongodb.org. For ordinary
    use that changes nothing; if you are reselling a managed service built
    on it, read the licence.
EOF
}

app_main "$@"
