#!/bin/sh
# app-setup: 1
# id: certbot
# name: Certbot (HTTPS)
# name.zh: Certbot 免费证书
# category: web
# order: 14
# summary: Free HTTPS certificates from Let's Encrypt, renewed automatically.
# summary.zh: 从 Let's Encrypt 申请免费 HTTPS 证书，到期自动续。
# includes: certbot, the nginx and apache plugins, a renewal timer
# includes.zh: certbot 主程序、nginx 与 apache 插件、自动续期任务
# disk: 45M
# memory: 0
# ports: 80
. /usr/lib/app-setup/common.sh

CHECK_BIN="certbot"

version_line() {
	_v="$(certbot --version 2>&1 | head -1)"
	_n="$(ls /etc/letsencrypt/live 2>/dev/null | grep -vc README || true)"
	printf '%s, %s certificate(s)' "$_v" "${_n:-0}"
}

do_install() {
	case "$PMF" in
		deb) pkg_install certbot
		     pkg_install_optional python3-certbot-nginx python3-certbot-apache ;;
		rpm) enable_epel
		     pkg_install certbot
		     pkg_install_optional python3-certbot-nginx python3-certbot-apache ;;
		apk) pkg_install certbot
		     pkg_install_optional certbot-nginx certbot-apache ;;
	esac

	# Renewal is a systemd timer on the systemd images and a cron line on
	# Alpine; the package sets up neither reliably, so check and say so.
	case "$INIT" in
	systemd)
		systemctl enable --now certbot.timer >/dev/null 2>&1 ||
		systemctl enable --now certbot-renew.timer >/dev/null 2>&1 ||
			warn "no renewal timer was found; add a cron line yourself (see docs)"
		;;
	*)
		if [ -d /etc/periodic/daily ]; then
			cat > /etc/periodic/daily/certbot-renew <<'EOF'
#!/bin/sh
/usr/bin/certbot renew --quiet --no-self-upgrade
EOF
			chmod +x /etc/periodic/daily/certbot-renew
			ok "daily renewal added to /etc/periodic/daily/certbot-renew"
		fi
		;;
	esac

	ok "certbot is installed. Nothing has a certificate yet — see the docs button."
}

do_uninstall() {
	rm -f /etc/periodic/daily/certbot-renew
	# The nginx and apache plugins depend on certbot, so removing certbot alone
	# is refused — and apk announces the refusal on stdout while exiting 0, so
	# the remove reported success and certbot was still installed. Take the
	# plugins first, whichever names this family uses.
	case "$PMF" in
		deb|rpm) pkg_remove python3-certbot-nginx python3-certbot-apache ;;
		apk)     pkg_remove certbot-nginx certbot-apache ;;
	esac
	pkg_remove certbot
	info "/etc/letsencrypt was kept. Delete it yourself to remove your certificates."
}

do_help() { cat <<'EOF'
Certbot

  Before it can work — all three, no exceptions
    1. You own a domain, and its A record points at this container's public
       address. Check with: dig +short example.com
    2. Port 80 reaches this container from the internet. Let's Encrypt
       proves you own the domain by fetching a file over plain HTTP, so
       even an HTTPS-only site needs 80 open for the challenge.
    3. A web server is running here and serving that domain.

    If the address in DNS is your host's and the panel forwards 80 to this
    container, that counts. If it does not forward 80, this cannot work and
    no amount of retrying will change it.

  Getting a certificate
    certbot --nginx  -d example.com -d www.example.com
    certbot --apache -d example.com

    It edits the web server's config, reloads it, and you are done. Say yes
    to the redirect question unless you have a reason not to.

  If you use a web server certbot cannot edit
    certbot certonly --webroot -w /var/www/html -d example.com
    Then point your config at:
      /etc/letsencrypt/live/example.com/fullchain.pem
      /etc/letsencrypt/live/example.com/privkey.pem

  Renewal
    Certificates last 90 days and renew at 60. The install turned on the
    timer (systemd) or a daily job (Alpine). Check it:
      certbot renew --dry-run
    That is the command that tells you renewal will work *before* it
    matters. Run it once now.

  Rate limits, which people hit while experimenting
    Five failures per account per hour, and fifty certificates per domain
    per week. While testing, add --dry-run or --test-cert; those use the
    staging service and do not count. A staging certificate will show as
    untrusted in a browser — that is expected.

  Where things are
    /etc/letsencrypt/live/<domain>/    the certificate you point config at
    /etc/letsencrypt/renewal/          how each one gets renewed
    /var/log/letsencrypt/              why it failed

  Caddy does all of this by itself
    If you have not committed to nginx, the `caddy` source needs none of
    the above.
EOF
}

app_main "$@"
