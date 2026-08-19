#!/bin/sh
# app-setup: 1
# id: postgresql
# name: PostgreSQL
# name.zh: PostgreSQL
# category: db
# order: 11
# summary: The database to pick when you get to choose. Stricter than MySQL, and better for it.
# summary.zh: 能自己选的时候就选它。比 MySQL 严格，也因此更可靠。
# includes: postgresql server and client, an initialised cluster
# includes.zh: PostgreSQL 服务端与客户端、已初始化的数据目录
# disk: 200M
# memory: 256M
# ports: 5432
# service: postgresql
# param: backup | default | Backup | 备份 | default,dump,files
# action: backup | backup | ▶ Back up now | ▶ 立即备份
. /usr/lib/app-setup/common.sh

PKGS="postgresql postgresql-client"
PKGS_rpm="postgresql-server postgresql"
PKGS_apk="postgresql postgresql-client"
SERVICE="postgresql"
CHECK_BIN="psql"

version_line() {
	_v="$(psql --version 2>/dev/null | sed 's/.*) //')"
	printf 'PostgreSQL %s' "$_v"
}

# The major version, as the paths spell it: 18, 16, 15.
pg_major() {
	local _v
	_v="$(postgres --version 2>/dev/null || psql --version 2>/dev/null)"
	_v="${_v##* }"
	printf '%s' "${_v%%.*}"
}

# Where the cluster the *service* will start actually lives.
#
# Order matters, and getting it wrong is silent. Alpine's package keeps its
# cluster under a version directory and its init script starts that one; the
# unversioned /var/lib/postgresql/data is a path this recipe used to initdb
# into itself, producing a second cluster nothing ever ran. Tuning written
# there took effect on nothing — the server came up on the other cluster with
# every default intact, and the only way to catch it was asking the running
# server rather than reading the file we had just written.
#
# So: versioned layouts first, bare ones last.
pg_data() {
	local _d
	for _d in /var/lib/postgresql/*/data /var/lib/postgresql/*/main \
	          /var/lib/pgsql/*/data /var/lib/pgsql/data /var/lib/postgresql/data; do
		[ -f "$_d/PG_VERSION" ] && { printf '%s' "$_d"; return 0; }
	done
	printf ''
}

# Move the cluster onto the data disk and leave a symlink at the old path.
#
# A symlink rather than a config change, and that is the whole reason this is
# three lines instead of three distro branches: the cluster lives at
# /var/lib/postgresql/<v>/main on Debian, /var/lib/pgsql/data on the RPM
# rebuilds and /var/lib/postgresql/<v>/data on Alpine, and each of those is
# pointed at by a different mechanism — `data_directory` in postgresql.conf,
# PGDATA in a systemd unit, data_dir in /etc/conf.d/postgresql. Symlinking the
# directory satisfies all three at once, and pg_data() keeps finding it because
# PG_VERSION is still there through the link.
#
# Postgres itself is content with a symlinked data directory; what it will not
# tolerate is the wrong owner or mode on it, and `mv` preserves both.
pg_set_datadir() {
	local _d
	_d="$(pg_data)"
	[ -n "$_d" ] || return 0
	if ! data_disk; then
		data_warn "$_d" "table"
		return 0
	fi
	[ -L "$_d" ] && { info "the cluster is already on the data disk: $_d -> $(readlink "$_d")"; return 0; }
	svc_running "$(svc)" && { step "stopping $(svc) to move its cluster"; svc_stop "$(svc)"; }
	data_relocate "$_d" "$DATA_DIR/postgresql" || return 0
	chown -h postgres:postgres "$_d" 2>/dev/null || true
}

do_movedata() {
	local _d _was
	data_disk || die "this container has no data disk, so there is nowhere durable to move to."
	_d="$(pg_data)"
	[ -n "$_d" ] || die "no cluster found to move"
	[ -L "$_d" ] && { ok "already on the data disk: $_d -> $(readlink "$_d")"; return 0; }
	_was=no
	if svc_running "$(svc)"; then _was=yes; fi
	pg_set_datadir
	if [ "$_was" = yes ]; then
		step "starting $(svc)"
		svc_start "$(svc)" || die "postgres will not start on the moved cluster — it is at $DATA_DIR/postgresql and $_d links to it"
	fi
	ok "the cluster is on the data disk now, and survives a reinstall."
}

MARK='# --- app-setup sizing ---'

# PostgreSQL's defaults are the most conservative of any database here, and
# still too big for a small container: shared_buffers is 128MB before anything
# connects, and every backend is a process rather than a thread — so
# max_connections is a memory setting, not just a limit.
#
# The two that matter are shared_buffers (charged once, up front) and work_mem
# (charged per sort, per connection, and more than once per query — a plan
# with three sorts in it can take three times work_mem for one backend).
#
# postgresql.conf takes the *last* value for a setting, so this appends a
# block rather than editing what the package shipped.
pg_tune() {
	local _d _conf _sb _wm _mw _conn _ecs
	_d="$(pg_data)"
	[ -n "$_d" ] || return 0
	_conf="$_d/postgresql.conf"
	# Debian keeps the config away from the data directory and symlinks it.
	[ -f "$_conf" ] || _conf="$(ls /etc/postgresql/*/main/postgresql.conf 2>/dev/null | head -1)"
	[ -n "$_conf" ] && [ -f "$_conf" ] || {
		warn "no postgresql.conf found; leaving its settings alone"
		return 0
	}
	backup_once "$_conf"

	if grep -qF "$MARK" "$_conf" 2>/dev/null; then
		if awk -v m="$MARK" 'index($0, m) { exit } { print }' "$_conf" > "$_conf.new"; then
			mv -f "$_conf.new" "$_conf"
			chown --reference="$_conf" "$_conf" 2>/dev/null || chown postgres:postgres "$_conf" 2>/dev/null || true
		else
			rm -f "$_conf.new"
			warn "could not rewrite $_conf; leaving its settings alone"
			return 0
		fi
	fi
	[ "$(mem_profile)" = normal ] && return 0

	_sb="$(mem_share 8 8 128)"      # shared_buffers: charged once, at startup
	_mw="$(mem_share 16 8 64)"      # maintenance_work_mem: VACUUM, CREATE INDEX
	_conn="$(mem_share 8 10 100)"   # every connection is a process
	_ecs="$(mem_share 2 32 512)"    # a hint to the planner, not an allocation
	if [ "$(mem_profile)" = tiny ]; then _wm=1; else _wm=2; fi

	step "sizing PostgreSQL for $(mem_total_mb)MB of memory"
	cat >> "$_conf" <<EOF
