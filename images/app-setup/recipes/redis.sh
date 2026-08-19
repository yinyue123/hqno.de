#!/bin/sh
# app-setup: 1
# id: redis
# name: Redis
# name.zh: Redis 缓存
# category: db
# order: 12
# summary: In-memory cache and queue. Bound to localhost with a password, because the alternative gets you owned.
# summary.zh: 内存缓存和队列。只监听本机并设了密码——不这么做的机器基本都被人挖矿了。
# includes: redis server, a generated password, localhost-only binding
# includes.zh: redis 服务端、自动生成的密码、只监听本机
# disk: 15M
# memory: 64M
# ports: 6379
# service: redis
# param: backup | default | Backup | 备份 | default,dump,files
# action: backup | backup | ▶ Back up now | ▶ 立即备份
. /usr/lib/app-setup/common.sh

PKGS="redis-server"
PKGS_rpm="redis"
PKGS_apk="redis"
SERVICE="redis-server"
SERVICE_rpm="redis"
SERVICE_apk="redis"
CHECK_BIN="redis-server"

redis_conf() {
	for _f in /etc/redis/redis.conf /etc/redis.conf /etc/redis/redis.conf.default; do
		[ -f "$_f" ] && { printf '%s' "$_f"; return 0; }
	done
	printf ''
}

version_line() {
	_v="$(redis-server --version 2>/dev/null | sed 's/.*v=//;s/ .*//')"
	printf 'Redis %s, localhost only' "$_v"
}

MARK='# --- app-setup sizing ---'

# Redis ships with **no maxmemory at all**. The default is not "a sensible
# fraction of the machine", it is "keep accepting writes until something
# dies", and on a small container the something is usually not Redis — it is
# whichever neighbour the kernel picks. A cache with no ceiling is the single
# most common way one of these boxes falls over.
#
# The other half is BGSAVE. Saving forks, and the fork's copy-on-write can
# briefly cost as much again as the dataset, so the snapshot schedule is
# stretched out here rather than left at the default's five overlapping rules.
redis_tune() {   # redis_tune <conf>
	local _conf _max
	_conf="$1"
	[ -n "$_conf" ] && [ -f "$_conf" ] || return 0

	# Ours is a block at the end: redis takes the last value for a key, so
	# appending overrides the shipped line without editing it. Strip the
	# previous block first or reinstalling stacks them up.
	if grep -qF "$MARK" "$_conf" 2>/dev/null; then
		if awk -v m="$MARK" 'index($0, m) { exit } { print }' "$_conf" > "$_conf.new"; then
			mv -f "$_conf.new" "$_conf"
		else
			rm -f "$_conf.new"
			warn "could not rewrite $_conf; leaving redis's own settings alone"
			return 0
		fi
	fi
	[ "$(mem_profile)" = normal ] && return 0

	# An eighth of the machine. Redis holds more than the values themselves —
	# key overhead, the expiry table, client buffers — so the process is
	# reliably larger than maxmemory, not equal to it.
	_max="$(mem_share 8 8 512)"

	step "sizing Redis for $(mem_total_mb)MB of memory"
	cat >> "$_conf" <<EOF
$MARK
$(tuning_header)
# Without this Redis has no ceiling and will grow until the kernel intervenes.
maxmemory ${_max}mb
# What to throw away when it reaches that. allkeys-lru treats Redis as a
# cache, which is what it is here; if you are using it as a durable store
# instead, change this to noeviction and give the machine more memory.
maxmemory-policy allkeys-lru

# One snapshot rule rather than the default's three overlapping ones: BGSAVE
# forks, and the copy-on-write during a save is the memory spike that kills a
# small box. \`save ""\` on its own line would turn snapshots off entirely.
save 900 1
stop-writes-on-bgsave-error no
EOF
	info "Redis: maxmemory ${_max}mb, allkeys-lru"
}

