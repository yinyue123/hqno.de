#!/bin/sh
# app-setup: 1
# id: nextcloud
# name: Nextcloud
# name.zh: Nextcloud 私有网盘
# category: stack
# order: 12
# summary: Your own file sync and share — the part of Dropbox you actually use, on your own disk. Set up ready to log in.
# summary.zh: 自己的网盘：文件同步、共享、手机备份，数据都在自己机器上。装完直接能登录。
# includes: Nextcloud, nginx, PHP-FPM with every extension it wants, MariaDB, an admin account
# includes.zh: Nextcloud 本体、nginx、装齐扩展的 PHP-FPM、MariaDB，以及建好的管理员账号
# disk: 2G
# memory: 1G
# ports: 80
# requires: nginx, php, mysql
# service: nginx
# param: backup | default | Backup | 备份 | default,dump,files
# action: backup | backup | ▶ Back up now | ▶ 立即备份
. /usr/lib/app-setup/common.sh

NC_ROOT=/var/www/nextcloud
NC_DATA=/var/lib/nextcloud-data
NC_DB=nextcloud
NC_USER=nextcloud

# occ has to run as the user that owns config/config.php, and Nextcloud checks:
# run it as root and it refuses with a message about file ownership that sends
# people off to chown the tree, which is the wrong fix. So there is no
# run-as-root fallback here — if neither sudo nor su is on this machine, say so
# rather than produce that message.
occ() {
	_ocu="$(web_user)"
	if have sudo; then
		sudo -u "$_ocu" -- "$(php_bin)" "$NC_ROOT/occ" "$@"
	elif have su; then
		su -s /bin/sh -c "$(php_bin) '$NC_ROOT/occ' $*" "$_ocu"
	else
		die "this needs sudo or su to run occ as $_ocu; Nextcloud will not let it run as root"
	fi
}

version_line() {
	_v="$(awk -F"'" '/OC_VersionString/ {print $2; exit}' "$NC_ROOT/version.php" 2>/dev/null)"
	printf 'Nextcloud %s, files in %s' "${_v:-?}" "$NC_DATA"
}

is_installed() { [ -f "$NC_ROOT/occ" ]; }

