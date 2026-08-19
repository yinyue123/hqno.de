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
# param: backup | default | Backup | 备份 | default,dump,files
# action: backup | backup | ▶ Back up now | ▶ 立即备份
. /usr/lib/app-setup/common.sh

PKGS="mariadb-server mariadb-client"
PKGS_rpm="mariadb-server mariadb"
PKGS_apk="mariadb mariadb-client"
SERVICE="mariadb"
CHECK_BIN="mysqld"
CHECK_FILE_apk="/usr/bin/mysqld"

# Where the tables actually go. /var/lib/mysql is on the container's root
# filesystem, and a reinstall replaces that whole filesystem while keeping
# /data — so on a container with a data disk the tables belong there, and a
# holder who reinstalls to change distro keeps their database instead of
# discovering it was never anywhere durable.
#
# Its own drop-in, not $TUNE_CNF: mysql_tune *deletes* that file on a machine
# with enough memory, which would take the datadir with it.
DATADIR_DEFAULT=/var/lib/mysql
DATADIR_CNF=10-app-setup-datadir.cnf
mysql_datadir() { data_path mysql "$DATADIR_DEFAULT"; }

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

# Point MariaDB at $1 and make sure what is there now ends up there. Safe to
# call twice: with the datadir already correct it writes the same drop-in and
# moves nothing.
mysql_set_datadir() {   # mysql_set_datadir <dir>
	local _dir _f _dd
	_dd="$1"
	if [ "$_dd" = "$DATADIR_DEFAULT" ]; then
		data_warn "$DATADIR_DEFAULT" "table"
		return 0
	fi

	# An existing install with data in it is not moved from under somebody as
	# a side effect of `install`. Say it, and leave the verb to do it.
	if [ -d "$DATADIR_DEFAULT/mysql" ] && [ ! -L "$DATADIR_DEFAULT" ] && [ -d "$_dd/mysql" ]; then
		warn "there are databases in both $DATADIR_DEFAULT and $_dd."
		warn "Leaving both alone. $_dd is the one this recipe will use."
		return 0
	fi

	_dir="$(mysql_conf_dir)" || {
		warn "no my.cnf.d directory to write to, so the data directory stays at $DATADIR_DEFAULT"
		return 0
	}
	_f="$_dir/$DATADIR_CNF"

	# Move first, then point at it: a server told to use a directory that is
	# not there yet will not start, and on Debian it is running right now.
	if [ -d "$DATADIR_DEFAULT" ] && [ ! -L "$DATADIR_DEFAULT" ] && [ ! -d "$_dd/mysql" ]; then
		svc_running "$(svc)" && { step "stopping $(svc) to move its data directory"; svc_stop "$(svc)"; }
		data_relocate "$DATADIR_DEFAULT" "$_dd" || return 0
	fi
	mkdir -p "$_dd"
	chown mysql:mysql "$_dd" 2>/dev/null || true

	step "keeping the databases on the data disk"
	cat > "$_f" <<EOF
# Written by app-setup. /data survives a reinstall of this container and the
# root filesystem does not, so the tables live there.
[mysqld]
datadir = $_dd
EOF
	chmod 0644 "$_f"
	ok "datadir = $_dd  ($_f)"
}

# The deliberate version of the above, for an install that already has data in
# the wrong place. Stop, move, relink, start.
do_movedata() {
	local _dd _was
	_dd="$(mysql_datadir)"
	if [ "$_dd" = "$DATADIR_DEFAULT" ]; then
		die "this container has no data disk, so there is nowhere durable to move to. Ask for a data disk first."
	fi
	[ -L "$DATADIR_DEFAULT" ] && { ok "already on the data disk: $DATADIR_DEFAULT -> $(readlink "$DATADIR_DEFAULT")"; return 0; }
	[ -d "$DATADIR_DEFAULT" ] || { ok "nothing at $DATADIR_DEFAULT to move"; return 0; }

	_was=no
	if svc_running "$(svc)"; then
		_was=yes
		step "stopping $(svc)"
		svc_stop "$(svc)" || die "could not stop $(svc); nothing has been moved"
	fi
	data_relocate "$DATADIR_DEFAULT" "$_dd" || die "nothing was moved"
	chown -R mysql:mysql "$_dd" 2>/dev/null || true
	mysql_set_datadir "$_dd"
	if [ "$_was" = yes ]; then
		step "starting $(svc)"
		svc_start "$(svc)" || die "MariaDB will not start on the moved data directory — it is at $_dd and $DATADIR_DEFAULT links to it"
	fi
	ok "the databases are on the data disk now, and survive a reinstall."
}

