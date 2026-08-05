#!/bin/sh
# app-setup: 1
# id: typecho
# name: Typecho
# name.zh: Typecho 轻量博客
# category: stack
# order: 11
# summary: A blog in about 2MB. Runs on SQLite, so it needs no database server and fits a 256MB box.
# summary.zh: 只有 2MB 左右的博客程序。可以直接用 SQLite，不必装数据库，256MB 的小机器也跑得动。
# includes: Typecho, nginx, PHP-FPM, SQLite — MariaDB only if you already have it
# includes.zh: Typecho 本体、nginx、PHP-FPM、SQLite；只有本机已装 MariaDB 时才会用它
# disk: 200M
# memory: 128M
# ports: 80
# requires: nginx, php
# service: nginx
. /usr/lib/app-setup/common.sh

TY_ROOT=/var/www/typecho
TY_DB=typecho
TY_USER=typecho

version_line() {
	_v="$(awk -F"'" '/TYPECHO_VERSION/ {print $4; exit}' "$TY_ROOT/var/Typecho/Common.php" 2>/dev/null)"
	[ -n "$_v" ] || _v="$(awk -F"'" '/VERSION *=/ {print $2; exit}' "$TY_ROOT/var/Typecho/Common.php" 2>/dev/null)"
	if [ -f "$TY_ROOT/config.inc.php" ]; then
		printf 'Typecho %s, set up' "${_v:-1.x}"
	else
		printf 'Typecho %s, installer not finished' "${_v:-1.x}"
	fi
}

is_installed() { [ -f "$TY_ROOT/install.php" ] || [ -f "$TY_ROOT/config.inc.php" ]; }

do_install() {
	recipe_ensure nginx
	recipe_ensure php

	# SQLite is the point of Typecho on a small machine: one file, no second
	# daemon, no 400MB of MariaDB. The driver is a separate package almost
	# everywhere, and its absence only shows up as a missing entry in the
	# installer's dropdown — which is impossible to diagnose from the browser.
	step "making sure PHP can talk to SQLite"
	case "$PMF" in
		deb) pkg_install_optional php-sqlite3 ;;
		rpm) pkg_install_optional php-pdo php-sqlite3 ;;
		apk) for _v in 84 83 82 81; do
		         pkg_present "php$_v" && pkg_install_optional "php$_v-pdo_sqlite" "php$_v-sqlite3" "php$_v-pdo"
		     done ;;
	esac

	# Typecho ships a .zip and nothing else, so unzip is not optional here.
	have unzip || pkg_install_first unzip

	_tmp="$(tmp_dir)"
	# Both are GitHub release assets, because that is the only place Typecho
	# actually publishes the built zip — typecho.org has no download path that
	# stays put. The second is a pinned version, for the day `latest` moves to
	# a release whose asset is named something else.
	_got=""
	for _u in "https://github.com/typecho/typecho/releases/latest/download/typecho.zip" \
	          "https://github.com/typecho/typecho/releases/download/v1.2.1/typecho.zip"; do
		step "downloading Typecho"
		if fetch "$_u" "$_tmp/typecho.zip" && [ -s "$_tmp/typecho.zip" ]; then _got=1; break; fi
		warn "that did not work; trying the next address"
	done
	[ -n "$_got" ] || { rm -rf "$_tmp"; die "could not download Typecho. Check this container has a route out: curl -I https://github.com/"; }

	step "unpacking into $TY_ROOT"
	unzip -q -o "$_tmp/typecho.zip" -d "$_tmp/x" || { rm -rf "$_tmp"; die "the zip did not open; the download was probably truncated"; }
	mkdir -p "$TY_ROOT"
	# The release zip has had the files at the top level in some versions and
	# inside a build/ directory in others, so find index.php rather than
	# assume either.
	_src="$_tmp/x"
	[ -f "$_src/index.php" ] || _src="$(dirname "$(find "$_tmp/x" -name index.php -maxdepth 3 2>/dev/null | head -1)")"
	[ -f "$_src/index.php" ] || { rm -rf "$_tmp"; die "this archive does not look like Typecho — no index.php in it"; }
	cp -a "$_src/." "$TY_ROOT/"
	rm -rf "$_tmp"

	# ---- database, but only if there already is one ----------------------
	# Installing MariaDB *because* somebody picked the small blog would undo
	# the reason they picked it. So: use the database that is already here,
	# and otherwise say SQLite and mean it.
	_dbline="SQLite — no database server needed"
	_rc=0
	recipe_status mysql || _rc=$?
	if [ "$_rc" != 2 ] && mysql_wait 2>/dev/null; then
		_pw="$(rand_pass 24)"
		step "MariaDB is already here — making a $TY_DB database for it"
		if db_mysql_create "$TY_DB" "$TY_USER" "$_pw"; then
			_dbline="MySQL/MariaDB — database $TY_DB, user $TY_USER, password $_pw"
		else
			warn "could not create the database; the installer can still use SQLite"
			_pw=""
		fi
	fi

	# ---- permissions -----------------------------------------------------
	# install.php writes config.inc.php itself, and the SQLite file lives in
	# usr/ — both have to be writable by php-fpm or the installer stops with
	# a message about a directory it cannot create.
	step "setting ownership to $(web_user)"
	mkdir -p "$TY_ROOT/usr/uploads"
	chown -R "$(web_user)":"$(web_group)" "$TY_ROOT"
	chmod 755 "$TY_ROOT"
	chmod -R 755 "$TY_ROOT/usr"

	# ---- nginx -----------------------------------------------------------
	step "pointing nginx at $TY_ROOT"
	rm -f "$(nginx_conf_dir)/app-setup.conf"
	nginx_drop_default
	cat > "$(nginx_conf_dir)/app-setup-typecho.conf" <<EOF