$MARK
$(tuning_header)
shared_buffers = ${_sb}MB
# per sort, per connection, and more than once per query — the real ceiling
# is this times the number of sorts in flight, which is why it stays small.
work_mem = ${_wm}MB
maintenance_work_mem = ${_mw}MB
max_connections = $_conn

# not an allocation: what the planner assumes the OS is caching for it.
effective_cache_size = ${_ecs}MB

# every parallel worker is another process with another backend's memory.
# On a machine this size the parallelism costs more than it returns.
max_parallel_workers_per_gather = 0
max_parallel_workers = 0
max_parallel_maintenance_workers = 0
autovacuum_max_workers = 1

wal_buffers = 512kB
EOF
	chown postgres:postgres "$_conf" 2>/dev/null || true
	info "PostgreSQL: shared_buffers ${_sb}MB, max_connections $_conn"
}

do_install() {
	pkg_install $(pmv PKGS)

	# Debian initialises a cluster in the package's postinst. Nothing else
	# does, and postgres refuses to start against an empty data directory.
	if [ -z "$(pg_data)" ]; then
		step "creating the database cluster"
		case "$PMF" in
		rpm)
			if have postgresql-setup; then
				postgresql-setup --initdb >/dev/null 2>&1 || postgresql-setup initdb >/dev/null 2>&1 || true
			fi
			;;
		apk)
			# Into the versioned directory, because that is the one Alpine's
			# init script starts. Initialising the bare /var/lib/postgresql/data
			# instead leaves a cluster the service never opens — and everything
			# afterwards, tuning included, is applied to the wrong one.
			_pgd="/var/lib/postgresql/$(pg_major)/data"
			mkdir -p "$_pgd" /run/postgresql
			chown -R postgres:postgres /var/lib/postgresql /run/postgresql
			su postgres -c "initdb -D '$_pgd' --encoding=UTF8 --locale=C" >/dev/null 2>&1 || true
			;;
		esac
	fi

	# Onto the data disk before anything is written into it, and before
	# pg_tune, which reads the config through whatever path pg_data now
	# returns. On Debian the postinst has already made the cluster by this
	# point, so this moves an empty one — which costs nothing, and is the
	# reason it happens at install rather than after six months of tables.
	pg_set_datadir

	# After the cluster exists — pg_data has to find a postgresql.conf before
	# there is anything to append to — and before the first start, so the
	# sizes are what it comes up with.
	pg_tune
	dump_tool_check pg_dumpall "app-setup dump postgresql writes a .sql you can read"

	svc_enable "$(svc)"
	if svc_running "$(svc)"; then
		svc_restart "$(svc)" || die "postgres would not come back up; see its log"
	else
		svc_start "$(svc)" || die "postgres would not start; see: journalctl -u postgresql"
	fi

	_n=0
	while [ "$_n" -lt 30 ]; do
		su postgres -c "psql -c 'SELECT 1'" >/dev/null 2>&1 && break
		_n=$((_n + 1)); sleep 1
	done

	# Ask the server, not the file. Writing a correct postgresql.conf into a
	# cluster the service does not start is silent, survives a restart, and
	# looks right in every way except the one that matters — which is exactly
	# what this recipe used to do on Alpine.
	if [ "$(mem_profile)" != normal ]; then
		_want="$(mem_share 8 8 128)"
		_got="$(su postgres -c "psql -tAc \"SELECT setting::bigint*8/1024 FROM pg_settings WHERE name='shared_buffers'\"" 2>/dev/null | tr -dc '0-9')"
		if [ -n "$_got" ] && [ "$_got" = "$_want" ]; then
			info "shared_buffers is ${_got}MB, as asked"
		else
			warn "sizing did not take: shared_buffers is ${_got:-unknown}MB, not ${_want}MB."
			warn "The server is reading a different postgresql.conf than the one written."
			warn "  su postgres -c 'psql -c \"SHOW config_file\"'   says which."
		fi
	fi

	if [ ! -f "$APP_SETUP_SECRETS/postgresql.txt" ]; then
		_pw="$(rand_pass 24)"
		if su postgres -c "psql -c \"ALTER USER postgres PASSWORD '$_pw';\"" >/dev/null 2>&1; then
			save_note postgresql <<EOF
