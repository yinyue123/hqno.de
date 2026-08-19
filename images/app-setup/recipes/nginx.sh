#!/bin/sh
# app-setup: 1
# id: nginx
# name: Nginx
# name.zh: Nginx 网页服务器
# category: web
# order: 10
# summary: The web server most guides assume. Serves files, and passes PHP or an app through.
# summary.zh: 教程默认用的网页服务器。发静态文件，也能把请求转给 PHP 或你的程序。
# includes: nginx, one document root at /var/www/html, a working default site
# includes.zh: nginx 主程序、统一的网站目录 /var/www/html、一个可用的默认站点
# disk: 15M
# memory: 24M
# ports: 80, 443
# service: nginx
. /usr/lib/app-setup/common.sh

PKGS="nginx"
SERVICE="nginx"
CHECK_BIN="nginx"

version_line() {
	_v="$(nginx -v 2>&1 | sed 's|.*nginx/||')"
	printf 'nginx %s, root %s' "$_v" "$WEBROOT"
}

# nginx is not what makes a small machine small — a master and one worker come
# to well under a megabyte resident, and none of the buffers it keeps by
# default are worth touching. There is exactly one thing here worth fixing:
# `worker_processes auto` counts the host's cores rather than the share this
# container was sold, so a 128MB box on a 16-core host starts sixteen workers
# to serve a blog.
nginx_tune() {
	local _conf _want
	_conf=/etc/nginx/nginx.conf
	[ -f "$_conf" ] || return 0
	grep -qE '^[[:space:]]*worker_processes[[:space:]]' "$_conf" || return 0

	if [ "$(mem_profile)" = normal ]; then _want='auto'; else _want='1'; fi
	grep -qE "^[[:space:]]*worker_processes[[:space:]]+$_want;" "$_conf" && return 0

	backup_once "$_conf"
	if sed -i "s|^[[:space:]]*worker_processes[[:space:]].*|worker_processes $_want;|" "$_conf"; then
		info "nginx: worker_processes $_want"
	else
		warn "could not set worker_processes; leaving nginx.conf alone"
	fi
	return 0
}

do_install() {
	enable_epel                 # CentOS 7 keeps nginx in EPEL
	pkg_install $(pmv PKGS)
	nginx_tune

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
<title>nginx is running</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:34rem;margin:15vh auto;padding:0 1rem}
code{background:#f4f4f5;padding:.1em .35em;border-radius:3px}</style>
<h1>nginx is running</h1>
<p>This page is <code>$WEBROOT/index.html</code>. Replace it with your site.</p>
<p>Installed by app-setup on $(date -u +%Y-%m-%d). Type <code>app-setup</code> to add a
database, PHP, or a whole suite like WordPress.</p>
EOF
	fi

	# One document root on every distro, so a tutorial that says
	# /var/www/html is true here whichever image this is.
	nginx_drop_default

	# ...but not if a suite is already the default server. WordPress, Typecho
	# and Nextcloud each write app-setup-<id>.conf holding `default_server`,
	# and adding a second one here makes nginx refuse the whole config:
	#
	#   nginx: [emerg] a duplicate default server for 0.0.0.0:80
	#
	# which is what `install nginx` did to a machine that already had
	# WordPress on it — nginx installed, and then would not start. The suite
	# is already serving this address; leave it alone.
	if default_site_holder >/dev/null; then
		info "$(default_site_holder) is already serving the default address;"
		info "leaving its site alone. nginx itself is installed and running."
	else
	cat > "$(nginx_conf_dir)/app-setup.conf" <<EOF
# written by app-setup. Your own sites go in files next to this one; this is
# the default server, which answers for any name that nothing else claims.
server {
    listen      80 default_server;
    listen      [::]:80 default_server;
    server_name _;
    root        $WEBROOT;
    index       index.html index.htm;

    access_log  /var/log/nginx/access.log;
    error_log   /var/log/nginx/error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\\. { deny all; }
}
EOF
	fi

	# Alpine's package ships no pid directory and nginx will not start without
	# one; the systemd packages create theirs in a tmpfiles rule.
	mkdir -p /run/nginx /var/log/nginx

	svc_enable "$(svc)"
	if nginx_test_reload; then
		svc_start "$(svc)" 2>/dev/null || true
		ok "nginx is serving $WEBROOT on port 80"
		info "reach it from this machine with: curl -I http://127.0.0.1/"
		info "from outside, use the address and port your panel published"
	else
		die "nginx was installed but its config does not parse"
	fi
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	rm -f "$(nginx_conf_dir)/app-setup.conf"
	restore_backup /etc/nginx/nginx.conf
	pkg_remove $(pmv PKGS)
	info "$WEBROOT was left alone — your files are still there"
}

do_help() { cat <<'EOF'
Nginx

  Where things are
    /var/www/html                       your site's files
    /etc/nginx/conf.d/app-setup.conf    the default site (http.d on Alpine)
    /var/log/nginx/access.log           who asked for what
    /var/log/nginx/error.log            read this first when something 500s

  Check it is up
    curl -I http://127.0.0.1/
    From your laptop, use the address and port the panel published for this
    container — a container's own 80 is not the internet's 80.

  Add a second site
    Make a file next to app-setup.conf:

      server {
          listen 80;
          server_name shop.example.com;
          root /var/www/shop;
          index index.html;
      }

    Then, every single time you edit nginx config:
      nginx -t          check it parses — this catches nearly every mistake
      systemctl reload nginx        (rc-service nginx reload on Alpine)

    reload keeps existing connections; restart drops them.

  PHP
    Install the `php` source and it will add the fastcgi block for you, or
    install the `lnmp` suite to get nginx, MariaDB and PHP wired together in
    one step.

  HTTPS
    Install `certbot`, point a real domain at this container, then:
      certbot --nginx -d example.com
    It edits the config and sets up renewal.

  When it will not start
    nginx -t                         the config
    journalctl -u nginx -n 50        why systemd gave up   (Alpine:
    tail -50 /var/log/nginx/error.log)
    ss -ltnp | grep :80              something else already has the port
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
