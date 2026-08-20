#!/bin/sh
# app-setup: 1
# id: store-webdav
# name: WebDAV
# name.zh: WebDAV
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 12
# summary: Where backups go: a Nextcloud, an ownCloud, a Synology, 坚果云 — anything with a WebDAV URL.
# summary.zh: 备份存到哪：Nextcloud、ownCloud、群晖、坚果云 —— 任何给得出 WebDAV 地址的地方。
# includes: rclone, with curl as the fallback, and a five-step connection test
# includes.zh: rclone，装不上时退回 curl，以及一个五步的连接测试
# disk: 60M
# memory: 64M
# requires: a WebDAV URL and an account that may create folders under it
# requires.zh: 一个 WebDAV 地址，以及一个能在下面建目录的账号
# param: url      |       | WebDAV URL | WebDAV 地址 |
# param: user     |       | User       | 用户名 |
# param: password |       | Password   | 密码   |
# param: vendor   | other | Server     | 服务端 | other,nextcloud,owncloud,sharepoint
# button: test | ✓ Test connection | ✓ 测试连接
#
# A store answers five questions about a remote directory and nothing else:
# make this folder, put this file in it, get that one back, what is in there,
# delete that one.
#
# This is the first of the six where "make this folder" is real work. On S3
# there are no directories and do_mkdir succeeds by doing nothing; here a
# collection is an object that has to exist before a file can be written into
# it, one level at a time — and creating one that already exists must not be an
# error, or the second night's backup fails on it and every night after that.
. /usr/lib/app-setup/common.sh

STORE=store-webdav

PKGS="rclone"
PKGS_apk="rclone"
PKGS_rpm="rclone"

# `vendor` is not decoration: rclone's WebDAV backend changes how it checksums
# and how it moves files per vendor, and a Nextcloud configured as `other`
# uploads fine and then fails to verify.
#
# RCLONE_CONFIG=/dev/null for the reason store-s3.sh gives at the same line:
# the configuration is these variables and nothing else, and a missing
# ~/.config/rclone/rclone.conf is not news anybody needs in the middle of a
# backup.
dav_rclone() {
	RCLONE_CONFIG=/dev/null \
	RCLONE_CONFIG_BK_TYPE=webdav \
	RCLONE_CONFIG_BK_URL="$(param url)" \
	RCLONE_CONFIG_BK_VENDOR="$(param vendor other)" \
	RCLONE_CONFIG_BK_USER="$(param user)" \
	RCLONE_CONFIG_BK_PASS="$(rclone obscure "$(param password)" 2>/dev/null)" \
	rclone "$@"
}

# The curl fallback exists because curl is in `essentials` and rclone is not in
# a RHEL rebuild's base repos. A machine that cannot install rclone can still
# push to WebDAV — slower, without checksums — and the recipe says which of the
# two it used rather than leaving somebody to guess.
dav_curl() {
	curl -sS --fail-with-body -u "$(param user):$(param password)" "$@"
}

dav_url() {  # dav_url [folder] [name]
	local _u
	_u="$(param url)"
	_u="${_u%/}"
	[ -n "${1-}" ] && _u="$_u/$1"
	[ -n "${2-}" ] && _u="$_u/$2"
	printf '%s' "$_u"
}

# A collection is addressed with a trailing slash, and the servers this card
# exists for enforce it: Apache's mod_dav — which is what a Synology, a
# Nextcloud and most of the rest are underneath — answers any method aimed at
# a collection *without* the slash with a 301 to the URL that has one. curl
# does not follow redirects and must not be told to, so both places that name
# a folder rather than a file say so in the URL.
#
# It failed silently in both, which is why it survived: the PROPFIND returned
# nothing and read as an empty directory — so a backup uploaded fine and then
# could not be listed, verified or restored — and the probe's DELETE did
# nothing, leaving a .app-setup-probe-* folder on the server for every
# connection test anybody ever pressed. Only on machines where rclone would
# not install, which is the half of this recipe nobody runs.
dav_dir_url() {  # dav_dir_url <folder>
	printf '%s/' "$(dav_url "$1")"
}

dav_configured() { [ -n "$(param url)" ] && [ -n "$(param user)" ]; }

dav_have() {
	have rclone && return 0
	have curl   && return 0
	err "neither rclone nor curl is here — run: app-setup install store-webdav"
	return 1
}

