#!/bin/sh
# app-setup: 1
# id: backup-mysql
# name: MySQL / MariaDB
# name.zh: MySQL / MariaDB 备份
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 20
# summary: Dump every database on a MySQL or MariaDB server — this one or another host — pack it, send it, thin the old ones.
# summary.zh: 把一台 MySQL / MariaDB 上的所有库导出来 —— 本机或者别的机器都行 —— 打包、传走、按梯度清理旧的。
# includes: mysqldump, a cron line, and one dated .tgz per run
# includes.zh: mysqldump、一条 cron、每次一个带日期的 .tgz
# disk: 20M
# memory: 32M
# requires: a store on this tab, set up and tested
# requires.zh: 本页里配置好并测试通过的一个备份源
#
# group: source | The database | 数据库 |
# param: host      | 127.0.0.1 | Host                    | 主机     |
# param: port      | 3306      | Port                    | 端口     | number
# param: user      | root      | User                    | 用户     |
# param: password  |           | Password                | 密码     |
# param: databases |           | Databases (blank = all) | 数据库（留空=全部） |
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
# This is a separate card from `mysql` on the Databases tab, and the split is
# the point: `mysql` is a server you install, start and stop on this machine;
# this is a database you connect to, which may be on another host and which you
# may not have installed at all. A container running only PHP, talking to a
# database somewhere else, has nothing on the Databases tab and everything here.
#
# There is no second mysqldump command line in this file. mysql_dumpcmd in
# common.sh is the only one in the tree, and `mysql.sh do_backup` and this card
# both point it at a connection — because the two must never drift into
# disagreeing about what a correct dump of this database is, and the one that
# drifts is always the one on the timer that nobody watches.
. /usr/lib/app-setup/common.sh

JOB=backup-mysql
CHECK_FILE="$APP_SETUP_CONF/params/$JOB.conf"

# The engine's service, only ever touched when the database is on this machine.
SERVICE="mariadb"

# ------------------------------------------------------------ connection --
# MY_DEFAULTS is what every mysql client in common.sh runs through. Pointing it
# at a throwaway file keeps the password out of `ps`, where a command-line
# -p would sit for the whole length of the dump.
#
# An empty password means *use the local credential file*, not *no password*:
# for a MariaDB on this machine the secret is never copied into a second place,
# and only somebody connecting to another host ever types one. That also
# disposes of the worst part of a plain-text form field — the common case never
# fills it in.
job_conn() {
	local _t
	_t="${JOB_CNF:-}"
	[ -n "$_t" ] || { JOB_TMP="$(tmp_dir)"; _t="$JOB_TMP/my.cnf"; JOB_CNF="$_t"; }
	MY_DEFAULTS="$(mysql_conn_cnf "$_t" \
		"$(param host 127.0.0.1)" "$(param port 3306)" \
		"$(param user root)" "$(param password)")"
	export MY_DEFAULTS
}

job_conn_drop() { [ -n "${JOB_TMP:-}" ] && rm -rf "$JOB_TMP"; JOB_TMP=""; JOB_CNF=""; return 0; }

job_where() { printf '%s:%s' "$(param host 127.0.0.1)" "$(param port 3306)"; }

# The named databases, or nothing at all, which mysql_dump_all reads as "every
# one on the server".
job_dbs() { printf '%s' "$(param databases | tr ',' ' ')"; }

# ---------------------------------------------------------------- backup --
do_backup() {
	local _m
	bk_need_store || exit 1
	_m="$(param method dump)"
	if [ "$_m" != dump ] && ! bk_job_local; then
		warn "$_m is a copy of files on the server's own disk, and $(param host) is"
		warn "not this machine. Falling back to dump, which goes over the wire."
		_m=dump
	fi
	job_conn
	bk_begin "$JOB"
	case "$_m" in
	files)
		# Always costs downtime, and always says so before it starts.
		# bk_begin's EXIT trap is what guarantees the server comes back —
		# including on a full disk or a Ctrl-C, which is why it is a trap and
		# not a tidy-up at the end.
		warn "method=files stops the database while its files are copied."
		step "stopping $(svc)"
		svc_running "$(svc)" && { BK_SVC_WAS="$(svc)"; svc_stop "$(svc)"; }
		bk_add "$(job_datadir)"
		;;
	binary)
		job_binary || {
			warn "falling back to a cold copy of the data directory."
			warn "method=files stops the database while its files are copied."
			step "stopping $(svc)"
			svc_running "$(svc)" && { BK_SVC_WAS="$(svc)"; svc_stop "$(svc)"; }
			bk_add "$(job_datadir)"
		}
		;;
	*)
		step "dumping $(job_where)"
		# An empty or truncated dump tarred up anyway is the failure this
		# whole feature exists to prevent; mysql_dump_all checks.
		# shellcheck disable=SC2046  # the database list is meant to split
		mysql_dump_all "$(bk_path all.sql)" $(job_dbs)
		;;
	esac
	# The config travels with the data when there is any to travel — restoring
	# a dump onto a server sized for a different machine is how you find out
	# the sizing drop-in mattered.
	if bk_job_local; then
		bk_add /etc/mysql
		bk_add /etc/my.cnf.d
	fi
	bk_finish
	job_conn_drop
}

