#!/bin/sh
# app-setup: 1
# id: backup-redis
# name: Redis
# name.zh: Redis 备份
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 22
# summary: An RDB snapshot, asked for over the wire — the server writes a whole one down the socket without stopping.
# summary.zh: 一份 RDB 快照，通过连接直接要过来 —— 服务器不停机，把整份写到 socket 上。
# includes: redis-cli, a cron line, and one dated .tgz per run
# includes.zh: redis-cli、一条 cron、每次一个带日期的 .tgz
# disk: 20M
# memory: 32M
# requires: a store on this tab, set up and tested
# requires.zh: 本页里配置好并测试通过的一个备份源
#
# group: source | The database | 数据库 |
# param: host     | 127.0.0.1 | Host     | 主机 |
# param: port     | 6379      | Port     | 端口 | number
# param: password |           | Password | 密码 |
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
# Redis has two methods and not three, and the card says so rather than
# offering a knob with no effect. `redis-cli --rdb` already produces the
# binary format — an RDB *is* the physical file — and the logical alternative,
# SCAN plus DUMP/RESTORE per key, is slower, larger, and loses TTL precision.
# So `binary` and `dump` would be the same command, and only `dump` is offered.
. /usr/lib/app-setup/common.sh

JOB=backup-redis
CHECK_FILE="$APP_SETUP_CONF/params/$JOB.conf"

SERVICE="redis-server"
SERVICE_rpm="redis"
SERVICE_apk="redis"

# ------------------------------------------------------------ connection --
job_cli() {  # job_cli <redis-cli arguments…>
	redis_cli_at "$(param host 127.0.0.1)" "$(param port 6379)" "$(param password)" "$@"
}

job_where() { printf '%s:%s' "$(param host 127.0.0.1)" "$(param port 6379)"; }

# Where this server keeps its dump.rdb. Asked of the server itself rather than
# guessed from a path, and only ever used when it is on this machine.
job_dir() {
	local _d
	_d="$(job_cli --raw CONFIG GET dir 2>/dev/null | sed -n 2p)"
	[ -n "$_d" ] || _d=/var/lib/redis
	printf '%s' "$_d"
}

job_conf() {
	local _f
	for _f in /etc/redis/redis.conf /etc/redis.conf /etc/redis/redis.conf.default; do
		[ -f "$_f" ] && { printf '%s' "$_f"; return 0; }
	done
	printf ''
}

# ---------------------------------------------------------------- backup --
do_backup() {
	local _m _dir
	bk_need_store || exit 1
	_m="$(param method dump)"
	if [ "$_m" = files ] && ! bk_job_local; then
		warn "method=files copies the server's own directory, and $(param host) is not"
		warn "this machine. Falling back to dump, which asks for the snapshot over"
		warn "the connection."
		_m=dump
	fi
	bk_begin "$JOB"
	case "$_m" in
	files)
		warn "method=files stops redis while its files are copied."
		_dir="$(job_dir)"
		step "stopping $(svc)"
		svc_running "$(svc)" && { BK_SVC_WAS="$(svc)"; svc_stop "$(svc)"; }
		# The append-only log lives beside the RDB and is the newer of the two
		# on a server configured for it. Copying the directory takes both.
		bk_add "$_dir"
		;;
	*)
		step "asking $(job_where) for a snapshot"
		# The server writes a full RDB down the socket. It never blocks for
		# more than the fork, and it works against another machine — which is
		# the whole reason this is the default.
		job_cli --rdb "$(bk_path dump.rdb)" >/dev/null 2>&1 ||
			die "could not get a snapshot — is redis running at $(job_where), and is the password right?"
		[ -s "$(bk_path dump.rdb)" ] || die "the snapshot came out empty; that is not a backup"
		;;
	esac
	[ -n "$(job_conf)" ] && bk_job_local && bk_add "$(job_conf)"
	bk_finish
}