PostgreSQL

  superuser       postgres
  password        $_pw
  listening on    127.0.0.1:5432 only

  As root on this machine you do not need the password:
    su postgres -c psql

  Make a database and a user for your application:
    su postgres -c "createuser --pwprompt myapp"
    su postgres -c "createdb --owner=myapp myapp"
EOF
		else
			warn "could not set the postgres password; local socket access still works"
		fi
	fi

	ok "PostgreSQL is running"
	show_note postgresql
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	# On Debian and Ubuntu `postgresql` and `postgresql-client` are version
	# meta-packages: purging them leaves postgresql-14 — the actual server and
	# the actual psql — installed and the card still reading "installed". Take
	# the versioned packages the meta-package pulled in as well.
	case "$PMF" in
		deb) pkg_remove $(pmv PKGS) $(dpkg-query -W -f='${Package} ${Status}\n' \
		         'postgresql-[0-9]*' 'postgresql-client-[0-9]*' 2>/dev/null |
		         awk '/ok installed/{print $1}') ;;
		*)   pkg_remove $(pmv PKGS) ;;
	esac
	drop_note postgresql
	warn "the data directory was NOT deleted — your databases are still there."
	warn "Remove it yourself if you mean it:  rm -rf /var/lib/postgresql /var/lib/pgsql $DATA_DIR/postgresql"
}

# -------------------------------------------------------------- dump/load --
# pg_dumpall, not pg_dump: roles and their passwords live outside any one
# database, and a dump without them restores the data perfectly and leaves
# every application unable to log in to it.
pg_dump_all() { su postgres -c "pg_dumpall"; }

do_dump() {
	local _f
	_f="$(dump_target postgresql sql "${1-}")"
	step "dumping every database, role and tablespace"
	pg_dump_all > "$_f" || die "pg_dumpall failed — is the cluster running?"
	[ -s "$_f" ] || die "the dump came out empty; that is not a backup"
	chmod 600 "$_f"
	ok "$_f  ($(du -h "$_f" 2>/dev/null | awk '{print $1}'))"
	info "put it back with:  app-setup load postgresql"
}

