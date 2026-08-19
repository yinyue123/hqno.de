#!/bin/sh
# app-setup: 1
# id: aapanel
# name: aaPanel (BT)
# name.zh: 宝塔面板 aaPanel
# category: stack
# order: 20
# summary: The web control panel a lot of people expect. It installs its own nginx, MySQL and PHP and manages them itself — it does not share a machine.
# summary.zh: 很多人习惯的网页控制面板。它会自己装一套 nginx、MySQL、PHP 并自行管理——不能和本机已装的共存。
# includes: the aaPanel/宝塔 daemon, its own web stack under /www, a login on port 8888
# includes.zh: aaPanel/宝塔 服务端、装在 /www 下的整套环境、8888 端口的管理后台
# disk: 3G
# memory: 1G
# ports: 8888, 80, 443, 888, 3306
# service: bt
. /usr/lib/app-setup/common.sh

BT_HOME=/www/server/panel
SERVICE="bt"

# ------------------------------------------------------------------ backup --
# Deliberately not implemented, and saying so beats the generic message. aaPanel
# owns /www entirely — its own MySQL, its own sites, its own users — and it
# ships its own backup with its own schedule and its own idea of where things
# go. A second scheduler copying the same files underneath it would be two
# tools disagreeing about one directory, which is how you end up with an
# archive that restores into a panel that has moved on.
do_backup() {
	info "aaPanel backs itself up: open the panel, then 计划任务 / Cron, and add"
	info "a backup task. It knows its own sites and databases; app-setup does not."
	info "Nothing under /www is managed here — see: app-setup docs aapanel"
	return 0
}
do_dump() { do_backup; }

version_line() {
	_v="$(cat "$BT_HOME/class/common.py" 2>/dev/null | awk -F"'" '/g.version *=/ {print $2; exit}')"
	[ -n "$_v" ] || _v="$(cat /www/server/panel/data/version.pl 2>/dev/null)"
	printf 'aaPanel %s, admin on port %s' "${_v:-?}" "$(cat "$BT_HOME/data/port.pl" 2>/dev/null || echo 8888)"
}

is_installed() { [ -f "$BT_HOME/BT-Panel" ] || [ -f "$BT_HOME/tools.py" ]; }

# It never learned to run on musl, and it will not: the installer fetches
# glibc-linked binaries and a Python build that has no Alpine equivalent.
# Saying so here is better than a twenty-minute install that ends in a
# segfault somebody has to read a Chinese forum to understand.
preflight() {
	case "$PMF" in
		deb|rpm) : ;;
		*) die "aaPanel does not run on this system. It supports Debian, Ubuntu, CentOS, AlmaLinux and Rocky only — Alpine's musl is not one of them. Use the LNMP card instead; it does the same job with the packages this system already has." ;;
	esac

	[ "$INIT" = none ] && warn "no init system here; the panel will not come back after a restart"

	_mem="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
	if [ "${_mem:-9999}" -lt 900 ] 2>/dev/null; then
		warn "this machine has ${_mem}MB of memory. aaPanel's own recommendation is 1GB,"
		warn "and that is before the nginx, MySQL and PHP it installs on top."
	fi

	# The real trap. aaPanel builds its own stack into /www and binds the same
	# ports; a machine that already runs ours ends up with two nginxes, one of
	# which silently fails to start, and the panel then reports it as broken.
	_clash=""
	svc_running nginx   2>/dev/null && _clash="$_clash nginx"
	svc_running mariadb 2>/dev/null && _clash="$_clash mariadb"
	svc_running apache2 2>/dev/null && _clash="$_clash apache2"
	svc_running httpd   2>/dev/null && _clash="$_clash httpd"
	if [ -n "$_clash" ]; then
		err "these are already running here:$_clash"
		err "aaPanel installs and manages its own copies of them and will fight with these."
		err "Remove them first — their cards have an uninstall — or install aaPanel on a"
		err "fresh container. Set APP_SETUP_FORCE=1 to do it anyway."
		[ -n "${APP_SETUP_FORCE:-}" ] || exit 1
		warn "APP_SETUP_FORCE is set; carrying on. You are on your own from here."
	fi
}

