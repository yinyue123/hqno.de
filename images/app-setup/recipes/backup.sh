#!/bin/sh
# app-setup: 1
# id: backup
# name: Backup
# name.zh: 备份
# category: system
# order: 15
# summary: Scheduled backups of your databases and sites, packed and sent off this machine
# summary.zh: 定时备份数据库和网站，打包后传到这台机器之外
# includes: rclone (or aws-cli), a cron entry, and one dated .tgz per app
# includes.zh: rclone（或 aws-cli）、一条 cron、每个软件一个带日期的 .tgz
# disk: 60M
# memory: 32M
# requires: somewhere to upload to — any S3-compatible bucket
# requires.zh: 一个能上传的地方 —— 任何 S3 兼容的存储桶
# param: targets    |              | What to back up | 备份哪些 | @backup
# action: targets   | backup       | ▶ Back up now   | ▶ 立即备份
# param: method     | dump         | How             | 方式     | dump,files
# param: keep       | 7            | Keep last       | 保留份数 | number
# param: schedule   | daily        | When            | 定时     | off,hourly,daily,weekly
# group: remote | Where it goes | 传到哪 |
# param: tool       | rclone       | Upload with     | 上传工具 | rclone,aws,none
# param: remote     |              | Bucket          | 存储桶   |
# param: endpoint   |              | S3 endpoint     | S3 地址  |
# param: region     | us-east-1    | Region          | 区域     |
# param: access_key |              | Access key      | Access key |
# param: secret_key |              | Secret key      | Secret key |
#
# The backup control panel. It owns nothing of its own except the schedule and
# the destination: what a backup of MariaDB actually *is* belongs to mysql.sh,
# and this file only ever calls `mysql.sh backup` and counts the results.
#
# That split is the same one the whole of app-setup is built on, and it is what
# makes this file short. Adding WordPress to the list did not change anything
# here; it changed wordpress.sh.
. /usr/lib/app-setup/common.sh

# The job's name, not a path: where a timer lives is the machine's business and
# common.sh knows the two answers. This file used to name /etc/cron.d directly,
# which is a directory Alpine does not have — see the cron section there.
CRON_NAME=app-setup-backup
# The recipe is installed when this exists, which is not the same as the timer
# being set: `schedule = off` is a thing somebody is allowed to choose, and it
# must not uninstall the card they chose it on. The timer is read back from
# cron itself, so the two facts never drift apart.
BK_STAMP="$APP_SETUP_STATE/backup.installed"
CHECK_FILE="$BK_STAMP"

# ------------------------------------------------------------------ status --
is_installed() { [ -f "$BK_STAMP" ]; }

version_line() {
	local _last _n
	_n="$(ls -1 "$BK_DIR"/*.tgz 2>/dev/null | wc -l | tr -d ' ')"
	_last="$(ls -1 "$BK_DIR"/*.tgz 2>/dev/null | sort -r | head -1)"
	if [ "${_n:-0}" -gt 0 ]; then
		printf '%s archives, newest %s' "$_n" "$(basename "$_last")"
	elif [ -n "$(cron_line_of "$CRON_NAME")" ]; then
		printf 'scheduled %s, nothing saved yet' "$(param schedule daily)"
	else
		printf 'no timer, nothing saved yet'
	fi
}

do_status() {
	is_installed || exit 2
	echo "detail=$(version_line)"
	# There is no daemon of ours to be up or down: cron either has the line or
	# it does not, and that is what `installed` already said.
	exit 0
}

# ----------------------------------------------------------------- install --
# `off` still installs: somebody who wants to press the button by hand and
# never on a timer should not have to leave the recipe uninstalled to get it.
# Where the timer ended up, for the help text and the note. Somebody who wants
# to look at it with their own eyes needs the answer for *this* machine, and it
# is two different answers.
cron_where() {
	case "$(cron_kind)" in
	dropin)  printf '/etc/cron.d/%s' "$CRON_NAME" ;;
	crontab) printf "root's crontab (\`crontab -l\`)" ;;
	*)       printf 'nowhere — this machine has no cron' ;;
	esac
}

