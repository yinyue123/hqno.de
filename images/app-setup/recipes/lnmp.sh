#!/bin/sh
# app-setup: 1
# id: lnmp
# name: LNMP
# name.zh: LNMP 一键环境
# category: stack
# order: 1
# summary: Nginx + MariaDB + PHP, installed and wired together. The base most PHP software wants.
# summary.zh: Nginx + MariaDB + PHP，装好并且互相接通。绝大多数 PHP 程序要的底座。
# includes: nginx, MariaDB, PHP-FPM with the usual extensions, a working default site
# includes.zh: nginx、MariaDB、带常用扩展的 PHP-FPM、一个可用的默认站点
# disk: 600M
# memory: 768M
# ports: 80, 3306
# service: nginx
. /usr/lib/app-setup/common.sh

version_line() {
	_php="$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo '?')"
	_ng="$(nginx -v 2>&1 | sed 's|.*nginx/||')"
	printf 'nginx %s, PHP %s, MariaDB' "$_ng" "$_php"
}

is_installed() {
	have nginx || return 1
	have php || return 1
	have mysqld || have mariadbd || [ -x /usr/libexec/mysqld ] || return 1
	return 0
}

do_install() {
	if [ "$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')" -lt 700 ] 2>/dev/null; then
		warn "this machine has under 700MB of memory. MariaDB alone wants ~400MB;"
		warn "expect it to be killed under load. See the docs button for the small-box settings."
	fi

	recipe nginx install
	recipe mysql install
	recipe php  install

	# php's own install wires nginx up when nginx is already there, which it
	# is by now — but write the site again so the order of the three above
	# cannot change the result.
	step "pointing nginx at PHP"
	php_nginx_site "$WEBROOT" > "$(nginx_conf_dir)/app-setup.conf"
	nginx_test_reload || die "nginx will not reload with the PHP config"

	if docroot_is_ours "$WEBROOT"; then
	rm -f "$WEBROOT/index.html"
	cat > "$WEBROOT/index.php" <<'EOF'
<?php
// app-setup placeholder
$db = 'not checked';
try {
  $cnf = @parse_ini_file('/root/.my.cnf');
  $db = 'MariaDB is running';
} catch (Throwable $e) { $db = 'MariaDB: ' . $e->getMessage(); }
?><!doctype html>
<meta charset="utf-8">
<title>LNMP is running</title>
<style>body{font:16px/1.7 system-ui,sans-serif;max-width:36rem;margin:12vh auto;padding:0 1rem}
code{background:#f4f4f5;padding:.1em .35em;border-radius:3px}
li{margin:.2em 0}</style>
<h1>LNMP is running</h1>
<ul>
  <li>nginx is serving this page</li>
  <li>PHP <?= PHP_VERSION ?> rendered it</li>
  <li><?= htmlspecialchars($db) ?></li>
</ul>
<p>This file is <code><?= __FILE__ ?></code>. Replace it with your site.</p>
<p>Your database password is in <code>/root/.app-setup/mysql.txt</code>.
Run <code>app-setup</code> to add WordPress, Typecho or Nextcloud on top.</p>
EOF
	else
		info "$WEBROOT already has a page in it that app-setup did not write."
		info "Leaving it alone — nginx and PHP are serving whatever is there."
	fi
	chown -R "$(web_user)":"$(web_group)" "$WEBROOT" 2>/dev/null || true

	ok "LNMP is up"
	info "check it: curl http://127.0.0.1/"
	show_note mysql
}

do_uninstall() {
	warn "removing nginx, PHP and MariaDB. Databases in /var/lib/mysql and files in $WEBROOT stay."
	recipe php   uninstall
	recipe mysql uninstall
	recipe nginx uninstall
	placeholder_remove "$WEBROOT/index.php"
}

do_start() {
	svc_start nginx || true
	svc_start "$(php_service)" || true
	svc_start mariadb || true
	ok "started"
}

do_stop() {
	svc_stop nginx
	svc_stop "$(php_service)"
	svc_stop mariadb
	ok "stopped"
}

do_enable()  { svc_enable nginx; svc_enable "$(php_service)"; svc_enable mariadb; ok "all three start at boot"; }
do_disable() { svc_disable nginx; svc_disable "$(php_service)"; svc_disable mariadb; ok "none of them start at boot"; }

# A suite is only up when all of it is up. Half of it running is reported as
# an error rather than as "running", because that is what it is.
do_status() {
	is_installed || exit 2
	_php="$(php_service)"
	_up=0
	_down=""
	if svc_running nginx;   then _up=$((_up + 1)); else _down="$_down nginx"; fi
	if svc_running "$_php"; then _up=$((_up + 1)); else _down="$_down php-fpm"; fi
	if svc_running mariadb; then _up=$((_up + 1)); else _down="$_down mariadb"; fi

	if [ "$_up" = 3 ]; then echo "detail=nginx + PHP + MariaDB, all running"
	else                    echo "detail=down:$_down"; fi
	if svc_enabled nginx; then echo "enabled=1"; else echo "enabled=0"; fi

	[ "$_up" = 3 ] && exit 0
	[ "$_up" = 0 ] && exit 1
	exit 3
}

do_help() { cat <<'EOF'
LNMP — Linux, Nginx, MariaDB, PHP

  What you have now
    nginx    serving /var/www/html on port 80
    PHP-FPM  handling .php in that directory
    MariaDB  on 127.0.0.1:3306, root password in /root/.app-setup/mysql.txt

    Check all three at once:  curl http://127.0.0.1/

  Put your site here
    /var/www/html — delete index.php and put your own files in. Ownership
    should be the PHP-FPM user (www-data on Debian and Ubuntu, nginx or
    apache on AlmaLinux, nginx on Alpine):

      chown -R www-data:www-data /var/www/html

  Make a database for it
    mysql -e "CREATE DATABASE mysite CHARACTER SET utf8mb4;"
    mysql -e "CREATE USER 'mysite'@'localhost' IDENTIFIED BY 'a-password';"
    mysql -e "GRANT ALL ON mysite.* TO 'mysite'@'localhost'; FLUSH PRIVILEGES;"

  Reaching it from outside
    A container's port 80 is not the internet's port 80. Use the address
    and port your panel published, or point a domain at the host and let
    the panel route it here.

  Adding software on top
    app-setup, then the Suites tab: WordPress, Typecho and Nextcloud all
    install onto this and skip the parts they find already done.

  The three things that break, and what each looks like
    502 Bad Gateway     nginx is up, php-fpm is not. Restart it:
                        systemctl restart php8.2-fpm  (the version is in
                        the name; systemctl list-units 'php*' shows it)
    413 Request Entity Too Large    an upload bigger than
                        client_max_body_size in the nginx config. It is
                        set to 64m here; php.ini's upload_max_filesize has
                        to be raised to match.
    "Error establishing a database connection"     MariaDB is not running,
                        usually killed for memory. dmesg | tail says so.

  On a small container
    MariaDB is the expensive part. Under about 700MB of memory it will be
    killed under load. Add this to the MariaDB config and restart it:

      [mysqld]
      innodb_buffer_pool_size = 64M
      performance_schema      = OFF
      max_connections         = 30

    Or use the `sqlite` source instead of MariaDB — for a small site it is
    genuinely the better answer.

  Uninstalling
    Removes all three packages. Your files in /var/www/html and your
    databases in /var/lib/mysql are deliberately left behind.
EOF
}

app_main "$@"
