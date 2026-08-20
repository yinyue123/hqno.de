#!/bin/sh
# app-setup: 1
# id: backup-mongodb
# name: MongoDB
# name.zh: MongoDB 备份
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 23
# summary: mongodump into one gzipped archive file — this server or another one, and one file you can scp.
# summary.zh: mongodump 出一个 gzip 压缩的单文件 —— 本机或者别的机器都行，出来就是一个能直接 scp 的文件。
# includes: mongodump, a cron line, and one dated .tgz per run
# includes.zh: mongodump、一条 cron、每次一个带日期的 .tgz
# disk: 20M
# memory: 32M
# requires: a store on this tab, set up and tested
# requires.zh: 本页里配置好并测试通过的一个备份源
#
# group: source | The database | 数据库 |
# param: host      | 127.0.0.1 | Host                    | 主机 |
# param: port      | 27017     | Port                    | 端口 | number
# param: user      |           | User                    | 用户 |
# param: password  |           | Password                | 密码 |
# param: authdb    | admin     | Auth database           | 认证库 |
# param: databases |           | Databases (blank = all) | 数据库（留空=全部） |
#
# group: how | How | 方式 |
# param: method | dump | Method | 方式 | dump,files
#
# group: where | Where it goes | 存到哪 |
# param: store        | none | Destination                    | 目的地   | none,s3,r2,webdav,ftp,rsync,scp
# param: folder       |      | Folder on the remote           | 远端目录 |
# param: prune_remote | off  | Also delete old archives there | 同时删除远端旧文件 | bool
#
# group: when | When, and how many to keep | 定时与保留 |
# param: schedule     | daily | When         | 定时       | off,hourly,daily,weekly,monthly
# param: keep_hourly  | 0     | Keep hourly  | 每小时保留 | number
# param: keep_daily   | 7     | Keep daily   | 每天保留   | number
# param: keep_weekly  | 4     | Keep weekly  | 每周保留   | number
# param: keep_monthly | 6     | Keep monthly | 每月保留   | number
#
# group: restore | Putting one back | 恢复 |
# param: archive |  | Which one (blank = the newest) | 哪一份 |
#
# button: backup  | ▶ Back up now  | ▶ 立即备份     | progress
# button: list    | ▤ List backups | ▤ 列出所有备份
# button: verify  | ✓ Verify       | ✓ 校验         | progress
# button: restore | ⟲ Restore      | ⟲ 恢复         | confirm
#
# Beyond what was asked for, and here because the plumbing is identical and
# mongodb.sh already knows how: --archive rather than --out, so a dump is one
# file you can scp rather than a directory of BSON, and the backup and the
# manual dump are the same call with a different destination.
. /usr/lib/app-setup/common.sh

JOB=backup-mongodb
CHECK_FILE="$APP_SETUP_CONF/params/$JOB.conf"

SERVICE="mongod"

# ------------------------------------------------------------ connection --
# A mongodb:// URI, built here, because mongodump takes the credential in one
# string and building it in two places is how the two end up differing. It does
# put the password in argv — which mongodump has no file-based alternative to,
# unlike mysqldump and pg_dumpall — so it is only ever built when somebody
# actually typed one.
job_uri() {
	local _u _p
	_u="$(param user)"
	[ -n "$_u" ] || { printf ''; return 0; }
	_p="$(param password)"
	printf 'mongodb://%s:%s@%s:%s/?authSource=%s' \
		"$(job_esc "$_u")" "$(job_esc "$_p")" \
		"$(param host 127.0.0.1)" "$(param port 27017)" "$(param authdb admin)"
}

# A password with an @ or a / in it splits the URI in the wrong place and the
# error says "no such host", which sends people looking at the network.
job_esc() { printf '%s' "$1" | sed 's/%/%25/g; s/:/%3A/g; s#/#%2F#g; s/@/%40/g; s/?/%3F/g; s/#/%23/g'; }

job_where() { printf '%s:%s' "$(param host 127.0.0.1)" "$(param port 27017)"; }

job_dbpath() {
	local _d
	_d="$(sed -n 's/^[[:space:]]*dbPath:[[:space:]]*//p' /etc/mongod.conf 2>/dev/null | head -1)"
	[ -n "$_d" ] || _d=/var/lib/mongo
	printf '%s' "$_d"
}

# When no user is typed, the connection is host/port on their own — which is a
# server with authorization off, the shape a local mongod installed by
# mongodb.sh has until somebody turns it on.
job_dump_args() {
	if [ -z "$(param user)" ]; then
		printf -- '--host %s --port %s' "$(param host 127.0.0.1)" "$(param port 27017)"
	fi
}