# ------------------------------------------------------------- the verbs --
# One level at a time, because MKCOL creates exactly one collection and fails
# with 409 Conflict if its parent is missing — which is what a folder of
# `web01/backup-mysql` is every first time.
#
# "Already exists" is swallowed and nothing else is. A 405 on MKCOL means the
# collection is there, which is success; a 401 or a 403 means the account
# cannot create it, which is a real failure that a 2>/dev/null would throw away
# along with the first one.
do_mkdir() {  # do_mkdir <folder>
	local _p _acc _rc
	dav_have || return 1
	_acc=""
	# shellcheck disable=SC2086  # splitting the folder on / is the point
	for _p in $(printf '%s' "$1" | tr '/' ' '); do
		_acc="${_acc:+$_acc/}$_p"
		if have rclone; then
			dav_rclone mkdir "BK:$_acc" >/dev/null 2>&1 || true
		else
			_rc=0
			dav_curl -X MKCOL "$(dav_url "$_acc")" >/dev/null 2>&1 || _rc=$?
			# curl exits 22 on any 4xx with --fail; ask what the code was
			# rather than treating every 4xx as the harmless one.
			if [ "$_rc" != 0 ]; then
				case "$(dav_curl -o /dev/null -w '%{http_code}' -X MKCOL "$(dav_url "$_acc")" 2>/dev/null)" in
					405|301|302) : ;;   # it is already there
					*) err "could not create $_acc on the server"; return 1 ;;
				esac
			fi
		fi
	done
	# rclone swallows its own errors above, so the folder is proved by looking
	# for it rather than by trusting an exit code.
	if have rclone; then
		dav_rclone lsd "BK:$1" >/dev/null 2>&1 ||
			{ err "could not create $1 on the server — can this account make folders?"; return 1; }
	fi
	return 0
}

do_put() {    # do_put <folder> <localfile>
	dav_have || return 1
	do_mkdir "$1" || return 1
	if have rclone; then
		dav_rclone copy "$2" "BK:$1" || { err "upload failed"; return 1; }
	else
		dav_curl -T "$2" "$(dav_url "$1" "$(basename "$2")")" >/dev/null ||
			{ err "upload failed"; return 1; }
	fi
}

do_get() {    # do_get <folder> <name> <localfile>
	dav_have || return 1
	if have rclone; then
		dav_rclone copyto "BK:$1/$2" "$3" || { err "could not fetch $2"; return 1; }
	else
		dav_curl -o "$3" "$(dav_url "$1" "$2")" || { err "could not fetch $2"; return 1; }
	fi
}

# Bare names, one per line, sorted — the same strings a local directory gives.
# The curl side is a PROPFIND with Depth 1, whose <d:href> values are
# URL-encoded paths; the tail after the last slash, percent-decoded, is the
# name. Depth 1 also returns the collection itself, which is the empty tail
# that gets dropped.
do_ls() {     # do_ls <folder>
	dav_have || return 1
	if have rclone; then
		dav_rclone lsf "BK:$1" 2>/dev/null | grep -v '/$' | sort
	else
		dav_curl -X PROPFIND -H 'Depth: 1' "$(dav_dir_url "$1")" 2>/dev/null |
			tr '<' '\n' | sed -n 's#^[dD]:\?href>##p' |
			sed 's#/$##; s#.*/##' |
			sed 's/%20/ /g; s/%2F/\//g' |
			grep -v '^$' | sort
	fi
}