# --------------------------------------------------------------- restore --
# Loading is a stop-copy-start and cannot be anything else: Redis reads
# dump.rdb once, at startup, and writes its own out on the way down — so
# replacing the file under a running server means the shutdown save overwrites
# exactly what was just restored.
do_restore() {
	local _d _dir _aside
	bk_job_local ||
		die "restoring writes a file into the server's own directory, so it can only be done on the machine redis is running on. $(param host) is not this machine."
	recipe_ensure redis
	bk_open "$JOB" "${1:-$(param archive)}"
	_d="$BK_UNPACKED"
	_dir="$(job_dir)"

	if [ -f "$_d/dump.rdb" ]; then
		step "stopping $(svc) — a running server would overwrite what we put back"
		svc_stop "$(svc)"
		_aside="$_dir/dump.rdb.before-restore-$(date -u +%Y%m%dT%H%MZ)"
		[ -f "$_dir/dump.rdb" ] && mv "$_dir/dump.rdb" "$_aside" &&
			info "the old snapshot is at $_aside"
		cp "$_d/dump.rdb" "$_dir/dump.rdb" || die "could not write $_dir/dump.rdb"
		chown redis:redis "$_dir/dump.rdb" 2>/dev/null || true
		# An append-only file that survives the restore is read *instead of*
		# the RDB on the next start, and the restore silently does nothing.
		# That is the one way this goes wrong quietly, so it is checked.
		if [ -f "$_dir/appendonly.aof" ] || [ -d "$_dir/appendonlydir" ]; then
			mv "$_dir/appendonly.aof" "$_dir/appendonly.aof.before-restore-$(date -u +%Y%m%dT%H%MZ)" 2>/dev/null || true
			mv "$_dir/appendonlydir" "$_dir/appendonlydir.before-restore-$(date -u +%Y%m%dT%H%MZ)" 2>/dev/null || true
			warn "this server has appendonly on. The AOF was moved aside, because"
			warn "redis reads it instead of the RDB and the restore would have"
			warn "appeared to do nothing."
		fi
		svc_start "$(svc)" || die "redis will not start on that snapshot"
	elif [ -d "$_d/files$_dir" ]; then
		step "stopping $(svc) to put the directory back"
		svc_stop "$(svc)"
		_aside="$_dir.before-restore-$(date -u +%Y%m%dT%H%MZ)"
		mv "$_dir" "$_aside" || die "could not move $_dir aside; nothing was changed"
		mkdir -p "$_dir"
		cp -a "$_d/files$_dir/." "$_dir/" || die "the copy failed. The old directory is at $_aside"
		chown -R redis:redis "$_dir" 2>/dev/null || true
		svc_start "$(svc)" || die "redis will not start on the restored directory. The old one is at $_aside"
		info "the old directory is at $_aside — delete it yourself when you are sure."
	else
		die "that archive has no snapshot in it"
	fi
	ok "restored — $(job_cli --raw DBSIZE 2>/dev/null || echo '?') keys"
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
port=$(job_read_port)
password=$(job_read_pass)
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
		info "  port      $(job_read_port)  (from $(job_conf))"
		info "  password  $([ -n "$(job_read_pass)" ] && echo '(taken from requirepass)' || echo '(none set on this server)')"
	fi

	dump_tool_check redis-cli "this job can ask redis for a snapshot"
	bk_keep_warn
	bk_migrate
	bk_cron_rebuild
	if [ "$(param schedule daily)" = off ]; then
		info "schedule is off — nothing runs on a timer. ▶ Back up now still works."
	else
		ok "scheduled $(param schedule daily), minute $(bk_cron_minute "$JOB")"
	fi
	save_note "$JOB" <<EOF
Backup job — Redis

  server      $(job_where)
  method      $(param method dump)
  goes to     $(bk_setting store none):$(bk_folder)
  schedule    $(param schedule daily)
  keeps       $(param keep_hourly 0) hourly, $(param keep_daily 7) daily, $(param keep_weekly 4) weekly, $(param keep_monthly 6) monthly
  archives    $BK_DIR/$JOB/

  Run one now:      app-setup backup $JOB
  See what exists:  app-setup archives $JOB
  Check the newest: app-setup verify $JOB
  Put one back:     app-setup restore $JOB
EOF
	ok "ready."
}

