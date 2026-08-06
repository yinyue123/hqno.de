#!/bin/sh
# app-setup: 1
# id: wordpress
# name: WordPress
# name.zh: WordPress 博客/建站
# category: stack
# order: 10
# summary: The blog and site software four sites in ten run on. Installed onto LNMP with its database already made.
# summary.zh: 全世界四成网站在用的建站程序。装在 LNMP 上，数据库和配置都替你建好。
# includes: WordPress, nginx, PHP-FPM, MariaDB, a database and wp-config.php written for you
# includes.zh: WordPress 本体、nginx、PHP-FPM、MariaDB，以及建好的数据库和 wp-config.php
# disk: 800M
# memory: 768M
# ports: 80
# requires: nginx, php, mysql
# service: nginx
. /usr/lib/app-setup/common.sh

WP_ROOT=/var/www/wordpress
WP_DB=wordpress
WP_USER=wordpress

version_line() {
	_v="$(awk -F"'" '/wp_version =/ {print $2; exit}' "$WP_ROOT/wp-includes/version.php" 2>/dev/null)"
	[ -n "$_v" ] || _v='?'
	printf 'WordPress %s at %s' "$_v" "$WP_ROOT"
}

is_installed() { [ -f "$WP_ROOT/wp-config.php" ] || [ -f "$WP_ROOT/wp-load.php" ]; }

do_install() {
	web_claim_default wordpress

	if [ "$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')" -lt 700 ] 2>/dev/null; then
		warn "under 700MB of memory here. WordPress runs, but MariaDB will be the"
		warn "first thing killed under load — the docs button has the small-box settings."
	fi

	recipe_ensure nginx
	recipe_ensure mysql
	recipe_ensure php

	mysql_wait || die "MariaDB is not answering, so the database cannot be created"

	# The archive, from the mirror that is near whoever is reading the screen.
	# cn.wordpress.org also carries the Chinese-language build, which is the
	# one a zh user wants anyway — not just a faster copy of the English one.
	if lang_zh; then
		_urls="https://cn.wordpress.org/latest-zh_CN.tar.gz https://wordpress.org/latest.tar.gz"
	else
		_urls="https://wordpress.org/latest.tar.gz https://cn.wordpress.org/latest.tar.gz"
	fi

	_tmp="$(tmp_dir)"
	_got=""
	for _u in $_urls; do
		step "downloading WordPress from ${_u%%/latest*}"
		if fetch "$_u" "$_tmp/wp.tar.gz"; then _got=1; break; fi
		warn "that mirror did not answer; trying the next one"
	done
	[ -n "$_got" ] || { rm -rf "$_tmp"; die "could not download WordPress. Check this container has a route out: curl -I https://wordpress.org/"; }

	step "unpacking into $WP_ROOT"
	tar -xzf "$_tmp/wp.tar.gz" -C "$_tmp" || { rm -rf "$_tmp"; die "the archive did not unpack; the download was probably truncated"; }
	mkdir -p "$WP_ROOT"
	# -a rather than -r: WordPress ships a .htaccess-ish set of dotfiles and
	# cp without -a skips them silently.
	cp -a "$_tmp/wordpress/." "$WP_ROOT/"
	rm -rf "$_tmp"

	# ---- database -------------------------------------------------------
	if [ -f "$WP_ROOT/wp-config.php" ]; then
		info "wp-config.php is already here; keeping it and its database"
	else
		_pw="$(rand_pass 24)"
		step "creating the $WP_DB database"
		db_mysql_create "$WP_DB" "$WP_USER" "$_pw" ||
			die "the database could not be created. \`mysql -e 'select 1'\` as root says why."

		# Salts come from wordpress.org, and when it cannot be reached they
		# are generated here instead. A WordPress with the default "put your
		# unique phrase here" salts has every cookie forgeable by anyone.
		step "writing wp-config.php"
		_salts="$(fetch_stdout https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || true)"
		if ! printf '%s' "$_salts" | grep -q AUTH_KEY; then
			warn "could not reach the salt service; generating the keys locally"
			_salts=""
			for _k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY \
			          AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
				_salts="$_salts
define('$_k', '$(rand_pass 64)');"
			done
		fi

		# A per-install table prefix. It is not a security boundary and
		# nobody should pretend it is; it is what lets a second WordPress
		# share this database later without a collision.
		_prefix="wp_"

		cat > "$WP_ROOT/wp-config.php" <<EOF
<?php
/**
 * Written by app-setup on $(date -u +%Y-%m-%d). Safe to edit.
 * The password below is also in /root/.app-setup/wordpress.txt.
 */

define('DB_NAME',     '$WP_DB');
define('DB_USER',     '$WP_USER');
define('DB_PASSWORD', '$_pw');
define('DB_HOST',     'localhost');
define('DB_CHARSET',  'utf8mb4');
define('DB_COLLATE',  '');
$_salts

\$table_prefix = '$_prefix';

/**
 * The address this site answers on.
 *
 * A container's port 80 is not the internet's port 80 — the panel publishes
 * it somewhere else, and it can move. WordPress normally stores one fixed
 * address in the database, and the day it stops matching every page redirects
 * to a host that is not there. So it is taken from the request instead, which
 * is right at every address this site is ever reached on.
 *
 * Once a real domain is pointed here, replace both lines with it:
 *   define('WP_HOME',    'https://example.com');
 *   define('WP_SITEURL', 'https://example.com');
 * That is faster, and it stops a forged Host header from rewriting your links.
 */
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$_SERVER['HTTPS'] = 'on';   /* TLS ends at the panel's front door, not here */
}
if (isset(\$_SERVER['HTTP_HOST'])) {
    define('WP_HOME',    ((isset(\$_SERVER['HTTPS']) && \$_SERVER['HTTPS'] !== 'off') ? 'https://' : 'http://') . \$_SERVER['HTTP_HOST']);
    define('WP_SITEURL', WP_HOME);
}