do_install() {
	enable_epel
	pkg_install $(pmv PKGS)

	_conf="$(redis_conf)"
	if [ -n "$_conf" ]; then
		backup_once "$_conf"
		# An open Redis with no password is the single most reliably exploited
		# thing on the internet: it will write an SSH key into your
		# authorized_keys through the CONFIG SET trick within hours.
		# `bind 127.0.0.1 -::1` — the leading dash meaning "bind this as well,
		# but do not refuse to start if it is unavailable" — arrived in Redis
		# 6.2. Ubuntu 22.04 and Debian 11 ship 6.0, where the dash is not
		# special: redis looks for a host literally called `-::1`, cannot find
		# it, and exits. The whole install failed on those, which is a large
		# part of the apt fleet.
		#
		#   Could not create server TCP listening socket -::1:6379:
		#   Name or service not known
		_rv="$(redis-server --version 2>/dev/null | sed 's/.*v=//;s/ .*//')"
		if version_ge "${_rv:-0}" 6.2; then _bind='bind 127.0.0.1 -::1'
		else                                _bind='bind 127.0.0.1'; fi
		sed -i "s/^[[:space:]]*bind .*/$_bind/" "$_conf"
		grep -q '^bind ' "$_conf" || echo "$_bind" >> "$_conf"
		sed -i 's/^[[:space:]]*protected-mode .*/protected-mode yes/' "$_conf"

		if ! grep -q '^requirepass ' "$_conf"; then
			_pw="$(rand_pass 32)"
			printf '\n# added by app-setup\nrequirepass %s\n' "$_pw" >> "$_conf"
			save_note redis <<EOF
Redis

  password        $_pw
  listening on    127.0.0.1:6379 only

  Command line:
    redis-cli -a '$_pw' ping

  From an application, the URL form:
    redis://:$_pw@127.0.0.1:6379/0
EOF
		fi
		redis_tune "$_conf"
	else
		warn "no redis.conf found; it is running with the package defaults"
	fi

	svc_enable "$(svc)"
	if svc_running "$(svc)"; then
		svc_restart "$(svc)" || die "redis would not come back up; check its log"
	else
		svc_start "$(svc)" || die "redis would not start; check its log"
	fi
	ok "Redis is running on 127.0.0.1:6379"
	show_note redis
	dump_tool_check redis-cli "app-setup dump redis writes an .rdb snapshot"
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove $(pmv PKGS)
	drop_note redis
	info "/var/lib/redis was left in place"
}

# -------------------------------------------------------- dump/load/backup --
# Redis has no mysqldump, and it does not need one: `redis-cli --rdb` asks the
# server for a full RDB and streams it out. That is better than BGSAVE plus a
# copy of dump.rdb, which races the fork that is still writing the file, and it
# works against a Redis that is not on this filesystem at all.
redis_cli_auth() {
	local _pw
	_pw="$(sed -n 's/^requirepass //p' "$(redis_conf)" 2>/dev/null | tail -1 | tr -d '"')"
	if [ -n "$_pw" ]; then redis-cli -a "$_pw" --no-auth-warning "$@"
	else                   redis-cli "$@"; fi
}

redis_dir() {
	local _d
	_d="$(redis_cli_auth --raw CONFIG GET dir 2>/dev/null | sed -n 2p)"
	[ -n "$_d" ] || _d=/var/lib/redis
	printf '%s' "$_d"
}

redis_rdb_to() {   # redis_rdb_to <file>
	redis_cli_auth --rdb "$1" >/dev/null 2>&1 ||
		die "could not get a snapshot — is redis running, and is the password in $(redis_conf) still current?"
	[ -s "$1" ] || die "the snapshot came out empty; that is not a backup"
}

do_dump() {
	local _f
	_f="$(dump_target redis rdb "${1-}")"
	step "asking redis for a snapshot"
	redis_rdb_to "$_f"
	chmod 600 "$_f"
	ok "$_f  ($(du -h "$_f" 2>/dev/null | awk '{print $1}'))"
	info "put it back with:  app-setup load redis"
}