# written by app-setup. Remove this file and restart nginx to stop serving
# Typecho from the default address.
server {
    listen      80 default_server;
    listen      [::]:80 default_server;
    server_name _;
    root        $TY_ROOT;
    index       index.php index.html;

    access_log  /var/log/nginx/access.log;
    error_log   /var/log/nginx/error.log;

    client_max_body_size 32m;

    # Typecho's permalinks are all rewritten to index.php. Without this only
    # the front page works.
    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location ~ \.php(/|\$) {
        # Typecho routes as /index.php/archives/1, so PATH_INFO has to be
        # split out — try_files \$uri =404 alone would 404 every article.
        fastcgi_split_path_info ^(.+\.php)(/.*)\$;
        # try_files clears \$fastcgi_path_info, so it has to be saved first
        # or every article arrives at PHP with no path at all.
        set \$_path_info \$fastcgi_path_info;
        # Refuse to run a .php that is not actually a file here. This is the
        # line that stops /uploads/photo.jpg/x.php from being executed.
        try_files      \$fastcgi_script_name =404;
        include        fastcgi_params;
        fastcgi_pass   $(php_fastcgi_pass);
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param  PATH_INFO       \$_path_info;
        fastcgi_read_timeout 120;
    }

    # The SQLite database is a file under the document root, and a web server
    # that will hand it out gives away every password in the site.
    location ~* \.(db|sqlite|sqlite3|db3)\$ { deny all; }
    location ~  ^/usr/uploads/.*\.(php|phar)\$ { deny all; }
    location ~  /\.  { deny all; }
    location = /config.inc.php { deny all; }

    location ~* \.(jpg|jpeg|png|gif|webp|svg|ico|css|js|woff2?)\$ {
        expires 30d;
        access_log off;
    }
}
EOF
	nginx_test_reload || die "nginx will not reload with the Typecho site"
	svc_start "$(php_service)" 2>/dev/null || true

	save_note typecho <<EOF
Typecho

  files       $TY_ROOT
  database    $_dbline

  Finish it in a browser: http://$(guess_host)/install.php

  With SQLite, the only thing the form asks for is where to put the file.
  Leave the suggested path alone — it is under $TY_ROOT/usr, which is the
  one directory PHP can write to here.

  Delete install.php once the site is up. Typecho reminds you; do it.
EOF

	ok "Typecho is unpacked and nginx is serving it"
	info "finish the setup:  http://$(guess_host)/install.php"
	if in_container; then
		info "from outside, use the address and port the panel published for port 80"
	fi
	show_note typecho
}

