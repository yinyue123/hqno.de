#!/bin/sh
# app-setup: 1
# id: store-scp
# name: SCP / SFTP
# name.zh: SCP / SFTP
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 15
# summary: Where backups go: a storage box with sshd on it and no rsync. Nothing but OpenSSH needed.
# summary.zh: 备份存到哪：一台只有 sshd、没有 rsync 的存储机器。只需要 OpenSSH。
# includes: an SSH key made for this, and a pinned host key
# includes.zh: 为此生成的 SSH 密钥、以及固定下来的主机指纹
# disk: 10M
# memory: 16M
# requires: an account on the far end that will accept a public key
# requires.zh: 对面机器上一个能接受公钥登录的账号
# param: target | | user@host:/path | 目标 |
# param: port   | 22 | SSH port | SSH 端口 | number
# button: showkey | Show the public key | 显示公钥
# button: test    | ✓ Test connection   | ✓ 测试连接
#
# A store answers five questions about a remote directory and nothing else:
# make this folder, put this file in it, get that one back, what is in there,
# delete that one. It has no schedule and knows nothing about databases —
# which is what lets `backup` point at any of them without a special case.
#
# The one that needs nothing on the far end but sshd. rsync resumes a transfer
# that died at 90% and only sends what changed, so prefer that card where the
# far end has the binary — a great many cheap storage boxes, and as it turns
# out a great many ordinary Debian installs, do not.
. /usr/lib/app-setup/common.sh

KEY="$APP_SETUP_CONF/secrets/backup_ed25519"
KNOWN="$APP_SETUP_CONF/secrets/backup_known_hosts"
STAMP="$APP_SETUP_STATE/backup/store-scp.ok"

PKGS="openssh-client"
PKGS_rpm="openssh-clients"
PKGS_apk="openssh-client"

# user@host:/path -> the three pieces. The path is the *base*; the folder the
# caller passes is made under it.
sc_user_host() { printf '%s' "${1%%:*}"; }
sc_base()      { case "$1" in *:*) printf '%s' "${1#*:}" ;; *) printf '' ;; esac; }

# One ssh invocation, built in one place, so a flag cannot end up on the copy
# and not on the listing. StrictHostKeyChecking=yes once the fingerprint has
# been pinned by `test`; `accept-new` before that would silently trust a new
# key on every later change, which is the thing pinning is for.
sc_ssh_cmd() {
	printf 'ssh -i %s -p %s -o IdentitiesOnly=yes -o UserKnownHostsFile=%s -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10' \
		"$KEY" "$(param port 22)" "$KNOWN"
}

sc_ssh() {   # sc_ssh <remote command…>
	local _t
	_t="$(param target)"
	[ -n "$_t" ] || { err "no target set — put user@host:/path in Settings"; return 1; }
	ssh -i "$KEY" -p "$(param port 22)" \
		-o IdentitiesOnly=yes -o UserKnownHostsFile="$KNOWN" \
		-o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10 \
		"$(sc_user_host "$_t")" "$@"
}

# The absolute path on the far end for this job's folder.
sc_path() {  # sc_path <folder> [name]
	local _b
	_b="$(sc_base "$(param target)")"
	[ -n "$_b" ] || _b=.
	if [ -n "${2-}" ]; then printf '%s/%s/%s' "$_b" "$1" "$2"
	else printf '%s/%s' "$_b" "$1"; fi
}

# ------------------------------------------------------------------- keys --
# One key for every SSH store on this machine, made once and never rotated by
# us. Mode 600 and no passphrase: this runs from cron at four in the morning
# and there is nobody to type one.
sc_ensure_key() {
	[ -f "$KEY" ] && return 0
	mkdir -p "$(dirname "$KEY")"; chmod 700 "$(dirname "$KEY")"
	step "making an SSH key for backups"
	ssh-keygen -t ed25519 -N '' -C "app-setup backup on $(hostname 2>/dev/null)" -f "$KEY" >/dev/null 2>&1 ||
		die "could not make an SSH key — is openssh-client installed?"
	chmod 600 "$KEY"; chmod 644 "$KEY.pub"
	ok "made $KEY"
}

