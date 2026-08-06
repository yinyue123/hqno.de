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

do_install() {
	enable_epel                 # CentOS 7 keeps nginx in EPEL
	pkg_install $(pmv PKGS)

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

app_main "$@"