/* Plugins and updates write straight to disk. Without this WordPress asks for
   FTP credentials that do not exist on this machine. */
define('FS_METHOD', 'direct');

/* Keep three revisions per post rather than one per save: the usual reason a
   small database is suddenly 2GB. */
define('WP_POST_REVISIONS', 3);

define('WP_DEBUG', false);

if (!defined('ABSPATH')) define('ABSPATH', __DIR__ . '/');
require_once ABSPATH . 'wp-settings.php';
EOF
		chmod 640 "$WP_ROOT/wp-config.php"

		save_note wordpress <<EOF
WordPress

  files            $WP_ROOT
  database         $WP_DB
  database user    $WP_USER
  database pass    $_pw
  config           $WP_ROOT/wp-config.php

  Finish the install in a browser. The first page asks for the site title and
  the account you will log in with — that account is not this password.

  If you lose the admin password later:
    cd $WP_ROOT && wp user update admin --user_pass='new-one' --allow-root
  or, with no wp-cli:
    mysql $WP_DB -e "UPDATE ${_prefix}users SET user_pass = MD5('new-one') WHERE user_login = 'admin';"
EOF
	fi

	# ---- ownership ------------------------------------------------------
	# The php-fpm user has to own this or the admin cannot install a plugin,
	# upload an image, or update itself. Directories 755, files 644, and
	# wp-config.php tighter than both.
	step "setting ownership to $(web_user)"
	chown -R "$(web_user)":"$(web_group)" "$WP_ROOT"
	find "$WP_ROOT" -type d -exec chmod 755 {} + 2>/dev/null || true
	find "$WP_ROOT" -type f -exec chmod 644 {} + 2>/dev/null || true
	chmod 640 "$WP_ROOT/wp-config.php" 2>/dev/null || true
	mkdir -p "$WP_ROOT/wp-content/uploads"
	chown -R "$(web_user)":"$(web_group)" "$WP_ROOT/wp-content"

	# ---- nginx ----------------------------------------------------------
	# WordPress becomes *the* site on this machine, so the plain default
	# server has to go: two `default_server` blocks on port 80 is a config
	# nginx refuses to load at all.
	step "pointing nginx at $WP_ROOT"
	rm -f "$(nginx_conf_dir)/app-setup.conf"
	nginx_drop_default
	cat > "$(nginx_conf_dir)/app-setup-wordpress.conf" <<EOF