do_install() {
	web_claim_default nextcloud

	_mem="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
	if [ "${_mem:-9999}" -lt 900 ] 2>/dev/null; then
		warn "this machine has ${_mem}MB of memory. Nextcloud plus MariaDB wants about 1GB;"
		warn "it will install and log in, and then be killed the first time somebody"
		warn "uploads a folder. Typecho or a plain file server may be the better answer."
	fi

	recipe_ensure nginx
	recipe_ensure mysql
	recipe_ensure php

	# Nextcloud refuses to finish setup without these, and names them one at a
	# time — twelve reloads of a browser page to find out what is missing.
	step "installing the PHP extensions Nextcloud requires"
	case "$PMF" in
	deb)
		pkg_install_optional php-gd php-mbstring php-xml php-zip php-curl php-mysql \
		                     php-intl php-bcmath php-gmp php-imagick php-apcu php-bz2
		;;
	rpm)
		enable_epel
		pkg_install_optional php-gd php-mbstring php-xml php-zip php-pecl-zip php-curl \
		                     php-mysqlnd php-intl php-bcmath php-gmp php-pecl-apcu \
		                     php-process php-posix
		;;
	apk)
		for _v in 84 83 82 81; do
			pkg_present "php$_v" || continue
			pkg_install_optional "php$_v-gd" "php$_v-mbstring" "php$_v-xml" "php$_v-zip" \
			                     "php$_v-curl" "php$_v-pdo_mysql" "php$_v-intl" \
			                     "php$_v-bcmath" "php$_v-gmp" "php$_v-pecl-apcu" \
			                     "php$_v-ctype" "php$_v-dom" "php$_v-fileinfo" \
			                     "php$_v-iconv" "php$_v-simplexml" "php$_v-xmlreader" \
			                     "php$_v-xmlwriter" "php$_v-posix" "php$_v-sysvsem" \
			                     "php$_v-sodium" "php$_v-exif" "php$_v-bz2"
			break
		done
		;;
	esac
	svc_restart "$(php_service)" 2>/dev/null || true

	# ---- fetch -----------------------------------------------------------
	if [ -f "$NC_ROOT/occ" ]; then
		info "Nextcloud is already unpacked in $NC_ROOT; leaving the files alone"
	else
		_tmp="$(tmp_dir)"
		# 280MB as of Nextcloud 31 — measured, not remembered. On a slow link
		# this single step can take an hour, and somebody watching a silent
		# terminal needs to know that before they conclude it has hung.
		step "downloading Nextcloud (280MB — this is the slow part, and on a slow"
		step "connection it can take an hour. It is not stuck.)"
		if fetch "https://download.nextcloud.com/server/releases/latest.tar.bz2" "$_tmp/nc.tar.bz2"; then
			step "unpacking into $NC_ROOT"
			tar -xjf "$_tmp/nc.tar.bz2" -C "$_tmp" ||
				{ rm -rf "$_tmp"; die "the archive did not unpack; the download was probably truncated"; }
		elif fetch "https://download.nextcloud.com/server/releases/latest.zip" "$_tmp/nc.zip"; then
			have unzip || pkg_install_first unzip
			step "unpacking into $NC_ROOT"
			unzip -q "$_tmp/nc.zip" -d "$_tmp" ||
				{ rm -rf "$_tmp"; die "the archive did not open; the download was probably truncated"; }
		else
			rm -rf "$_tmp"
			die "could not download Nextcloud. Check this container has a route out: curl -I https://download.nextcloud.com/"
		fi
		mkdir -p "$NC_ROOT"
		cp -a "$_tmp/nextcloud/." "$NC_ROOT/"
		rm -rf "$_tmp"
	fi

	# ---- data directory, outside the web root ----------------------------
	# Nextcloud's own advice, and the reason for it is that a web server
	# misconfiguration in front of a data directory hands out every file
	# everybody uploaded. Keep it somewhere nginx does not serve.
	mkdir -p "$NC_DATA"
	chown -R "$(web_user)":"$(web_group)" "$NC_DATA" "$NC_ROOT"
	chmod 750 "$NC_DATA"

	# ---- database + headless setup ---------------------------------------
	if occ status 2>/dev/null | grep -q 'installed: true'; then
		info "Nextcloud is already set up; not touching the database"
	else
		mysql_wait || die "MariaDB is not answering, so the database cannot be created"
		_dbpw="$(rand_pass 24)"
		step "creating the $NC_DB database"
		db_mysql_create "$NC_DB" "$NC_USER" "$_dbpw" ||
			die "the database could not be created. \`mysql -e 'select 1'\` as root says why."

		_adminpw="$(rand_pass 18)"
		step "running the installer (this takes a minute)"
		# Headless. The browser installer asks the same five questions and
		# then times out on a small box halfway through creating tables,
		# which leaves a half-installed instance nobody can repair.
		if ! occ maintenance:install \
			--database mysql \
			--database-name "$NC_DB" \
			--database-user "$NC_USER" \
			--database-pass "$_dbpw" \
			--admin-user admin \
			--admin-pass "$_adminpw" \
			--data-dir "$NC_DATA"; then
			err "the Nextcloud installer failed. The usual causes, in order:"
			err "  - a PHP extension is missing: php -m | sort, and compare with"
			err "    what the Administration → Overview page asks for"
			err "  - not enough memory: dmesg | tail will say so"
			err "  - PHP's memory_limit is under 512M"
			die "nothing was left running"
		fi

		# The Host header has to be on this list or Nextcloud answers every
		# request with "access through untrusted domain". A container's
		# address is not knowable here, so seed the ones we can see and
		# tell the person how to add theirs.
		_i=1
		for _h in localhost 127.0.0.1 "$(guess_host)" "$(hostname 2>/dev/null)"; do
			[ -n "$_h" ] || continue
			occ config:system:set trusted_domains "$_i" --value="$_h" >/dev/null 2>&1 || true
			_i=$((_i + 1))
		done

		# Default phone region stops the "some settings are missing" warning
		# on the admin page, which otherwise looks like something is broken.
		if lang_zh; then occ config:system:set default_phone_region --value=CN >/dev/null 2>&1 || true
		else            occ config:system:set default_phone_region --value=US >/dev/null 2>&1 || true; fi
		occ config:system:set maintenance_window_start --value=1 >/dev/null 2>&1 || true

		save_note nextcloud <<EOF
