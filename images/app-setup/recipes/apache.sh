#!/bin/sh
# app-setup: 1
# id: apache
# name: Apache
# name.zh: Apache 网页服务器
# category: web
# order: 11
# summary: The other web server. .htaccess works, which some old software insists on.
# summary.zh: 另一个网页服务器。支持 .htaccess，有些老软件非它不可。
# includes: apache2/httpd, mod_rewrite, one document root at /var/www/html
# includes.zh: apache 主程序、mod_rewrite 重写模块、统一网站目录 /var/www/html
# disk: 30M
# memory: 40M
# ports: 80, 443
# service: apache2
. /usr/lib/app-setup/common.sh

PKGS="apache2"
PKGS_rpm="httpd"
SERVICE="apache2"
SERVICE_rpm="httpd"
CHECK_BIN="apache2"
CHECK_BIN_rpm="httpd"
# Alpine's package is called apache2 but the binary it installs is httpd, so
# without this the card read "absent" for an Apache that was installed, running
# and serving — and version_line, which resolves the same variable, printed
# nothing.
CHECK_BIN_apk="httpd"

version_line() {
	_b="$(pmv CHECK_BIN)"
	_v="$("$_b" -v 2>/dev/null | head -1 | sed 's|.*Apache/||;s| .*||')"
	printf 'Apache %s, root %s' "$_v" "$WEBROOT"
}

do_install() {
	pkg_install $(pmv PKGS)

	mkdir -p "$WEBROOT"
	if [ ! -f "$WEBROOT/index.html" ] && [ ! -f "$WEBROOT/index.php" ]; then
		cat > "$WEBROOT/index.html" <<EOF
<!doctype html>
<!-- app-setup placeholder -->
<meta charset="utf-8">
<title>Apache is running</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:34rem;margin:15vh auto;padding:0 1rem}
code{background:#f4f4f5;padding:.1em .35em;border-radius:3px}</style>
<h1>Apache is running</h1>
<p>This page is <code>$WEBROOT/index.html</code>. Replace it with your site.</p>
EOF
	fi

	case "$PMF" in
	deb)
		a2enmod rewrite headers expires >/dev/null 2>&1 || true
		# Debian's default vhost already points at /var/www/html; what it does
		# not do is allow .htaccess, which is the reason most people are here.
		if [ -f /etc/apache2/apache2.conf ] && ! grep -q 'app-setup' /etc/apache2/apache2.conf; then
			backup_once /etc/apache2/apache2.conf
			cat >> /etc/apache2/apache2.conf <<EOF

# added by app-setup
<Directory $WEBROOT>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
		fi
		;;
	rpm)
		if [ -f /etc/httpd/conf/httpd.conf ] && ! grep -q 'app-setup' /etc/httpd/conf/httpd.conf; then
			backup_once /etc/httpd/conf/httpd.conf
			cat >> /etc/httpd/conf/httpd.conf <<EOF

# added by app-setup
<Directory $WEBROOT>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
		fi
		;;
	apk)
		# Alpine serves /var/www/localhost/htdocs; move it to the shared root
		# so that every image agrees on where a site lives.
		if [ -f /etc/apache2/httpd.conf ]; then
			backup_once /etc/apache2/httpd.conf
			sed -i "s|^DocumentRoot .*|DocumentRoot \"$WEBROOT\"|" /etc/apache2/httpd.conf
			sed -i "s|<Directory \"/var/www/localhost/htdocs\">|<Directory \"$WEBROOT\">|" /etc/apache2/httpd.conf
			sed -i 's|^\([[:space:]]*\)AllowOverride None|\1AllowOverride All|' /etc/apache2/httpd.conf
			sed -i 's|^#LoadModule rewrite_module|LoadModule rewrite_module|' /etc/apache2/httpd.conf
		fi
		;;
	esac

	svc_enable "$(svc)"
	svc_start "$(svc)" || die "apache was installed but would not start; see the log"
	ok "Apache is serving $WEBROOT on port 80"
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	restore_backup /etc/apache2/apache2.conf
	restore_backup /etc/httpd/conf/httpd.conf
	restore_backup /etc/apache2/httpd.conf
	pkg_remove $(pmv PKGS)
	info "$WEBROOT was left alone — your files are still there"
}

do_help() { cat <<'EOF'
Apache

  Names, by distro
    Debian / Ubuntu / Alpine    the package and the service are apache2
    AlmaLinux / Rocky / CentOS  both are httpd
    Everything below works either way; use the name your machine uses.

  Where things are
    /var/www/html                    your site
    /etc/apache2/    or  /etc/httpd/ the config
    /var/log/apache2/ or /var/log/httpd/   access and error logs

  .htaccess
    AllowOverride All is set for /var/www/html, so .htaccess files work.
    That is the main reason to choose Apache over nginx — a lot of older PHP
    software ships rewrite rules in one and nothing else.

  After editing config, always
    apachectl configtest         (or: apache2ctl configtest)
    systemctl reload apache2     (rc-service apache2 reload on Alpine)

  A second site (Debian and Ubuntu)
    /etc/apache2/sites-available/shop.conf, then a2ensite shop && reload.
    On AlmaLinux drop the same <VirtualHost> into /etc/httpd/conf.d/.

  PHP
    Install the `php` source, or the `lamp` suite for Apache + MariaDB + PHP
    in one go.

  Do not run this and nginx at once
    Both want port 80 and the second one to start will fail. Pick one, or
    change the other's listen port.
EOF
}

app_main "$@"