do_showkey() {
	sc_ensure_key
	cat <<EOF
This machine's backup public key
--------------------------------
$(cat "$KEY.pub")

Put that one line into ~/.ssh/authorized_keys on the far end, for the user in
your target. From this machine, if you can already log in with a password:

    ssh-copy-id -i $KEY -p $(param port 22) $(sc_user_host "$(param target)")

Or on the far end, by hand:

    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    echo '$(cat "$KEY.pub")' >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys

Worth doing while you are there: restrict what this key may do, so a stolen
container cannot use it for a shell. \`restrict\` turns off port forwarding,
agent forwarding, X11 and a pty, and leaves file transfer working.

    restrict $(cat "$KEY.pub")

Then press ✓ Test connection.
EOF
}

# Trust on first use, and only when somebody pressed Test. Weaker than a
# fingerprint handed to you out of band, and much stronger than
# StrictHostKeyChecking=no, which is where a script that skips this ends up.
# The fingerprint is printed so anybody who does have it can compare, and a
# key that changes afterwards fails loudly rather than being trusted quietly.
sc_pin_host() {
	local _h _p
	_h="$(sc_user_host "$(param target)")"; _h="${_h#*@}"
	_p="$(param port 22)"
	mkdir -p "$(dirname "$KNOWN")"
	if ssh-keygen -F "[$_h]:$_p" -f "$KNOWN" >/dev/null 2>&1 ||
	   { [ "$_p" = 22 ] && ssh-keygen -F "$_h" -f "$KNOWN" >/dev/null 2>&1; }; then
		return 0
	fi
	step "recording the host key for $_h"
	ssh-keyscan -p "$_p" -T 10 "$_h" >> "$KNOWN" 2>/dev/null ||
		{ err "could not read a host key from $_h:$_p — is it reachable?"; return 1; }
	chmod 600 "$KNOWN"
	info "fingerprint, compare it if you have it from somewhere else:"
	ssh-keygen -lf "$KNOWN" 2>/dev/null | tail -3 | sed 's/^/    /'
}

# ------------------------------------------------------------- the verbs --
do_mkdir() {  # do_mkdir <folder>
	sc_ensure_key
	sc_ssh "mkdir -p '$(sc_path "$1")'" || { err "could not make $(sc_path "$1") on the far end"; return 1; }
}

do_put() {    # do_put <folder> <localfile>
	local _n
	_n="$(basename "$2")"
	sc_ensure_key
	do_mkdir "$1" || return 1
	# -O forces the old SCP protocol off on OpenSSH 9+, where scp already
	# speaks SFTP — which is the point of this card: nothing but sshd is
	# needed on the far end. -p keeps the mode, so a 600 archive stays 600.
	scp -p -q -i "$KEY" -P "$(param port 22)" \
		-o IdentitiesOnly=yes -o UserKnownHostsFile="$KNOWN" \
		-o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10 \
		"$2" "$(sc_user_host "$(param target)"):$(sc_path "$1" "$_n")" ||
		{ err "scp failed"; return 1; }
}

do_get() {    # do_get <folder> <name> <localfile>
	sc_ensure_key
	scp -p -q -i "$KEY" -P "$(param port 22)" \
		-o IdentitiesOnly=yes -o UserKnownHostsFile="$KNOWN" \
		-o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10 \
		"$(sc_user_host "$(param target)"):$(sc_path "$1" "$2")" "$3" ||
		{ err "could not fetch $2"; return 1; }
}

# Bare names, one per line, sorted — the same strings a local directory gives,
# which is what lets one prune walk both.
do_ls() {     # do_ls <folder>
	sc_ssh "ls -1 '$(sc_path "$1")' 2>/dev/null" | sort
}

do_rm() {     # do_rm <folder> <name>
	case "$2" in
		''|*/*|.|..) err "refusing to delete '$2' — a bare filename only"; return 1 ;;
	esac
	sc_ssh "rm -f -- '$(sc_path "$1" "$2")'"
}

# Five operations because each one fails on its own, and a store that has
# never passed all five is not a destination anybody should rely on. It probes
# into a folder rather than into the base, because that is what a backup does:
# an account that can write files into the directory it was given and cannot
# create one under it is a normal configuration, and testing at the base would
# pass and then every backup would die at its first mkdir.
do_test() {
	local _f _d _rc _probe
	bk_unbless "$(basename "$STAMP" .ok)"
	sc_ensure_key
	[ -n "$(param target)" ] || die "no target set. Put user@host:/path in Settings first."
	sc_pin_host || return 1
	_f=".app-setup-probe-$(date -u +%Y%m%dT%H%M%SZ)"
	_d="$(tmp_dir)"; _probe="$_d/probe"
	printf 'app-setup backup reachability check\n' > "$_probe"
	_rc=0

	step "making a folder"
	do_mkdir "$_f" || _rc=1
	if [ "$_rc" = 0 ]; then
		step "writing a file into it";  do_put "$_f" "$_probe" || _rc=1
	fi
	if [ "$_rc" = 0 ]; then
		step "listing it"
		do_ls "$_f" | grep -q '^probe$' || { err "the file was written and does not appear in the listing"; _rc=1; }
	fi
	if [ "$_rc" = 0 ]; then
		step "reading it back"
		do_get "$_f" probe "$_d/back" || _rc=1
		cmp -s "$_probe" "$_d/back" || { err "what came back is not what went out"; _rc=1; }
	fi
	if [ "$_rc" = 0 ]; then
		step "deleting it"; do_rm "$_f" probe || _rc=1
	fi
	# Whether it passed or failed: the probe folder does not stay behind.
	sc_ssh "rm -rf -- '$(sc_path "$_f")'" >/dev/null 2>&1 || true
	rm -rf "$_d"

	mkdir -p "$(dirname "$STAMP")"
	if [ "$_rc" = 0 ]; then
		date -u +%Y%m%d%H%M%S > "$STAMP"
		ok "folder, write, read and delete all worked — $(param target)"
	else
		rm -f "$STAMP"
		err "this destination is not usable yet. Nothing above should be relied on until it is."
	fi
	return "$_rc"
}

# ------------------------------------------------------------------ state --
# Never touches the network: do_status is killed at eight seconds and a card
# grid that probed six remotes on every redraw would spend that budget on the
# first one. The stamp is what `test` wrote.
is_installed() { [ -n "$(param target)" ]; }

do_status() {
	is_installed || exit 2
	if [ -f "$STAMP" ]; then
		echo "detail=$(param target) — tested $(cat "$STAMP")"
		exit 0
	fi
	echo "detail=$(param target) — never tested. Press Test connection."
	exit 3
}

do_install() {
	step "making sure there is an ssh client"
	pkg_install $(pmv PKGS) || die "could not install an ssh client here"
	sc_ensure_key
	chmod 600 "$APP_SETUP_CONF/params/store-scp.conf" 2>/dev/null || true
	if [ -z "$(param target)" ]; then
		warn "no target yet. Open Settings and put user@host:/path in it,"
		warn "then press Show the public key, then Test connection."
	else
		do_test || warn "fix the above, then press Test connection again"
	fi
	save_note store-scp <<EOF
Backup destination — SCP over SSH

  target      $(param target)
  port        $(param port 22)
  key         $KEY  (public key in $KEY.pub)
  host key    pinned in $KNOWN

  Point a backup at it:
    app-setup set backup store=scp
    app-setup backup mysql
EOF
	ok "ready. This holds no password — the key is what gets you in."
}

do_uninstall() {
	drop_note store-scp
	rm -f "$STAMP"
	info "the key at $KEY was left alone — remove it yourself if you mean it,"
	info "and take it out of authorized_keys on the far end while you are there."
}

do_help() {
	if lang_zh; then
		cat <<EOF
SCP 备份存储源

  它是什么
    把打包好的备份用 scp 送到另一台机器上。对面只要有 sshd 就行，不需要
    装任何东西。不用密码，用密钥。

  怎么配
    目标        user@host:/path      例：backup@nas.local:/volume1/backups
    SSH 端口    默认 22

    然后按「显示公钥」，把打印出来的那一行加到对面机器上那个用户的
    ~/.ssh/authorized_keys 里。最后按「测试连接」。

  测试连接做了什么
    建目录 → 写文件 → 列目录 → 读回来比对 → 删掉。五步，因为每一步都会
    单独失败：能上传但不能列目录的账号、能写文件但不能建子目录的账号，
    都很常见，而且在第一次备份真跑起来之前都看着正常。

    它是在一个临时子目录里探测，不是在根目录 —— 因为备份就是这么写的。

  主机指纹
    第一次测试时记下来，存在 $KNOWN。
    之后每次连接都要求指纹一致，变了就直接失败，不会默默信任新的。
    第一次记的时候会把指纹打出来，你要是有别的渠道拿到的指纹，对一下。

  什么时候用它
    对面只有 sshd、没有 rsync 的时候 —— 便宜的存储机器基本都是这样，
    很多普通的 Debian 装机也是。对面有 rsync 就用 rsync 那张卡：断了
    能续，而且只传变化的部分。

  用它
    app-setup set backup store=scp
    app-setup backup mysql
EOF
	else
		cat <<EOF
SCP backup destination

  What it is
    Sends packed backups to another machine with scp. The far end needs
    nothing but sshd. No password: a key.

  Setting it up
    target      user@host:/path      e.g. backup@nas.local:/volume1/backups
    SSH port    22 unless you moved it

    Then press Show the public key and put the line it prints into
    ~/.ssh/authorized_keys for that user on the far end. Then Test connection.

  What Test connection does
    Makes a folder, writes a file into it, lists it, reads it back and
    compares the bytes, then deletes it. Five steps because each one fails on
    its own: an account that can upload but not list, and one that can write
    files but not create a folder, are both normal and both look fine until
    the first backup runs.

    It probes inside a folder rather than at the base, because that is what a
    backup does.

  The host key
    Recorded the first time you press Test, into $KNOWN. Every connection
    afterwards requires it to match, and a changed host key fails loudly
    rather than being trusted quietly. The fingerprint is printed when it is
    recorded — compare it if you have it from somewhere else.

  When to use this one
    When the far end has sshd and no rsync — which is most cheap storage
    boxes, and a good many ordinary Debian installs. Where rsync is
    available, prefer that card: it resumes a transfer that died at 90% and
    only sends what changed.

  Using it
    app-setup set backup store=scp
    app-setup backup mysql
EOF
	fi
}

app_main "$@"
