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
. /usr/lib/app-setup/common.sh

MONGO_VER=8.0
PKGS="mongodb-org"
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

	mkdir -p /var/lib/mongo /var/log/mongodb
	chown -R mongod:mongod /var/lib/mongo /var/log/mongodb 2>/dev/null ||
		chown -R mongodb:mongodb /var/lib/mongo /var/log/mongodb 2>/dev/null || true

	svc_enable "$(svc)"
	svc_start "$(svc)" || die "mongod started and then stopped. Check /var/log/mongodb/mongod.log and \`journalctl -u mongod\` — on a small container this is usually memory, and \`signal=ILL\` there means the CPU is too old for this MongoDB."

	ok "MongoDB is running on 127.0.0.1:27017 with no authentication."
	warn "Turn authentication on before anything else can reach it — the docs button says how."
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove mongodb-org mongodb-org-server mongodb-org-mongos mongodb-org-tools mongodb-mongosh
	rm -f /etc/apt/sources.list.d/mongodb-org.list /etc/yum.repos.d/mongodb-org.repo
	rm -f /usr/share/keyrings/mongodb-server-*.gpg
	warn "/var/lib/mongo was NOT deleted — your data is still there."
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
    /data survives a reinstall of this container. /var/lib/mongo does not.

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
