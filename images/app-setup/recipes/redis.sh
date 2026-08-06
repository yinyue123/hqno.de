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
	else
		warn "no redis.conf found; it is running with the package defaults"
	fi

	svc_enable "$(svc)"
	svc_start "$(svc)" || die "redis would not start; check its log"
	ok "Redis is running on 127.0.0.1:6379"
	show_note redis
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove $(pmv PKGS)
	drop_note redis
	info "/var/lib/redis was left in place"
}

do_help() { cat <<'EOF'
Redis

  Your password
    cat /root/.app-setup/redis.txt

  Talk to it
    redis-cli -a "$(awk '/password/{print $2}' /root/.app-setup/redis.txt)" ping
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
