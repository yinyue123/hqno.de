#!/bin/sh
# app-setup: 1
# id: mysql
# name: MySQL (MariaDB)
# name.zh: MySQL（MariaDB）
# category: db
# order: 10
# summary: The database WordPress and most PHP software expect. A root password is set for you.
# summary.zh: WordPress 和大多数 PHP 程序要用的数据库。会自动生成 root 密码并保存。
# includes: mariadb-server, the mysql client, a generated root password
# includes.zh: mariadb 服务端、mysql 客户端、自动生成的 root 密码
# disk: 250M
# memory: 400M
# ports: 3306
# service: mariadb
. /usr/lib/app-setup/common.sh

PKGS="mariadb-server mariadb-client"
PKGS_rpm="mariadb-server mariadb"
PKGS_apk="mariadb mariadb-client"
SERVICE="mariadb"
CHECK_BIN="mysqld"
CHECK_FILE_apk="/usr/bin/mysqld"

version_line() {
	_v="$(mysql --version 2>/dev/null | sed 's/.*Distrib //;s/,.*//;s/ .*//')"
	[ -n "$_v" ] || _v="$(mysqld --version 2>/dev/null | sed 's/.*Ver //;s/ .*//')"
	printf 'MariaDB %s' "$_v"
}

mysql_root() {
	# Prefer the socket: root gets in without a password on a fresh install.
	# Once this recipe has written $MY_CNF, that file is named explicitly —
	# `mysql` would only find it by way of HOME, which is not root's home under
	# sudo, under cron, or in a systemd unit.
	if [ -r "$MY_CNF" ]; then
		mysql --defaults-file="$MY_CNF" "$@" 2>/dev/null && return 0
	fi
	mysql --protocol=socket -uroot "$@" 2>/dev/null || mysql -uroot "$@"
}

TUNE_CNF=90-app-setup.cnf

# MariaDB ships sized for a machine whose job is being a database server, and
# the three big caches default to 128M *each*:
#
#   innodb_buffer_pool_size      128M
#   key_buffer_size              128M
#   aria_pagecache_buffer_size   128M
#
# The third is the one nobody has heard of, and it is charged on every server:
# MariaDB keeps its own system tables in Aria and builds internal temp tables
# there, so a machine that never opens a MyISAM or Aria table of its own pays
# for it anyway. Left alone on a small container that is the whole machine
# three times over, and mysqld comes up over 100MB resident having served
# nothing.
#
# So the sizes are computed from the memory this machine actually has. At 1G
# the arithmetic lands back on MariaDB's own numbers, which is why anything
# that big is left alone entirely rather than tuned to the same place.
mysql_tune() {
	local _dir _f _pool _aria _tmp _conn _toc _redo
	_dir="$(mysql_conf_dir)" || {
		warn "no my.cnf.d directory to write to; leaving MariaDB's settings alone"
		return 0
	}
	_f="$_dir/$TUNE_CNF"

	if [ "$(mem_profile)" = normal ]; then
		if [ -f "$_f" ]; then
			tuning_drop "$_f"
			info "this machine is big enough now; removed $_f"
		fi
		return 0
	fi

	_pool="$(mem_share 8 8 192)"     # an eighth of RAM to InnoDB
	_aria="$(mem_share 32 2 32)"     # a thirty-second to each legacy cache
	_tmp="$_aria"
	_conn="$(mem_share 8 10 100)"
	_toc=$((_conn * 4))
	[ "$_toc" -gt 400 ] && _toc=400
	# The redo log is disk rather than memory, but the default pair comes to
	# 200M and a machine this small does not have 200M to give to a log it
	# will read once, after a crash, if ever.
	_redo="$(mem_share 4 16 96)"

	step "sizing MariaDB for $(mem_total_mb)MB of memory"
	tuning_write "$_f" <<EOF
$(tuning_header)
[mysqld]
# the three that matter — each of these is 128M on its own by default
innodb_buffer_pool_size       = ${_pool}M
aria_pagecache_buffer_size    = ${_aria}M
key_buffer_size               = ${_aria}M

innodb_buffer_pool_chunk_size = 1M
innodb_log_buffer_size        = 1M
innodb_log_file_size          = ${_redo}M

# per-connection buffers: one set per client, so what matters is not the
# number but the number times max_connections
sort_buffer_size              = 256K
read_buffer_size              = 64K
read_rnd_buffer_size          = 128K
join_buffer_size              = 128K
binlog_cache_size             = 32K

tmp_table_size                = ${_tmp}M
max_heap_table_size           = ${_tmp}M

max_connections               = ${_conn}
thread_cache_size             = 0
table_open_cache              = ${_toc}
table_definition_cache        = ${_toc}

# background threads, one of each: these default to a count scaled off the
# host's CPUs, and a container allowed a fifth of a core does not want four
# purge threads competing for it
innodb_read_io_threads        = 1
innodb_write_io_threads       = 1
innodb_purge_threads          = 1
innodb_page_cleaners          = 1

# already OFF in these builds. Written down because "turn off
# performance_schema" is the advice everyone repeats, and on this server it
# buys nothing — the caches above are where the memory actually went.
performance_schema            = OFF
EOF

	# Already up under the old sizes: the new ones are only read at start, and
	# leaving it running at 128M buffers is the thing we came here to fix.
	if svc_running "$(svc)"; then
		step "restarting MariaDB onto the new sizes"
		svc_restart "$(svc)" || warn "MariaDB did not come back up; check its log"
	fi
}

