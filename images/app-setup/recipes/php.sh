#!/bin/sh
# app-setup: 1
# id: php
# name: PHP
# name.zh: PHP 运行环境
# category: web
# order: 12
# summary: PHP-FPM with the extensions WordPress and friends actually need, wired into nginx.
# summary.zh: PHP-FPM，装好 WordPress 这类程序真正需要的扩展，并接到 nginx 上。
# includes: php-fpm, php-cli, mysql, gd, mbstring, xml, curl, zip, opcache
# includes.zh: php-fpm、命令行 php，以及 mysql、gd、mbstring、xml、curl、zip、opcache 扩展
# disk: 90M
# memory: 60M
# service: php-fpm
. /usr/lib/app-setup/common.sh

CHECK_BIN="php"
SERVICE="$(php_service)"

version_line() {
	_v="$($(php_bin) -r 'echo PHP_VERSION;' 2>/dev/null)"
	printf 'PHP %s, fpm on %s' "$_v" "$(php_fpm_listen)"
}

# Alpine names every package after the exact release — php83-gd, php84-gd —
# and which releases exist depends on which Alpine this is.
alpine_php() {
	for _v in 84 83 82 81; do
		if apk info -e "php$_v" >/dev/null 2>&1 || apk search -q -x "php$_v" 2>/dev/null | grep -q .; then
			printf 'php%s' "$_v"; return 0
		fi
	done
	printf 'php83'
}

do_install() {
	case "$PMF" in
	deb)
		# Debian's php-* are virtual packages pointing at whatever release
		# this distro shipped, which is exactly the indirection we want.
		pkg_install php-fpm php-cli php-mysql php-curl php-gd php-mbstring php-xml php-zip
		pkg_install_optional php-intl php-bcmath php-opcache php-soap php-gmp
		;;
	rpm)
		enable_epel
		pkg_install php php-fpm php-cli php-mysqlnd php-gd php-mbstring php-xml php-opcache
		pkg_install_optional php-intl php-bcmath php-zip php-pecl-zip php-json php-process php-soap
		;;
	apk)
		_p="$(alpine_php)"
		pkg_install "$_p" "$_p-fpm" "$_p-cli" "$_p-mysqli" "$_p-pdo_mysql" "$_p-gd" \
		            "$_p-mbstring" "$_p-xml" "$_p-session" "$_p-opcache" "$_p-curl" \
		            "$_p-phar" "$_p-openssl" "$_p-fileinfo" "$_p-dom"
		pkg_install_optional "$_p-zip" "$_p-tokenizer" "$_p-simplexml" "$_p-xmlwriter" \
		                     "$_p-xmlreader" "$_p-iconv" "$_p-bcmath" "$_p-intl" "$_p-ctype"

		# Alpine installs the binary as php84 and ships no plain `php`, so the
		# link is what makes every instruction on the internet true here.
		#
		# It is re-derived rather than reusing $_p from above, and then
		# checked: a link pointing at something that is not there is silent —
		# `have php` says yes, running it says "not found", and the failure
		# surfaces three recipes later as LNMP claiming PHP is missing.
		_php="/usr/bin/$(alpine_php)"
		if [ -x "$_php" ]; then
			ln -sf "$_php" /usr/bin/php
		else
			warn "no PHP binary at $_php; leaving /usr/bin/php alone"
		fi
		[ -x /usr/bin/php ] || die "/usr/bin/php does not run. apk info -L $(alpine_php) shows what was installed."
		;;
	*)
		die "no PHP packages for this system"
		;;
	esac

	_svc="$(php_service)"
	mkdir -p "$WEBROOT"

	# The one file that makes "is PHP working" a five-second question. It is
	# deliberately not phpinfo(): that page lists every path and extension on
	# the machine and people leave it there for years.
	cat > "$WEBROOT/app-setup-php.php" <<'EOF'
<?php
header('Content-Type: text/plain; charset=utf-8');
echo "PHP ", PHP_VERSION, " is working.\n";
echo "extensions: ", implode(', ', array_slice(get_loaded_extensions(), 0, 40)), "\n";
echo "\nDelete this file when you are done: ", __FILE__, "\n";
EOF

	svc_enable "$_svc"
	svc_start "$_svc" || warn "php-fpm did not start; check its log"

	# If nginx is here, teach it to hand .php files over. The whole default
	# site is rewritten rather than patched: editing a config file with sed
	# works until the day somebody has edited it first, and then it produces
	# a file that neither of us can explain.
	if have nginx && [ -f "$(nginx_conf_dir)/app-setup.conf" ]; then
		if grep -q 'fastcgi_pass' "$(nginx_conf_dir)/app-setup.conf"; then
			info "nginx already passes .php through"
		else
			step "wiring php-fpm into nginx"
			php_nginx_site > "$(nginx_conf_dir)/app-setup.conf"
			nginx_test_reload || warn "nginx did not reload; its config needs a look"
		fi
	elif have nginx; then
		info "nginx is here but its default site is not one app-setup wrote;"
		info "add the php location block yourself — the docs button has it"
	fi

	ok "PHP is installed"
	info "check it: curl http://127.0.0.1/app-setup-php.php"
}

do_uninstall() {
	_svc="$(php_service)"
	svc_stop "$_svc"
	svc_disable "$_svc"
	rm -f "$WEBROOT/app-setup-php.php"
	case "$PMF" in
		deb) pkg_remove php-fpm php-cli php-mysql php-curl php-gd php-mbstring php-xml php-zip ;;
		rpm) pkg_remove php php-fpm php-cli php-mysqlnd php-gd php-mbstring php-xml php-opcache ;;
		apk) apk del $(apk info 2>/dev/null | grep -E '^php[0-9]+' | tr '\n' ' ') 2>/dev/null || true
		     rm -f /usr/bin/php ;;
	esac
}

do_help() { cat <<'EOF'
PHP

  Check it works
    php -v                              the command line
    curl http://127.0.0.1/app-setup-php.php     through the web server

    Delete that test file when you are done. It is harmless, but leaving
    files you did not write in a public directory is a habit worth not
    forming.

  Where things are
    /etc/php/*/fpm/php.ini              Debian, Ubuntu
    /etc/php.ini                        AlmaLinux, Rocky, CentOS
    /etc/php*/php.ini                   Alpine
    The pool config — how many workers, which socket — is www.conf next to
    it.

  After editing php.ini, restart the pool
    systemctl restart php8.2-fpm        the name has the version in it on
                                        Debian; `systemctl list-units 'php*'`
    rc-service php-fpm83 restart        Alpine

  The three settings people come back for
    upload_max_filesize = 64M
    post_max_size       = 64M
    memory_limit        = 256M
    All three in php.ini. Uploading a large file needs the first two raised
    *and* nginx's client_max_body_size, which is a separate setting in the
    nginx config — a 413 error is nginx, not PHP.

  Missing extension
    "Call to undefined function ..." means an extension is not installed.
      Debian/Ubuntu   apt-get install php-imagick
      AlmaLinux       dnf install php-imagick
      Alpine          apk add php83-imagick   (match your php version)
    Then restart php-fpm.

  Nginx
    If nginx was already installed, the .php location block was added to
    /etc/nginx/conf.d/app-setup.conf. If you install nginx *after* PHP, run
    the PHP install again to wire them together.

  Composer
    Not installed here. To add it:
      php -r "copy('https://getcomposer.org/installer','/tmp/c.php');"
      php /tmp/c.php --install-dir=/usr/local/bin --filename=composer
EOF
}

app_main "$@"
