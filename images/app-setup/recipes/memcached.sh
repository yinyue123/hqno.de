#!/bin/sh
# app-setup: 1
# id: memcached
# name: Memcached
# name.zh: Memcached
# category: db
# order: 14
# summary: A plain memory cache. Smaller and simpler than Redis, and that is the whole pitch.
# summary.zh: 纯内存缓存。比 Redis 小、比 Redis 简单，卖点就是这个。
# includes: memcached, bound to localhost
# includes.zh: memcached 服务，只监听本机
# disk: 3M
# memory: 64M
# ports: 11211
# service: memcached
. /usr/lib/app-setup/common.sh

PKGS="memcached"
SERVICE="memcached"
CHECK_BIN="memcached"

version_line() { printf 'memcached %s' "$(memcached --version 2>/dev/null | sed 's/memcached //')"; }

do_install() {
	pkg_install $(pmv PKGS)

	# Memcached has no authentication at all in its default mode. The only
	# thing standing between it and the internet is the address it binds.
	for _f in /etc/memcached.conf /etc/sysconfig/memcached /etc/conf.d/memcached; do
		[ -f "$_f" ] || continue
		backup_once "$_f"
		case "$_f" in
			/etc/memcached.conf)
				grep -q '^-l ' "$_f" && sed -i 's/^-l .*/-l 127.0.0.1/' "$_f" || echo '-l 127.0.0.1' >> "$_f"
				;;
			*)
				sed -i 's/^OPTIONS=.*/OPTIONS="-l 127.0.0.1"/' "$_f" 2>/dev/null || true
				grep -q '^OPTIONS=' "$_f" || echo 'OPTIONS="-l 127.0.0.1"' >> "$_f"
				;;
		esac
	done

	svc_enable "$(svc)"
	svc_start "$(svc)" || die "memcached would not start"
	ok "memcached is running on 127.0.0.1:11211"
}

do_help() { cat <<'EOF'
Memcached

  Check it
    echo stats | nc 127.0.0.1 11211 | head
    (nc comes with the base image; `stats` is the only command you can type
    by hand that is worth anything.)

  Using it
    PHP     apt-get install php-memcached   (dnf install php-pecl-memcached,
            apk add php83-memcached), then restart php-fpm
    Node    npm install memjs
    Both connect to 127.0.0.1:11211 with no password.

  Redis or this?
    Memcached does exactly one thing: key to value, in memory, evicted when
    full. No persistence, no data types, no pub/sub, no scripting. If you
    want any of those, install Redis instead. If you want a cache in front
    of a database and nothing more, this uses less memory per key and is
    genuinely simpler to reason about.

  Why it is on localhost only
    Memcached has no authentication. Anything that can reach the port can
    read and overwrite every cached item, and for years it was the largest
    source of amplified denial-of-service traffic on the internet because
    its UDP port would answer strangers. Keep it on 127.0.0.1.

  Size
    The default is 64MB. To change it, edit the -m value:
      /etc/memcached.conf         Debian, Ubuntu, Alpine
      /etc/sysconfig/memcached    AlmaLinux, Rocky, CentOS
    Then restart. There is no point setting it larger than the memory your
    container was actually given.
EOF
}

app_main "$@"