# Loading is a stop-copy-start and cannot be anything else: Redis reads
# dump.rdb once, at startup, and writes its own out on the way down — so
# replacing the file under a running server means the shutdown save overwrites
# exactly what was just restored.
redis_rdb_from() { # redis_rdb_from <file>
	local _dir
	_dir="$(redis_dir)"
	step "stopping $(svc)"
	svc_stop "$(svc)"
	cp "$1" "$_dir/dump.rdb" || die "could not write $_dir/dump.rdb"
	chown redis:redis "$_dir/dump.rdb" 2>/dev/null || true
	svc_start "$(svc)" || die "redis will not start on that snapshot"
}

do_load() {
	local _f
	_f="$(dump_source redis rdb "${1-}")"
	step "loading $_f"
	warn "this replaces everything currently in Redis"
	redis_rdb_from "$_f"
	ok "loaded — $(redis_cli_auth --raw DBSIZE 2>/dev/null || echo '?') keys"
}

do_backup() {
	bk_begin redis
	if [ "$(bk_method)" = files ]; then
		bk_quiesce
		bk_add "$(redis_dir)"
	else
		step "asking redis for a snapshot"
		redis_rdb_to "$(bk_path dump.rdb)"
	fi
	bk_add "$(redis_conf)"
	bk_finish
}

do_restore() {
	local _d _dir
	bk_open redis "${1-}"
	_d="$BK_UNPACKED"
	_dir="$(redis_dir)"
	if [ -f "$_d/dump.rdb" ]; then
		redis_rdb_from "$_d/dump.rdb"
	elif [ -d "$_d/files$_dir" ]; then
		step "stopping $(svc) to put the data directory back"
		svc_stop "$(svc)"
		bk_restore_files "$_d"
		chown -R redis:redis "$_dir" 2>/dev/null || true
		svc_start "$(svc)" || die "redis will not start on the restored data directory"
	else
		die "that archive has no snapshot in it"
	fi
	ok "restored — $(redis_cli_auth --raw DBSIZE 2>/dev/null || echo '?') keys"
	bk_close
}

do_help() { cat <<'EOF'
Redis

  Your password
    cat /etc/app-setup/secrets/redis.txt

  Talk to it
    redis-cli -a "$(awk '/password/{print $2}' /etc/app-setup/secrets/redis.txt)" ping
    → PONG

    Or start redis-cli and type: AUTH thepassword

  The commands you will actually use
    SET key value          GET key
    SETEX key 300 value    expires in 300 seconds
    DEL key                EXISTS key
    KEYS pattern           never on a busy server — it blocks; use SCAN
    INFO memory            how much it is holding
    FLUSHALL               delete everything, immediately, no confirmation

  Using it as a PHP or Node cache
    PHP     needs the redis extension: apt-get install php-redis
            (dnf install php-pecl-redis, apk add php83-redis)
    Node    npm install redis
    Both want the URL: redis://:PASSWORD@127.0.0.1:6379/0

  Why it is locked down like this
    Redis with no password on a public address is the most reliably
    exploited service there is. The attack does not need a bug: an
    anonymous client can CONFIG SET the data directory to /root/.ssh and
    write itself an authorized_keys. Scanners find a new one in minutes.

    So: bind 127.0.0.1, protected-mode yes, requirepass set. If you need
    another machine to reach it, put it behind a private network or an SSH
    tunnel rather than opening 6379.

  Memory limits
    By default Redis grows until the container's memory runs out and
    something gets killed. If you are using it purely as a cache, tell it
    to evict instead, in redis.conf:
      maxmemory 128mb
      maxmemory-policy allkeys-lru

  Persistence
    Out of the box it snapshots to /var/lib/redis. If you are using Redis
    as a cache, that is wasted disk — `save ""` turns it off. If you are
    using it as a queue you actually care about, read up on AOF first.

  Where things are
    /etc/redis/redis.conf  or  /etc/redis.conf
    /var/lib/redis         snapshots
EOF
}

app_main "$@"