do_install() {
	local _dd
	pkg_install $(pmv PKGS)

	# Before the data directory is created, so the redo logs are made at the
	# size we asked for rather than written at 100M and resized on next start.
	mysql_tune

	# Where the tables go, decided before anything is written into them. On
	# Debian the package's postinst has already started the server and made
	# /var/lib/mysql by now, so this may have to move an empty directory —
	# which costs nothing, and is why it happens here rather than after
	# somebody has six months of data in it.
	_dd="$(mysql_datadir)"
	mysql_set_datadir "$_dd"

	# Debian and the RPM images initialise the data directory in the service's
	# own start-up. Alpine does not, and mysqld exits immediately without it.
	if [ ! -d "$_dd/mysql" ]; then
		step "initialising the data directory"
		if have mariadb-install-db; then
			mariadb-install-db --user=mysql --datadir="$_dd" >/dev/null 2>&1 || true
		elif have mysql_install_db; then
			mysql_install_db --user=mysql --datadir="$_dd" >/dev/null 2>&1 || true
		fi
		chown -R mysql:mysql "$_dd" 2>/dev/null || true
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
  data in         $(mysql_datadir)$(data_disk || printf ' — on the root filesystem, which a reinstall replaces')

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
	# mysqldump ships in the client package, which is in PKGS — but a distro
	# that splits it differently would leave `backup` broken and nobody would
	# find out until the night it mattered.
	if have mysqldump; then
		ok "mysqldump is here — app-setup dump mysql writes a .sql you can read"
	else
		pkg_install_optional mariadb-backup mariadb-client mysql-client
		have mysqldump || warn "mysqldump is missing; app-setup dump/backup will not work here"
	fi

	mysql_root -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
	mysql_root -e "DELETE FROM mysql.user WHERE User=''; FLUSH PRIVILEGES;" 2>/dev/null || true

	ok "MariaDB is running"
	if [ "$(mem_profile)" != normal ]; then
		info "sized for $(mem_total_mb)MB — see $(mysql_conf_dir)/$TUNE_CNF"
	fi
	show_note mysql
}

do_uninstall() {
	local _d _dd
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove $(pmv PKGS)
	rm -f /root/.my.cnf
	_d="$(mysql_conf_dir)" && tuning_drop "$_d/$TUNE_CNF"
	drop_note mysql
	_dd="$(mysql_datadir)"
	warn "$_dd was NOT deleted — your databases are still there."
	warn "Remove it yourself if you mean it:  rm -rf $_dd"
}

# ------------------------------------------------------------------ backup --
# `dump` is the default and the right answer for InnoDB: --single-transaction
# takes a consistent snapshot without locking anybody out, so a nightly backup
# costs the site nothing. `files` exists for the other job — moving the data
# directory itself to another machine — and for that the server has to be
# stopped, which bk_quiesce does when the setting says so.
do_backup() {
	bk_begin mysql
	bk_quiesce
	if [ "$(bk_method)" = files ]; then
		bk_add "$(mysql_datadir)"
	else
		step "dumping every database"
		# An empty or truncated dump that gets tarred up anyway is the failure
		# mode this whole feature exists to prevent; mysql_dump_all checks.
		mysql_dump_all "$(bk_path all.sql)"
	fi
	# The config travels with the data either way. Restoring a dump onto a
	# server sized for a different machine is how you find out the sizing
	# drop-in mattered.
	bk_add /etc/mysql
	bk_add /etc/my.cnf.d
	bk_add /root/.my.cnf
	bk_finish
}

