#!/bin/sh
# app-setup: 1
# id: files
# name: Files and folders
# name.zh: 文件和目录
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 24
# summary: Back up any directories you name — an app's config, its uploads, anything with no recipe of its own.
# summary.zh: 备份你指定的任意目录 —— 程序的配置、上传的文件，任何没有专门脚本管的东西。
# includes: nothing to install; it saves paths you list
# includes.zh: 不装任何东西，只保存你列出的路径
# disk: 0
# memory: 0
#
# group: what | What to save | 备份哪些 |
# param: paths   |                                  | What to save    | 备份哪些 |
# action: paths  | backup                           | ▶ Back up now   | ▶ 立即备份
# param: exclude | *.log, *.tmp, node_modules, .git | Skip            | 跳过     |
# param: service |                                  | Stop first      | 先停掉   |
#
# group: where | Where it goes | 存到哪 |
# param: store        | none | Destination                    | 目的地   | none,s3,r2,webdav,ftp,rsync,scp
# param: folder       |      | Folder on the remote           | 远端目录 |
# param: prune_remote | off  | Also delete old archives there | 同时删除远端旧文件 | bool
#
# group: when | When, and how many to keep | 定时与保留 |
# param: schedule     | off | When         | 定时       | off,hourly,daily,weekly,monthly
# param: keep_hourly  | 0   | Keep hourly  | 每小时保留 | number
# param: keep_daily   | 7   | Keep daily   | 每天保留   | number
# param: keep_weekly  | 4   | Keep weekly  | 每周保留   | number
# param: keep_monthly | 6   | Keep monthly | 每月保留   | number
#
# group: restore | Putting one back | 恢复 |
# param: archive |  | Which one (blank = the newest) | 哪一份 |
#
# button: backup  | ▶ Back up now  | ▶ 立即备份     | progress
# button: list    | ▤ List backups | ▤ 列出所有备份
# button: verify  | ✓ Verify       | ✓ 校验         | progress
# button: restore | ⟲ Restore      | ⟲ 恢复         | confirm
#
# The catch-all, and the reason it exists: a recipe knows what *its* data is,
# and app-setup only has recipes for what it ships. Somebody running their own
# Go binary out of /opt/thing, with its config in /etc/thing and its uploads in
# /var/lib/thing, has three directories that nothing here would ever save. The
# database half of that is already covered by `mysql`; this is the other half.
#
# It installs nothing. "Installed" here means "configured" — there are paths
# listed — which is the only honest reading of the state machine for a recipe
# that has no package and no service.
. /usr/lib/app-setup/common.sh

# ------------------------------------------------------------------- state --
files_paths() {
	local _f _out _p
	_out=""
	# Unquoted on purpose: the setting may hold globs, and this is where they
	# are meant to expand.
	for _p in $(param paths | tr ',' ' '); do
		for _f in $_p; do [ -e "$_f" ] && _out="$_out $_f"; done
	done
	printf '%s' "${_out# }"
}

# What was asked for but is not there. Worth saying out loud rather than
# skipping quietly: a typo in a path is indistinguishable from a working
# backup until the day it is not.
files_missing() {
	local _f _out _p
	_out=""
	for _p in $(param paths | tr ',' ' '); do
		_f=""
		for _f in $_p; do [ -e "$_f" ] && break; _f=""; done
		[ -n "$_f" ] || _out="$_out $_p"
	done
	printf '%s' "${_out# }"
}

is_installed() { [ -n "$(param paths)" ]; }

version_line() {
	local _f _n _sz
	_n=0
	for _f in $(files_paths); do _n=$((_n + 1)); done
	[ "$_n" != 0 ] || { printf 'nothing listed yet'; return 0; }
	# shellcheck disable=SC2086  # our own list of paths, split on purpose
	_sz="$(du -shc $(files_paths) 2>/dev/null | tail -1 | awk '{print $1}')"
	printf '%s path%s, %s' "$_n" "$([ "$_n" = 1 ] || printf s)" "${_sz:-?}"
}

do_status() {
	is_installed || exit 2
	# The same three states every card on this tab has. A job with nowhere to
	# send its output is visibly in error rather than looking configured and
	# quietly saving to one disk.
	if ! bk_store_set; then
		echo "detail=$(version_line) · no destination — set up a store first"
		exit 3
	fi
	if ! bk_store_ready; then
		echo "detail=$(bk_setting store) has never passed a connection test"
		exit 3
	fi
	if [ "$(param schedule off)" = off ]; then
		echo "detail=$(version_line) · off"
		exit 1
	fi
	echo "detail=$(version_line) · $(param schedule off) → $(bk_setting store)"
	exit 0
}

# ----------------------------------------------------------------- install --
# Nothing is installed. This checks the list is real and says how big it is,
# which is the question somebody actually has before turning on a schedule.
do_install() {
	local _miss
	[ -n "$(param paths)" ] ||
		die "nothing listed yet. Open Settings and put the directories in Paths, comma separated — e.g. /etc/myapp, /opt/myapp, /var/lib/myapp"

	_miss="$(files_missing)"
	[ -z "$_miss" ] || warn "listed but not on this machine: $_miss"

	[ -n "$(files_paths)" ] || die "none of the listed paths exist; nothing would be saved"

	step "measuring"
	ok "$(version_line)"
	case "$(param service)" in
		"") : ;;
		*)  info "$(param service) will be stopped while these are copied" ;;
	esac

	bk_need_store || die "nothing was scheduled."
	bk_keep_warn
	bk_migrate
	bk_cron_rebuild
	if [ "$(param schedule off)" = off ]; then
		info "schedule is off — nothing runs on a timer. ▶ Back up now still works."
	else
		ok "scheduled $(param schedule off), minute $(bk_cron_minute files)"
	fi
	ok "ready — press ▶ Back up now to take one"
}