# Where MariaDB keeps its files here. Only ever asked when the server is local.
job_datadir() {
	local _d
	_d="$(mysql_root -N -B -e 'SELECT @@datadir;' 2>/dev/null | sed 's#/$##')"
	[ -n "$_d" ] || _d=/var/lib/mysql
	printf '%s' "$_d"
}

# A physical copy taken by the database's own tool, without stopping it —
# 纯二进制备份. The package is mariadb-backup on Debian and Alpine and
# MariaDB-backup on the RPM rebuilds, and absent altogether on a machine
# running Oracle MySQL. Non-zero here means the caller falls back to a cold
# copy, having said so: a stop-copy-start somebody was told about is a
# different thing from a site that went down at 04:41 for no stated reason.
job_binary() {
	local _bin
	for _bin in mariabackup mariadb-backup xtrabackup; do
		have "$_bin" && break
		_bin=""
	done
	if [ -z "$_bin" ]; then
		step "installing mariadb-backup"
		pkg_install_first mariadb-backup MariaDB-backup mariadb-backup-10.11 >/dev/null 2>&1 || true
		for _bin in mariabackup mariadb-backup xtrabackup; do
			have "$_bin" && break
			_bin=""
		done
	fi
	[ -n "$_bin" ] || { warn "no mariadb-backup on this machine, and it would not install."; return 1; }
	step "physical copy with $_bin, without stopping the server"
	mkdir -p "$(bk_path binary)"
	"$_bin" --defaults-file="$MY_DEFAULTS" --backup --target-dir="$(bk_path binary)" \
		>/dev/null 2>&1 || { warn "$_bin failed"; return 1; }
	# Restoring one of these needs --prepare run over it first. do_restore does
	# that; somebody unpacking the archive by hand has to be told, so it is
	# written into the archive beside the files.
	cat > "$(bk_path binary/HOW-TO-RESTORE.txt)" <<EOF
This is a physical MariaDB backup taken with $_bin.
It is NOT usable as-is. Before the files can be started on:

    $_bin --prepare --target-dir=<this directory>

then stop the server, put the directory in place of the data directory,
chown -R mysql:mysql it, and start.

app-setup does all of that for you:  app-setup restore $JOB
EOF
	ok "physical copy taken"
	return 0
}

