#!/bin/sh
# app-setup: 1
# id: backup-postgresql
# name: PostgreSQL
# name.zh: PostgreSQL 备份
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 21
# summary: pg_dumpall, or a hot physical copy over the replication protocol — which is the one backup here that reaches another host properly.
# summary.zh: pg_dumpall，或者走复制协议的物理热备 —— 这是这一页里唯一一个能真正备份远程机器的物理备份。
# includes: pg_dumpall, a cron line, and one dated .tgz per run
# includes.zh: pg_dumpall、一条 cron、每次一个带日期的 .tgz
# disk: 20M
# memory: 32M
# requires: a store on this tab, set up and tested
# requires.zh: 本页里配置好并测试通过的一个备份源
#
# group: source | The database | 数据库 |
# param: host      |      | Host (blank = the local socket) | 主机（留空=本机 socket） |
# param: port      | 5432 | Port                    | 端口     | number
# param: user      |      | User                    | 用户     |
# param: password  |      | Password                | 密码     |
# param: databases |      | Databases (blank = all) | 数据库（留空=全部） |
#
# group: how | How | 方式 |
# param: method | dump | Method | 方式 | dump,binary,files
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
# The local case here is the good case, and unusually so: on the unix socket
# Postgres uses peer authentication, so a job pointed at this machine stores no
# password at all — there is nothing in params/ that a stolen container could
# read. Only a job pointed at another host ever holds a credential, and that one
# goes in a .pgpass at mode 600 rather than into a command line.
. /usr/lib/app-setup/common.sh

JOB=backup-postgresql
CHECK_FILE="$APP_SETUP_CONF/params/$JOB.conf"

SERVICE="postgresql"

# ------------------------------------------------------------ connection --
job_conn() {
	local _h
	_h="$(param host)"
	# Blank host is the local socket, which is peer auth as the postgres user
	# and needs nothing stored. That is the default, and it is the default on
	# purpose.
	[ -n "$_h" ] || { PG_CONN=""; return 0; }
	JOB_TMP="$(tmp_dir)"
	pg_conn_file "$JOB_TMP/pgpass" "$_h" "$(param port 5432)" \
		"$(param user postgres)" "$(param password)" >/dev/null
}

job_conn_drop() { [ -n "${JOB_TMP:-}" ] && rm -rf "$JOB_TMP"; JOB_TMP=""; return 0; }

job_where() {
	if [ -n "$(param host)" ]; then printf '%s:%s' "$(param host)" "$(param port 5432)"
	else printf 'the local socket'; fi
}