do_uninstall() {
	bk_cron_rebuild
	info "nothing was installed, so nothing was removed."
	info "clear Paths in Settings if you want this to stop being listed."
	warn "$BK_DIR/files was NOT deleted — your archives are still there."
}

# ------------------------------------------------------------------ backup --
do_backup() {
	local _f _list _miss _svc
	_list="$(files_paths)"
	[ -n "$_list" ] || die "nothing listed. Put the directories in Settings, comma separated."
	_miss="$(files_missing)"
	[ -z "$_miss" ] || warn "listed but missing, so not saved: $_miss"
	bk_need_store || exit 1

	bk_begin files

	# A plain directory has no notion of a consistent snapshot, so if something
	# is writing to it the honest answer is to stop that thing first. Naming a
	# service here is optional and off by default, because most config
	# directories are not being written to at four in the morning.
	_svc="$(param service)"
	if [ -n "$_svc" ] && svc_running "$_svc"; then
		BK_SVC_WAS="$_svc"
		step "stopping $_svc"
		svc_stop "$_svc"
	fi

	# Set for bk_add, cleared by nothing else — this recipe is the only caller
	# that has an exclude list.
	BK_EXCLUDE="$(param exclude | tr ',' ' ')"
	for _f in $_list; do
		step "copying $_f"
		bk_add "$_f"
	done
	BK_EXCLUDE=""

	# An archive with nothing in it but the empty directory tree is the failure
	# worth catching here: every path excluded, or every path unreadable.
	[ -n "$(find "$BK_WORK/$BK_PREFIX/files" -mindepth 1 2>/dev/null | head -1)" ] ||
		die "nothing was actually copied — check What to save and Skip"

	bk_finish
}

do_list()   { bk_list files; }
do_verify() { bk_verify files "${1:-$(param archive)}"; }

do_restore() {
	local _d
	bk_open files "${1:-$(param archive)}"
	_d="$BK_UNPACKED"
	[ -d "$_d/files" ] || die "that archive has no files in it"
	echo
	echo "This puts back, overwriting what is there now:"
	# `.` is the root of the copy and `./srv` is a path under it; substituting
	# the dot alone turned the second into `//srv`, which reads as a typo in
	# the one list somebody checks before overwriting their own files.
	(cd "$_d/files" && find . -maxdepth 3 -type d |
		sed -e 's|^\.$|    /|' -e 's|^\./|    /|' | head -20)
	echo
	warn "existing files at those paths are overwritten, not moved aside —"
	warn "there is no one directory to move, the way there is for a site."
	bk_restore_files "$_d"
	bk_close
	ok "restored"
}

do_help() {
	if lang_zh; then
		cat <<EOF
文件和目录

  这是干嘛的
    数据库有专门的脚本管，但你自己跑的程序没有。比如一个 Go 程序在
    /opt/thing，配置在 /etc/thing，上传的文件在 /var/lib/thing —— 这三个
    目录没人管。库那半边 mysql 已经管了，这里管另外半边。

    它不装任何东西。这里的「已安装」就是「已配置」。

  怎么用
    1. 在设置里填 备份哪些，逗号分隔，可以用通配符：
         /etc/myapp, /opt/myapp, /var/lib/myapp/uploads
    2. 跳过 里填不想要的，默认已经排掉了日志、临时文件、node_modules、.git
    3. 如果那个目录一直在被写，把服务名填进 先停掉
    4. 按 ▶ 立即备份

    要定时跑，去「备份」卡片的列表里加上 files：
         mysql,files

  恢复
    app-setup restore files

    注意它是直接覆盖回原路径的。网站那种有一个根目录，可以整个挪开再放
    回去；这里是一堆散在各处的路径，没有「一个目录」可挪。要保险就先
    自己拷一份。

  两个已经替你挡掉的坑
    · /data/backups 和 /data/dumps 永远不会被打进包里。不然你备份 /data
      的时候会把之前每一份备份都装进新的那份，一天比一天大，直到磁盘满。
    · / 、/proc、/sys、/dev、/run 直接拒绝。

  大小
    装的时候会告诉你一共多大。传到桶里之前先看一眼这个数 —— 一个 40G 的
    上传目录每天传一次，账单和带宽都不是开玩笑的。
EOF
	else
		cat <<EOF
Files and folders

  What this is for
    Databases have recipes. The program you wrote does not. Something running
    from /opt/thing, with its config in /etc/thing and its uploads in
    /var/lib/thing, has three directories nothing here would ever save. The
    database half is already covered by \`mysql\`; this is the other half.

    It installs nothing. "Installed" here means "configured".

  Using it
    1. Settings → What to save, comma separated, globs allowed:
         /etc/myapp, /opt/myapp, /var/lib/myapp/uploads
    2. Skip already drops logs, temp files, node_modules and .git
    3. If something writes to those paths continuously, name it in Stop first
    4. Press ▶ Back up now

    To have it run on the schedule, add \`files\` to the Backup card's list:
         mysql,files

  Restoring
    app-setup restore files

    This overwrites the paths in place. A site has one document root that can
    be moved aside and put back; this is a handful of paths scattered around
    and there is no single directory to move. Take your own copy first if it
    matters.

  Two mistakes already prevented
    · /data/backups and /data/dumps are never packed into an archive. Without
      that, backing up /data would put every previous archive inside the new
      one, and each night's would be bigger than the last until the disk fills.
    · /, /proc, /sys, /dev and /run are refused outright.

  Size
    Installing prints the total. Look at that number before turning on an
    upload — a 40G uploads directory going to a bucket every night is a real
    bandwidth bill.
EOF
	fi
}

app_main "$@"