# ---------------------------------------------------------------- backup --
do_backup() {
	local _m _db _uri
	bk_need_store || exit 1
	_m="$(param method dump)"
	if [ "$_m" = files ] && ! bk_job_local; then
		warn "method=files copies the server's own dbPath, and $(param host) is not this"
		warn "machine. Falling back to dump."
		_m=dump
	fi
	bk_begin "$JOB"
	case "$_m" in
	files)
		warn "method=files stops mongod while its files are copied."
		step "stopping $(svc)"
		svc_running "$(svc)" && { BK_SVC_WAS="$(svc)"; svc_stop "$(svc)"; }
		bk_add "$(job_dbpath)"
		;;
	*)
		step "dumping $(job_where)"
		_uri="$(job_uri)"
		# shellcheck disable=SC2046  # job_dump_args is our own flag list
		if [ -n "$(param databases)" ]; then
			for _db in $(param databases | tr ',' ' '); do
				step "  $_db"
				mongo_dumpcmd "$_uri" $(job_dump_args) --gzip --db "$_db" \
					--archive="$(bk_path "$_db.archive")" ||
					die "mongodump failed on $_db"
				[ -s "$(bk_path "$_db.archive")" ] || die "$_db came out empty; that is not a backup"
			done
		else
			mongo_dumpcmd "$_uri" $(job_dump_args) --gzip \
				--archive="$(bk_path dump.archive)" ||
				die "mongodump failed — if authorization is on, this job needs a user and password"
			[ -s "$(bk_path dump.archive)" ] || die "mongodump wrote nothing; that is not a backup"
		fi
		;;
	esac
	[ -f /etc/mongod.conf ] && bk_job_local && bk_add /etc/mongod.conf
	bk_finish
}

# --------------------------------------------------------------- restore --
do_restore() {
	local _d _f _uri _aside _dbp
	if bk_job_local; then
		recipe_ensure mongodb
		svc_running "$(svc)" || { step "starting $(svc)"; svc_start "$(svc)"; svc_settle "$(svc)" || true; }
	fi
	bk_open "$JOB" "${1:-$(param archive)}"
	_d="$BK_UNPACKED"
	_uri="$(job_uri)"

	if ls "$_d"/*.archive >/dev/null 2>&1; then
		for _f in "$_d"/*.archive; do
			step "restoring $(basename "$_f" .archive) — collections of the same name are dropped first"
			# shellcheck disable=SC2046
			mongo_restorecmd "$_uri" $(job_dump_args) --gzip --drop --archive="$_f" ||
				die "mongorestore failed"
		done
		ok "databases restored"
	elif [ -d "$_d/files" ]; then
		bk_job_local || die "a cold copy can only be put back on the machine that holds the files"
		_dbp="$(job_dbpath)"
		[ -d "$_d/files$_dbp" ] || die "that archive holds no copy of $_dbp"
		_aside="$_dbp.before-restore-$(date -u +%Y%m%dT%H%MZ)"
		step "stopping $(svc) to put the dbPath back"
		svc_stop "$(svc)"
		mv "$_dbp" "$_aside" || die "could not move $_dbp aside; nothing was changed"
		mkdir -p "$_dbp"
		cp -a "$_d/files$_dbp/." "$_dbp/" || die "the copy failed. The old directory is at $_aside"
		chown -R mongod:mongod "$_dbp" 2>/dev/null || chown -R mongodb:mongodb "$_dbp" 2>/dev/null || true
		svc_start "$(svc)" || die "mongod will not start on the restored dbPath. The old one is at $_aside"
		ok "dbPath restored to $_dbp"
		info "the old one is at $_aside — delete it yourself when you are sure."
	else
		die "that archive has no database in it"
	fi
	bk_close
}

do_list()   { bk_list "$JOB"; }
do_verify() { bk_verify "$JOB" "${1:-$(param archive)}"; }

# ----------------------------------------------------------------- state --
is_installed() { [ -f "$CHECK_FILE" ]; }

do_status() {
	is_installed || exit 2
	bk_job_card "$JOB" "$(job_where)"
}

do_install() {
	need_root
	bk_need_store || die "nothing was installed."

	if bk_seed "$JOB" <<EOF
host=127.0.0.1
port=27017
user=$(job_read_user)
password=$(job_read_pass)
authdb=admin
databases=
method=dump
store=$(bk_setting store none)
folder=
prune_remote=off
schedule=daily
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
EOF
	then
		info "read this machine's install:"
		info "  host      127.0.0.1"
		info "  port      27017"
		if [ -n "$(job_read_user)" ]; then
			info "  user      $(job_read_user)  (from $APP_SETUP_SECRETS/mongodb.txt)"
		else
			info "  user      (none — this server has authorization off)"
		fi
	fi

	dump_tool_check mongodump "this job can take a logical backup"
	bk_keep_warn
	bk_migrate
	bk_cron_rebuild
	if [ "$(param schedule daily)" = off ]; then
		info "schedule is off — nothing runs on a timer. ▶ Back up now still works."
	else
		ok "scheduled $(param schedule daily), minute $(bk_cron_minute "$JOB")"
	fi
	save_note "$JOB" <<EOF
Backup job — MongoDB

  server      $(job_where)
  user        $(param user | sed 's/^$/(none — authorization is off)/')
  databases   $(param databases | sed 's/^$/(all of them)/')
  method      $(param method dump)
  goes to     $(bk_setting store none):$(bk_folder)
  schedule    $(param schedule daily)
  keeps       $(param keep_hourly 0) hourly, $(param keep_daily 7) daily, $(param keep_weekly 4) weekly, $(param keep_monthly 6) monthly
  archives    $BK_DIR/$JOB/

  Run one now:      app-setup backup $JOB
  See what exists:  sh $APP_SETUP_CONF/$JOB.sh list
  Put one back:     app-setup restore $JOB
EOF
	ok "ready."
}

# mongodb.sh writes the admin credential into secrets/mongodb.txt when it turns
# authorization on. Read, not asked for — and nothing is discovered when this
# machine has no mongod, which is the normal shape for a job pointed elsewhere.
job_read_user() {
	sed -n 's/^ *user *//p'     "$APP_SETUP_SECRETS/mongodb.txt" 2>/dev/null | head -1
}
job_read_pass() {
	sed -n 's/^ *password *//p' "$APP_SETUP_SECRETS/mongodb.txt" 2>/dev/null | head -1
}

