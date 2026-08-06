#!/bin/sh
# app-setup: 1
# id: lamp
# name: LAMP
# name.zh: LAMP 一键环境
# category: stack
# order: 2
# summary: Apache + MariaDB + PHP. Pick this over LNMP when your software needs .htaccess.
# summary.zh: Apache + MariaDB + PHP。软件需要 .htaccess 的时候选这个，不选 LNMP。
# includes: apache with mod_rewrite, MariaDB, PHP, a working default site
# includes.zh: 带 mod_rewrite 的 Apache、MariaDB、PHP，以及可用的默认站点
# disk: 620M
# memory: 768M
# ports: 80, 3306
# service: apache2
. /usr/lib/app-setup/common.sh

SERVICE="apache2"
SERVICE_rpm="httpd"

version_line() {
	_php="$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo '?')"
	printf 'Apache + PHP %s + MariaDB' "$_php"
}

is_installed() {
	{ have apache2 || have httpd; } || return 1
	have php || return 1
	have mysqld || have mariadbd || [ -x /usr/libexec/mysqld ] || return 1
	return 0
}

do_install() {
	if have nginx && svc_running nginx; then
		warn "nginx is running and holds port 80. Apache will not start until it stops."
		warn "Stop nginx first, or install the 'lnmp' suite instead of this one."
	fi

	# `free` reads the host's numbers in a container without lxcfs, which is
	# how a 128MB box talks itself into believing it has 2G. mem_total_mb asks
	# the cgroup first.
	case "$(mem_profile)" in
		tiny)
			warn "this machine has $(mem_total_mb)MB of memory. All three are being sized"
			warn "down to fit: Apache to a handful of workers rather than 150, MariaDB"
			warn "to about half what it asks for, and php-fpm to workers that exist only"
			warn "while a page is being served. LNMP is the lighter of the two suites —"
			warn "pick this one only if your software genuinely needs .htaccess."
			;;
		small)
			info "sizing all three for $(mem_total_mb)MB rather than using the defaults"
			;;
	esac

	recipe apache install
	recipe mysql  install
	recipe php    install

	# Apache runs PHP through its own module or through php-fpm; which one
	# depends on the distro, and getting the wrong one is a page that offers
	# to download the .php file instead of running it.
	step "connecting Apache to PHP"
	case "$PMF" in
	deb)
		pkg_install_optional libapache2-mod-php php-fpm libapache2-mod-fcgid
		if a2enconf "php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)-fpm" >/dev/null 2>&1; then
			a2enmod proxy_fcgi setenvif >/dev/null 2>&1 || true
		fi
		a2enmod rewrite >/dev/null 2>&1 || true
		;;
	rpm)
		# The php package on the RPM images already drops a conf file into
		# /etc/httpd/conf.d that hands .php to php-fpm over a socket.
		pkg_install_optional php
		;;
	apk)
		_p="$(apk info 2>/dev/null | grep -m1 -oE '^php[0-9]+')"
		[ -n "$_p" ] && pkg_install_optional "${_p}-apache2"
		sed -i 's|^#LoadModule rewrite_module|LoadModule rewrite_module|' /etc/apache2/httpd.conf 2>/dev/null || true
		;;
	esac

	if docroot_is_ours "$WEBROOT"; then
	rm -f "$WEBROOT/index.html"
	cat > "$WEBROOT/index.php" <<'EOF'
<?php ?><!doctype html>
<!-- app-setup placeholder -->
<meta charset="utf-8">
<title>LAMP is running</title>
<style>body{font:16px/1.7 system-ui,sans-serif;max-width:36rem;margin:12vh auto;padding:0 1rem}
code{background:#f4f4f5;padding:.1em .35em;border-radius:3px}</style>
<h1>LAMP is running</h1>
<ul>
  <li>Apache is serving this page</li>
  <li>PHP <?= PHP_VERSION ?> rendered it</li>
  <li>.htaccess is enabled for this directory</li>
</ul>
<p>This file is <code><?= __FILE__ ?></code>. Replace it with your site.</p>
<p>Your database password is in <code>/root/.app-setup/mysql.txt</code>.</p>
EOF
	else
		info "$WEBROOT already has a page in it that app-setup did not write."
		info "Leaving it alone — Apache and PHP are serving whatever is there."
	fi
	chown -R "$(web_user)":"$(web_group)" "$WEBROOT" 2>/dev/null || true

	svc_restart "$(svc)" || die "apache would not restart after adding PHP"
	ok "LAMP is up"
	info "check it: curl http://127.0.0.1/"
	show_note mysql
}

