#!/bin/sh
# app-setup: 1
# id: store-ftp
# name: FTP / FTPS
# name.zh: FTP / FTPS
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 13
# summary: Where backups go: the FTP space a cheap host gives you. Encrypted if the server will take it.
# summary.zh: 备份存到哪：便宜主机送的那个 FTP 空间。服务器支持的话就加密传。
# includes: rclone, with curl as the fallback, and a five-step connection test
# includes.zh: rclone，装不上时退回 curl，以及一个五步的连接测试
# disk: 60M
# memory: 64M
# requires: an FTP account that can create a folder and delete a file
# requires.zh: 一个能建目录、能删文件的 FTP 账号
# param: host     |          | Host        | 主机     |
# param: port     | 21       | Port        | 端口     | number
# param: user     |          | User        | 用户名   |
# param: password |          | Password    | 密码     |
# param: path     | /backups | Base folder | 根目录   |
# param: tls      | on       | FTPS        | 加密传输 | bool
# button: test | ✓ Test connection | ✓ 测试连接
#
# The one a cheap host gives you, and the reason it is here at all: a great
# many hosting accounts come with FTP space and nothing else, and an off-machine
# copy on a protocol nobody likes is worth a great deal more than no off-machine
# copy at all.
#
# `tls` defaults on. FTP without it sends the password and every byte of the
# archive in clear, and a recipe that finds it off says so in one sentence
# rather than leaving it to be discovered.
. /usr/lib/app-setup/common.sh

STORE=store-ftp

PKGS="rclone"
PKGS_apk="rclone"
PKGS_rpm="rclone"

ftp_rclone() {
	RCLONE_CONFIG_BK_TYPE=ftp \
	RCLONE_CONFIG_BK_HOST="$(param host)" \
	RCLONE_CONFIG_BK_PORT="$(param port 21)" \
	RCLONE_CONFIG_BK_USER="$(param user)" \
	RCLONE_CONFIG_BK_PASS="$(rclone obscure "$(param password)" 2>/dev/null)" \
	RCLONE_CONFIG_BK_EXPLICIT_TLS="$(param_on tls on && echo true || echo false)" \
	rclone "$@"
}

# The curl fallback, for a machine where rclone is not in the repos. --ssl-reqd
# rather than --ssl: the first refuses to continue in the clear when the server
# will not negotiate TLS, and the second quietly does — which turns the FTPS
# switch into a suggestion.
ftp_curl() {
	curl -sS --fail-with-body \
		--user "$(param user):$(param password)" \
		$(param_on tls on && printf '%s' --ssl-reqd) \
		"$@"
}

ftp_base() { local _p; _p="$(param path /backups)"; printf '%s' "${_p%/}"; }

ftp_url() {  # ftp_url [folder] [name]
	local _u
	_u="ftp://$(param host):$(param port 21)$(ftp_base)"
	[ -n "${1-}" ] && _u="$_u/$1"
	[ -n "${2-}" ] && _u="$_u/$2"
	printf '%s' "$_u"
}

ftp_path() { # ftp_path [folder]
	printf '%s' "$(ftp_base)${1:+/$1}"
}

ftp_configured() { [ -n "$(param host)" ] && [ -n "$(param user)" ]; }

ftp_have() {
	have rclone && return 0
	have curl   && return 0
	err "neither rclone nor curl is here — run: app-setup install store-ftp"
	return 1
}

# ------------------------------------------------------------- the verbs --
# MKD creates exactly one directory and fails if the parent is missing, so this
# walks the levels. "Already exists" is 550 and is success here — the second
# night's backup would fail on it otherwise, every night, forever.
do_mkdir() {  # do_mkdir <folder>
	local _p _acc
	ftp_have || return 1
	_acc=""
	# shellcheck disable=SC2086
	for _p in $(printf '%s' "$1" | tr '/' ' '); do
		_acc="${_acc:+$_acc/}$_p"
		if have rclone; then
			ftp_rclone mkdir "BK:$(ftp_path "$_acc")" >/dev/null 2>&1 || true
		else
			# -Q sends a raw command; the URL it is attached to is only there
			# to say which server. A 550 back is "it is already there".
			ftp_curl -Q "MKD $(ftp_path "$_acc")" "ftp://$(param host):$(param port 21)/" \
				>/dev/null 2>&1 || true
		fi
	done
	# Proved by looking, because both tools above swallow the harmless failure
	# and the harmful one at the same time.
	if have rclone; then
		ftp_rclone lsd "BK:$(ftp_path "$1")" >/dev/null 2>&1 ||
			{ err "could not create $(ftp_path "$1") — can this account make folders?"; return 1; }
	else
		ftp_curl -l "$(ftp_url "$1")/" >/dev/null 2>&1 ||
			{ err "could not create $(ftp_path "$1") — can this account make folders?"; return 1; }
	fi
	return 0
}

do_put() {    # do_put <folder> <localfile>
	ftp_have || return 1
	do_mkdir "$1" || return 1
	if have rclone; then
		ftp_rclone copy "$2" "BK:$(ftp_path "$1")" || { err "upload failed"; return 1; }
	else
		ftp_curl -T "$2" "$(ftp_url "$1")/" >/dev/null || { err "upload failed"; return 1; }
	fi
}

do_get() {    # do_get <folder> <name> <localfile>
	ftp_have || return 1
	if have rclone; then
		ftp_rclone copyto "BK:$(ftp_path "$1")/$2" "$3" ||
			{ err "could not fetch $2"; return 1; }
	else
		ftp_curl -o "$3" "$(ftp_url "$1" "$2")" || { err "could not fetch $2"; return 1; }
	fi
}