# Where the cluster keeps its files. Only ever asked when it is on this machine.
job_pgdata() {
	local _d
	for _d in /var/lib/postgresql/*/data /var/lib/postgresql/*/main \
	          /var/lib/pgsql/*/data /var/lib/pgsql/data /var/lib/postgresql/data; do
		[ -f "$_d/PG_VERSION" ] && { printf '%s' "$_d"; return 0; }
	done
	printf ''
}

# ---------------------------------------------------------------- backup --
do_backup() {
	local _m _db
	bk_need_store || exit 1
	_m="$(param method dump)"
	# files is a copy of a directory on the server's own disk. binary is not —
	# see job_basebackup — so only files is refused for a remote host.
	if [ "$_m" = files ] && ! bk_job_local "$(param host 127.0.0.1)"; then
		warn "method=files copies the server's own data directory, and $(param host) is"
		warn "not this machine. Falling back to dump."
		_m=dump
	fi
	job_conn
	bk_begin "$JOB"
	case "$_m" in
	files)
		warn "method=files stops the cluster while its files are copied."
		_db="$(job_pgdata)"
		[ -n "$_db" ] || die "cannot find the data directory on this machine"
		step "stopping $(svc)"
		svc_running "$(svc)" && { BK_SVC_WAS="$(svc)"; svc_stop "$(svc)"; }
		bk_add "$_db"
		;;
	binary)
		job_basebackup || {
			warn "falling back to pg_dumpall."
			step "dumping every database, role and tablespace from $(job_where)"
			pg_dumpcmd > "$(bk_path all.sql)" || die "pg_dumpall failed"
			[ -s "$(bk_path all.sql)" ] || die "the dump came out empty; that is not a backup"
		}
		;;
	*)
		step "dumping every database, role and tablespace from $(job_where)"
		if [ -n "$(param databases)" ]; then
			# Named databases, one file each, through pg_dump rather than
			# pg_dumpall — pg_dumpall has no way to select. Roles come along
			# separately because a per-database dump does not carry them, and
			# a restore into a cluster that has never heard of the owner fails
			# on the first GRANT.
			for _db in $(param databases | tr ',' ' '); do
				step "  $_db"
				if [ -n "$PG_CONN" ]; then
					# shellcheck disable=SC2086
					pg_dump $PG_CONN -Fc "$_db" > "$(bk_path "$_db.dump")"
				else
					su postgres -c "pg_dump -Fc '$_db'" > "$(bk_path "$_db.dump")"
				fi || die "could not dump $_db"
			done
			pg_dumpcmd --roles-only > "$(bk_path roles.sql)" || true
		else
			pg_dumpcmd > "$(bk_path all.sql)" || die "pg_dumpall failed — is the cluster running?"
			[ -s "$(bk_path all.sql)" ] || die "the dump came out empty; refusing to call that a backup"
		fi
		;;
	esac
	bk_finish
	job_conn_drop
}

# The one genuinely good remote physical backup on this tab. pg_basebackup
# speaks the replication protocol rather than reading the data directory, so it
# works against a server on another machine — which nothing else in the
# `binary` column of this feature can say.
#
# It needs wal_level >= replica (the default since 9.6) and a role with
# REPLICATION. Failing back to a dump is the right answer when it does not, and
# saying which one was taken is the difference between a restore that works and
# one that surprises somebody.
job_basebackup() {
	have pg_basebackup || { warn "pg_basebackup is not installed here"; return 1; }
	step "physical copy over the replication protocol, without stopping the cluster"
	mkdir -p "$(bk_path binary)"
	if [ -n "$PG_CONN" ]; then
		# shellcheck disable=SC2086
		pg_basebackup $PG_CONN -D "$(bk_path binary)" -Ft -X stream >/dev/null 2>&1 || {
			warn "pg_basebackup failed — the server needs wal_level >= replica and a"
			warn "role with REPLICATION, and pg_hba.conf must let it connect."
			return 1
		}
	else
		su postgres -c "pg_basebackup -D '$(bk_path binary)' -Ft -X stream" >/dev/null 2>&1 || {
			warn "pg_basebackup failed — check wal_level and the replication role."
			return 1
		}
	fi
	cat > "$(bk_path binary/HOW-TO-RESTORE.txt)" <<EOF
This is a physical PostgreSQL backup taken with pg_basebackup -Ft -X stream.
base.tar is the data directory; pg_wal.tar is the WAL streamed alongside it.

Putting it back is deliberately not one button. It is:

  1. stop the server
  2. move the existing data directory aside — do not delete it
  3. unpack base.tar into the new data directory, and pg_wal.tar into its
     pg_wal/ subdirectory
  4. decide whether this is a restore or a standby, and write the right file:
       a restore  -> touch <PGDATA>/recovery.signal
       a standby  -> touch <PGDATA>/standby.signal
     (before PG 12 this was recovery.conf instead, and the contents differ)
  5. chown -R postgres:postgres <PGDATA> && chmod 700 <PGDATA>
  6. start the server and watch the log until it says it has reached a
     consistent recovery state

Step 4 is why this is not a button: what "right" is changed at PG 12 and is
different again for a cluster that was taking WAL archives. A recipe that
guesses here does not fail loudly — it produces a server that starts and is
missing the last hour.
EOF
	ok "physical copy taken"
	return 0
}

# --------------------------------------------------------------- restore --
do_restore() {
	local _d _f _pgd _aside
	if bk_job_local "$(param host 127.0.0.1)" && [ -z "$(param host)" ]; then
		recipe_ensure postgresql
		svc_running "$(svc)" || { step "starting $(svc)"; svc_start "$(svc)"; svc_settle "$(svc)" || true; }
	fi
	job_conn
	bk_open "$JOB" "${1:-$(param archive)}"
	_d="$BK_UNPACKED"

	if [ -f "$_d/all.sql" ]; then
		# pg_dumpall's output is CREATE-then-populate and expects a live
		# cluster and a superuser. It does not drop what is already there, so
		# an existing database of the same name collides loudly rather than
		# being silently half-overwritten.
		step "loading all.sql into $(job_where)"
		job_psql_file "$_d/all.sql"
		ok "cluster restored"
	elif ls "$_d"/*.dump >/dev/null 2>&1; then
		[ -f "$_d/roles.sql" ] && { step "restoring roles"; job_psql_file "$_d/roles.sql"; }
		for _f in "$_d"/*.dump; do
			step "restoring $(basename "$_f" .dump)"
			if [ -n "$PG_CONN" ]; then
				# shellcheck disable=SC2086
				pg_restore $PG_CONN --clean --if-exists -d "$(basename "$_f" .dump)" "$_f" ||
					warn "pg_restore reported errors on $(basename "$_f") — read them"
			else
				cp "$_f" /tmp/app-setup-restore.dump
				chown postgres /tmp/app-setup-restore.dump 2>/dev/null || true
				su postgres -c "pg_restore --clean --if-exists -d '$(basename "$_f" .dump)' /tmp/app-setup-restore.dump" ||
					warn "pg_restore reported errors on $(basename "$_f") — read them"
				rm -f /tmp/app-setup-restore.dump
			fi
		done
		ok "databases restored"
	elif [ -d "$_d/binary" ]; then
		# Deliberately not one button. See the file the backup wrote beside
		# the tars, and §4 of docs/app-setup.backup.md for why.
		_pgd="$(job_pgdata)"
		_aside="$BK_DIR/$JOB/restore-$(date -u +%Y%m%dT%H%MZ)"
		mkdir -p "$_aside"
		cp -a "$_d/binary/." "$_aside/" || die "could not unpack it beside the cluster"
		err "this is a physical backup, and putting one back is not one button."
		info ""
		cat "$_aside/HOW-TO-RESTORE.txt" 2>/dev/null | sed 's/^/    /'
		info ""
		info "The archive is unpacked and waiting at:"
		info "    $_aside"
		info "This cluster's data directory is:"
		info "    ${_pgd:-(not on this machine)}"
		info "Nothing has been changed. Do the six steps above, in that order."
		bk_close
		job_conn_drop
		return 1
	elif [ -d "$_d/files" ]; then
		_pgd="$(job_pgdata)"
		[ -n "$_pgd" ] || die "cannot find a data directory to restore into"
		[ -d "$_d/files$_pgd" ] || die "that archive holds no copy of $_pgd"
		_aside="$_pgd.before-restore-$(date -u +%Y%m%dT%H%MZ)"
		step "stopping $(svc) to put the data directory back"
		svc_stop "$(svc)"
		mv "$_pgd" "$_aside" || die "could not move $_pgd aside; nothing was changed"
		mkdir -p "$_pgd"
		cp -a "$_d/files$_pgd/." "$_pgd/" || die "the copy failed. The old directory is at $_aside"
		chown -R postgres:postgres "$_pgd" 2>/dev/null || true
		chmod 700 "$_pgd" 2>/dev/null || true
		svc_start "$(svc)" || die "postgres will not start on the restored directory. The old one is at $_aside"
		ok "data directory restored to $_pgd"
		info "the old one is at $_aside — delete it yourself when you are sure."
	else
		die "that archive has no database in it"
	fi
	bk_close
	job_conn_drop
}

# psql has to read the file as the postgres user, and /root is not somewhere
# that user can get to on most of these images.
job_psql_file() {  # job_psql_file <file>
	if [ -n "$PG_CONN" ]; then
		# shellcheck disable=SC2086
		psql $PG_CONN -q -f "$1" || warn "psql reported errors — read them before assuming this worked"
	else
		cp "$1" /tmp/app-setup-restore.sql
		chown postgres /tmp/app-setup-restore.sql 2>/dev/null || true
		su postgres -c "psql -q -f /tmp/app-setup-restore.sql" ||
			warn "psql reported errors — read them before assuming this worked"
		rm -f /tmp/app-setup-restore.sql
	fi
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
host=
port=5432
user=postgres
password=
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
		info "  host      (blank — the local socket)"
		info "  port      5432"
		info "  user      postgres"
		info "  password  (none stored — the socket is peer auth)"
	fi

	dump_tool_check pg_dumpall "this job can take a logical backup"
	bk_keep_warn
	bk_migrate
	bk_cron_rebuild
	if [ "$(param schedule daily)" = off ]; then
		info "schedule is off — nothing runs on a timer. ▶ Back up now still works."
	else
		ok "scheduled $(param schedule daily), minute $(bk_cron_minute "$JOB")"
	fi
	save_note "$JOB" <<EOF
Backup job — PostgreSQL

  cluster     $(job_where)
  user        $(param user postgres)
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

do_uninstall() {
	drop_note "$JOB"
	rm -f "$CHECK_FILE"
	bk_cron_rebuild
	warn "$BK_DIR/$JOB was NOT deleted — your archives are still there."
}

do_help() {
	if lang_zh; then
		cat <<EOF
PostgreSQL 备份任务

  本机这一种是最省事的
    主机留空 = 走本机 unix socket。Postgres 在 socket 上用的是 peer 认证，
    所以**一个密码都不用存** —— params/ 里没有任何东西是偷到容器的人能用的。
    只有连别的机器时才需要填密码，那个会写进一个 600 权限的 .pgpass，
    不会出现在命令行里。

  先做哪一步
    先在本页配好一个备份源，按「测试连接」通过。没有目的地的任务装不上。

  三种方式
    dump     pg_dumpall，热备。留空数据库就是整个集群（含角色、表空间）；
             填了名字就每个库一个 -Fc 文件，另外单独存一份角色。**默认**
    binary   pg_basebackup -Ft -X stream。**这是这一页里唯一一个能真正备份
             远程机器的物理备份** —— 它走的是复制协议，不是读文件。
             需要 wal_level >= replica（9.6 以后是默认）和一个有 REPLICATION
             权限的角色
    files    停掉集群、拷 \$PGDATA、再启动。一定有停机时间。只能备本机

  物理备份的恢复不是一个按钮
    这是故意的。把 pg_basebackup 放回去，要停服务、把旧目录挪开、解包、
    然后**判断这是一次恢复还是要做一个备库**，再把 recovery.signal /
    standby.signal 写对 —— 这件事在 PG 12 变过一次，对开了 WAL 归档的集群
    又不一样。这里猜错不会响亮地失败，它会给你一个能启动、但少了最近一小时
    数据的服务器。
    所以 ⟲ 恢复 遇到物理备份时，会把它解到数据目录旁边，把这个版本的
    Postgres 该敲的命令打出来，然后停下。这比一个错的按钮值钱得多。

  保留梯度
    每小时 $(param keep_hourly 0) / 每天 $(param keep_daily 7) / 每周 $(param keep_weekly 4) / 每月 $(param keep_monthly 6)
    留下每个小时/天/周/月里最新的那一份，只要那个周期还在额度内。

  用它
    app-setup backup $JOB
    app-setup restore $JOB
EOF
	else
		cat <<EOF
PostgreSQL backup job

  The local case is the easy one, and unusually so
    A blank Host means the local unix socket, where Postgres uses peer
    authentication — so **no password is stored anywhere at all**. There is
    nothing in params/ for a stolen container to read. You only ever type a
    credential for another host, and that one goes into a .pgpass at mode 600
    rather than onto a command line.

  Do this first
    Set up a store on this tab and press ✓ Test connection until it passes. A
    job with nowhere to send its output will not install.

  Three methods
    dump     pg_dumpall, hot. Blank Databases is the whole cluster, roles and
             tablespaces included; naming some gives one -Fc file each plus a
             separate roles dump. **The default.**
    binary   pg_basebackup -Ft -X stream. **The one physical backup on this
             tab that properly reaches another host** — it speaks the
             replication protocol rather than reading the data directory.
             Needs wal_level >= replica (the default since 9.6) and a role
             with REPLICATION.
    files    stop the cluster, copy \$PGDATA, start it. Always costs downtime,
             and this machine only.

  Restoring a physical backup is deliberately not one button
    Putting a pg_basebackup back is: stop, move the old \$PGDATA aside,
    unpack, **decide whether this is a restore or a standby**, and get
    recovery.signal / standby.signal right — which changed at PG 12 and is
    different again for a cluster that was taking WAL archives. Guessing here
    does not fail loudly; it produces a server that starts and is missing the
    last hour.

    So ⟲ Restore on a physical archive unpacks it beside the data directory,
    prints the commands for this version of Postgres, and stops. That is worth
    considerably more than a wrong button.

  The retention ladder
    $(param keep_hourly 0) hourly / $(param keep_daily 7) daily / $(param keep_weekly 4) weekly / $(param keep_monthly 6) monthly. An archive is kept if it
    is the newest in its hour, day, week or month and that period is still
    inside the matching budget.

  Using it
    app-setup backup $JOB
    app-setup restore $JOB
EOF
	fi
}

app_main "$@"