# written by app-setup. Remove this file and restart nginx to stop serving
# WordPress from the default address.
server {
    listen      80 default_server;
    listen      [::]:80 default_server;
    server_name _;
    root        $WP_ROOT;
    index       index.php index.html;

    access_log  /var/log/nginx/access.log;
    error_log   /var/log/nginx/error.log;

    # Media libraries fill up fast. Raise php.ini's upload_max_filesize and
    # post_max_size to match, or the 413 just moves from nginx to PHP.
    client_max_body_size 64m;

    # Pretty permalinks. Without this, every URL but the front page is a 404
    # as soon as the permalink setting is changed away from "plain".
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files      \$uri =404;
        include        fastcgi_params;
        fastcgi_pass   $(php_fastcgi_pass);
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        # Updates and imports are slow, and a 504 halfway through one leaves
        # the database in a state somebody has to clean up by hand.
        fastcgi_read_timeout 300;
    }

    # xmlrpc.php is how WordPress sites get brute-forced, and almost nothing
    # still uses it. Delete these four lines if the Jetpack or WordPress
    # mobile app needs it.
    location = /xmlrpc.php {
        deny all;
        access_log off;
    }

    # Nothing under wp-content should ever be executed as PHP. This is what
    # turns "someone uploaded a .php disguised as a .jpg" from a compromise
    # into a file sitting on disk doing nothing.
    location ~* ^/wp-content/.*\.(php|phar)\$ {
        deny all;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { log_not_found off; access_log off; }
    location ~ /\.         { deny all; }

    # Browsers should cache these; the default is not to.
    location ~* \.(jpg|jpeg|png|gif|webp|svg|ico|css|js|woff2?)\$ {
        expires 30d;
        access_log off;
    }
}
EOF
	nginx_test_reload || die "nginx will not reload with the WordPress site; the config is at $(nginx_conf_dir)/app-setup-wordpress.conf"

	svc_start "$(php_service)" 2>/dev/null || true

	ok "WordPress is installed"
	info "open it and finish the setup:  http://$(guess_host)/"
	if in_container; then
		info "from outside, use the address and port the panel published for port 80"
	fi
	show_note wordpress
}

do_uninstall() {
	warn "this removes the WordPress files, its database and its nginx site."
	warn "nginx, PHP and MariaDB stay — remove those from their own cards."

	# Put the plain default site back *before* the files go, and reload onto
	# it. nginx's reload is asynchronous — the old worker keeps serving until
	# it drains — so deleting the tree first leaves it answering from a
	# document root that is no longer there, which is a 404 on a site the
	# person has not finished removing yet.
	rm -f "$(nginx_conf_dir)/app-setup-wordpress.conf"
	if have nginx && [ ! -f "$(nginx_conf_dir)/app-setup.conf" ]; then
		mkdir -p "$WEBROOT"
		php_nginx_site "$WEBROOT" > "$(nginx_conf_dir)/app-setup.conf"
		nginx_test_reload || true
	fi

	if mysql_wait 2>/dev/null; then
		step "dropping the $WP_DB database"
		db_mysql_drop "$WP_DB" "$WP_USER"
	else
		warn "MariaDB is not running, so the $WP_DB database is still there"
	fi

	# Everything except what somebody wrote. Uploads are the one thing here
	# that cannot be downloaded again, so they are moved rather than deleted
	# and the person is told where they went.
	if [ -d "$WP_ROOT/wp-content/uploads" ]; then
		_keep="/root/wordpress-uploads-$(date -u +%Y%m%d%H%M%S)"
		mv "$WP_ROOT/wp-content/uploads" "$_keep" 2>/dev/null &&
			warn "your uploads were moved to $_keep rather than deleted"
	fi
	rm -rf "$WP_ROOT"
	drop_note wordpress
	ok "WordPress is gone"
}

do_start()   { svc_start nginx || true; svc_start "$(php_service)" || true; svc_start mariadb || true; ok "started"; }
do_stop()    { svc_stop nginx; svc_stop "$(php_service)"; svc_stop mariadb; ok "stopped"; }
do_enable()  { svc_enable nginx; svc_enable "$(php_service)"; svc_enable mariadb; ok "the site comes back at boot"; }
do_disable() { svc_disable nginx; svc_disable "$(php_service)"; svc_disable mariadb; ok "it will not come back at boot"; }