do_uninstall() {
	warn "this removes the Typecho files and its nginx site."

	# The default site goes back first, and nginx reloads onto it, before the
	# files go. A reload is asynchronous: delete the tree first and the old
	# worker answers 404 from a document root that is no longer there.
	rm -f "$(nginx_conf_dir)/app-setup-typecho.conf"
	if have nginx && [ ! -f "$(nginx_conf_dir)/app-setup.conf" ]; then
		mkdir -p "$WEBROOT"
		php_nginx_site "$WEBROOT" > "$(nginx_conf_dir)/app-setup.conf"
		nginx_test_reload || true
	fi

	if [ -d "$TY_ROOT/usr/uploads" ]; then
		_keep="/root/typecho-uploads-$(date -u +%Y%m%d%H%M%S)"
		mv "$TY_ROOT/usr/uploads" "$_keep" 2>/dev/null &&
			warn "your uploads were moved to $_keep rather than deleted"
	fi

	# The SQLite file is the whole site's content, and it is inside the tree
	# about to be deleted. Take a copy first; it is a few hundred KB.
	for _db in "$TY_ROOT"/usr/*.db "$TY_ROOT"/usr/*.sqlite*; do
		[ -f "$_db" ] || continue
		cp -a "$_db" "/root/typecho-$(basename "$_db")" 2>/dev/null &&
			warn "the SQLite database was copied to /root/typecho-$(basename "$_db")"
	done

	if mysql_wait 2>/dev/null; then
		db_mysql_drop "$TY_DB" "$TY_USER"
	fi

	rm -rf "$TY_ROOT"
	drop_note typecho
	ok "Typecho is gone"
}

do_start()   { svc_start nginx || true; svc_start "$(php_service)" || true; ok "started"; }
do_stop()    { svc_stop nginx; svc_stop "$(php_service)"; ok "stopped"; }
do_enable()  { svc_enable nginx; svc_enable "$(php_service)"; ok "the site comes back at boot"; }
do_disable() { svc_disable nginx; svc_disable "$(php_service)"; ok "it will not come back at boot"; }

do_status() {
	is_installed || exit 2
	_php="$(php_service)"
	_down=""
	svc_running nginx   || _down="$_down nginx"
	svc_running "$_php" || _down="$_down php-fpm"

	if [ -z "$_down" ]; then echo "detail=$(version_line)"
	else                     echo "detail=down:$_down"; fi
	if svc_enabled nginx; then echo "enabled=1"; else echo "enabled=0"; fi

	[ -z "$_down" ] && exit 0
	[ "$_down" = " nginx php-fpm" ] && exit 1
	exit 3
}

do_help() { cat <<'EOF'
Typecho

  What it is, and when to pick it over WordPress
    A blog engine in about 2MB, from the same era and the same idea as
    early WordPress, still maintained. It runs on SQLite, which means no
    MariaDB, which means it is comfortable on a 256MB container where
    WordPress is not. If you want to write posts and nothing else, this is
    the better answer. If you need a plugin for something specific, the
    WordPress catalogue is thirty times the size and that will decide it.

  Where it is
    /var/www/typecho                 the site
    /var/www/typecho/config.inc.php  written by the installer, not by us
    /var/www/typecho/usr/            uploads, themes, plugins, and the
                                     SQLite file if you chose SQLite

  Finishing the install
    http://<your address>/install.php

    Pick SQLite unless you have a reason not to. The form then asks only
    for a file path — keep the suggested one, which is under usr/ and is
    the directory PHP is allowed to write to here.

    If MariaDB was already installed when this ran, a database, a user and
    a password were made for it and printed at the end. They are also in
    /root/.app-setup/typecho.txt.

  Then delete install.php
    rm /var/www/typecho/install.php
    Typecho nags about this and it is right: leaving it there lets anybody
    who finds it re-run the installer.

  Permalinks
    Settings → Permalinks, and turn on the rewrite option. The nginx config
    here already passes PATH_INFO through, so the "custom" styles work
    without any further change. If every article 404s but the front page
    loads, that setting is the reason.

  Themes and plugins
    Drop them into usr/themes and usr/plugins, then enable them from the
    admin. They must be owned by the PHP user to be writable:
      chown -R $(stat -c %U /var/www/typecho) /var/www/typecho/usr

  Backing it up
    With SQLite it is one file plus the uploads:
      tar -czf /data/typecho.tar.gz -C /var/www typecho
    With MySQL, the database as well:
      mysqldump --single-transaction typecho > /data/typecho.sql

    /data is the only path that survives a reinstall of this container.

  Moving it to a domain
    Nothing here pins an address, so pointing a domain at this container is
    enough — no config to edit. Set the site address in Settings once you
    have one, so links in feeds and emails are absolute and right.

  Uninstalling
    Removes the files and the nginx site. The SQLite database and the
    uploads are copied to /root first, because they are the only part
    nobody can download again.
EOF
}

app_main "$@"