do_uninstall() {
	warn "removing Apache, PHP and MariaDB. Databases and $WEBROOT stay."
	recipe php    uninstall
	recipe mysql  uninstall
	recipe apache uninstall
	placeholder_remove "$WEBROOT/index.php"
}

do_start()   { svc_start "$(svc)" || true; svc_start "$(php_service)" 2>/dev/null || true; svc_start mariadb || true; ok "started"; }
do_stop()    { svc_stop "$(svc)"; svc_stop "$(php_service)" 2>/dev/null || true; svc_stop mariadb; ok "stopped"; }
do_enable()  { svc_enable "$(svc)"; svc_enable mariadb; ok "Apache and MariaDB start at boot"; }
do_disable() { svc_disable "$(svc)"; svc_disable mariadb; ok "neither starts at boot"; }

do_status() {
	is_installed || exit 2
	_up=0
	_down=""
	if svc_running "$(svc)"; then _up=$((_up + 1)); else _down="$_down apache"; fi
	if svc_running mariadb;  then _up=$((_up + 1)); else _down="$_down mariadb"; fi

	if [ "$_up" = 2 ]; then echo "detail=Apache + PHP + MariaDB, all running"
	else                    echo "detail=down:$_down"; fi
	if svc_enabled "$(svc)"; then echo "enabled=1"; else echo "enabled=0"; fi

	[ "$_up" = 2 ] && exit 0
	[ "$_up" = 0 ] && exit 1
	exit 3
}

do_help() { cat <<'EOF'
LAMP — Linux, Apache, MariaDB, PHP

  Why this and not LNMP
    One reason: .htaccess. A great deal of older PHP software ships its URL
    rewriting rules in .htaccess files and has no nginx equivalent. If your
    software's install instructions mention .htaccess, use this. Otherwise
    LNMP is lighter and faster.

  What you have now
    Apache   serving /var/www/html on port 80, mod_rewrite on,
             AllowOverride All so .htaccess works
    PHP      through the Apache module or php-fpm, depending on the distro
    MariaDB  on 127.0.0.1:3306, password in /root/.app-setup/mysql.txt

  Names, by distro
    Debian, Ubuntu, Alpine      the service is apache2
    AlmaLinux, Rocky, CentOS    the service is httpd

  After editing any config
    apachectl configtest
    systemctl reload apache2        (or httpd, or rc-service apache2 reload)

  A second site (Debian and Ubuntu)
    /etc/apache2/sites-available/shop.conf:

      <VirtualHost *:80>
          ServerName shop.example.com
          DocumentRoot /var/www/shop
          <Directory /var/www/shop>
              AllowOverride All
              Require all granted
          </Directory>
      </VirtualHost>

    a2ensite shop && systemctl reload apache2
    On AlmaLinux drop the same block into /etc/httpd/conf.d/shop.conf.

  It cannot start
    Almost always port 80 is taken by nginx. One of them has to go:
      ss -ltnp | grep :80
      systemctl stop nginx && systemctl disable nginx

  The .php file downloads instead of running
    PHP is not connected to Apache. Run this install again — it is the step
    it exists to get right.

  Small containers
    Under 1G of memory app-setup sizes all three down as it installs them.
    What it wrote, and where:

      zz-app-setup-sizing.conf in Apache's conf directory — MaxRequestWorkers
        cut from 150 to a number this machine can actually hold, for prefork
        and for the threaded MPMs, plus a short KeepAliveTimeout so a child
        held open for an idle browser is not a child nobody else can use.
      90-app-setup.cnf in MariaDB's config directory — three caches that
        default to 128M each. Measured on a 128MB container: 76MB of
        unreclaimable memory before, 45MB after.
      99-app-setup.ini in php's conf.d, and a block at the end of php-fpm's
        www.conf — opcache, and pm = ondemand.

    Even so, LNMP is the lighter of the two suites and by a wide margin. The
    reason is prefork: if PHP is attached as mod_php, every Apache child
    holds its own interpreter, so the pool size and the PHP count are the
    same number. nginx and php-fpm keep those two ceilings separate, which
    is why the same machine serves more behind LNMP. Pick LAMP when your
    software genuinely needs .htaccess, not by default.
EOF
}

app_main "$@"
