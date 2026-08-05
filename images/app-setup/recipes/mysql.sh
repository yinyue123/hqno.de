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

do_install() {
	pkg_install $(pmv PKGS)

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
	svc_start "$(svc)" || die "mariadb would not start. On a small container this is usually memory — it wants ~400MB."

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
	show_note mysql
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove $(pmv PKGS)
	rm -f /root/.my.cnf
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
    MariaDB wants roughly 400MB to be comfortable. On a 512MB container it
    will start and then be killed under load. If mysqld keeps disappearing,
    check `dmesg | tail` for the out-of-memory killer, and add to the
    config:
      [mysqld]
      innodb_buffer_pool_size = 64M
      performance_schema = OFF

  Where things are
    /var/lib/mysql                    the data
    /etc/mysql/  or  /etc/my.cnf.d/   the config
    journalctl -u mariadb             why it will not start
EOF
}

app_main "$@"