do_rm() {     # do_rm <folder> <name>
	case "$2" in
		''|*/*|.|..) err "refusing to delete '$2' — a bare filename only"; return 1 ;;
	esac
	dav_have || return 1
	if have rclone; then
		dav_rclone deletefile "BK:$1/$2" 2>/dev/null
	else
		dav_curl -X DELETE "$(dav_url "$1" "$2")" >/dev/null 2>&1
	fi
}

# The probe folder goes when the probe does, whether it passed or failed.
bk_probe_cleanup() {
	if have rclone; then dav_rclone purge "BK:$1" >/dev/null 2>&1 || true
	else dav_curl -X DELETE "$(dav_dir_url "$1")" >/dev/null 2>&1 || true; fi
}

do_test() {
	bk_unbless "$STORE"
	dav_configured || die "no URL or user yet. Fill in Settings first."
	dav_have || return 1
	if ! have rclone; then
		warn "rclone is not here — using curl, which is slower and does not checksum."
	fi
	case "$(param url)" in
		https://*) : ;;
		http://*)  warn "this URL is http, so the password and the backups both cross the network in clear." ;;
	esac
	bk_probe "$STORE" "$(param url)"
}

# ------------------------------------------------------------------ state --
is_installed() { dav_configured; }

do_status() {
	is_installed || exit 2
	bk_store_card "$STORE" "$(param url)"
}

do_install() {
	step "installing a WebDAV client"
	case "$PM" in dnf|yum) enable_epel ;; esac
	if have rclone; then
		ok "rclone is already here"
	elif pkg_install $(pmv PKGS); then
		ok "rclone installed"
	else
		ensure_downloader
		have curl || die "neither rclone nor curl could be installed here"
		warn "rclone would not install — falling back to curl. Uploads have no"
		warn "checksum and no resume; everything else works."
	fi
	chmod 600 "$APP_SETUP_CONF/params/$STORE.conf" 2>/dev/null || true
	if ! dav_configured; then
		warn "no URL yet. Open Settings, put in the WebDAV URL, the user and the"
		warn "password, pick the server kind, then press ✓ Test connection."
	else
		do_test || warn "fix the above, then press ✓ Test connection again"
	fi
	save_note "$STORE" <<EOF
Backup destination — WebDAV

  url         $(param url)
  user        $(param user)
  server      $(param vendor other)

  Point a backup at it:
    app-setup test store-webdav
    app-setup set backup store=webdav
    app-setup backup mysql
EOF
	ok "ready."
}

do_uninstall() {
	drop_note "$STORE"
	rm -f "$BK_STATE/$STORE.ok" "$BK_STATE/$STORE.state"
	info "nothing on the server was deleted."
}

do_help() {
	if lang_zh; then
		cat <<EOF
WebDAV 备份存储源

  它是什么
    把打包好的备份用 WebDAV 传到网盘或者 NAS 上。

  地址从哪来
    Nextcloud    https://你的域名/remote.php/dav/files/用户名/
    ownCloud     https://你的域名/remote.php/webdav/
    群晖         https://nas:5006/  （先在「WebDAV Server」套件里开）
    坚果云       https://dav.jianguoyun.com/dav/
                 密码用「应用密码」，不是登录密码

  服务端 这一项要选对
    rclone 会按不同服务端改校验方式和移动文件的方式。Nextcloud 配成 other
    是能传上去的 —— 然后校验会失败。有对应选项就选对应的那个。

  测试连接做了什么
    建目录 → 写文件 → 列目录 → 读回来比对 → 删掉。五步，因为每一步都会
    单独失败。特别是**建目录**：一个允许你往给定目录里写文件、但不允许你
    在下面建子目录的账号，是很常见的配置 —— 在根目录上测会通过，然后每次
    备份都会在第一步挂掉。所以它是在子目录里探测的。

  http 还是 https
    地址是 http 的话，密码和备份内容都是明文过网络的。局域网里的 NAS 也
    一样。能上 https 就上。

  装不上 rclone 的机器
    退回用 curl（MKCOL / PUT / PROPFIND / DELETE）。慢一些、没有校验和，
    但五个动作都能做。用了哪个，测试连接时会说。

  用它
    app-setup test store-webdav
    app-setup set backup store=webdav
    app-setup backup mysql
EOF
	else
		cat <<EOF
WebDAV backup destination

  What it is
    Sends packed backups over WebDAV to a cloud drive or a NAS.

  Where the URL comes from
    Nextcloud    https://your-host/remote.php/dav/files/USERNAME/
    ownCloud     https://your-host/remote.php/webdav/
    Synology     https://nas:5006/   (turn on the WebDAV Server package first)
    坚果云       https://dav.jianguoyun.com/dav/
                 use an app password, not your login password

  Get the Server field right
    rclone changes how it checksums and how it moves files per vendor. A
    Nextcloud configured as \`other\` uploads perfectly well and then fails to
    verify. If yours is in the list, pick it.

  What Test connection does
    Makes a folder, writes a file into it, lists it, reads it back and
    compares the bytes, then deletes it. Five steps because each one fails on
    its own — **making the folder** above all: an account that lets you write
    files into the directory it gave you and refuses to let you create one
    under it is a normal configuration, not an exotic one. Testing at the base
    would pass and then every backup would die at its first mkdir, so this
    probes inside a folder.

  http or https
    On an http URL the password and the backups both cross the network in
    clear. That is just as true of a NAS on the LAN. Use https where you can.

  On a machine where rclone will not install
    It falls back to curl — MKCOL, PUT, PROPFIND, DELETE. Slower, no
    checksums, and all five operations still work. Test connection says which
    one it used.

  Using it
    app-setup test store-webdav
    app-setup set backup store=webdav
    app-setup backup mysql
EOF
	fi
}

app_main "$@"