# --------------------------------------------------------------- restore --
do_restore() {
	local _d _was _bin
	# No bk_need_store here: an archive already on this disk is restorable with
	# no destination configured at all, and bk_open says the useful thing when
	# there is neither a local copy nor a remote to fetch one from.
	#
	# The case this whole feature exists for: a reinstalled container has
	# /data and nothing else — no MariaDB, no /root/.my.cnf. `restore` on a
	# bare machine has to install the engine before it can load anything into
	# it, which is the same composition `lnmp` already uses for nginx.
	if bk_job_local; then
		recipe_ensure mysql
		svc_running "$(svc)" || { step "starting $(svc)"; svc_start "$(svc)"; mysql_wait || true; }
	fi
	job_conn
	bk_open "$JOB" "${1:-$(param archive)}"
	_d="$BK_UNPACKED"

	if [ -f "$_d/all.sql" ]; then
		step "loading all.sql into $(job_where) — this replaces the databases in it"
		mysql_root < "$_d/all.sql" || die "the import failed; nothing else was touched"
		mysql_root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
		ok "databases restored"
		# A restored dump brings its own users and passwords, which are the
		# ones from the old machine and not the ones `install mysql` just
		# generated. Saying so is the difference between a puzzle and a step.
		if bk_job_local && [ -f "$MY_CNF" ]; then
			if ! mysql --defaults-file="$MY_CNF" -e 'SELECT 1' >/dev/null 2>&1; then
				warn "$MY_CNF no longer works: the restored dump brought the old"
				warn "machine's root password with it. Put that password into"
				warn "$MY_CNF, or set a new one with SET PASSWORD."
			fi
		fi
	elif [ -d "$_d/binary" ]; then
		bk_job_local || die "a physical backup can only be put back on the machine that holds the files"
		for _bin in mariabackup mariadb-backup xtrabackup; do have "$_bin" && break; _bin=""; done
		[ -n "$_bin" ] || die "restoring this needs mariadb-backup, which is not here"
		step "preparing the physical copy with $_bin --prepare"
		"$_bin" --prepare --target-dir="$_d/binary" >/dev/null 2>&1 ||
			die "--prepare failed; the data directory was not touched"
		_was="$(job_datadir)"
		job_swap_datadir "$_was" "$_d/binary"
	elif [ -d "$_d/files" ]; then
		bk_job_local || die "a cold copy can only be put back on the machine that holds the files"
		_was="$(job_datadir)"
		[ -d "$_d/files$_was" ] || die "that archive holds no copy of $_was"
		job_swap_datadir "$_was" "$_d/files$_was"
	else
		die "that archive has no database in it"
	fi
	bk_close
	job_conn_drop
}