do_install() {
	pkg_install $(pmv PKGS)

	# Before the data directory is created, so the redo logs are made at the
	# size we asked for rather than written at 100M and resized on next start.
	mysql_tune

	# Debian and the RPM images initialise the data directory in the service's
	# own start-up. Alpine does not, and mysqld exits immediately without it.
	if [ ! -d /var/lib/mysql/mysql ]; then
		step "initialising the data directory"
		if have mariadb-install-db; then
			mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1 || true
		elif have mysql_install_db; then
			mysql_install_db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1 || true
		fi
		chown -R mysql:mysql /var/lib/mysql 2>/dev/null || true
	fi

	svc_enable "$(svc)"
	svc_start "$(svc)" || die "mariadb would not start. Its log says why; on a small container it is usually memory, and $(mysql_conf_dir)/$TUNE_CNF is where the sizes we chose are."

	# Give it a moment: the service is up before the socket is.
	_n=0
	while [ "$_n" -lt 30 ]; do
		mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
		_n=$((_n + 1)); sleep 1
	done

	if [ -f /root/.my.cnf ]; then
		info "root already has a password in /root/.my.cnf; leaving it alone"
	else
		_pw="$(rand_pass 24)"
		step "setting the root password"
		if mysql_root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$_pw'; FLUSH PRIVILEGES;" 2>/dev/null ||
		   mysql_root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$_pw'); FLUSH PRIVILEGES;" 2>/dev/null; then
			cat > /root/.my.cnf <<EOF
[client]
user=root
password=$_pw
EOF
			chmod 600 /root/.my.cnf
			save_note mysql <<EOF
MariaDB (MySQL)

  root password   $_pw
  saved in        /root/.my.cnf, so \`mysql\` as root needs no password
  listening on    127.0.0.1:3306 only

  Make a database and a user for your application:
    mysql -e "CREATE DATABASE myapp CHARACTER SET utf8mb4;"
    mysql -e "CREATE USER 'myapp'@'localhost' IDENTIFIED BY 'pick-a-password';"
    mysql -e "GRANT ALL ON myapp.* TO 'myapp'@'localhost'; FLUSH PRIVILEGES;"
EOF
		else
			warn "could not set a root password; root still logs in over the socket"
		fi
	fi

	# The default test database and the anonymous users are what
	# mysql_secure_installation removes, and there is no reason to keep them.
	mysql_root -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
	mysql_root -e "DELETE FROM mysql.user WHERE User=''; FLUSH PRIVILEGES;" 2>/dev/null || true

	ok "MariaDB is running"
	if [ "$(mem_profile)" != normal ]; then
		info "sized for $(mem_total_mb)MB — see $(mysql_conf_dir)/$TUNE_CNF"
	fi
	show_note mysql
}

do_uninstall() {
	local _d
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove $(pmv PKGS)
	rm -f /root/.my.cnf
	_d="$(mysql_conf_dir)" && tuning_drop "$_d/$TUNE_CNF"
	drop_note mysql
	warn "/var/lib/mysql was NOT deleted — your databases are still there."
	warn "Remove it yourself if you mean it:  rm -rf /var/lib/mysql"
}

do_help() { cat <<'EOF'
MySQL (MariaDB)

  Which is this?
    MariaDB. It is the fork of MySQL that every distribution ships, it
    speaks the same protocol, the command is still `mysql`, and software
    written for MySQL does not know the difference.

  Your root password
    cat /root/.app-setup/mysql.txt
    It is also in /root/.my.cnf, which is why `mysql` as root just works
    with no password on this machine.

  Make a database for an application
    mysql -e "CREATE DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER 'myapp'@'localhost' IDENTIFIED BY 'a-good-password';"
    mysql -e "GRANT ALL PRIVILEGES ON myapp.* TO 'myapp'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    Use utf8mb4, not utf8. MySQL's "utf8" cannot store emoji and will
    truncate a row at the first one.

  Backup and restore
    mysqldump --single-transaction --all-databases > /data/all.sql
    mysql < /data/all.sql

    /data survives a reinstall of this container; /var/lib/mysql does not.
    A backup anywhere else is not a backup.

  Connecting from outside this container
    By default it listens on 127.0.0.1 only, which is the right answer. If
    you genuinely need remote access, change bind-address in the config,
    create a user with a host of '%' rather than 'localhost', and make sure
    something in front is restricting who can reach 3306. An open MySQL
    with a weak password is found by scanners within hours.

  Memory
    400MB is what MariaDB wants to be comfortable, not what it needs to run.
    Under 1G of RAM app-setup writes sizes that fit this machine into
    90-app-setup.cnf beside the other config, and leaves a comment in it
    saying what each one is for:

      cat /etc/my.cnf.d/90-app-setup.cnf       Alpine, AlmaLinux, Rocky
      cat /etc/mysql/conf.d/90-app-setup.cnf   Debian, Ubuntu

    Measured on a 128MB container: mysqld resident 103MB with the defaults,
    65MB with that file. The saving is almost entirely three settings, each
    of which defaults to 128M on its own:

      innodb_buffer_pool_size      the one everybody tunes
      key_buffer_size              MyISAM, which you probably do not use
      aria_pagecache_buffer_size   MariaDB's own system tables and every
                                   internal temp table — so this one is
                                   charged even on a server that never
                                   opens an Aria table itself

    performance_schema is already OFF in these builds. Turning it off is the
    advice everyone repeats and it buys nothing here.

    Delete that file and restart to get the defaults back. Give the machine
    more memory and install again and it is rewritten to match, or removed
    once there is 1G to work with.

    If mysqld still disappears it was the out-of-memory killer, and
    `dmesg | tail` says so in as many words.

  Where things are
    /var/lib/mysql                    the data
    /etc/mysql/  or  /etc/my.cnf.d/   the config
    journalctl -u mariadb             why it will not start
EOF
}

app_main "$@"