cron_line() {
	case "$(param schedule daily)" in
		off)    printf '' ;;
		hourly) printf '17 *    * * *' ;;
		weekly) printf '17 4    * * 0' ;;
		*)      printf '17 4    * * *' ;;
	esac
}

# Never fatal. A machine with no cron at all is a machine where the button
# still works and the timer does not, and taking the whole install down over
# that leaves somebody with neither.
write_cron() {
	local _when
	_when="$(cron_line)"
	# Output goes to app-setup's own log rather than to cron's mail, which
	# nothing in a container reads. The `--no-color` matters: a log full of
	# escape sequences is a log nobody opens twice.
	# Nothing ticked is not a schedule. A timer that fires nightly onto an
	# empty list writes a log line saying so and nothing else, forever, and
	# looks from the outside exactly like a backup that is running.
	if [ -z "$(param targets)" ]; then
		cron_clear "$CRON_NAME" >/dev/null 2>&1 || true
		return 0
	fi
	if cron_set "$CRON_NAME" "$_when" \
	     "app-setup --no-color backup $(param targets | tr ',' ' ') >/dev/null 2>&1"; then
		return 0
	fi
	warn "no cron on this machine — the ▶ button still works, the timer will not"
	return 0
}

# Neither tool is in a RHEL rebuild's base repos, so the enterprise distros
# need EPEL turned on first — the same thing atop and htop already do here.
install_tool() {
	local _pkg _want
	_want="$(param tool rclone)"
	case "$_want" in
	none) info "no upload tool wanted — archives stay in $BK_DIR"; return 0 ;;
	aws)  have aws    && { ok "aws-cli is already here"; return 0; } ;;
	*)    have rclone && { ok "rclone is already here";  return 0; } ;;
	esac
	case "$PM" in dnf|yum) enable_epel ;; esac
	if [ "$_want" = aws ]; then
		# Alpine calls it aws-cli; everyone else calls it awscli.
		case "$PM" in apk) _pkg=aws-cli ;; *) _pkg=awscli ;; esac
	else
		_pkg=rclone
	fi
	pkg_install "$_pkg" ||
		die "could not install $_pkg here. Install it yourself, or set Upload with = none and copy $BK_DIR somewhere safe another way."
}