do_install() {
	preflight
	ensure_downloader

	# aaPanel is the international build of 宝塔, from the same people. It is
	# the default because it installs unattended and needs no account; the
	# bt.cn build wants a Chinese phone number bound to it before the panel
	# will do anything.
	_ed="${APP_SETUP_BT_EDITION:-intl}"
	_tmp="$(tmp_dir)"

	case "$_ed" in
	cn)
		step "downloading the bt.cn installer"
		fetch "https://download.bt.cn/install/install_lts.sh" "$_tmp/install.sh" ||
			{ rm -rf "$_tmp"; die "download.bt.cn did not answer"; }
		# The trailing token is the vendor's own "yes I meant it" argument and
		# it changes between their releases. APP_SETUP_BT_KEY overrides it if
		# theirs has moved on; the current one is printed on bt.cn's front page.
		_arg="${APP_SETUP_BT_KEY:-ed8484bec}"
		;;
	*)
		step "downloading the aaPanel installer"
		fetch "https://www.aapanel.com/script/install_7.0_en.sh" "$_tmp/install.sh" ||
		fetch "https://www.aapanel.com/script/install_6.0_en.sh" "$_tmp/install.sh" ||
			{ rm -rf "$_tmp"; die "aapanel.com did not answer"; }
		_arg="aapanel"
		;;
	esac

	step "running the vendor's installer — this takes 10 to 30 minutes"
	info "it compiles its own nginx, MySQL and PHP. Nothing here can make that faster."
	# `yes |` because the script asks for a y/n it will otherwise block on
	# forever under the TUI, where there is no keyboard attached to it.
	yes y 2>/dev/null | sh "$_tmp/install.sh" "$_arg" || {
		rm -rf "$_tmp"
		die "the aaPanel installer failed. Its own log is /tmp/panelBoot.pl, and it is more specific than anything this recipe can say."
	}
	rm -rf "$_tmp"

	is_installed || die "the installer finished but $BT_HOME is not there. Read /tmp/panelBoot.pl."

	svc_enable bt 2>/dev/null || true
	svc_start  bt 2>/dev/null || true

	# The installer prints the login once, at the end of a very long scroll,
	# and it is the one thing anybody needs from all of it.
	_port="$(cat "$BT_HOME/data/port.pl" 2>/dev/null || echo 8888)"
	# The random "entry path" is the panel's main defence against a bot that
	# found the port, so it is worth writing down rather than rediscovering.
	_path="$(cat "$BT_HOME/data/admin_path.pl" 2>/dev/null || true)"
	save_note aapanel <<EOF