# Every swap moves the old directory aside rather than deleting it. Restoring
# from the wrong archive is a thing people do at four in the morning, and the
# five seconds this costs is the difference between a mistake and an incident.
# It is deleted by the holder, never by us.
job_swap_datadir() {  # job_swap_datadir <live datadir> <what to put there>
	local _aside
	_aside="$1.before-restore-$(date -u +%Y%m%dT%H%MZ)"
	step "stopping $(svc) to put the data directory back"
	svc_stop "$(svc)"
	mv "$1" "$_aside" || die "could not move $1 aside; nothing was changed"
	mkdir -p "$1"
	cp -a "$2/." "$1/" || die "the copy failed. The old directory is at $_aside"
	chown -R mysql:mysql "$1" 2>/dev/null || true
	svc_start "$(svc)" || die "MariaDB will not start on the restored data directory. The old one is at $_aside"
	ok "data directory restored to $1"
	info "the old one is at $_aside — $(du -sh "$_aside" 2>/dev/null | awk '{print $1}'). Delete it yourself when you are sure."
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
	# Dies before it seeds anything or writes a cron line. Somebody arrives
	# here, at do_status and at ▶ Back up now, and all three say the same
	# sentence because it is the same problem.
	bk_need_store || die "nothing was installed."

	if bk_seed "$JOB" <<EOF
host=127.0.0.1
port=$(job_read_port)
user=root
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
		info "  host      127.0.0.1"
		info "  port      $(job_read_port)"
		info "  user      root"
		info "  password  (left empty — $MY_CNF is here and will be used)"
	fi

	dump_tool_check mysqldump "this job can take a logical backup"
	bk_keep_warn
	bk_migrate
	bk_cron_rebuild
	if [ "$(param schedule daily)" = off ]; then
		info "schedule is off — nothing runs on a timer. ▶ Back up now still works."
	else
		ok "scheduled $(param schedule daily), minute $(bk_cron_minute "$JOB")"
	fi
	save_note "$JOB" <<EOF
Backup job — MySQL / MariaDB

  database    $(job_where)
  user        $(param user root)
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

# The running server's port, read rather than asked for. Nothing is discovered
# when there is no server here — the form then comes up on its declared
# defaults and the card stays in error until a host answers.
job_read_port() {
	local _p
	_p="$(mysql --defaults-file="$MY_CNF" -N -B -e 'SELECT @@port;' 2>/dev/null)" ||
		_p="$(mysql --protocol=socket -uroot -N -B -e 'SELECT @@port;' 2>/dev/null)" || _p=""
	case "$_p" in ''|*[!0-9]*) _p=3306 ;; esac
	printf '%s' "$_p"
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
MySQL / MariaDB 备份任务

  它和「数据库」页那张 mysql 卡的区别
    那张卡是**装一个服务**：装上、启动、停止，都在这台机器上。
    这张卡是**连一个数据库**：可以是本机的，也可以是另一台机器上的，
    甚至你根本没装过数据库 —— 一个只跑 PHP、连别人家数据库的容器，
    在「数据库」页什么都没有，在这里什么都有。

  先做哪一步
    先在本页配好一个备份源（S3 / R2 / WebDAV / FTP / rsync / SCP），
    按「测试连接」通过。没有目的地的任务是装不上的，也不会偷偷跑。

  数据库这一组
    主机/端口   默认读本机正在跑的那个
    用户        默认 root
    密码        **留空 = 用本机的 $MY_CNF**，不是「没有密码」。
                只有连别的机器时才需要真的填一个。
    数据库      留空就是全部

  三种方式
    dump     mysqldump，热备，不停服务。能连别的机器。**默认，多数人用这个**
    binary   mariabackup 物理热备。需要 mariadb-backup 这个包；装不上就
             退回 files，并且会告诉你退了。只能备本机
    files    停掉数据库，直接拷数据目录，再启动。**一定会有停机时间**，
             开始之前会说。只能备本机

  保留梯度
    每小时 $(param keep_hourly 0) / 每天 $(param keep_daily 7) / 每周 $(param keep_weekly 4) / 每月 $(param keep_monthly 6)
    规则是：一份备份，如果它是它所在的那个小时/天/周/月里最新的一份，
    并且那个小时/天/周/月还在对应的额度里，就留下。其余删掉。
    按默认值、每天一备，一年多的历史会收敛到 14 个文件。

    有一个地方容易想错：**每天保留 7 是七个「天」，不是七份备份。**
    如果你设的是每周一备，那七天里最多只有一份，daily 这一档就只留 1 个。

  恢复
    ▤ 列出所有备份    本地和远端都列出来，两边不是同一批
    ✓ 校验            下载、解开、看里面是不是一个完整的导出。不碰数据库
    ⟲ 恢复            把「哪一份」里写的那个放回去；留空就是最新的一份

    恢复到一台空机器上：先 install backup-mysql，再把备份源和目录填对，
    然后 ⟲ 恢复 —— 它会先把 MariaDB 装上，再往里灌。

  用它
    app-setup backup $JOB
    app-setup restore $JOB
EOF
	else
		cat <<EOF
MySQL / MariaDB backup job

  How this differs from the mysql card on the Databases tab
    That one is **a server you install**: install it, start it, stop it, all on
    this machine. This one is **a database you connect to** — here, or on
    another host, or on a machine where you never installed anything. A
    container running only PHP against somebody else's database has nothing on
    the Databases tab and everything here.

  Do this first
    Set up a store on this tab (S3, R2, WebDAV, FTP, rsync or SCP) and press
    ✓ Test connection until it passes. A job with nowhere to send its output
    will not install, and will not quietly run either.

  The database
    Host / Port   read from the server running here, if one is
    User          root by default
    Password      **blank means use this machine's $MY_CNF**, not "no
                  password". You only ever type one for another host.
    Databases     blank is all of them

  Three methods
    dump     mysqldump, hot, nothing stops. Reaches another host.
             **The default, and the right answer for most people.**
    binary   mariabackup — a physical copy, hot. Needs the mariadb-backup
             package; if that will not install it falls back to files and says
             so. This machine only.
    files    stop the database, copy the data directory, start it again.
             **Always costs downtime**, and always says so first. This
             machine only.

  The retention ladder
    $(param keep_hourly 0) hourly / $(param keep_daily 7) daily / $(param keep_weekly 4) weekly / $(param keep_monthly 6) monthly.
    The rule: keep an archive if it is the newest one in its hour, day, week
    or month, and that period is inside the matching budget. Delete the rest.
    At the defaults, on a daily schedule, a year of history settles at 14
    files.

    One thing that surprises everybody: **keep_daily 7 is seven *days*, not
    seven backups.** On a weekly schedule at most one archive is ever inside
    seven days, so that rung keeps one.

  Putting one back
    ▤ List backups   both sides, labelled — they are not the same set
    ✓ Verify         downloads, unpacks, checks it holds a complete dump.
                     Never touches the database, safe on a running site.
    ⟲ Restore        loads what is in "Which one"; blank is the newest.

    Onto a bare container: install $JOB first, set the store and folder, then
    Restore — it installs MariaDB before it loads anything into it.

  Using it
    app-setup backup $JOB
    app-setup restore $JOB
EOF
	fi
}

app_main "$@"