do_install() {
	step "checking there is somewhere to put them"
	mkdir -p "$BK_DIR" || die "cannot create $BK_DIR"
	chmod 700 "$BK_DIR"
	# A path that merely *starts* with /data proves nothing: without a data
	# disk, /data is an ordinary directory on the root filesystem and a
	# reinstall takes it along with everything else. Ask whether it is a
	# mount, which is the only question that distinguishes the two.
	case "$BK_DIR" in
		"$DATA_DIR"/*) data_disk ||
			warn "$DATA_DIR is not a data disk on this container — it is an ordinary directory on the root filesystem, and a reinstall takes it. The copy in your bucket is the only one that would survive." ;;
		*) warn "$BK_DIR is not under $DATA_DIR, which is the only directory that survives a reinstall" ;;
	esac

	install_tool

	step "writing the schedule"
	mkdir -p "$APP_SETUP_STATE" && : > "$BK_STAMP"
	write_cron
	[ -z "$(cron_line)" ] || info "the timer is in $(cron_where)"
	# The Settings form holds an S3 secret. params_save truncates without
	# changing the mode, so setting it once here keeps it for every later save.
	chmod 600 "$APP_SETUP_CONF/params/backup.conf" 2>/dev/null || true

	if [ -z "$(param targets)" ]; then
		warn "nothing is ticked under 'What to back up' — open Settings and pick"
		warn "what to save. The list is what this machine has that can be saved."
	fi

	step "checking the destination"
	if [ -z "$(param remote)" ] || [ "$(param tool rclone)" = none ]; then
		warn "no bucket set yet — archives will only be written to $BK_DIR."
		warn "open Settings and fill in Bucket, Access key and Secret key."
	else
		bk_check_remote || warn "the upload did not work yet — see the note above, then press Back up now"
	fi

	save_note backup <<EOF
backups     $BK_DIR/<name>_YYYYMMDDHHMMSS.tgz
schedule    $(param schedule daily)$([ -n "$(cron_line)" ] && printf ' (%s), in %s' "$(cron_line)" "$(cron_where)")
targets     $(param targets)
method      $(param method dump)
keep        $(param keep 7) locally
uploads to  $(param remote)$([ -n "$(param endpoint)" ] && printf ' via %s' "$(param endpoint)")
restore     app-setup restore <name>
EOF
	ok "backup is set up. Press ▶ Back up now to prove it before you rely on it."
}

do_uninstall() {
	cron_clear "$CRON_NAME" || true
	rm -f "$BK_STAMP"
	drop_note backup
	ok "the schedule is gone."
	info "$BK_DIR was left alone — your archives are in it."
}

# A backup nobody has ever restored is a hope, not a backup. This writes a
# small object and reads it back, which is the cheapest thing that actually
# proves the credentials, the endpoint and the bucket policy all agree.
bk_check_remote() {
	local _d _rc
	_d="$(tmp_dir)"
	printf 'app-setup backup reachability check\n' > "$_d/.app-setup-check"
	_rc=0
	bk_upload "$_d/.app-setup-check" || _rc=1
	rm -rf "$_d"
	[ "$_rc" = 0 ] && ok "the destination accepted a test upload"
	return "$_rc"
}

# ------------------------------------------------------------------ backup --
# Every target, one after another, and one failure does not stop the rest: if
# MariaDB is broken tonight the WordPress files should still leave the machine.
do_backup() {
	local _bad _id _n _targets
	_targets="$(param targets | tr ',' ' ')"
	[ -n "$_targets" ] || die "nothing selected — open Settings and tick what to back up in 'What to back up'"
	# Re-assert the schedule from the settings as they are now. The Settings
	# form's Save & Apply runs `install`, which writes it — but `app-setup set
	# backup targets=…` from a script does not, and a cron line still naming
	# last month's list is a backup nobody knows is incomplete.
	write_cron
	_bad=0
	_n=0; for _id in $_targets; do _n=$((_n + 1)); done
	step_total "$_n"
	_n=0
	for _id in $_targets; do
		_n=$((_n + 1))
		# `recipe` finds the file on APP_SETUP_PATH and runs the verb, which is
		# how lnmp already composes nginx and mysql. A target that is not
		# installed says so and does not stop the ones that are.
		if recipe "$_id" backup; then :; else
			err "$_id did not back up"
			_bad=$((_bad + 1))
		fi
	done
	if [ "$_bad" != 0 ]; then
		die "$_bad of $_n did not back up — the rest did"
	fi
	ok "all $_n backed up to $BK_DIR"
}

do_restore() {
	cat <<EOF
Restoring is per-application, because only that application knows what to do
with what was saved:

    app-setup restore mysql          the newest mysql_*.tgz in $BK_DIR

To pick a particular one, run its recipe directly:

    sh /etc/app-setup/mysql.sh restore mysql_20210403123221.tgz

What is available right now:

$(ls -1 "$BK_DIR"/*.tgz 2>/dev/null | sort -r | sed 's|^|    |' || true)
$([ -z "$(ls -1 "$BK_DIR"/*.tgz 2>/dev/null)" ] && echo "    (nothing in $BK_DIR yet)")
EOF
}

do_help() {
	if lang_zh; then
		cat <<EOF
备份

  它做什么
    按你选的时间，把每个软件各自打包成一个带时间戳的 .tgz，放进
    $BK_DIR，再传到你的存储桶里，最后只保留最近几份。

    名字长这样：mysql_20210403123221.tgz —— 前缀是软件的 id，时间是
    UTC 的 年月日时分秒。固定宽度，所以按文件名排序就是按时间排序。

  先填这几项
    存储桶      s3://你的桶名/backups
    S3 地址     非 AWS 的都要填，比如：
                  阿里云 OSS   https://oss-cn-hangzhou.aliyuncs.com
                  腾讯云 COS   https://cos.ap-guangzhou.myqcloud.com
                  Cloudflare   https://<账号id>.r2.cloudflarestorage.com
                  Backblaze    https://s3.us-west-000.backblazeb2.com
    Access key / Secret key

    填完按 ▶ 立即备份，看着它跑完一次。没亲手恢复过的备份不算备份。

  两种方式
    dump   热备。数据库自己导出一份，不停服务，网站不断。
    files  停掉服务 → 打包数据目录 → 再起来。文件级的一致性只能这么拿，
           代价是这几十秒站点是停的。

    数据库用 dump 就够了（mysqldump --single-transaction 对 InnoDB 是
    一致的）。除非你要连数据目录一起搬机器，才需要 files。

  定时
    off / hourly / daily / weekly，写进 $(cron_where)。
    daily 是每天 4:17，weekly 是周日 4:17 —— 错开整点，因为整点是全世界
    的定时任务一起醒来的时刻。

  恢复
    app-setup restore mysql                   最新的那份
    sh /etc/app-setup/mysql.sh restore mysql_20210403123221.tgz

  保留份数
    只管本机的 $BK_DIR。存储桶那边的历史请用桶自己的生命周期规则，
    脚本不该拿着一个可能填错的前缀去删你的远端数据。

  要紧的一句
    $BK_DIR 在 /data 下面，重装容器还在；但它和你的网站在同一块盘上。
    真出事的时候救你的是传到桶里的那一份。
EOF
	else
		cat <<EOF
Backup

  What it does
    On the schedule you pick, packs each application into its own dated .tgz
    under $BK_DIR, uploads it to your bucket, and keeps the last few.

    The name is: mysql_20210403123221.tgz — the application's id, then UTC
    YYYYMMDDHHMMSS. Fixed width, so sorting by name sorts by time.

  Fill these in first
    Bucket        s3://your-bucket/backups
    S3 endpoint   anything that is not AWS needs one:
                    Cloudflare R2  https://<account>.r2.cloudflarestorage.com
                    Backblaze B2   https://s3.us-west-000.backblazeb2.com
                    Aliyun OSS     https://oss-cn-hangzhou.aliyuncs.com
                    MinIO          https://minio.example.com
    Access key / Secret key

    Then press ▶ Back up now and watch one finish. A backup nobody has
    restored is a hope, not a backup.

  Two methods
    dump   hot. The database exports itself, nothing stops, the site stays up.
    files  stop the service, pack the data directory, start it again. That is
           the only honest way to copy files out from under a running
           database, and it costs however long the copy takes.

    dump is right for databases — mysqldump --single-transaction is
    consistent on InnoDB without stopping anything. Use files when you want
    the data directory itself, to move it to another machine.

  Schedule
    off / hourly / daily / weekly, written to $(cron_where).
    daily is 04:17, weekly is Sunday 04:17 — off the hour on purpose, because
    the top of the hour is when every cron job on earth wakes up at once.

  Restoring
    app-setup restore mysql                   the newest one
    sh /etc/app-setup/mysql.sh restore mysql_20210403123221.tgz

  Keep last N
    Local only. Prune the bucket with its own lifecycle rules — a shell
    script deleting your remote history on a guessed prefix is not a risk
    worth taking for a little storage.

  The thing worth remembering
    $BK_DIR survives a reinstall because it is under /data. It does not
    survive the disk. The copy in the bucket is the one that saves you.
EOF
	fi
}

app_main "$@"