Nextcloud

  address          http://$(guess_host)/
  admin user       admin
  admin password   $_adminpw

  files            $NC_DATA   (deliberately outside the web root)
  program          $NC_ROOT
  database         $NC_DB, user $NC_USER, password $_dbpw

  Change the admin password after the first login.

  Reaching it from a domain — Nextcloud refuses any Host it does not know:
    occ config:system:set trusted_domains 4 --value=cloud.example.com

  Behind the panel's HTTPS front door, so links come back as https://:
    occ config:system:set overwriteprotocol --value=https
EOF
	fi

	# ---- nginx -----------------------------------------------------------
	step "pointing nginx at $NC_ROOT"
	rm -f "$(nginx_conf_dir)/app-setup.conf"
	nginx_drop_default
	cat > "$(nginx_conf_dir)/app-setup-nextcloud.conf" <<EOF
# written by app-setup, from Nextcloud's own recommended nginx config.
# Remove this file and restart nginx to stop serving Nextcloud.
upstream php-handler-nextcloud { server $(php_fastcgi_pass); }

server {
    listen      80 default_server;
    listen      [::]:80 default_server;
    server_name _;
    root        $NC_ROOT;
    index       index.php index.html;

    access_log  /var/log/nginx/access.log;
    error_log   /var/log/nginx/error.log;

    # Nextcloud's own value. Uploads are chunked, but a folder upload still
    # sends large parts, and 0 means "no limit here, let PHP decide".
    client_max_body_size 0;
    client_body_timeout 300s;
    fastcgi_buffers 64 4K;

    # The desktop and mobile clients look for these two at the root and get
    # them wrong without the redirect.
    location = /.well-known/carddav { return 301 \$scheme://\$host/remote.php/dav; }
    location = /.well-known/caldav  { return 301 \$scheme://\$host/remote.php/dav; }

    # Never served, whatever else happens.
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)          { deny all; }
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)/  { deny all; }

    location / {
        rewrite ^/remote/(.*) /remote.php last;
        try_files \$uri \$uri/ /index.php\$request_uri;
    }

    location ~ \.php(?:\$|/) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        set \$_path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include   fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO       \$_path_info;
        fastcgi_param front_controller_active true;
        fastcgi_pass  php-handler-nextcloud;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        # A first sync of a large folder genuinely takes minutes.
        fastcgi_read_timeout 3600;
    }

    location ~ \.(?:css|js|mjs|svg|gif|png|jpg|ico|wasm|woff2?)\$ {
        try_files \$uri /index.php\$request_uri;
        expires 6M;
        access_log off;
    }
}
EOF
	nginx_test_reload || die "nginx will not reload with the Nextcloud site"

	# ---- background jobs -------------------------------------------------
	# Nextcloud's AJAX cron only runs while somebody has a page open, and the
	# admin page complains about it forever. A real cron entry is what it
	# wants and it is two lines.
	if have crontab; then
		step "adding the five-minute background job"
		( crontab -u "$(web_user)" -l 2>/dev/null | grep -v 'nextcloud/cron.php';
		  echo "*/5 * * * * $(php_bin) -f $NC_ROOT/cron.php" ) | crontab -u "$(web_user)" - 2>/dev/null ||
			warn "could not install the cron job; Nextcloud will fall back to AJAX cron"
		occ background:cron >/dev/null 2>&1 || true
	else
		warn "no crontab on this machine; Nextcloud will use AJAX cron, which is slower"
	fi

	ok "Nextcloud is running"
	info "log in at  http://$(guess_host)/  as admin"
	if in_container; then
		info "from outside, use the address and port the panel published for port 80"
	fi
	show_note nextcloud
}

