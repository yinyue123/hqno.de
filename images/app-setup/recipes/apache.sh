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

TUNE_CONF=zz-app-setup-sizing.conf

# Apache's memory is its process pool, and the default pool is sized for a
# dedicated web server: MaxRequestWorkers 150. What one worker costs depends
# entirely on which MPM is running and how PHP is attached to it —
#
#   prefork + mod_php   every child holds its own PHP interpreter, 15-30MB.
#                       150 of those is 3GB, and the machine dies long before
#                       Apache decides it has enough workers.
#   event/worker + fpm  children are threads and cost well under a megabyte;
#                       the PHP interpreters live in php-fpm's pool instead,
#                       which app-setup has already capped.
#
# Both are sized here, in IfModule blocks, because which one is loaded is a
# per-distro answer and changes when someone installs mod_php later.
apache_tune() {
	local _dir _f _kids _threads _workers
	_dir="$(apache_conf_dir)" || {
		warn "no Apache conf directory found; leaving its MPM settings alone"
		return 0
	}
	_f="$_dir/$TUNE_CONF"

	if [ "$(mem_profile)" = normal ]; then
		if [ -f "$_f" ]; then
			tuning_drop "$_f"
			info "this machine is big enough now; removed $_f"
		fi
		return 0
	fi

	# prefork: one process per request in flight, and possibly a PHP each.
	_kids="$(mem_share 40 2 16)"
	# event/worker: threads are cheap, so the ceiling is about file
	# descriptors and connection buffers rather than about memory.
	_threads=12
	_workers=$((_kids * _threads))
	[ "$_workers" -lt 24 ] && _workers=24

	step "sizing Apache for $(mem_total_mb)MB of memory"
	tuning_write "$_f" <<EOF
$(tuning_header)
# Both MPMs are sized: which one is loaded is a per-distro answer, and it
# changes the day somebody installs mod_php on top of an event build.

<IfModule mpm_prefork_module>
    StartServers            1
    MinSpareServers         1
    MaxSpareServers         2
    MaxRequestWorkers       $_kids
    MaxConnectionsPerChild  500
</IfModule>

<IfModule mpm_event_module>
    StartServers            1
    MinSpareThreads         $_threads
    MaxSpareThreads         $((_threads * 2))
    ThreadsPerChild         $_threads
    MaxRequestWorkers       $_workers
    MaxConnectionsPerChild  1000
</IfModule>

<IfModule mpm_worker_module>
    StartServers            1
    MinSpareThreads         $_threads
    MaxSpareThreads         $((_threads * 2))
    ThreadsPerChild         $_threads
    MaxRequestWorkers       $_workers
    MaxConnectionsPerChild  1000
</IfModule>

# A child held open for a keep-alive is a child not serving anyone else, and
# on a pool this small that is the difference between slow and refusing.
KeepAlive               On
KeepAliveTimeout        3
MaxKeepAliveRequests    100
EOF
	info "Apache: at most $_kids prefork workers / $_workers threaded"
}

do_install() {
	pkg_install $(pmv PKGS)
	apache_tune

	# Before anything is written into it. On a container with a data disk
	# /var/www/html becomes a link onto it, so the path every tutorial
	# names is unchanged and the files survive a reinstall. Uploads are
	# the half of a site nobody can download again.
	web_root_on_data

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
	# Restart rather than start when it is already up, or the MPM sizes just
	# written sit unread until something else happens to bounce it.
	if svc_running "$(svc)"; then
		svc_restart "$(svc)" || die "apache would not come back up; see its log"
	else
		svc_start "$(svc)" || die "apache was installed but would not start; see the log"
	fi
	ok "Apache is serving $WEBROOT on port 80"
	if [ "$(mem_profile)" != normal ]; then
		info "sized for $(mem_total_mb)MB — see $(apache_conf_dir)/$TUNE_CONF"
	fi
}

do_uninstall() {
	local _d
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	_d="$(apache_conf_dir)" && tuning_drop "$_d/$TUNE_CONF"
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

# The web root is /var/www/html on every distro by design, and on a container
# with a data disk it should be a link onto that disk. This is the deliberate
# version for a server installed before that was true, or one whose document
# root already had a site in it when it was installed.
do_movedata() {
	data_disk || die "this container has no data disk, so there is nowhere durable to move to."
	[ -L "$WEBROOT" ] && { ok "already on the data disk: $WEBROOT -> $(readlink "$WEBROOT")"; return 0; }
	data_relocate "$WEBROOT" "$DATA_DIR/www" || die "nothing was moved"
	# nginx and apache keep serving through the link without a reload — the
	# path they were configured with has not changed — but a worker holding an
	# open file descriptor is still reading the old inode, so tell them.
	svc_running "$(svc)" && { step "reloading $(svc)"; svc_reload "$(svc)" || svc_restart "$(svc)" || true; }
	ok "the document root is on the data disk now, and survives a reinstall."
}

app_main "$@"