# Bare names, one per line, sorted. `curl -l` is NLST, which already returns
# bare names — except on the servers that answer with full paths, so the tail
# is taken either way.
do_ls() {     # do_ls <folder>
	ftp_have || return 1
	if have rclone; then
		ftp_rclone lsf "BK:$(ftp_path "$1")" 2>/dev/null | grep -v '/$'
	else
		ftp_curl -l "$(ftp_url "$1")/" 2>/dev/null | sed 's#.*/##'
	fi | grep -v '^$' | sort
}

do_rm() {     # do_rm <folder> <name>
	case "$2" in
		''|*/*|.|..) err "refusing to delete '$2' — a bare filename only"; return 1 ;;
	esac
	ftp_have || return 1
	if have rclone; then
		ftp_rclone deletefile "BK:$(ftp_path "$1")/$2" 2>/dev/null
	else
		ftp_curl -Q "DELE $(ftp_path "$1")/$2" "ftp://$(param host):$(param port 21)/" \
			>/dev/null 2>&1
	fi
}

bk_probe_cleanup() {
	if have rclone; then ftp_rclone purge "BK:$(ftp_path "$1")" >/dev/null 2>&1 || true
	else ftp_curl -Q "RMD $(ftp_path "$1")" "ftp://$(param host):$(param port 21)/" \
		>/dev/null 2>&1 || true; fi
}

do_test() {
	bk_unbless "$STORE"
	ftp_configured || die "no host or user yet. Fill in Settings first."
	ftp_have || return 1
	if ! param_on tls on; then
		warn "FTPS is off, so the password and every byte of every backup cross"
		warn "the network in clear. Turn it on unless the server refuses it."
	fi
	have rclone || warn "rclone is not here — using curl, which is slower and does not checksum."
	bk_probe "$STORE" "$(param host):$(param port 21)$(ftp_base)"
}

# ------------------------------------------------------------------ state --
is_installed() { ftp_configured; }

do_status() {
	is_installed || exit 2
	bk_store_card "$STORE" "$(param user)@$(param host)$(ftp_base)$(param_on tls on || printf ' (no TLS)')"
}

do_install() {
	step "installing an FTP client"
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
	if ! ftp_configured; then
		warn "no host yet. Open Settings, fill in the host, user and password,"
		warn "then press ✓ Test connection."
	else
		do_test || warn "fix the above, then press ✓ Test connection again"
	fi
	save_note "$STORE" <<EOF
Backup destination — FTP

  host        $(param host):$(param port 21)
  user        $(param user)
  base folder $(ftp_base)
  FTPS        $(param_on tls on && echo on || echo 'OFF — everything crosses the network in clear')

  Point a backup at it:
    app-setup set backup store=ftp
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
FTP / FTPS 备份存储源

  它是什么
    把打包好的备份传到 FTP 空间上 —— 便宜主机、老 NAS、虚拟主机送的那种。
    这是六个里最弱的一个，但**一份传到机器外面的备份，比没有强得多**。

  怎么配
    主机 / 端口   端口默认 21
    用户名 / 密码
    根目录        默认 /backups。很多虚拟主机会把你锁在自己的家目录里，
                  那就填一个相对的名字，比如 backups
    加密传输      默认开。开着的时候用 FTPS（AUTH TLS，显式加密）

  加密传输这一项
    关掉的话，密码和备份里的每一个字节都是明文过网络的 —— 也就是说，
    路上任何一跳都能读到你的整个数据库。只有在服务器确实不支持的时候
    才关它，而且知道自己在换什么。

  测试连接做了什么
    建目录 → 写文件 → 列目录 → 读回来比对 → 删掉。五步，因为每一步都会
    单独失败。FTP 上最常见的是：登进去了，落在一个你写不了的目录里；
    或者能写文件、但不能建子目录；或者能上传、不能删 —— 最后这个要到
    一个月后第一次清理旧文件时才会发现。

  用它
    app-setup set backup store=ftp
    app-setup backup mysql
EOF
	else
		cat <<EOF
FTP / FTPS backup destination

  What it is
    Sends packed backups to FTP space — a cheap host, an old NAS, the storage
    that came with a shared hosting account. It is the weakest of the six, and
    **a copy that is off this machine beats no copy by a very long way.**

  Setting it up
    Host / Port   21 unless they moved it
    User / Password
    Base folder   /backups by default. Plenty of shared hosts drop you into
                  your own home directory and go no higher — put a relative
                  name like \`backups\` in that case
    FTPS          on by default; explicit TLS (AUTH TLS)

  About that FTPS switch
    With it off, the password and every byte of every backup cross the network
    in clear — which means every hop between here and there can read your
    whole database. Turn it off only when the server genuinely will not do TLS,
    and know what you are trading.

  What Test connection does
    Makes a folder, writes a file into it, lists it, reads it back and
    compares the bytes, then deletes it. Five steps because each one fails on
    its own, and FTP fails in all five ways: an account that logs in and lands
    somewhere it cannot write, one that can write files but not create a
    folder, one that can upload and not delete — and that last one is not
    discovered until the first prune, a month later, on a timer, in a log
    nobody opens.

  Using it
    app-setup set backup store=ftp
    app-setup backup mysql
EOF
	fi
}

app_main "$@"