do_uninstall() {
	warn "this removes the Nextcloud program and its database."
	warn "$NC_DATA — everybody's files — is deliberately left behind."

	# Default site back and reloaded before anything is deleted; nginx's
	# reload is asynchronous and the draining worker would otherwise answer
	# from a document root that has gone.
	rm -f "$(nginx_conf_dir)/app-setup-nextcloud.conf"
	if have nginx && [ ! -f "$(nginx_conf_dir)/app-setup.conf" ]; then
		mkdir -p "$WEBROOT"
		php_nginx_site "$WEBROOT" > "$(nginx_conf_dir)/app-setup.conf"
		nginx_test_reload || true
	fi
	( crontab -u "$(web_user)" -l 2>/dev/null | grep -v 'nextcloud/cron.php' ) |
		crontab -u "$(web_user)" - 2>/dev/null || true

	if mysql_wait 2>/dev/null; then
		step "dropping the $NC_DB database"
		db_mysql_drop "$NC_DB" "$NC_USER"
	else
		warn "MariaDB is not running, so the $NC_DB database is still there"
	fi

	rm -rf "$NC_ROOT"
	drop_note nextcloud
	warn "the files are still in $NC_DATA. Remove them yourself if you mean it:"
	warn "  rm -rf $NC_DATA"
	ok "Nextcloud is gone"
}

do_start()   { svc_start nginx || true; svc_start "$(php_service)" || true; svc_start mariadb || true; ok "started"; }
do_stop()    { svc_stop nginx; svc_stop "$(php_service)"; svc_stop mariadb; ok "stopped"; }
do_enable()  { svc_enable nginx; svc_enable "$(php_service)"; svc_enable mariadb; ok "it comes back at boot"; }
do_disable() { svc_disable nginx; svc_disable "$(php_service)"; svc_disable mariadb; ok "it will not come back at boot"; }

do_status() {
	is_installed || exit 2
	_php="$(php_service)"
	_down=""
	svc_running nginx   || _down="$_down nginx"
	svc_running "$_php" || _down="$_down php-fpm"
	svc_running mariadb || _down="$_down mariadb"

	if [ -z "$_down" ]; then echo "detail=$(version_line)"
	else                     echo "detail=down:$_down"; fi
	if svc_enabled nginx; then echo "enabled=1"; else echo "enabled=0"; fi

	[ -z "$_down" ] && exit 0
	[ "$_down" = " nginx php-fpm mariadb" ] && exit 1
	exit 3
}

# -------------------------------------------------------------- dump/load --
# The database only. The files are what `backup` adds on top — a .sql on its
# own is the thing people want before an upgrade, and it is small enough to
# keep several of.
do_dump() {
	local _f
	_f="$(dump_target nextcloud sql "${1-}")"
	step "dumping the $NC_DB database"
	mysql_dump_db "$NC_DB" "$_f"
	chmod 600 "$_f"
	ok "$_f  ($(du -h "$_f" 2>/dev/null | awk '{print $1}'))"
	info "put it back with:  app-setup load nextcloud"
	info "this is the database only; app-setup backup nextcloud takes the files too"
}

do_load() {
	local _f
	_f="$(dump_source nextcloud sql "${1-}")"
	step "loading $_f"
	warn "this replaces the $NC_DB database"
	mysql_load_file "$_f"
	ok "loaded"
}

# ------------------------------------------------------------------ backup --
# Maintenance mode, not a stopped web server: Nextcloud's own way of saying
# "no writes right now" keeps the database and the file tree agreeing with each
# other, which is the pair that actually has to be consistent. Without it a
# user uploading during the backup lands a row in oc_filecache pointing at a
# file that is not in the archive.
#
# The data directory is the one that can be enormous. It is copied because a
# Nextcloud database without its files restores to a list of everything the
# user has lost; if that is too much for this machine, back the two up
# separately and say so — do not quietly ship half.
do_backup() {
	local _maint
	bk_begin nextcloud
	is_installed || die "Nextcloud is not installed here"
	_maint=""
	if occ maintenance:mode --on >/dev/null 2>&1; then
		_maint=1
		info "maintenance mode on — the site says 'be right back' until this finishes"
	else
		warn "could not enter maintenance mode; backing up a live site anyway"
	fi

	bk_mysql_db "$NC_DB"
	step "copying $NC_ROOT"
	bk_add "$NC_ROOT"
	step "copying $NC_DATA — this is the big one"
	bk_add "$NC_DATA"

	[ -n "$_maint" ] && occ maintenance:mode --off >/dev/null 2>&1
	bk_finish
}

