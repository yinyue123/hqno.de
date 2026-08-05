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

pg_data() {
	for _d in /var/lib/postgresql/data /var/lib/pgsql/data /var/lib/postgresql/*/main; do
		[ -f "$_d/PG_VERSION" ] && { printf '%s' "$_d"; return 0; }
	done
	printf ''
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
			mkdir -p /var/lib/postgresql/data /run/postgresql
			chown -R postgres:postgres /var/lib/postgresql /run/postgresql
			su postgres -c "initdb -D /var/lib/postgresql/data --encoding=UTF8 --locale=C" >/dev/null 2>&1 || true
			;;
		esac
	fi

	svc_enable "$(svc)"
	svc_start "$(svc)" || die "postgres would not start; see: journalctl -u postgresql"

	_n=0
	while [ "$_n" -lt 30 ]; do
		su postgres -c "psql -c 'SELECT 1'" >/dev/null 2>&1 && break
		_n=$((_n + 1)); sleep 1
	done

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
	pkg_remove $(pmv PKGS)
	drop_note postgresql
	warn "the data directory was NOT deleted — your databases are still there."
	warn "Remove it yourself if you mean it:  rm -rf /var/lib/postgresql /var/lib/pgsql"
}

do_help() { cat <<'EOF'
PostgreSQL

  Getting a prompt
    su postgres -c psql            as root on this machine, no password
    psql -U postgres -h 127.0.0.1  over TCP, which does want the password
                                   from /root/.app-setup/postgresql.txt

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
