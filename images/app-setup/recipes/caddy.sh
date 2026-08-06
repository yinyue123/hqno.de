#!/bin/sh
# app-setup: 1
# id: caddy
# name: Caddy
# name.zh: Caddy 网页服务器
# category: web
# order: 13
# summary: A web server that gets its own HTTPS certificate. Two lines of config, no certbot.
# summary.zh: 会自己申请 HTTPS 证书的网页服务器。配置只有两行，不用装 certbot。
# includes: caddy, a Caddyfile, automatic Let's Encrypt certificates
# includes.zh: caddy 主程序、Caddyfile 配置、自动申请的 Let's Encrypt 证书
# disk: 50M
# memory: 40M
# ports: 80, 443
# service: caddy
. /usr/lib/app-setup/common.sh

SERVICE="caddy"
CHECK_BIN="caddy"
CADDYFILE=/etc/caddy/Caddyfile

version_line() {
	printf 'Caddy %s' "$(caddy version 2>/dev/null | head -1 | cut -d' ' -f1)"
}

do_install() {
	if pkg_exists caddy; then
		# Alpine has it in community, and the package brings its own service.
		pkg_install caddy
	else
		step "no caddy package here; fetching the official release binary"
		ensure_downloader
		_ver="$(fetch_stdout https://api.github.com/repos/caddyserver/caddy/releases/latest 2>/dev/null |
			sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\([^"]*\)".*/\1/p' | head -1)"
		[ -n "$_ver" ] || die "could not ask github for the current version — is this machine online?"
		_tmp="$(tmp_dir)"
		_url="https://github.com/caddyserver/caddy/releases/download/v${_ver}/caddy_${_ver}_linux_${ARCH}.tar.gz"
		info "$_url"
		fetch "$_url" "$_tmp/caddy.tgz" || die "download failed"
		tar -xzf "$_tmp/caddy.tgz" -C "$_tmp" caddy
		install -m 0755 "$_tmp/caddy" /usr/bin/caddy
		rm -rf "$_tmp"

		id caddy >/dev/null 2>&1 || {
			(useradd --system --home /var/lib/caddy --create-home --shell /usr/sbin/nologin caddy 2>/dev/null) ||
			(adduser -S -D -H -h /var/lib/caddy -s /sbin/nologin caddy 2>/dev/null) || true
		}
		mkdir -p /var/lib/caddy /etc/caddy
		chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true

		# Caddy needs to bind 80 and 443 as a non-root user. The capability is
		# the tidy way; without it the service would have to run as root.
		SVC_ENVIRON="Environment=XDG_DATA_HOME=/var/lib/caddy
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE"
		make_service caddy "Caddy web server" \
			"/usr/bin/caddy run --config $CADDYFILE --adapter caddyfile" caddy /var/lib/caddy
	fi

	mkdir -p "$WEBROOT" /etc/caddy
	[ -f "$WEBROOT/index.html" ] || cat > "$WEBROOT/index.html" <<EOF
<!doctype html><!-- app-setup placeholder --><meta charset="utf-8"><title>Caddy is running</title>
<h1>Caddy is running</h1>
<p>This page is $WEBROOT/index.html.</p>
EOF

	if [ ! -f "$CADDYFILE" ] || ! grep -q app-setup "$CADDYFILE"; then
		backup_once "$CADDYFILE"
		cat > "$CADDYFILE" <<EOF
# written by app-setup.
#
# To turn this into a real HTTPS site, replace the ":80" line with your
# domain name — caddy will get and renew the certificate by itself:
#
#     example.com {
#         root * $WEBROOT
#         file_server
#     }
#
# That only works once the domain's DNS points at this container and ports
# 80 and 443 reach it from the internet.

:80 {
	root * $WEBROOT
	file_server
	encode gzip
}
EOF
	fi
	chown -R caddy:caddy /etc/caddy 2>/dev/null || true

	svc_enable "$(svc)"
	svc_start "$(svc)" || die "caddy would not start; check: caddy validate --config $CADDYFILE"
	ok "Caddy is serving $WEBROOT on port 80"
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	if pkg_present caddy; then
		pkg_remove caddy
	else
		remove_service caddy
		rm -f /usr/bin/caddy
	fi
	rm -rf /etc/caddy
	info "certificates in /var/lib/caddy were kept; delete that directory to be rid of them"
}

do_help() { cat <<'EOF'
Caddy

  Why this instead of nginx
    It gets and renews its HTTPS certificate on its own. No certbot, no
    cron job, no remembering in ninety days. In exchange it is less widely
    documented, so a random tutorial will assume nginx.

  Turning on HTTPS
    Edit /etc/caddy/Caddyfile, change the ":80" line to your domain:

      example.com {
          root * /var/www/html
          file_server
      }

    Then: systemctl reload caddy     (rc-service caddy reload on Alpine)

    Requirements, all three: the domain's A record points at this
    container's public address, ports 80 and 443 reach it from the
    internet, and the domain resolves already. Caddy proves ownership over
    port 80, so a blocked 80 means no certificate even for an HTTPS site.

  Proxying to your own app
    example.com {
        reverse_proxy 127.0.0.1:3000
    }
    That is the whole config for putting HTTPS in front of a Node or Go
    program. Compression, HTTP/2 and the certificate are automatic.

  Checking config
    caddy validate --config /etc/caddy/Caddyfile
    caddy fmt --overwrite /etc/caddy/Caddyfile

  Where things are
    /etc/caddy/Caddyfile      config
    /var/lib/caddy            certificates and account keys — back this up,
                              or at least do not be surprised when deleting
                              it means re-issuing everything
    journalctl -u caddy       the log on the systemd images

  Note on the binary
    Only Alpine packages Caddy. On the other images the official release
    binary is downloaded from github, so this install needs the machine to
    be online and reaching github.
EOF
}

app_main "$@"