do_restore() {
	local _d
	bk_open nextcloud "${1-}"
	_d="$BK_UNPACKED"
	bk_mysql_load "$_d"
	occ maintenance:mode --on >/dev/null 2>&1 || true
	if [ -d "$_d/files$NC_ROOT" ] || [ -d "$_d/files$NC_DATA" ]; then
		step "putting the files back"
		[ -d "$NC_ROOT" ] && mv "$NC_ROOT" "$NC_ROOT.before-restore.$(date -u +%Y%m%d%H%M%S)"
		[ -d "$NC_DATA" ] && mv "$NC_DATA" "$NC_DATA.before-restore.$(date -u +%Y%m%d%H%M%S)"
		bk_restore_files "$_d"
		chown -R "$(web_user)":"$(web_group)" "$NC_ROOT" "$NC_DATA" 2>/dev/null || true
		chmod 750 "$NC_DATA" 2>/dev/null || true
	fi
	occ maintenance:mode --off >/dev/null 2>&1 || true
	# The file cache is a database table describing a directory tree. Restoring
	# both from the same archive keeps them in step, but a scan costs nothing
	# and is the difference between "my files are gone" and "there they are".
	step "rescanning files"
	occ files:scan --all >/dev/null 2>&1 || warn "occ files:scan failed — run it yourself once the site is up"
	bk_close
	ok "Nextcloud restored"
}

do_help() { cat <<'EOF'
Nextcloud

  What you have
    File sync and share, on your own disk. Desktop clients for Windows,
    macOS and Linux, apps for iOS and Android, camera roll backup, calendar
    and contacts over CalDAV/CardDAV, and a web interface for the rest.

  Logging in
    cat /etc/app-setup/secrets/nextcloud.txt   the admin password
    The account is `admin`. Change the password after the first login.

  "Access through untrusted domain"
    This is the message you get when the address you typed is not on
    Nextcloud's list, and it is deliberate — it is what stops a forged Host
    header from stealing password resets. Add yours:

      cd /var/www/nextcloud
      sudo -u www-data php occ config:system:set trusted_domains 4 --value=cloud.example.com

    (The user is www-data on Debian and Ubuntu, nginx or apache on
    AlmaLinux, nginx on Alpine. `stat -c %U /var/www/nextcloud` says which.)
    The number is just a slot; use one that is not taken. `occ
    config:system:get trusted_domains` lists them.

  Behind the panel's HTTPS
    TLS ends at the host, and the request arrives here as plain http. Until
    you tell Nextcloud that, it writes http:// links into pages served over
    https and browsers block them:

      occ config:system:set overwriteprotocol --value=https

    Do that only once the site really is reached over https, or you get a
    redirect loop instead.

  Where the files are
    /var/lib/nextcloud-data     everybody's uploads. Not under the web root,
                                on purpose — a web server misconfiguration
                                in front of it would hand out every file.
    /var/www/nextcloud          the program
    /var/www/nextcloud/config/config.php    all the settings above

  Backing it up
    Three parts, and you need all three:
      occ maintenance:mode --on
      mysqldump --single-transaction nextcloud > /data/nextcloud.sql
      tar -czf /data/nextcloud-data.tar.gz /var/lib/nextcloud-data
      cp /var/www/nextcloud/config/config.php /data/
      occ maintenance:mode --off

    /data is the only path that survives a reinstall of this container.

  Background jobs
    A cron entry runs cron.php every five minutes as the web user. It is
    what makes deleted files expire, previews generate and sync scale. If
    the admin page says jobs are not running:
      crontab -u www-data -l

  Upgrading
    Use the built-in updater from Administration → Overview, one major
    release at a time — 28 to 29 to 30, never 28 to 30. Take the backup
    above first; the updater does not.

  When it feels slow
    1. Memory caching is the big one. If php-apcu was installed, turn it on:
         occ config:system:set memcache.local --value='\OC\Memcache\APCu'
    2. Then Redis for file locking, if you install the redis card:
         occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
         occ config:system:set redis host --value=127.0.0.1
         occ config:system:set redis port --value=6379 --type=integer
    3. Turn off the apps you do not use. Each one runs on every request.

  Honest note on size
    Nextcloud plus MariaDB plus PHP wants about 1GB of memory to be
    comfortable and 2GB of disk before a single file is uploaded. On a
    512MB container it will install, log in, and then be killed the first
    time somebody uploads a folder. If that is the machine you have, this
    is the wrong card.

  Uninstalling
    Removes the program and drops the database. /var/lib/nextcloud-data is
    left alone — that is everybody's files, and no uninstall should decide
    to delete those.
EOF
}

app_main "$@"