do_status() {
	is_installed || exit 2
	_php="$(php_service)"
	_down=""
	svc_running nginx   || _down="$_down nginx"
	svc_running "$_php" || _down="$_down php-fpm"
	svc_running mariadb || _down="$_down mariadb"

	if [ -z "$_down" ]; then
		if [ -f "$WP_ROOT/wp-config.php" ]; then echo "detail=$(version_line)"
		else echo "detail=downloaded, but not configured yet"; fi
	else
		echo "detail=down:$_down"
	fi
	if svc_enabled nginx; then echo "enabled=1"; else echo "enabled=0"; fi

	[ -z "$_down" ] && exit 0
	case "$_down" in " nginx php-fpm mariadb") exit 1 ;; esac
	exit 3
}

do_help() { cat <<'EOF'
WordPress

  Where it is
    /var/www/wordpress            the site
    /var/www/wordpress/wp-config.php   database details and keys
    /root/.app-setup/wordpress.txt     the same, readable by root only

  Finishing the install
    Open the site in a browser. The first page asks for a title and an
    admin account — that account is new, and is not the database password
    this recipe generated. Write down what you choose.

    Inside a container, http://127.0.0.1/ only works from inside. From your
    laptop, use the address and port your panel published for port 80.

  The address problem, and why this install does not have it
    WordPress normally writes one fixed URL into the database, and every
    page redirects to it forever after. On a container whose published port
    can change, that is a site that works today and redirects into nothing
    next week. So wp-config.php takes the address from the request instead.

    Once you have a real domain pointed here, pin it — it is faster, and it
    stops a forged Host header from rewriting your links:

      define('WP_HOME',    'https://example.com');
      define('WP_SITEURL', 'https://example.com');

  Plugins and themes
    Install them from the admin screens. They write straight to disk here;
    FS_METHOD is set to 'direct' so WordPress never asks for the FTP details
    that this machine does not have.

    If an install fails with a permission error, ownership has drifted:
      chown -R $(stat -c %U /var/www/wordpress) /var/www/wordpress

  Making it fast enough for a small container
    1. A page cache does more than everything else together. Install
       WP Super Cache or W3 Total Cache and turn it on. A cached page never
       reaches PHP or the database at all.
    2. Do not run more than a handful of plugins. Each one runs on every
       request.
    3. Static files are already cached for 30 days by the nginx config.

  Uploads bigger than 64MB
    Two limits, and both have to move:
      nginx     client_max_body_size in
                /etc/nginx/conf.d/app-setup-wordpress.conf (http.d on Alpine)
      PHP       upload_max_filesize and post_max_size in php.ini
    A 413 is nginx. "The uploaded file exceeds the upload_max_filesize
    directive" is PHP.

  Backing it up
    Two halves, and a backup with only one is not a backup:
      mysqldump --single-transaction wordpress > /data/wordpress.sql
      tar -czf /data/wordpress-files.tar.gz -C /var/www wordpress

    /data is the only path that survives a reinstall of this container.

  Keeping it patched
    WordPress updates itself from the admin screens, and you should let it.
    An out-of-date WordPress with a popular plugin is the single most
    commonly compromised thing on the public internet. Turn on automatic
    updates for minor releases at the very least.

  Security this install already did for you
    - xmlrpc.php is blocked. It is what brute-force scripts use. If the
      WordPress mobile app or Jetpack needs it, delete that location block.
    - PHP under wp-content is refused, so an uploaded file that pretends to
      be an image cannot be executed.
    - Unique keys and salts are set. The default ones make every login
      cookie forgeable.

  What still needs a person
    Use a real password on the admin account, and do not call it "admin".
    Everything else on this list is automated; that one is not.

  On a small container
    MariaDB is the expensive part — see the MySQL card's docs for the
    64MB-buffer-pool settings. Under about 700MB of memory, install a page
    cache before you announce the address to anybody.

  Removing it
    Uninstall deletes the files and drops the database. Your uploads are
    moved to /root/wordpress-uploads-<date> rather than deleted, because
    they are the one thing here that cannot be downloaded again.
EOF
}

app_main "$@"