do_load() {
	local _f
	_f="$(dump_source postgresql sql "${1-}")"
	step "loading $_f"
	# psql has to read it as the postgres user, and /root is not somewhere
	# that user can get to on most of these images.
	cp "$_f" /tmp/app-setup-load.sql
	chown postgres /tmp/app-setup-load.sql 2>/dev/null || true
	su postgres -c "psql -q -f /tmp/app-setup-load.sql" ||
		warn "psql reported errors — read them before assuming this worked"
	rm -f /tmp/app-setup-load.sql
	ok "loaded"
}

# ------------------------------------------------------------------ backup --
do_backup() {
	local _d
	bk_begin postgresql
	bk_quiesce
	if [ "$(bk_method)" = files ]; then
		_d="$(pg_data)"
		[ -n "$_d" ] || die "cannot find the data directory"
		bk_add "$_d"
	else
		step "dumping every database, role and tablespace"
		pg_dump_all > "$(bk_path all.sql)" || die "pg_dumpall failed — is the cluster running?"
		[ -s "$(bk_path all.sql)" ] || die "the dump came out empty; refusing to call that a backup"
	fi
	bk_finish
}

do_restore() {
	local _d _pgd
	bk_open postgresql "${1-}"
	_d="$BK_UNPACKED"
	if [ -f "$_d/all.sql" ]; then
		svc_running "$(svc)" || { step "starting $(svc)"; svc_start "$(svc)"; }
		# pg_dumpall's output is CREATE-then-populate and expects to run as a
		# superuser against a live cluster. It does not drop what is already
		# there, so an existing database of the same name collides loudly
		# rather than being silently half-overwritten.
		step "loading all.sql"
		cp "$_d/all.sql" /tmp/app-setup-restore.sql
		chown postgres /tmp/app-setup-restore.sql 2>/dev/null || true
		su postgres -c "psql -q -f /tmp/app-setup-restore.sql" ||
			warn "psql reported errors — read them before assuming this worked"
		rm -f /tmp/app-setup-restore.sql
		ok "cluster restored"
	elif [ -d "$_d/files" ]; then
		_pgd="$(pg_data)"
		[ -n "$_pgd" ] || die "cannot find the data directory to restore into"
		step "stopping $(svc) to put the data directory back"
		svc_stop "$(svc)"
		rm -rf "$_pgd"
		bk_restore_files "$_d"
		chown -R postgres:postgres "$_pgd" 2>/dev/null || true
		chmod 700 "$_pgd" 2>/dev/null || true
		svc_start "$(svc)" || die "PostgreSQL will not start on the restored data directory"
		ok "data directory restored"
	else
		die "that archive has neither a dump nor a data directory in it"
	fi
	bk_close
}

do_help() { cat <<'EOF'
PostgreSQL

  Getting a prompt
    su postgres -c psql            as root on this machine, no password
    psql -U postgres -h 127.0.0.1  over TCP, which does want the password
                                   from /etc/app-setup/secrets/postgresql.txt

  Make a database for an application
    su postgres -c "createuser --pwprompt myapp"
    su postgres -c "createdb --owner=myapp myapp"

    Then the connection string your app wants:
      postgresql://myapp:thepassword@127.0.0.1:5432/myapp

  psql, the ten commands that matter
    \l           list databases        \c dbname    switch to one
    \dt          list tables           \d tablename describe one
    \du          list users            \dn          list schemas
    \x           wide output on/off — makes one-row results readable
    \timing      show how long queries take
    \q           quit

  Backup and restore
    su postgres -c "pg_dumpall" > /data/all.sql
    su postgres -c "psql" < /data/all.sql

    One database only:
      su postgres -c "pg_dump -Fc myapp" > /data/myapp.dump
      su postgres -c "pg_restore -d myapp" < /data/myapp.dump

    Put backups in /data — it is the path that survives a reinstall.

  Connecting from elsewhere
    Two files, both needed, and forgetting the second is the usual reason a
    remote connection is refused:
      postgresql.conf   listen_addresses = '*'
      pg_hba.conf       host all all 10.0.0.0/8 scram-sha-256
    Then restart. Find them with: su postgres -c "psql -c 'SHOW config_file'"

  Differences from MySQL that catch people out
    Identifiers are case-folded to lower case unless you quote them, so
    "SELECT myColumn" and "SELECT mycolumn" are the same and "myColumn" is
    not. Strings use single quotes only. There is no `LIMIT 1,10` — it is
    `LIMIT 10 OFFSET 1`.
EOF
}

app_main "$@"