do_uninstall() {
	drop_note "$JOB"
	rm -f "$CHECK_FILE"
	bk_cron_rebuild
	warn "$BK_DIR/$JOB was NOT deleted — your archives are still there."
}

do_help() {
	if lang_zh; then
		cat <<EOF
MongoDB 备份任务

  为什么用 --archive
    出来是**一个文件**，不是一整个目录的 BSON。一个文件才能 scp、才能上传、
    才能塞进这一页的存储源里。也因为这样，「立即备份」和手动 dump 是同一条
    命令，只是写到不同地方。

  两种方式
    dump   mongodump --archive --gzip，热备，不停服务，能备远程机器。默认
    files  停掉 mongod、拷 dbPath、再启动。一定有停机时间，只能备本机

  认证
    用户留空 = 这台服务器没开 authorization（mongodb.sh 装出来默认就是这样，
    除非你自己开过）。开了的话，安装时会从
    $APP_SETUP_SECRETS/mongodb.txt 里把 admin 账号读出来。

    密码里有 @ / : 这类字符是会出问题的 —— 它们在连接串里有含义。这里会
    转义好再拼，所以你按原样填就行。

  恢复
    ⟲ 恢复 用的是 --drop：同名的集合会**先被删掉**再写回去。archive 里
    没有的集合不会被动。

  用它
    app-setup backup $JOB
    app-setup restore $JOB
EOF
	else
		cat <<EOF
MongoDB backup job

  Why --archive
    It produces **one file** rather than a directory of BSON. One file is what
    can be scp'd, uploaded, and handed to a store on this tab — and it is why
    ▶ Back up now and a manual dump are the same command with a different
    destination.

  Two methods
    dump   mongodump --archive --gzip, hot, nothing stops, reaches another
           host. The default.
    files  stop mongod, copy the dbPath, start it again. Always costs
           downtime, and this machine only.

  Authentication
    A blank User means this server has authorization off — which is how
    mongodb.sh leaves it unless you turned it on. If it is on, install reads
    the admin credential out of $APP_SETUP_SECRETS/mongodb.txt.

    A password containing @ : / or ? would otherwise split the connection
    string in the wrong place, and the error you get says "no such host",
    which sends people looking at the network. They are escaped here, so type
    the password as it is.

  Restoring
    ⟲ Restore uses --drop: a collection of the same name is **deleted first**
    and then written back. Collections not in the archive are left alone.

  Using it
    app-setup backup $JOB
    app-setup restore $JOB
EOF
	fi
}

app_main "$@"
