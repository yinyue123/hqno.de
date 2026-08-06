#!/bin/sh
# app-setup: 1
# id: nettools
# name: Network tools
# name.zh: 网络工具包
# category: system
# order: 15
# summary: ping, dig, netstat, traceroute, tcpdump — everything you need to answer "is it the network?"
# summary.zh: ping、dig、netstat、traceroute、tcpdump——排查"是不是网络问题"用的全套。
# includes: iputils, net-tools, iproute2, bind-utils, traceroute, mtr, tcpdump
# includes.zh: ping、netstat、ss、dig、traceroute、mtr、tcpdump
# disk: 20M
# memory: 0
. /usr/lib/app-setup/common.sh

PKGS="iputils-ping net-tools iproute2 dnsutils traceroute mtr-tiny tcpdump"
PKGS_rpm="iputils net-tools iproute bind-utils traceroute mtr tcpdump"
PKGS_apk="iputils net-tools iproute2 bind-tools traceroute mtr tcpdump"
# Not CHECK_BIN="ping": busybox provides a ping applet in the base Alpine
# image, so every fresh Alpine box read as "network tools installed". tcpdump
# is in all three package lists and busybox has no applet by that name.
CHECK_PKG="tcpdump"

version_line() { echo "ping, dig, ss, netstat, traceroute, mtr, tcpdump"; }

do_install() {
	enable_epel
	pkg_install $(pmv PKGS)
}

# iproute2 is not a network *tool* here, it is plumbing: on Debian and Ubuntu
# nginx and a good deal else depend on it, and apt answers a purge that
# includes it with "impossible situation" and then removes none of the other
# six either. The whole uninstall was a silent no-op. Ask for the six.
do_uninstall() {
	local _p _keep _want
	_keep="iproute2 iproute"
	_want=""
	for _p in $(pmv PKGS); do
		case " $_keep " in *" $_p "*) continue ;; esac
		_want="$_want $_p"
	done
	pkg_remove $_want
	info "ip(8) was left installed — it is part of the base system here, not"
	info "part of this package, and removing it would take nginx with it."
}

do_help() { cat <<'EOF'
Network tools

  Work through it in this order when something cannot be reached.

  1. Is the name resolving?
       dig +short example.com
       dig @1.1.1.1 +short example.com     ask a public resolver instead
     Different answers mean your resolver is the problem, not the site.

  2. Can you reach the host at all?
       ping -c 4 example.com
     Note that many hosts drop ping on purpose; a timeout here is a hint,
     not a verdict.

  3. Where does it stop?
       traceroute example.com
       mtr --report --report-cycles 10 example.com    same thing, with loss

  4. Is the port open?
       nc -zv example.com 443        (nc comes with the base image)
     Not "is the server up" but "is this one service listening".

  5. What is listening on *this* machine?
       ss -ltnp                      every TCP port, and who holds it
       netstat -ltnp                 the older command, same answer

  6. What is actually on the wire?
       tcpdump -i any -n port 80 -c 20

  In a container
    The address you see on eth0 is private to this container. Whatever the
    outside world connects to belongs to the host, so a service that answers
    on 127.0.0.1 here may still be unreachable from your laptop — check that
    it binds 0.0.0.0 and that the port is published.
EOF
}

app_main "$@"