# -------------------------------------------------------------- dump/load --
# The same call the scheduled backup makes, writing one plain .sql where
# somebody can actually look at it. `app-setup dump mysql` and a mysqldump line
# typed from memory produce the same file; this one just gets the flags right.
do_dump() {
	local _f
	_f="$(dump_target mysql sql "${1-}")"
	step "dumping every database"
	mysql_dump_all "$_f"
	chmod 600 "$_f"
	ok "$_f  ($(du -h "$_f" 2>/dev/null | awk '{print $1}'))"
	info "put it back with:  app-setup load mysql"
}

do_load() {
	local _f
	_f="$(dump_source mysql sql "${1-}")"
	step "loading $_f"
	warn "this replaces every database named in that file"
	mysql_root < "$_f" || die "the import failed"
	mysql_root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
	ok "loaded"
}

do_restore() {
	local _d _was
	bk_open mysql "${1-}"
	_d="$BK_UNPACKED"
	if [ -f "$_d/all.sql" ]; then
		svc_running "$(svc)" || { step "starting $(svc)"; svc_start "$(svc)"; }
		step "loading all.sql — this replaces the databases in it"
		mysql_root < "$_d/all.sql" || die "the import failed; nothing else was touched"
		mysql_root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
		ok "databases restored"
	elif [ -d "$_d/files$(mysql_datadir)" ] || [ -d "$_d/files$DATADIR_DEFAULT" ]; then
		# The archive carries whatever path the datadir had when it was taken,
		# which is not necessarily where it is now: a container reinstalled
		# with a data disk restores a backup made without one, and the other
		# way round. Put the files back where the archive says, then point the
		# server at that.
		if [ -d "$_d/files$(mysql_datadir)" ]; then _was="$(mysql_datadir)"
		else _was="$DATADIR_DEFAULT"; fi
		step "stopping $(svc) to put the data directory back"
		svc_stop "$(svc)"
		rm -rf "$_was"
		bk_restore_files "$_d"
		chown -R mysql:mysql "$_was" 2>/dev/null || true
		mysql_set_datadir "$_was"
		svc_start "$(svc)" || die "MariaDB will not start on the restored data directory"
		ok "data directory restored to $_was"
		[ "$_was" = "$DATADIR_DEFAULT" ] && data_disk &&
			info "it went back to $DATADIR_DEFAULT, which a reinstall takes. Move it with:  app-setup movedata mysql"
	else
		die "that archive has neither a dump nor a data directory in it"
	fi
	bk_close
	warn "the config in the archive was NOT written back — check it by hand if"
	warn "you need it:  tar tzf <archive> | grep etc/"
}

do_help() { cat <<'EOF'
MySQL (MariaDB)

  Which is this?
    MariaDB. It is the fork of MySQL that every distribution ships, it
    speaks the same protocol, the command is still `mysql`, and software
    written for MySQL does not know the difference.

  Your root password
    cat /etc/app-setup/secrets/mysql.txt
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
    app-setup install backup     once, to set a bucket and a schedule
    app-setup backup mysql       now — mysql_20210403123221.tgz
    app-setup restore mysql      the newest one back again

    Install `Backup` and this runs itself nightly and uploads off the
    machine. The archive holds a --single-transaction dump of every
    database plus the config, and nothing stops while it is taken.

  Just a .sql file, right now
    app-setup dump mysql         /data/dumps/mysql_20260819034206.sql
    app-setup load mysql         the newest one back in

    That is plain SQL — open it, grep it, scp it, feed it to another
    server. Name one if you want:
      sh /etc/app-setup/mysql.sh dump /data/before-the-upgrade.sql
      sh /etc/app-setup/mysql.sh load /data/before-the-upgrade.sql

    By hand, if you would rather:
      mysqldump --single-transaction --all-databases > /data/all.sql
      mysql < /data/all.sql

    /data survives a reinstall of this container; the root filesystem does
    not. On a container with a data disk this recipe already keeps the
    tables at /data/mysql for that reason — \`app-setup movedata mysql\`
    moves an older install that is still on the root filesystem. Either
    way, a backup on the same disk as the database is not a backup.

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
    $(mysql_datadir)                the data
                                      (/data survives a reinstall; / does not)
    /etc/mysql/  or  /etc/my.cnf.d/   the config
    journalctl -u mariadb             why it will not start
EOF
}

app_main "$@"
