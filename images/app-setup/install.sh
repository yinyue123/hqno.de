#!/bin/sh
#
# install.sh — put app-setup on this machine the way the images put it in a
# container. Same binary, same three paths, same login hint:
#
#   /bin/app-setup              the picker
#   /usr/lib/app-setup/         the helpers every recipe sources
#   /etc/app-setup/*.sh         one file per package
#   /var/log/app-setup/         every action's output
#   /var/lib/app-setup/         state, settings, the refresh stamp
#   /etc/profile.d/app-setup.sh the usage banner on an interactive login
#
# It is the install block of help/images/*/Dockerfile, run against `/` instead
# of against an image, so that what you are testing here is what ships.
#
#   sh install.sh              install, demo recipes included
#   sh install.sh --no-demo    install exactly what an image gets
#   sh install.sh --uninstall  take it all off again
#   sh install.sh --check      the demo cycle on the CLI, exit code a line
#
# Then just type: app-setup
#
# Note that this is a real install: `app-setup` on this machine can install
# nginx on this machine, the same as it would in a container. The four demo
# recipes are the safe ones — they are named 演示 / Demo, install nothing, and
# only write under /var/lib/app-setup/demo.
set -e

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
demo=1

for a in "$@"; do
	case "$a" in
		--no-demo)   demo=0 ;;
		--uninstall) mode=uninstall ;;
		--check)     mode=check ;;
		-h|--help)   sed -n '/^# install.sh/,/^set -e/p' "$0" | sed 's/^#\{0,1\} \{0,1\}//' | sed '$d'; exit 0 ;;
		*) echo "install.sh: unknown option: $a" >&2; exit 2 ;;
	esac
done

[ "$(id -u)" = 0 ] || { echo "install.sh: needs root — try: sudo sh $0 $*" >&2; exit 1; }

case "${mode-}" in
uninstall)
	rm -f /bin/app-setup /etc/profile.d/app-setup.sh
	rm -rf /usr/lib/app-setup /etc/app-setup
	echo "removed the binary, the helpers, the recipes and the login hint."
	echo "left alone: /var/log/app-setup and /var/lib/app-setup — rm -rf them"
	echo "yourself if you want the logs and saved settings gone too."
	exit 0
	;;
check)
	command -v app-setup >/dev/null 2>&1 || { echo "install.sh: not installed yet — run without --check first" >&2; exit 1; }
	DEMO_SPEED=0; export DEMO_SPEED
	# `status` answers with its exit code, so a non-zero one here is the
	# expected answer rather than a failure — hence the `if`, which also keeps
	# `set -e` from ending the run at the first stopped service.
	run() { printf '%-40s ' "$*"; if "$@" >/dev/null 2>&1; then echo "rc=0"; else echo "rc=$?"; fi; }
	app-setup --version
	run app-setup doctor
	run app-setup status demo-web          # 2, absent
	run app-setup install demo-web
	run app-setup status demo-web          # 0, running
	run app-setup set demo-web port=9090
	run app-setup install demo-web         # again — the reinstall path
	app-setup status demo-web || true      # the port change must show here
	run app-setup stop demo-web
	run app-setup status demo-web          # 1, stopped
	run app-setup start demo-web
	run app-setup install demo-fail        # expected to fail
	run app-setup remove demo-web
	run app-setup status demo-web          # 2, absent again
	exit 0
	;;
esac

# ------------------------------------------------------------------ build --
# The images compile against musl in an Alpine builder stage and get a ~150KB
# static binary. Here it is whatever this machine's cc produces; the source is
# the same file, which is the part that matters for testing.
cc=""
for c in ${CC:-} cc gcc clang; do
	[ -n "$c" ] || continue
	command -v "$c" >/dev/null 2>&1 && { cc=$c; break; }
done
[ -n "$cc" ] || { echo "install.sh: no C compiler. apt install gcc" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "compiling with $cc …"
"$cc" -static -O2 -s -o "$tmp/app-setup" "$here/app-setup.c" 2>/dev/null ||
	"$cc" -O2 -s -o "$tmp/app-setup" "$here/app-setup.c"

# ---------------------------------------------------------------- install --
# Same order, same modes, same doctor check as the Dockerfile.
install -m 0755 "$tmp/app-setup" /bin/app-setup

rm -rf /usr/lib/app-setup /etc/app-setup
mkdir -p /usr/lib/app-setup /etc/app-setup /var/log/app-setup /var/lib/app-setup
for f in "$here"/lib/*.sh;     do install -m 0644 "$f" /usr/lib/app-setup/; done
for f in "$here"/recipes/*.sh; do install -m 0755 "$f" /etc/app-setup/; done
if [ "$demo" = 1 ]; then
	for f in "$here"/demo/*.sh; do install -m 0755 "$f" /etc/app-setup/; done
fi

printf '%s\n' \
  '# What somebody wants on the way in: how much of their box is left, and' \
  '# the two words that do something about it. Delete this file to stay quiet.' \
  'case $- in' \
  '  *i*)' \
  '    # The usage block is the daemon'"'"'s answer, and is silent when it cannot' \
  '    # be reached: a login must never wait on it, or report to somebody' \
  '    # holding a shell prompt a thing they cannot do anything about.' \
  '    app-setup dashboard --brief 2>/dev/null' \
  '    case "${LANG-}${LC_ALL-}" in' \
  '      zh*|*zh_CN*)' \
  '        printf "\033[2m装软件：\033[0m\033[1mapp-setup\033[0m\033[2m — LNMP、WordPress、数据库、开发环境\033[0m\n"' \
  '        printf "\033[2m看状态：\033[0m\033[1mdashboard\033[0m\033[2m — 配额、流量、端口、域名、到期\033[0m\n" ;;' \
  '      *)' \
  '        printf "\033[2mInstall software: \033[0m\033[1mapp-setup\033[0m\033[2m — web servers, databases, WordPress, dev tools.\033[0m\n"' \
  '        printf "\033[2mCheck this box:   \033[0m\033[1mdashboard\033[0m\033[2m — allowances, traffic, ports, domains, expiry.\033[0m\n" ;;' \
  '    esac' \
  '    ;;' \
  'esac' \
  > /etc/profile.d/app-setup.sh
chmod 0644 /etc/profile.d/app-setup.sh

app-setup doctor >/dev/null

n=$(ls /etc/app-setup/*.sh 2>/dev/null | wc -l)
echo
echo "installed. $n recipes in /etc/app-setup, binary $(wc -c < /bin/app-setup) bytes."
[ "$demo" = 1 ] && echo "the four under 演示 / Demo install nothing — start with those."
echo
echo "now type:  app-setup"