aaPanel / 宝塔面板

  address     http://$(guess_host):${_port}${_path}
  username    printed by the installer above, and recoverable with:
                bt default
  password    same — \`bt default\` prints the current login

  Useful commands
    bt              the menu: change the port, the password, the entry path
    bt default      print the current login details
    bt 5            reset the password
    bt stop / start / restart

  Ports it wants published for anything to work from outside:
    ${_port}   the panel itself
    80, 443    the sites it hosts
    888        phpMyAdmin, if you install it from inside the panel
    3306       MySQL, only if you really mean to expose it

  Its entire world is /www. Nothing app-setup installs goes there, and
  nothing in there is managed by app-setup.
EOF

	ok "aaPanel is installed"
	info "run  bt default  to see the login. It is not stored anywhere else."
	if in_container; then
		warn "port $_port has to be published by the panel before you can reach this"
		warn "from your laptop — a container's 8888 is not the host's 8888."
	fi
	show_note aapanel
}

do_uninstall() {
	warn "this runs aaPanel's own uninstaller, which removes /www — the panel,"
	warn "every site it hosts, and its MySQL data directory."

	if [ -f "$BT_HOME/install/uninstall.sh" ]; then
		yes y 2>/dev/null | sh "$BT_HOME/install/uninstall.sh" || warn "its uninstaller reported a problem; cleaning up what is left"
	fi

	svc_stop bt 2>/dev/null || true
	svc_disable bt 2>/dev/null || true
	rm -f /etc/init.d/bt /usr/bin/bt
	rm -f /etc/systemd/system/bt.service
	[ "$INIT" = systemd ] && systemctl daemon-reload 2>/dev/null || true

	if [ -d /www ]; then
		warn "/www is still on disk. It holds the sites and databases it managed."
		warn "Remove it yourself if you mean it:  rm -rf /www"
	fi
	drop_note aapanel
	ok "aaPanel is gone"
}

do_status() {
	is_installed || exit 2
	_port="$(cat "$BT_HOME/data/port.pl" 2>/dev/null || echo 8888)"
	if svc_running bt || pgrep -f 'BT-Panel|BT-Task' >/dev/null 2>&1; then
		echo "detail=$(version_line)"
		if svc_enabled bt; then echo "enabled=1"; else echo "enabled=0"; fi
		exit 0
	fi
	echo "detail=installed, panel not running — port $_port"
	if svc_enabled bt; then echo "enabled=1"; else echo "enabled=0"; fi
	exit 1
}

do_help() { cat <<'EOF'
aaPanel / 宝塔面板

  Read this part first
    This is not like the other cards. aaPanel is a control panel: it wants
    to own the machine. It downloads and builds its own nginx, MySQL, PHP
    and FTP server into /www, manages them with its own service scripts,
    and expects nothing else to be touching them.

    So it does not share. If you have installed LNMP, nginx, or MariaDB
    from this catalogue, remove those first, or put aaPanel on a fresh
    container. Installing it alongside them gives you two web servers
    fighting over port 80, and the one that loses fails quietly.

    It is also closed source, made by a company in China, and it talks to
    their servers — for updates, for the plugin store, and for the account
    the bt.cn build requires. That is a reasonable trade for a lot of
    people and a dealbreaker for others. It should be your decision rather
    than a surprise.

  Which build you got
    The international one, aapanel.com, unless you asked otherwise. It
    installs unattended and needs no account.

    For the bt.cn build instead, uninstall and reinstall with:
      APP_SETUP_BT_EDITION=cn app-setup install aapanel
    It requires binding a Chinese phone number before the panel will do
    much of anything. If their install token has changed, the front page of
    bt.cn shows the current one:
      APP_SETUP_BT_EDITION=cn APP_SETUP_BT_KEY=xxxxxxx app-setup install aapanel

  Logging in
    bt default        prints the address, the username and the password

    The installer prints these once, at the end of twenty minutes of build
    output. `bt default` is how you get them back. They are not stored by
    app-setup, because the panel changes them itself.

  The bt command
    bt              a numbered menu for everything below
    bt default      show the login
    bt 5            reset the password
    bt 6            reset the username
    bt 8            change the port
    bt stop | start | restart | reload
    bt 22           turn off the "entry path" if you have locked yourself out

  Reaching it from outside this container
    The panel listens on 8888 inside the container. That is not the host's
    8888. Publish the port from the hqnode panel first — and publish 80 and
    443 too, or the sites it hosts are unreachable even when the panel
    itself works.

    If the panel loads but every site 404s, that is almost always this:
    port 80 was never published.

  Security, briefly
    The default configuration puts an admin login on a public port. Before
    you announce the address:
      1. `bt 8` — move it off 8888, which is scanned constantly.
      2. `bt 22` — keep the random entry path. It is the main thing
         standing between the panel and a bot that found the port.
      3. Use a real password. `bt 5` sets one.
      4. Do not publish 3306 unless something outside genuinely needs it.

  Where everything lives
    /www/server/panel     the panel itself
    /www/server/nginx     its nginx, not the system one
    /www/server/mysql     its MySQL, and its data
    /www/wwwroot          the sites it hosts
    /www/backup           its backups, on the same disk as the original,
                          which is not a backup — copy them to /data

  Backing it up
    The panel's own backup writes into /www/backup, which disappears with
    the container. /data is the only path that survives a reinstall:
      tar -czf /data/www-backup.tar.gz /www/wwwroot /www/backup

  If you would rather not
    The LNMP card does the same job with this system's own packages: no
    twenty-minute build, no second copy of nginx, no account, about 600MB
    instead of 3GB, and everything in the places the rest of the internet's
    instructions assume. What you give up is the web interface.

  Uninstalling
    Runs aaPanel's own uninstaller. /www is left on disk afterwards,
    because it holds the sites and the databases, and no uninstall should
    decide to delete those for you.
EOF
}

app_main "$@"
