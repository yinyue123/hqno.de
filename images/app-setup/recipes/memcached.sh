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

# KEY="value" in a shell-sourced conf file: replace the line if it is there,
# add it if it is not. Never append blindly — these files are sourced, so a
# second assignment silently wins over the first and the file stops saying
# what the daemon is doing.
mc_var() {   # mc_var <file> <key> <value>
	if grep -qE "^[[:space:]]*$2=" "$1"; then
		sed -i "s|^[[:space:]]*$2=.*|$2=\"$3\"|" "$1"
	else
		printf '%s="%s"\n' "$2" "$3" >> "$1"
	fi
}

# `-flag value` on its own line, which is Debian's memcached.conf format.
mc_flag() {  # mc_flag <file> <flag> <value>
	if grep -qE "^[[:space:]]*\\$2[[:space:]]" "$1"; then
		sed -i "s|^[[:space:]]*\\$2[[:space:]].*|$2 $3|" "$1"
	else
		printf '%s %s\n' "$2" "$3" >> "$1"
	fi
}

do_install() {
	pkg_install $(pmv PKGS)

	# Memcached is the one service here whose memory is a single number and
	# whose default — 64MB — is half of a small container. It is also a hard
	# ceiling rather than a hint: memcached allocates slabs up to -m and
	# evicts rather than growing, so this is the whole story.
	if [ "$(mem_profile)" = normal ]; then
		_mb=64
	else
		_mb="$(mem_share 16 8 64)"
		step "sizing memcached for $(mem_total_mb)MB of memory"
	fi

	# Memcached has no authentication at all in its default mode. The only
	# thing standing between it and the internet is the address it binds.
	#
	# Three config formats, and they share nothing. Writing OPTIONS= into all
	# of them is the obvious thing and it is wrong: Alpine's OpenRC script
	# never reads OPTIONS. It builds the command line out of LISTENON,
	# MEMUSAGE and MAXCONN, so a `-l 127.0.0.1` written to OPTIONS there goes
	# into a variable nothing reads — and memcached with no password is not a
	# thing to be wrong about by accident. Check with the command line it
	# actually got, never with the file:
	#
	#   grep -a memcached /proc/*/cmdline
	for _f in /etc/memcached.conf /etc/sysconfig/memcached /etc/conf.d/memcached; do
		[ -f "$_f" ] || continue
		backup_once "$_f"
		case "$_f" in
			/etc/memcached.conf)
				# Debian: the file *is* the argument list, one flag per line.
				mc_flag "$_f" '-l' '127.0.0.1'
				mc_flag "$_f" '-m' "$_mb"
				;;
			/etc/conf.d/memcached)
				# Alpine, Gentoo: OpenRC assembles the flags from these.
				mc_var "$_f" LISTENON '127.0.0.1'
				mc_var "$_f" MEMUSAGE "$_mb"
				;;
			/etc/sysconfig/memcached)
				# RHEL: CACHESIZE is its own variable and beats OPTIONS.
				mc_var "$_f" CACHESIZE "$_mb"
				mc_var "$_f" OPTIONS '-l 127.0.0.1'
				;;
		esac
	done

	svc_enable "$(svc)"
	if svc_running "$(svc)"; then
		svc_restart "$(svc)" || die "memcached would not come back up"
	else
		svc_start "$(svc)" || die "memcached would not start"
	fi
	ok "memcached is running on 127.0.0.1:11211, holding at most ${_mb}MB"
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