# redis.sh already locates the conf per distro; these read the two values out
# of it rather than asking for them again.
job_read_port() {
	local _p _c
	_c="$(job_conf)"
	_p="$(sed -n 's/^port  *//p' "$_c" 2>/dev/null | tail -1 | tr -d '"'"'"' ')"
	case "$_p" in ''|*[!0-9]*) _p=6379 ;; esac
	printf '%s' "$_p"
}

job_read_pass() {
	local _c
	_c="$(job_conf)"
	sed -n 's/^requirepass  *//p' "$_c" 2>/dev/null | tail -1 | tr -d '"'
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
Redis 备份任务

  为什么只有两种方式，没有 binary
    RDB 本身就是二进制格式 —— \`redis-cli --rdb\` 拿到的就是那个文件。
    所谓「逻辑备份」在 Redis 这里是 SCAN + 每个 key 一次 DUMP/RESTORE，
    更慢、更大，而且 TTL 会掉精度。所以 binary 和 dump 会是同一条命令，
    这里就只给一个，不摆一个按下去没区别的开关。

  两种方式
    dump   让服务器把一份完整 RDB 写到连接上。只在 fork 的那一下有停顿，
           **而且能备份另一台机器**。默认
    files  停掉 redis，把整个目录拷走（RDB 和 AOF 都在里面），再启动。
           一定有停机时间，只能备本机

  恢复为什么一定要停机
    Redis 只在启动时读一次 dump.rdb，退出时会把自己内存里的写回去。
    所以在服务器还跑着的时候换掉那个文件，关机时的那次保存会把刚恢复的
    东西原样覆盖掉 —— 恢复看着成功了，其实什么都没发生。

    还有一个更隐蔽的：如果这台开了 appendonly，redis 启动时读的是 AOF，
    **不是** RDB。恢复时会把 AOF 挪开并且告诉你，否则你会看到一次「成功」
    的恢复和一个数据没变的服务器。

  恢复只能在本机做
    它是往服务器自己的目录里写文件。远程的 Redis 备得了、恢复不了 ——
    要恢复就到那台机器上去做。

  用它
    app-setup backup $JOB
    app-setup archives $JOB
    app-setup verify $JOB
    app-setup restore $JOB
EOF
	else
		cat <<EOF
Redis backup job

  Why there are two methods and no \`binary\`
    An RDB *is* the binary format — \`redis-cli --rdb\` hands you that exact
    file. The logical alternative in Redis is SCAN plus DUMP/RESTORE per key,
    which is slower, larger, and loses TTL precision. So \`binary\` and \`dump\`
    would be the same command, and this card offers one rather than a knob
    with no effect behind it.

  Two methods
    dump   the server writes a full RDB down the connection. It blocks only
           for the fork, and **it works against another machine**. The default.
    files  stop redis, copy the whole directory (RDB and AOF both), start it
           again. Always costs downtime, and this machine only.

  Why restoring must stop the server
    Redis reads dump.rdb once, at startup, and writes its own memory back out
    on the way down. Replacing that file under a running server means the
    shutdown save overwrites exactly what was restored — the restore looks
    like it worked and nothing happened.

    There is a quieter version of the same trap: if this server has appendonly
    on, redis reads the AOF at startup and **not** the RDB. The restore moves
    the AOF aside and tells you, because otherwise you get a successful-looking
    restore and a server whose data did not change.

  Restoring only works on this machine
    It writes a file into the server's own directory. A remote Redis can be
    backed up from here and has to be restored over there.

  Using it
    app-setup backup $JOB
    app-setup archives $JOB
    app-setup verify $JOB
    app-setup restore $JOB
EOF
	fi
}

app_main "$@"
