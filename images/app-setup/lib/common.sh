#!/bin/sh
#
# app-setup recipe helpers.
#
# Sourced by every file in /etc/app-setup/*.sh. It exists so a recipe can say
# "install nginx, start it, tell me if it is running" once instead of five
# times — Debian's apt and systemd, Alma's dnf and systemd, Alpine's apk and
# OpenRC, and the two elderly releases that still want yum.
#
# POSIX sh only. Alpine's /bin/sh is busybox ash and has no arrays, no
# `local -a`, no `[[ ]]`, and no bashisms of any kind. `local` itself is not
# POSIX but every shell we run on (dash, ash, bash, ksh) has it.
#
# A recipe looks like this, and nothing more is required:
#
#   #!/bin/sh
#   # app-setup: 1
#   # id: nginx
#   # ... header the TUI reads ...
#   . /usr/lib/app-setup/common.sh
#   PKGS="nginx"
#   SERVICE="nginx"
#   CHECK_BIN="nginx"
#   do_install()   { pkg_install $(pmv PKGS); svc_enable "$(pmv SERVICE)"; }
#   do_uninstall() { pkg_remove  $(pmv PKGS); }
#   do_help()      { cat <<'EOF' ... EOF
#   app_main "$@"
#
# See docs/app-setup-sources.md for the whole contract.

set -e

APP_SETUP_LIB=1
# Everything a person might open lives under one directory, and that directory
# is /etc, because that is where they will look: the recipes as *.sh, what the
# Settings form saved in params/, generated passwords in secrets/ (0700, and
# each file 0600). APP_SETUP_STATE is the other half — bookkeeping nobody
# edits, the package-index refresh stamp above all — and stays in /var/lib.
#
# All three are overridable so the demo recipes under images/app-setup/demo can
# be driven on a workstation without writing anywhere a real install would.
# Nothing in a published image sets any of them.
APP_SETUP_CONF="${APP_SETUP_CONF:-/etc/app-setup}"
APP_SETUP_STATE="${APP_SETUP_STATE:-/var/lib/app-setup}"
APP_SETUP_SECRETS="${APP_SETUP_SECRETS:-$APP_SETUP_CONF/secrets}"

# ---------------------------------------------------------------- output --
# Colour only on a real terminal. Under the TUI the output is a pipe that is
# also being appended to /var/log/app-setup/<id>.log, and a log full of escape
# sequences is a log nobody reads.
if [ -t 1 ]; then
	C_B='\033[1m'; C_D='\033[2m'; C_G='\033[32m'; C_Y='\033[33m'; C_R='\033[31m'; C_0='\033[0m'
else
	C_B=''; C_D=''; C_G=''; C_Y=''; C_R=''; C_0=''
fi

step() { printf '%b==>%b %s\n' "$C_B" "$C_0" "$*"; }
info() { printf '    %s\n' "$*"; }

# The installer screen's progress bar is built out of these, and out of `step`
# above, which every recipe already calls before each phase of its work. That
# is deliberate: the sentence under the bar is the recipe's own, so it says
# "fetching WordPress" rather than something this library invented.
#
# `step_total` is the single line a recipe adds to make the bar a true
# fraction. A recipe that does not declare one still gets a bar — it just
# approaches the end without claiming to know where the end is, which is the
# honest rendering of not knowing. Declare it once, at the top of do_install,
# and count the `step` calls on the path actually taken.
step_total() { printf '==| total %s\n' "$1"; }
ok()   { printf '%b  ok%b %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%b  ! %b %s\n' "$C_Y" "$C_0" "$*" >&2; }
err()  { printf '%b  x %b %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# app-setup exports its own language to every recipe it runs, which is what
# lets a download pick a mirror rather than making somebody in Shanghai wait
# on a US host for 60MB of WordPress.
lang_zh() {
	case "${APP_SETUP_LANG:-${LC_ALL:-${LANG:-}}}" in
		zh*|*zh_CN*|*zh_TW*|*ZH*) return 0 ;;
	esac
	return 1
}

need_root() {
	[ "$(id -u)" = 0 ] || die "this needs root. Run app-setup as root, or with sudo."
}

# ------------------------------------------------------------- settings ---
# A recipe declares what a holder is allowed to change in its header:
#
#   # param: port | 80            | Listen port | 监听端口 | number
#   # param: root | /var/www/html | Document root | 网站目录
#   # param: ssl  | off           | Enable HTTPS  | 启用 HTTPS | bool
#   # param: level| info          | Log level     | 日志级别   | debug,info,warn
#
# and reads it back with `param port 80`. The Settings form in app-setup edits
# those and saves them under $APP_SETUP_CONF/params/<id>.conf — next to the
# recipe itself, so one directory answers "where is the config"; every verb
# then runs with APP_PARAM_PORT and friends in its environment.
#
# The default given here is what applies when nothing has been saved and when
# somebody runs `sh /etc/app-setup/nginx.sh install` by hand, so a recipe never
# depends on the form having been opened.
param() {
	local _n _v
	# Explicit letters rather than a tr range: busybox tr and GNU tr disagree
	# about ranges under some locales, and this runs under both.
	_n="$(printf '%s' "$1" | tr 'abcdefghijklmnopqrstuvwxyz-' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_')"
	eval "_v=\${APP_PARAM_$_n-}"
	[ -n "$_v" ] || _v="${2-}"
	printf '%s' "$_v"
}

# `param_on ssl && ...` — the bool form, accepting everything a person might
# reasonably have typed into the file by hand.
param_on() {
	case "$(param "$1" "${2-}")" in
		on|On|ON|1|yes|Yes|YES|true|True|TRUE) return 0 ;;
	esac
	return 1
}

# --------------------------------------------------------------- identity --
# Read once into plain variables; every branch below reads these rather than
# calling out again.
OS_ID=linux
OS_LIKE=""
OS_VERSION=""
OS_NAME="Linux"
if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	OS_ID="${ID:-linux}"
	OS_LIKE="${ID_LIKE:-}"
	OS_VERSION="${VERSION_ID:-}"
	OS_NAME="${PRETTY_NAME:-$OS_ID}"
	OS_CODENAME="${VERSION_CODENAME:-}"
fi
OS_CODENAME="${OS_CODENAME:-}"
OS_MAJOR="${OS_VERSION%%.*}"
# `-` is legal in an ID (opensuse-leap) and illegal in a shell variable name,
# and pmv() builds variable names out of it.
OS_KEY="$(printf '%s' "$OS_ID" | tr -c 'a-zA-Z0-9' '_')"

if   have apt-get; then PM=apt;    PMF=deb
elif have dnf;     then PM=dnf;    PMF=rpm
elif have yum;     then PM=yum;    PMF=rpm
elif have apk;     then PM=apk;    PMF=apk
elif have zypper;  then PM=zypper; PMF=rpm
elif have pacman;  then PM=pacman; PMF=arch
else PM=none; PMF=none
fi

# systemd is only systemd when it is actually PID 1. `systemctl` exists in
# plenty of images where nothing is listening on the bus, and calling it there
# fails with a message that reads like the package is broken.
if [ -d /run/systemd/system ]; then INIT=systemd
elif have rc-service || [ -f /etc/rc.conf ]; then INIT=openrc
elif [ -d /etc/init.d ] && have service; then INIT=sysv
else INIT=none
fi

case "$(uname -m)" in
	x86_64|amd64)  ARCH=amd64; ARCH_ALT=x86_64  ;;
	aarch64|arm64) ARCH=arm64; ARCH_ALT=aarch64 ;;
	armv7l)        ARCH=armv7; ARCH_ALT=armv7l  ;;
	*)             ARCH="$(uname -m)"; ARCH_ALT="$ARCH" ;;
esac

in_container() {
	[ -f /run/.containerenv ] || [ -f /.dockerenv ] ||
		grep -qE '(docker|lxc|containerd|libpod)' /proc/1/cgroup 2>/dev/null
}

# Most specific wins: a name pinned to this exact distro, then to its package
# manager, then to the family, then the plain one.
#
#   PKGS="python3"  PKGS_apk="python3 py3-pip"  PKGS_centos="python3"
#   $(pmv PKGS)
pmv() {
	local _n _v
	_n="$1"
	eval "_v=\${${_n}_${OS_KEY}-}"
	[ -n "$_v" ] || eval "_v=\${${_n}_${PM}-}"
	[ -n "$_v" ] || eval "_v=\${${_n}_${PMF}-}"
	[ -n "$_v" ] || eval "_v=\${${_n}-}"
	printf '%s' "$_v"
}

# ----------------------------------------------------------------- sizing --
# How much memory this machine really has, in MB.
#
# /proc/meminfo is the *host's* number inside a container unless lxcfs is
# mounted, and half the machines we run on do not have it — which is how a
# 128MB container talks itself into sizing MariaDB for 2G. The cgroup limit is
# the figure that is true either way, so read that first and fall back.
mem_total_mb() {
	local _f _v _m
	_m=""
	for _f in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
		[ -r "$_f" ] || continue
		_v="$(cat "$_f" 2>/dev/null)"
		# "max" is cgroup v2 for no limit. v1 says the same thing with a number
		# so large it is really PAGE_COUNTER_MAX, and dividing it gives nonsense.
		case "$_v" in ''|*[!0-9]*) continue ;; esac
		[ "$_v" -gt 0 ] 2>/dev/null || continue
		[ "$_v" -gt 1099511627776 ] 2>/dev/null && continue
		_m=$((_v / 1024 / 1024))
		break
	done
	if [ -z "$_m" ] || ! [ "$_m" -gt 0 ] 2>/dev/null; then
		_m="$(awk '/^MemTotal:/{print int($2/1024); exit}' /proc/meminfo 2>/dev/null)"
	fi
	[ -n "$_m" ] && [ "$_m" -gt 0 ] 2>/dev/null || _m=1024
	printf '%s' "$_m"
}

# Which set of buffer sizes a service should give itself.
#
#   tiny    under 512MB — every default is wrong and has to be cut
#   small   512MB to under 1G — trim the worst of them
#   normal  1G and up — the distro's defaults are what they were tuned for
#
# Every recipe asks this one question rather than reading `free` its own way,
# which is what stops LNMP and LAMP from disagreeing about what "small" means.
# APP_SETUP_PROFILE overrides it, for a person who knows better than we do and
# for the test rig, which has to exercise all three on one machine.
mem_profile() {
	local _t
	case "${APP_SETUP_PROFILE:-}" in
		tiny|small|normal) printf '%s' "$APP_SETUP_PROFILE"; return 0 ;;
	esac
	_t="$(mem_total_mb)"
	if   [ "$_t" -lt 512  ]; then printf 'tiny'
	elif [ "$_t" -lt 1024 ]; then printf 'small'
	else                          printf 'normal'
	fi
}

# Scale a setting to this machine: one <divisor>th of RAM, held between a
# floor and a ceiling. Every tuned number in every recipe comes from here, so
# they are all the same shape and all move together when the box changes size.
#
#   mem_share 8 8 192      # an eighth of RAM, at least 8MB, at most 192MB
mem_share() {
	local _v
	_v=$(( $(mem_total_mb) / $1 ))
	[ "$_v" -lt "$2" ] && _v="$2"
	[ "$_v" -gt "$3" ] && _v="$3"
	printf '%s' "$_v"
}

# Write a tuning fragment. Every one goes through here so that uninstall has a
# single thing to delete, and so a fragment is never left half-written when
# the disk fills in the middle of it.
tuning_write() {   # tuning_write <path> <<'EOF' ... EOF
	local _p
	_p="$1"
	mkdir -p "$(dirname "$_p")" 2>/dev/null || true
	cat > "$_p.tmp" || { rm -f "$_p.tmp"; warn "could not write $_p"; return 1; }
	mv -f "$_p.tmp" "$_p"
	chmod 644 "$_p"
	info "sized for this machine: $_p"
}

tuning_drop() { rm -f "$1" "$1.tmp"; }

# The header every tuning file carries, so the next person to open one knows
# what wrote it, why, and how to get rid of it.
tuning_header() {
	cat <<EOF
# written by app-setup for a machine with $(mem_total_mb)MB of memory.
# profile: $(mem_profile)
#
# These are ceilings chosen to keep the service alive on a small box, not
# performance settings. Give this machine more memory and run the app-setup
# install again and this file is rewritten to match — above 1G it is removed
# and the distro's own defaults are used, because by then they are right.
# Delete it and restart the service to go back to those defaults now.
EOF
}

# --------------------------------------------------------------- packages --
# DPkg::Lock::Timeout covers dpkg's own lock, which is the one an *install*
# contends for. It does not cover /var/lib/apt/lists/lock, which is what
# `apt-get update` takes — so it is necessary but not sufficient; see
# pm_wait_unlocked. Releases too old to have the option (16.04, 18.04) ignore
# an unknown -o key rather than failing on it.
apt_get() {
	DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=180 "$@"
}

# Is another package operation running right now?
pm_busy() {
	have pgrep || return 1        # cannot tell; do not pretend to wait
	case "$PM" in
		apt)     pgrep -x 'apt|apt-get|dpkg|unattended-upgr' >/dev/null 2>&1 ;;
		dnf|yum) pgrep -x 'dnf|dnf5|yum|rpm' >/dev/null 2>&1 ;;
		apk)     pgrep -x 'apk' >/dev/null 2>&1 ;;
		zypper)  pgrep -x 'zypper|rpm' >/dev/null 2>&1 ;;
		pacman)  pgrep -x 'pacman' >/dev/null 2>&1 ;;
		*)       return 1 ;;
	esac
}

# Every image fetches the package index at boot, so a container a minute old
# has an apt-get holding the lock — and somebody who logs in and immediately
# types `app-setup` lands exactly there. apt's answer to a lock it cannot take
# during `update` is to fail, and the *next* command then reports "Unable to
# locate package wget", which reads like the package does not exist rather than
# like the index was never fetched. unattended-upgrades does the same thing at
# random for the rest of the machine's life.
#
# So: wait for the other operation rather than collide with it. Three minutes
# is longer than a boot-time index fetch and shorter than somebody's patience.
# Waiting on a process rather than retrying the command means a genuine
# failure — no route out, a dead mirror — still fails immediately.
pm_wait_unlocked() {
	local _n
	pm_busy || return 0
	step "another package operation is running; waiting for it to finish"
	_n=0
	while pm_busy && [ "$_n" -lt 90 ]; do
		sleep 2
		_n=$((_n + 1))
	done
	[ "$_n" -lt 90 ] || warn "it is still running after three minutes; carrying on anyway"
	return 0
}

# One refresh per hour, not one per recipe: installing LNMP is four recipes
# deep and `apt-get update` four times is three minutes of nothing.
pm_refresh() {
	local _age _fresh _stamp
	_stamp="$APP_SETUP_STATE/pm-refreshed"
	mkdir -p "$APP_SETUP_STATE"
	if [ -f "$_stamp" ]; then
		_age=$(( $(date +%s) - $(stat -c %Y "$_stamp" 2>/dev/null || echo 0) ))
		[ "$_age" -lt 3600 ] && return 0
	fi
	pm_wait_unlocked
	step "refreshing the package index"
	_fresh=1
	case "$PM" in
		apt)    apt_get update -qq || _fresh=0 ;;
		dnf)    dnf -q makecache   || _fresh=0 ;;
		yum)    yum -q makecache   || _fresh=0 ;;
		apk)    apk update -q      || _fresh=0 ;;
		zypper) zypper -q refresh  || _fresh=0 ;;
		pacman) pacman -Sy --noconfirm >/dev/null || _fresh=0 ;;
	esac
	# Only a refresh that worked gets stamped. Stamping a failed one suppresses
	# the retry for an hour, and every install in that hour then fails with
	# "Unable to locate package" — which reads like the package does not exist
	# rather than like the index was never fetched. On a container created a
	# minute ago that is the difference between app-setup working and app-setup
	# looking broken on first use.
	if [ "$_fresh" = 1 ]; then
		: > "$_stamp"
	else
		warn "could not refresh the package index; will try again on the next install"
	fi
	return 0
}

pkg_install() {
	[ $# -gt 0 ] || return 0
	need_root
	pm_refresh
	pm_wait_unlocked
	step "installing: $*"
	case "$PM" in
		apt)    apt_get install -y --no-install-recommends "$@" ;;
		dnf)    dnf install -y "$@" ;;
		yum)    yum install -y "$@" ;;
		apk)    apk add --no-cache "$@" ;;
		zypper) zypper -n install "$@" ;;
		pacman) pacman -S --noconfirm "$@" ;;
		*)      die "no package manager found on this system" ;;
	esac
}

# Every branch here used to end in `|| true`, so a removal that removed nothing
# was indistinguishable from one that worked. Two ways that happens, both found
# on real containers rather than by reading:
#
#   apt   the transaction is all-or-nothing. One package the system depends on
#         — iproute2 in the nettools list — and apt resolves the whole thing to
#         "impossible situation" and removes *none* of the other six. `remove
#         nettools` and `remove essentials` were both silent no-ops on Ubuntu.
#   apk   refuses a package something else depends on, says so on stdout, and
#         exits 0 regardless. `remove git` and `remove certbot` left both
#         installed and reported success.
#
# `|| true` stays — a recipe removing a package that was never installed must
# not fail — but now something looks at the result and says so. Nothing here
# retries per-package: on apt that would ask it to remove nginx and half the
# system to satisfy one purge, which is worse than doing nothing.
pkg_remove() {
	local _out _rc
	[ $# -gt 0 ] || return 0
	need_root
	pm_wait_unlocked
	step "removing: $*"
	_rc=0
	case "$PM" in
		apt)    _out="$(apt_get purge -y "$@" 2>&1)" || _rc=$?
		        printf '%s\n' "$_out"
		        apt_get autoremove -y >/dev/null 2>&1 || true ;;
		dnf)    _out="$(dnf remove -y "$@" 2>&1)" || _rc=$?
		        printf '%s\n' "$_out" ;;
		yum)    _out="$(yum remove -y "$@" 2>&1)" || _rc=$?
		        printf '%s\n' "$_out" ;;
		apk)    _out="$(apk del "$@" 2>&1)" || _rc=$?
		        printf '%s\n' "$_out"
		        case "$_out" in *"not removed due to"*) _rc=1 ;; esac ;;
		zypper) _out="$(zypper -n remove "$@" 2>&1)" || _rc=$?
		        printf '%s\n' "$_out" ;;
		pacman) _out="$(pacman -Rns --noconfirm "$@" 2>&1)" || _rc=$?
		        printf '%s\n' "$_out" ;;
	esac
	[ "$_rc" = 0 ] && return 0
	# Careful what this claims. A non-zero here means one of two very different
	# things and the output above says which: dnf and apk both fail when asked
	# for a package that was never installed (mongodb's uninstall list on
	# Alpine prints five "No such package" lines), and apt fails when one entry
	# in the list is something the system depends on. Neither is a broken
	# machine, and guessing between them in the message would be worse than
	# describing both.
	warn "not everything on that list came off. Either it was not installed"
	warn "here, or something else on this machine depends on it — the package"
	warn "manager's own output above says which. Nothing was broken."
	return 0
}

pkg_present() {
	case "$PM" in
		apt)    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed' ;;
		dnf|yum|zypper) rpm -q "$1" >/dev/null 2>&1 ;;
		apk)    apk info -e "$1" >/dev/null 2>&1 ;;
		pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
		*)      return 1 ;;
	esac
}

pkg_exists() {          # is this name offered by the configured repos?
	case "$PM" in
		apt)    apt-cache show "$1" >/dev/null 2>&1 ;;
		dnf)    dnf -q info "$1" >/dev/null 2>&1 ;;
		yum)    yum -q info "$1" >/dev/null 2>&1 ;;
		apk)    apk info -e "$1" >/dev/null 2>&1 || apk search -q -x "$1" 2>/dev/null | grep -q . ;;
		zypper) zypper -n info "$1" >/dev/null 2>&1 ;;
		pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
		*)      return 1 ;;
	esac
}

# Install the first name that this distro actually has. Package names drift
# between releases far more than anything else in a recipe — php8.2-fpm on
# Debian 12, php8.4-fpm on 13, php-fpm on Alma.
pkg_install_first() {
	local _p
	pm_refresh
	for _p in "$@"; do
		if pkg_exists "$_p"; then pkg_install "$_p"; return 0; fi
	done
	die "none of these packages exist here: $*"
}

# Best effort: extras that only some distros carry, and whose absence must not
# fail the install.
pkg_install_optional() {
	local _p
	for _p in "$@"; do
		pkg_exists "$_p" 2>/dev/null || continue
		pkg_install "$_p" || warn "could not install $_p; carrying on"
	done
	return 0
}

# Half the ordinary system tools — htop, atop, screen, ncdu, fail2ban — are not
# in a RHEL rebuild's base repos at all. EPEL is where the enterprise distros
# keep the things everyone actually installs, and CRB/PowerTools is where they
# keep the -devel halves.
enable_epel() {
	[ "$PMF" = rpm ] || return 0
	case "$OS_ID" in fedora) return 0 ;; esac      # Fedora carries them itself
	rpm -q epel-release >/dev/null 2>&1 && return 0
	step "enabling EPEL"
	if [ "$PM" = dnf ]; then
		dnf install -y epel-release >/dev/null 2>&1 ||
			dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_MAJOR}.noarch.rpm" >/dev/null 2>&1 ||
			warn "could not enable EPEL; some packages will not be found"
	else
		yum install -y epel-release >/dev/null 2>&1 ||
			yum install -y "https://archives.fedoraproject.org/pub/archive/epel/epel-release-latest-${OS_MAJOR}.noarch.rpm" >/dev/null 2>&1 ||
			warn "could not enable EPEL; some packages will not be found"
	fi
	enable_crb
}

enable_crb() {
	[ "$PM" = dnf ] || return 0
	have dnf || return 0
	dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
	# It was called PowerTools on 8 and CRB from 9 on, and asking for the
	# wrong one is a warning rather than a failure.
	dnf config-manager --set-enabled crb >/dev/null 2>&1 ||
		dnf config-manager --set-enabled powertools >/dev/null 2>&1 ||
		dnf config-manager --enable crb >/dev/null 2>&1 || true
}

# --------------------------------------------------------------- services --
svc_supported() { [ "$INIT" != none ]; }

svc_start() {
	local _rc
	[ -n "${1:-}" ] || return 0
	case "$INIT" in
		systemd) systemctl start "$1" ;;
		openrc)  rc-service "$1" start ;;
		sysv)    service "$1" start || /etc/init.d/"$1" start ;;
		*)       warn "no init system here; start $1 yourself"; return 1 ;;
	esac
	_rc=$?
	[ "$_rc" = 0 ] || return $_rc
	# Starting is not running. `systemctl start` on a Type=forking unit returns
	# 0 the moment the daemon forks — mongod forks, dies of SIGILL a second
	# later, and the install went on to print "MongoDB is running on
	# 127.0.0.1:27017" over a corpse. Callers write `svc_start X || die`, and
	# that is the right thing to happen, so it has to be able to fail.
	svc_settle "$1" || return 1
	return 0
}

# Wait for a just-started service to admit that it is running.
#
# `rc-service X start` returns as soon as it has forked the daemon, and the
# very next `rc-service X status` answers 32 — OpenRC's "starting", not
# "started". A recipe whose do_install ends in svc_start and whose card is then
# painted by do_status milliseconds later showed the service as *down* on a
# machine where it was coming up perfectly well. Same shape as the nginx reload
# race, one layer down, and it hits every OpenRC recipe rather than one.
#
# Bounded and quiet: at worst this adds a second or two to an install that has
# already spent a minute in the package manager. Never call it from do_status —
# status must stay fast.
svc_settle() {
	local _i
	[ -n "${1:-}" ] || return 0
	_i=0
	while [ "$_i" -lt 30 ]; do
		svc_running "$1" && return 0
		sleep 1
		_i=$((_i + 1))
	done
	return 1
}

svc_stop() {
	[ -n "${1:-}" ] || return 0
	case "$INIT" in
		systemd) systemctl stop "$1" || true ;;
		openrc)  rc-service "$1" stop || true ;;
		sysv)    service "$1" stop || /etc/init.d/"$1" stop || true ;;
		*)       return 0 ;;
	esac
}

svc_restart() {
	[ -n "${1:-}" ] || return 0
	case "$INIT" in
		systemd) systemctl restart "$1" ;;
		openrc)  rc-service "$1" restart ;;
		sysv)    service "$1" restart || /etc/init.d/"$1" restart ;;
		*)       return 1 ;;
	esac
}

svc_reload() {
	[ -n "${1:-}" ] || return 0
	case "$INIT" in
		systemd) systemctl reload "$1" 2>/dev/null || systemctl restart "$1" ;;
		openrc)  rc-service "$1" reload 2>/dev/null || rc-service "$1" restart ;;
		sysv)    service "$1" reload 2>/dev/null || service "$1" restart ;;
		*)       return 1 ;;
	esac
}

svc_enable() {
	[ -n "${1:-}" ] || return 0
	case "$INIT" in
		systemd) systemctl enable "$1" >/dev/null 2>&1 || warn "could not enable $1 at boot" ;;
		openrc)  rc-update add "$1" default >/dev/null 2>&1 || warn "could not enable $1 at boot" ;;
		sysv)    (have update-rc.d && update-rc.d "$1" defaults >/dev/null 2>&1) ||
		         (have chkconfig && chkconfig "$1" on >/dev/null 2>&1) ||
		         warn "could not enable $1 at boot" ;;
		*)       return 0 ;;
	esac
}

svc_disable() {
	[ -n "${1:-}" ] || return 0
	case "$INIT" in
		systemd) systemctl disable "$1" >/dev/null 2>&1 || true ;;
		openrc)  rc-update del "$1" default >/dev/null 2>&1 || true ;;
		sysv)    (have update-rc.d && update-rc.d -f "$1" remove >/dev/null 2>&1) ||
		         (have chkconfig && chkconfig "$1" off >/dev/null 2>&1) || true ;;
		*)       return 0 ;;
	esac
}

svc_running() {
	[ -n "${1:-}" ] || return 1
	case "$INIT" in
		systemd) systemctl is-active --quiet "$1" ;;
		openrc)  rc-service "$1" status >/dev/null 2>&1 ;;
		sysv)    service "$1" status >/dev/null 2>&1 ;;
		*)       pgrep -x "$1" >/dev/null 2>&1 ;;
	esac
}

svc_enabled() {
	[ -n "${1:-}" ] || return 1
	case "$INIT" in
		systemd) systemctl is-enabled --quiet "$1" 2>/dev/null ;;
		openrc)  rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx "$1" ;;
		sysv)    ls /etc/rc3.d/S??"$1" >/dev/null 2>&1 ||
		         (have chkconfig && chkconfig --list "$1" 2>/dev/null | grep -q '3:on') ;;
		*)       return 1 ;;
	esac
}

# The name a service goes by is one of the least portable things there is:
# apache2 on Debian, httpd on Alma, apache2 again on Alpine. A recipe declares
# SERVICE plus any SERVICE_<pm> it needs and calls this.
svc() { pmv SERVICE; }

# Software that ships as one binary — Caddy, Gitea, Halo — brings no unit file
# with it, and writing two of them by hand in every such recipe is how they
# drift. One description in, a systemd unit or an OpenRC script out.
#
#   make_service gitea "Gitea" "/usr/local/bin/gitea web" git /var/lib/gitea
make_service() {
	local _args _bin _desc _dir _exec _name _user
	_name="$1"; _desc="$2"; _exec="$3"; _user="${4:-root}"; _dir="${5:-/}"
	case "$INIT" in
	systemd)
		cat > "/etc/systemd/system/$_name.service" <<EOF
[Unit]
Description=$_desc
Documentation=app-setup
After=network.target

[Service]
Type=simple
User=$_user
WorkingDirectory=$_dir
ExecStart=$_exec
Restart=on-failure
RestartSec=5
${SVC_ENVIRON:-}

[Install]
WantedBy=multi-user.target
EOF
		systemctl daemon-reload
		;;
	openrc)
		# command_background plus a pidfile is what makes OpenRC supervise a
		# program that does not daemonise itself, which none of these do.
		_bin="${_exec%% *}"
		_args="${_exec#"$_bin"}"
		cat > "/etc/init.d/$_name" <<EOF
#!/sbin/openrc-run
name="$_name"
description="$_desc"
command="$_bin"
command_args="$_args"
command_user="$_user"
command_background=true
directory="$_dir"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.log"

depend() {
	need net
	after firewall
}
EOF
		chmod +x "/etc/init.d/$_name"
		;;
	*)
		warn "no init system here — start it yourself with: $_exec"
		return 1
		;;
	esac
}

remove_service() {
	svc_stop "$1"
	svc_disable "$1"
	case "$INIT" in
		systemd) rm -f "/etc/systemd/system/$1.service"; systemctl daemon-reload 2>/dev/null || true ;;
		openrc)  rm -f "/etc/init.d/$1" ;;
	esac
}

# ---------------------------------------------------------------- network --
fetch() {          # fetch <url> <dest>
	local _dst _url
	_url="$1"; _dst="$2"
	ensure_downloader
	if have curl; then
		curl -fsSL --retry 3 --connect-timeout 20 -o "$_dst" "$_url" && return 0
		# curl error 16, "Error in the HTTP2 framing layer": Ubuntu 22.04's
		# curl against GitHub's CDN, reproducibly. --retry does not cover it
		# because curl treats it as fatal rather than transient, and HTTP/1.1
		# fetches the identical bytes.
		curl -fsSL --http1.1 --retry 3 --connect-timeout 20 -o "$_dst" "$_url"
	else
		wget -q -t 3 -T 20 -O "$_dst" "$_url"
	fi
}

# run_bounded <seconds> <command...>
#
# fetch() bounds its own curl, but a *vendor* installer we hand control to does
# not: Oh My Zsh's install.sh ends in `git fetch https://github.com/...`, and
# git has no default timeout at all. Where github.com is blackholed rather than
# refused — a firewall that drops instead of rejecting, which is the common
# case — that fetch waits forever and the picker shows an install that never
# ends. Anything that runs somebody else's script goes through here.
#
# Returns **124** on timeout, on every system. Two reasons it is not a plain
# call to timeout(1):
#
#   - timeout(1) signals the process it started. The thing that actually hangs
#     is a *grandchild*: `sh install.sh` is what we launch, and the `git fetch`
#     inside it is what waits forever. Killing the wrapper leaves the fetch
#     running. Here the child gets its own session, and the whole group is
#     signalled, so the tree goes.
#   - busybox's timeout returns 143 (128+TERM) where GNU returns 124. Neither
#     number is portable, and busybox setsid has no `-w`, so
#     `setsid -w timeout …` is not a way out. This returns 124 either way.
#
# **Everything here is guarded**, because this file runs under `set -e` and the
# expected path is a `kill` that fails: after the TERM lands there is no group
# left for the KILL to find, and one unguarded non-zero would take the caller
# down at exactly the moment it is trying to recover. Callers write
# `run_bounded N cmd || warn …`, which is itself guarded — but a helper must
# not depend on its caller for that.
run_bounded() {
	local _secs _pid _i _rc
	_secs="$1"; shift
	_rc=0
	if ! have setsid; then "$@" || _rc=$?; return $_rc; fi
	setsid "$@" &
	_pid=$!
	_i=0
	while kill -0 "$_pid" 2>/dev/null; do
		if [ "$_i" -ge "$_secs" ]; then
			kill -TERM "-$_pid" 2>/dev/null || kill -TERM "$_pid" 2>/dev/null || true
			sleep 2
			kill -KILL "-$_pid" 2>/dev/null || kill -KILL "$_pid" 2>/dev/null || true
			wait "$_pid" 2>/dev/null || true
			return 124
		fi
		sleep 1
		_i=$((_i + 1))
	done
	wait "$_pid" || _rc=$?
	return $_rc
}

fetch_stdout() {
	ensure_downloader
	if have curl; then
		curl -fsSL --retry 3 --connect-timeout 20 "$1" ||
			curl -fsSL --http1.1 --retry 3 --connect-timeout 20 "$1"
	else
		wget -q -t 3 -T 20 -O - "$1"
	fi
}

ensure_downloader() {
	have curl && return 0
	have wget && return 0
	# The RPM bases ship curl-minimal and refuse plain `curl` on a conflict,
	# so wget is the one to ask for there.
	case "$PMF" in
		rpm) pkg_install wget ;;
		*)   pkg_install curl || pkg_install wget ;;
	esac
}

port_busy() {      # is anything already listening on this TCP port?
	if have ss; then ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$"
	elif have netstat; then netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$"
	else return 1; fi
}

require_ports() {
	local _p
	for _p in "$@"; do
		if port_busy "$_p"; then
			warn "port $_p is already in use — whatever holds it will have to move"
		fi
	done
	return 0
}

# -------------------------------------------------------------------- web --
#
# One document root on every distro. Debian puts it at /var/www/html, the RPM
# nginx at /usr/share/nginx/html, Alpine at /var/www/localhost/htdocs, and a
# person following a WordPress tutorial should not have to know which machine
# they are on. The recipes point the server at this instead.
WEBROOT=/var/www/html

nginx_conf_dir() {
	# Alpine moved to http.d; everyone else is still conf.d.
	if [ -d /etc/nginx/http.d ]; then printf '/etc/nginx/http.d'
	else printf '/etc/nginx/conf.d'; fi
}

# Every distro ships a default server on port 80, and a second one is either a
# duplicate-default error or a conflicting-server-name warning. Take the
# shipped one out of the way before writing ours.
# web_claim_default <my-id> — refuse if another suite already holds port 80.
#
# WordPress, Typecho and Nextcloud each write app-setup-<id>.conf with
# `listen 80 default_server`, and each clears the distro's default site and the
# generic LNMP one before doing it. None of them looked for a *sibling*. nginx
# allows exactly one default server per address, so installing a second suite
# produced `a duplicate default server for 0.0.0.0:80` and the reload failed —
# at the very end, after a 280MB download and a completed database install, with
# the new site on disk and nothing serving it.
#
# Refuse at the top of do_install instead, and say who has the address. Evicting
# somebody's WordPress to make room would be worse than not installing.
# default_site_holder [id-to-ignore] — print the suites holding `default_server`,
# and exit non-zero when there are none. `install nginx` uses it to keep its
# hands off a document root that WordPress is already serving, which it
# otherwise broke outright.
default_site_holder() {
	local _me _f _other _ids
	_me="${1:-}"
	_ids=""
	for _f in "$(nginx_conf_dir)"/app-setup-*.conf; do
		[ -f "$_f" ] || continue
		_other="${_f##*/app-setup-}"; _other="${_other%.conf}"
		[ -n "$_me" ] && [ "$_other" = "$_me" ] && continue
		grep -q 'default_server' "$_f" 2>/dev/null || continue
		_ids="${_ids:+$_ids }$_other"
	done
	[ -n "$_ids" ] || return 1
	printf '%s' "$_ids"
}

web_claim_default() {
	local _me _other _ids
	_me="$1"
	_ids="$(default_site_holder "$_me")" || return 0
	err "another site is already serving this container's address: $_ids"
	err "nginx allows one default site on port 80, so $_me cannot take it too."
	err "Remove the other one first, then install this:"
	for _other in $_ids; do err "  app-setup remove $_other"; done
	err "Nothing was downloaded or changed."
	exit 1
}

nginx_drop_default() {
	rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
	rm -f "$(nginx_conf_dir)/default.conf" 2>/dev/null || true
	# The RPM packages put the default server inside nginx.conf itself, so it
	# has to be cut out rather than deleted. Only the first server block goes.
	if [ -f /etc/nginx/nginx.conf ] && grep -qE '^[[:space:]]*server[[:space:]]*\{' /etc/nginx/nginx.conf; then
		backup_once /etc/nginx/nginx.conf
		awk '
			!skip && $0 ~ /^[[:space:]]*server[[:space:]]*\{/ { skip = 1; depth = 0 }
			skip {
				depth += gsub(/\{/, "{") - gsub(/\}/, "}")
				if (depth <= 0) skip = 0
				next
			}
			{ print }
		' /etc/nginx/nginx.conf > /etc/nginx/nginx.conf.new
		mv /etc/nginx/nginx.conf.new /etc/nginx/nginx.conf
	fi
}

nginx_test_reload() {
	if nginx -t 2>&1 | grep -q 'test is successful'; then
		svc_reload nginx 2>/dev/null || svc_start nginx
		# A reload is asynchronous: SIGHUP returns immediately and the old
		# workers keep answering until they drain. That is invisible on a
		# running site and very visible here, because the recipe's last line
		# is "finish the setup at http://…/install.php" — and a person who
		# clicks it in the next half second gets one 404 from a worker still
		# using the previous document root. A second is nothing next to the
		# install that just ran, and it makes that link true when it is
		# printed.
		sleep 1
		return 0
	fi
	err "the nginx config does not parse; nothing was reloaded:"
	nginx -t 2>&1 | sed 's/^/    /'
	return 1
}

# php-fpm's package name, service name and listening socket all differ per
# distro *and* per release, so all three are discovered rather than assumed.
php_service() {
	local _b _s _u
	case "$PMF" in rpm) printf 'php-fpm'; return 0 ;; esac
	for _u in /lib/systemd/system/php*-fpm.service /usr/lib/systemd/system/php*-fpm.service; do
		[ -f "$_u" ] || continue
		_b="${_u##*/}"; printf '%s' "${_b%.service}"; return 0
	done
	for _s in /etc/init.d/php-fpm* /etc/init.d/php*-fpm; do
		[ -f "$_s" ] || continue
		printf '%s' "${_s##*/}"; return 0
	done
	printf 'php-fpm'
}

php_fpm_listen() {
	local _f _v
	for _f in /etc/php/*/fpm/pool.d/www.conf /etc/php-fpm.d/www.conf \
	          /etc/php*/php-fpm.d/www.conf /etc/php*/php-fpm.conf; do
		[ -f "$_f" ] || continue
		_v="$(awk -F= '/^[[:space:]]*listen[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$_f")"
		[ -n "$_v" ] && { printf '%s' "$_v"; return 0; }
	done
	printf '127.0.0.1:9000'
}

# Where an Apache fragment goes. Debian's convention is a file in
# conf-available plus a symlink that a2enconf makes; the RPM images and Alpine
# just scan a directory. Debian reads conf-enabled directly too, so writing
# there works on all three without shelling out to a2enconf.
apache_conf_dir() {
	local _d
	for _d in /etc/apache2/conf-enabled /etc/httpd/conf.d /etc/apache2/conf.d; do
		[ -d "$_d" ] && { printf '%s' "$_d"; return 0; }
	done
	return 1
}

# The pool file — how many workers, which user, which socket. Same three
# layouts as php_fpm_listen, and the first one that exists wins.
php_pool_file() {
	local _f
	for _f in /etc/php/*/fpm/pool.d/www.conf /etc/php-fpm.d/www.conf \
	          /etc/php*/php-fpm.d/www.conf; do
		[ -f "$_f" ] && { printf '%s' "$_f"; return 0; }
	done
	return 1
}

# Where a .ini drop-in is read from. Every layout scans a directory next to
# php.ini — it is how the extension packages add themselves — so a file we put
# there is read the same way, and php.ini itself is never edited.
php_ini_dir() {
	local _d
	for _d in /etc/php/*/fpm/conf.d /etc/php.d /etc/php*/conf.d; do
		[ -d "$_d" ] && { printf '%s' "$_d"; return 0; }
	done
	return 1
}

php_fastcgi_pass() {
	local _l
	_l="$(php_fpm_listen)"
	case "$_l" in
		/*) printf 'unix:%s' "$_l" ;;
		*)  printf '%s' "$_l" ;;
	esac
}

# The default nginx site, with PHP wired in. Written whole rather than patched
# into an existing file: sed-ing a config works right up until somebody has
# edited it first, and then it produces a file nobody can explain.
#
#   php_nginx_site [document-root] > "$(nginx_conf_dir)/app-setup.conf"
php_nginx_site() {
	local _root
	_root="${1:-$WEBROOT}"
	cat <<EOF
# written by app-setup. Your own sites go in files next to this one; this is
# the default server, which answers for any name nothing else claims.
server {
    listen      80 default_server;
    listen      [::]:80 default_server;
    server_name _;
    root        $_root;
    index       index.php index.html index.htm;

    access_log  /var/log/nginx/access.log;
    error_log   /var/log/nginx/error.log;

    # Large uploads need this raised here *and* in php.ini. A 413 is nginx.
    client_max_body_size 64m;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files      \$uri =404;
        include        fastcgi_params;
        fastcgi_pass   $(php_fastcgi_pass);
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 120;
    }

    location ~ /\. { deny all; }
    location = /favicon.ico { log_not_found off; access_log off; }
}
EOF
}

# version_ge <have> <want> — true when <have> is at least <want>.
#
# Compares dotted numbers field by field, so 6.10 is correctly newer than 6.9
# (a string compare says otherwise, and that is the trap). Non-numeric tails
# like "6.0.16-1ubuntu1" are cut at the first field that is not a number.
version_ge() {
	local _h _w _hp _wp
	_h="$1"; _w="$2"
	while [ -n "$_h" ] || [ -n "$_w" ]; do
		_hp="${_h%%.*}"; _wp="${_w%%.*}"
		_hp="$(printf '%s' "${_hp:-0}" | tr -cd '0-9')"
		_wp="$(printf '%s' "${_wp:-0}" | tr -cd '0-9')"
		[ "${_hp:-0}" -gt "${_wp:-0}" ] && return 0
		[ "${_hp:-0}" -lt "${_wp:-0}" ] && return 1
		case "$_h" in *.*) _h="${_h#*.}" ;; *) _h="" ;; esac
		case "$_w" in *.*) _w="${_w#*.}" ;; *) _w="" ;; esac
	done
	return 0
}

# --------------------------------------------------- the placeholder page --
# Every web recipe drops a "it works" page into an empty document root, and
# takes it away again on uninstall. Both halves were unconditional: `install
# lamp` ran `rm -f $WEBROOT/index.html` and overwrote `index.php` whatever was
# in it, and `uninstall` deleted `index.php` — while printing "files in
# $WEBROOT stay". A holder who replaced the page with their own site lost it
# to a *second* install and again to the removal.
#
# So the pages carry a marker, and nothing is deleted unless the marker is
# there. Rule one of this whole catalogue is that uninstall does not delete
# somebody's data, and a page they wrote is their data.
PLACEHOLDER_MARK='app-setup placeholder'

# True when the path is safe for us to write over or delete: either it is not
# there at all, or it is a page this tool wrote.
placeholder_ours() {
	[ -e "$1" ] || return 0
	grep -qF "$PLACEHOLDER_MARK" "$1" 2>/dev/null
}

# True when the document root has no page of somebody else's in it.
docroot_is_ours() {
	placeholder_ours "$1/index.php" && placeholder_ours "$1/index.html"
}

# Take our own placeholder away, and only ours.
placeholder_remove() {
	placeholder_ours "$1" && rm -f "$1"
	return 0
}

# Who should own the files under the document root. php-fpm's pool user is the
# authority when PHP is installed — it is the process that has to write uploads
# — and the guess list is ordered by how each distro names its web account.
web_user() {
	local _f _u
	for _f in /etc/php/*/fpm/pool.d/www.conf /etc/php-fpm.d/www.conf /etc/php*/php-fpm.d/www.conf; do
		[ -f "$_f" ] || continue
		_u="$(awk -F= '/^[[:space:]]*user[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$_f")"
		[ -n "$_u" ] && id "$_u" >/dev/null 2>&1 && { printf '%s' "$_u"; return 0; }
	done
	for _u in www-data nginx apache http lighttpd; do
		id "$_u" >/dev/null 2>&1 && { printf '%s' "$_u"; return 0; }
	done
	printf 'nobody'
}

web_group() {
	local _u
	_u="$(web_user)"
	id -gn "$_u" 2>/dev/null || printf '%s' "$_u"
}

php_bin() {
	local _p
	have php && { printf 'php'; return 0; }
	for _p in /usr/bin/php8* /usr/bin/php7*; do
		[ -x "$_p" ] && { printf '%s' "$_p"; return 0; }
	done
	printf 'php'
}

# ------------------------------------------------------------ composition --
# A suite is other recipes plus the wiring between them. Calling them rather
# than repeating them is what stops LNMP and LAMP from disagreeing with the
# nginx and MariaDB cards about what is installed.
# app-setup hands a recipe its saved settings as APP_PARAM_* in the
# environment. A recipe started by *another recipe* — `recipe files backup`,
# which is how the backup card runs everything on its list — never went
# through app-setup, so without this it sees only the defaults in its own
# header.
#
# The symptom is the nastiest shape a bug can have here: pressing the button
# works, because that call did come through app-setup, and the nightly run
# silently saves nothing. Both `files` and `sqlite` are configured entirely by
# their settings, so for them "nothing" is the whole backup.
#
# Always called inside a subshell, so the exports die with the child.
param_export() {   # param_export <id>
	local _f _line _n _v
	_f="$APP_SETUP_CONF/params/$1.conf"
	[ -f "$_f" ] || return 0
	while IFS= read -r _line; do
		case "$_line" in ''|\#*) continue ;; esac
		_n="${_line%%=*}"; _v="${_line#*=}"
		[ "$_n" != "$_line" ] || continue
		_n="$(printf '%s' "$_n" | tr 'abcdefghijklmnopqrstuvwxyz-' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_')"
		export "APP_PARAM_$_n=$_v"
	done < "$_f"
}

recipe() {         # recipe <id> <verb>
	local _d _found _verb _want
	_want="$1"; _verb="$2"; _found=""
	for _d in $(printf '%s' "${APP_SETUP_PATH:-/etc/app-setup:/etc/app-setup/local}" | tr ':' ' '); do
		[ -f "$_d/$_want.sh" ] && _found="$_d/$_want.sh"
	done
	[ -n "$_found" ] || die "this needs the '$_want' source, which is not on this machine"
	step "$_verb: $_want"
	( param_export "$_want"; sh "$_found" "$_verb" )
}

recipe_status() {  # 0 running, 1 stopped, 2 absent — same codes as the verb
	local _d _found _want
	_want="$1"; _found=""
	for _d in $(printf '%s' "${APP_SETUP_PATH:-/etc/app-setup:/etc/app-setup/local}" | tr ':' ' '); do
		[ -f "$_d/$_want.sh" ] && _found="$_d/$_want.sh"
	done
	[ -n "$_found" ] || return 2
	( param_export "$_want"; sh "$_found" status ) >/dev/null 2>&1
}

# Install a part only if it is missing. An application suite laid on top of a
# machine that already runs LNMP must not reinstall nginx underneath a site
# that is currently serving — and `recipe nginx install` rewrites the default
# server, so calling it unconditionally would take that site down.
recipe_ensure() {
	local _rc
	_rc=0
	recipe_status "$1" || _rc=$?
	if [ "$_rc" = 2 ]; then recipe "$1" install
	else info "$1 is already here"; fi
	return 0
}

# -------------------------------------------------------------- databases --
# WordPress, Typecho and Nextcloud all want the same four statements, and
# writing them out three times is how one of them ends up on `utf8` — the
# MySQL encoding that is not UTF-8 and truncates a row at the first emoji.
# Where the mysql recipe put root's password. It is named explicitly rather
# than left to `mysql` finding ~/.my.cnf, because HOME is not reliably root's
# home in any of the ways this actually runs: `sudo` keeps the *invoking*
# user's HOME, cron sets none at all, and neither does a systemd unit. The
# symptom when it is wrong is "Access denied for user 'root'@'localhost'
# (using password: NO)" — which reads like the password is wrong rather than
# like the file was never opened.
MY_CNF=/root/.my.cnf

# Where a .cnf fragment goes. Debian keeps two of these directories and reads
# both; the RPM images and Alpine keep one. Ours is a file in the directory
# rather than an edit to my.cnf, so the package can upgrade its own config
# freely and `apt` never stops to ask about a modified conffile.
mysql_conf_dir() {
	local _d
	for _d in /etc/mysql/conf.d /etc/my.cnf.d /etc/mysql/mariadb.conf.d; do
		[ -d "$_d" ] && { printf '%s' "$_d"; return 0; }
	done
	# Nothing to drop into: make the one my.cnf already says it will include.
	for _d in /etc/mysql/conf.d /etc/my.cnf.d; do
		if grep -rqs "includedir.*${_d#/etc/}" /etc/my.cnf /etc/mysql/my.cnf 2>/dev/null; then
			mkdir -p "$_d" && { printf '%s' "$_d"; return 0; }
		fi
	done
	return 1
}

mysql_root() {
	if [ -r "$MY_CNF" ]; then
		# Authoritative once it exists: an error from here is a real error and
		# should be seen, not masked by a retry that gets access denied.
		mysql --defaults-file="$MY_CNF" "$@"
	else
		# A fresh install lets root in over the unix socket with no password.
		mysql --protocol=socket -uroot "$@" 2>/dev/null || mysql -uroot "$@"
	fi
}

mysql_wait() {     # the service is up before the socket is
	local _n
	_n=0
	while [ "$_n" -lt 30 ]; do
		if [ -r "$MY_CNF" ]; then
			mysqladmin --defaults-file="$MY_CNF" ping >/dev/null 2>&1 && return 0
		fi
		mysqladmin --protocol=socket ping >/dev/null 2>&1 && return 0
		mysqladmin ping >/dev/null 2>&1 && return 0
		_n=$((_n + 1)); sleep 1
	done
	return 1
}

db_mysql_create() {   # db_mysql_create <database> <user> <password>
	local _db _dp _du
	_db="$1"; _du="$2"; _dp="$3"
	mysql_root -e "CREATE DATABASE IF NOT EXISTS \`$_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" ||
		return 1
	# Three ways to say the same thing, because the syntax changed twice and
	# we publish images from CentOS 7 (MariaDB 5.5, none of the modern forms)
	# to Fedora 43. Whichever one this server understands wins; the last is
	# 5.5's own idiom, where GRANT ... IDENTIFIED BY creates the user.
	mysql_root -e "CREATE USER IF NOT EXISTS '$_du'@'localhost' IDENTIFIED BY '$_dp';" 2>/dev/null ||
	mysql_root -e "CREATE USER '$_du'@'localhost' IDENTIFIED BY '$_dp';" 2>/dev/null ||
	mysql_root -e "GRANT USAGE ON *.* TO '$_du'@'localhost' IDENTIFIED BY '$_dp';" 2>/dev/null ||
		true
	# The user may have existed already with a password nobody wrote down.
	mysql_root -e "ALTER USER '$_du'@'localhost' IDENTIFIED BY '$_dp';" 2>/dev/null ||
	mysql_root -e "SET PASSWORD FOR '$_du'@'localhost' = PASSWORD('$_dp');" 2>/dev/null ||
		true
	mysql_root -e "GRANT ALL PRIVILEGES ON \`$_db\`.* TO '$_du'@'localhost'; FLUSH PRIVILEGES;"
}

db_mysql_drop() {     # db_mysql_drop <database> <user>
	mysql_root -e "DROP DATABASE IF EXISTS \`$1\`;" 2>/dev/null || true
	mysql_root -e "DROP USER '$2'@'localhost';" 2>/dev/null || true
}

# ---------------------------------------------------------------- secrets --
rand_pass() {
	local _n
	_n="${1:-20}"
	if [ -r /dev/urandom ]; then
		LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "$_n"
		echo
	else
		date +%s%N | sha256sum | head -c "$_n"; echo
	fi
}

# Generated passwords go in one place, mode 600, and `app-setup docs <id>`
# prints them back. Nobody can be asked to scroll up through an install log.
save_note() {      # save_note <id> <<'EOF' ... EOF
	mkdir -p "$APP_SETUP_SECRETS"
	chmod 700 "$APP_SETUP_SECRETS"
	cat > "$APP_SETUP_SECRETS/$1.txt"
	chmod 600 "$APP_SETUP_SECRETS/$1.txt"
	info "saved to $APP_SETUP_SECRETS/$1.txt"
}

show_note() {
	[ -f "$APP_SETUP_SECRETS/$1.txt" ] || return 0
	echo
	echo "--- what was set up on this machine ---"
	cat "$APP_SETUP_SECRETS/$1.txt"
	echo "---------------------------------------"
}

drop_note() { rm -f "$APP_SETUP_SECRETS/$1.txt"; }

# The address a person should actually type. Inside a container the public
# address is the host's, which we cannot know, so say so rather than print a
# 172.x that will not work from their laptop.
guess_host() {
	local _ip
	_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')"
	[ -n "$_ip" ] || _ip="$(hostname -i 2>/dev/null | awk '{print $1}')"
	[ -n "$_ip" ] || _ip="127.0.0.1"
	printf '%s' "$_ip"
}

# ------------------------------------------------------------------ files --
backup_once() {    # keep the distro's original the first time we touch it
	[ -f "$1" ] || return 0
	[ -f "$1.app-setup-orig" ] && return 0
	cp -a "$1" "$1.app-setup-orig"
}

restore_backup() {
	[ -f "$1.app-setup-orig" ] || return 0
	mv -f "$1.app-setup-orig" "$1"
}

tmp_dir() {
	local _d
	_d="$(mktemp -d 2>/dev/null || echo "/tmp/app-setup.$$")"
	mkdir -p "$_d"
	printf '%s' "$_d"
}

# ----------------------------------------------------------------- backup --
#
# Five steps, in the order they have to happen: get a tool that can upload,
# quiesce whatever is being copied, pack it, put it somewhere that is not this
# machine, and be able to walk all of it backwards. A recipe supplies only the
# middle — it is the only thing that knows what its own data is — and the rest
# lives here so that every archive is named the same way, pruned the same way
# and uploaded to the same place:
#
#   do_backup() {
#           bk_begin mysql                      # -> mysql_20210403123221.tgz
#           bk_quiesce                          # stops the service if bk_method is files
#           mysqldump --all-databases > "$(bk_path all.sql)"
#           bk_add /etc/mysql                   # config travels with the data
#           bk_finish                           # pack, upload, prune, restart
#   }
#
# The settings all of this reads belong to the `backup` recipe, not to the
# recipe being backed up: one destination and one schedule for the machine,
# edited in one form, and `bk_conf` is how the other recipes see them.
BK_DIR="${BK_DIR:-/data/backups}"

# `dump` and `load` are the other half, and deliberately not the same thing as
# `backup` and `restore`. A backup is the whole pipeline — packed, dated,
# uploaded, pruned, on a timer. A dump is one plain file you can open, read,
# scp somewhere, mail to somebody who asked, or feed to a different server.
# Both exist because people want both, and a tool that only offers the
# packaged one gets worked around with a half-remembered mysqldump line.
DUMP_DIR="${DUMP_DIR:-/data/dumps}"

# Where a dump should be written: what was asked for, or a dated name under
# $DUMP_DIR using the same stamp the archives use.
dump_target() {    # dump_target <prefix> <ext> [given]
	local _g
	_g="${3-}"
	if [ -n "$_g" ]; then
		case "$_g" in */*) : ;; *) _g="$DUMP_DIR/$_g" ;; esac
		mkdir -p "$(dirname "$_g")"
		printf '%s' "$_g"
		return 0
	fi
	mkdir -p "$DUMP_DIR"
	printf '%s/%s_%s.%s' "$DUMP_DIR" "$1" "$(date -u +%Y%m%d%H%M%S)" "$2"
}

# Which dump to read: what was named, or the newest of that kind. Same
# name-sorts-as-time trick as bk_latest.
dump_source() {    # dump_source <prefix> <ext> [given]
	local _f _g
	_g="${3-}"
	if [ -n "$_g" ]; then
		[ -f "$_g" ] && { printf '%s' "$_g"; return 0; }
		[ -f "$DUMP_DIR/$_g" ] && { printf '%s' "$DUMP_DIR/$_g"; return 0; }
		die "no such dump: $_g"
	fi
	_f="$(ls -1 "$DUMP_DIR/${1}_"*".$2" 2>/dev/null | sort -r | head -1)"
	[ -n "$_f" ] || die "no $1 dump in $DUMP_DIR — make one with: app-setup dump $1"
	printf '%s' "$_f"
}

# The Settings form writes the S3 secret into params/backup.conf, and a secret
# key that any process on the box can read is not much of a secret. fopen("w")
# truncates without touching the mode, so app-setup's own saves keep whatever
# is set here — but the *first* save creates the file at the umask, so this
# re-asserts it on every read rather than once at install.
bk_conf() {        # bk_conf <key> [default]
	local _f _v
	_f="$APP_SETUP_CONF/params/backup.conf"
	[ -f "$_f" ] || { printf '%s' "${2-}"; return 0; }
	chmod 600 "$_f" 2>/dev/null || true
	_v="$(sed -n "s/^$1=//p" "$_f" | head -1)"
	[ -n "$_v" ] || _v="${2-}"
	printf '%s' "$_v"
}

# The one piece of naming the whole feature is judged on. UTC, because a
# machine that moves timezone or crosses a DST boundary must not produce two
# archives an hour apart that sort in the wrong order.
bk_name() {        # bk_name <prefix> -> mysql_20210403123221.tgz
	printf '%s_%s.tgz' "$1" "$(date -u +%Y%m%d%H%M%S)"
}

bk_begin() {       # bk_begin <prefix>
	BK_PREFIX="$1"
	BK_ARCHIVE="$(bk_name "$1")"
	BK_WORK="$(tmp_dir)"
	BK_SVC_WAS=""
	mkdir -p "$BK_WORK/$BK_PREFIX"
	# Whatever happens between here and bk_finish — a dump that fails, a full
	# disk, somebody's Ctrl-C — the service must come back up and the staging
	# directory must not survive. A backup that leaves the database stopped is
	# worse than no backup at all, which is the whole reason this trap exists
	# rather than a tidy-up at the end of do_backup.
	trap 'bk_abort' EXIT INT TERM
	step "backing up $BK_PREFIX"
}

bk_abort() {
	bk_resume
	[ -n "${BK_WORK:-}" ] && rm -rf "$BK_WORK"
	BK_WORK=""
}

# Where a dump should write itself. Inside the staging tree, so it lands in the
# archive without a second copy.
bk_path() {        # bk_path <name> -> /tmp/…/mysql/<name>
	mkdir -p "$BK_WORK/$BK_PREFIX"
	printf '%s' "$BK_WORK/$BK_PREFIX/$1"
}

# A file or directory copied in under files/, keeping its absolute path, so a
# restore is `cp -a files/. /` and nothing has to remember where it came from.
# Copied with tar rather than cp, because an exclude list has to be honoured
# *while* copying: a node_modules or a cache directory that gets copied and
# then pruned out of the staging tree has already cost the disk and the
# minutes. $BK_EXCLUDE is a space-separated list of tar patterns and is unset
# for everything that does not want one.
#
# The backup directories are always excluded. A recipe told to save /data
# would otherwise pack every previous archive into the new one, and each
# night's backup would be bigger than the last until the disk filled.
bk_add() {         # bk_add <path>
	local _e _ex _rel
	[ -e "$1" ] || { warn "nothing at $1 — skipped"; return 0; }
	case "$1" in
		/|/proc|/sys|/dev|/proc/*|/sys/*|/dev/*|/run|/run/*)
			warn "refusing to copy $1 — that is not a thing to put in a backup"
			return 0 ;;
	esac
	_ex="--exclude=${BK_DIR#/} --exclude=${DUMP_DIR#/}"
	for _e in ${BK_EXCLUDE:-}; do _ex="$_ex --exclude=$_e"; done
	_rel="${1#/}"
	mkdir -p "$BK_WORK/$BK_PREFIX/files"
	# shellcheck disable=SC2086  # $_ex is our own list of flags, split on purpose
	(cd / && tar cf - $_ex -- "$_rel") 2>/dev/null |
		tar xf - -C "$BK_WORK/$BK_PREFIX/files" 2>/dev/null ||
		warn "could not copy $1 in full — check the log"
}

# `dump` takes a hot logical copy and never interrupts anybody; `files` stops
# the service first, which is the only honest way to copy a data directory
# out from under a running database. A recipe calls both of these either way
# and lets the setting decide — that is what keeps do_backup readable.
# The machine-wide setting lives on the `backup` recipe; a single database can
# override it with its own Backup field, because "everything nightly by dump,
# except this one which has to be a cold copy" is a real thing to want and the
# alternative is two schedules.
bk_method() {
	local _m
	_m="$(param backup default)"
	case "$_m" in dump|files) printf '%s' "$_m"; return 0 ;; esac
	bk_conf method dump
}

bk_quiesce() {
	local _s
	[ "$(bk_method)" = files ] || return 0
	_s="$(svc)"
	[ -n "$_s" ] || return 0
	svc_running "$_s" || return 0
	BK_SVC_WAS="$_s"
	step "stopping $_s so the files cannot change while they are copied"
	svc_stop "$_s"
}

bk_resume() {
	[ -n "${BK_SVC_WAS:-}" ] || return 0
	step "starting $BK_SVC_WAS again"
	svc_start "$BK_SVC_WAS" || err "$BK_SVC_WAS did not come back up — start it yourself"
	BK_SVC_WAS=""
}

bk_finish() {
	local _arch _sz
	_arch="$BK_DIR/$BK_ARCHIVE"
	mkdir -p "$BK_DIR" || die "cannot write to $BK_DIR"
	step "packing $BK_ARCHIVE"
	tar czf "$_arch" -C "$BK_WORK" "$BK_PREFIX" || die "could not pack the archive"
	chmod 600 "$_arch"
	# The service goes back up before the upload, not after: a slow or broken
	# remote must not be the reason a site is down for another two minutes.
	bk_resume
	rm -rf "$BK_WORK"; BK_WORK=""
	trap - EXIT INT TERM
	_sz="$(du -h "$_arch" 2>/dev/null | awk '{print $1}')"
	ok "$_arch${_sz:+  ($_sz)}"
	bk_upload "$_arch"
	bk_prune "$BK_PREFIX"
}

# Everything that talks to the bucket goes through one of these two, so the
# credentials are assembled in exactly one place and a typo cannot make upload
# work while download quietly does not.
#
# rclone is configured entirely from the environment: nothing is written to
# /root/.config/rclone.conf, so the secret never outlives the process. `Other`
# is the provider that works for every S3-compatible endpoint there is —
# Aliyun OSS, Tencent COS, Cloudflare R2, Backblaze B2, MinIO.
bk_rclone() {
	RCLONE_CONFIG_BK_TYPE=s3 \
	RCLONE_CONFIG_BK_PROVIDER="$([ -n "$(bk_conf endpoint)" ] && echo Other || echo AWS)" \
	RCLONE_CONFIG_BK_ACCESS_KEY_ID="$(bk_conf access_key)" \
	RCLONE_CONFIG_BK_SECRET_ACCESS_KEY="$(bk_conf secret_key)" \
	RCLONE_CONFIG_BK_ENDPOINT="$(bk_conf endpoint)" \
	RCLONE_CONFIG_BK_REGION="$(bk_conf region us-east-1)" \
	rclone --no-check-certificate=false "$@"
}

bk_aws() {
	local _ep
	_ep="$(bk_conf endpoint)"
	AWS_ACCESS_KEY_ID="$(bk_conf access_key)" \
	AWS_SECRET_ACCESS_KEY="$(bk_conf secret_key)" \
	AWS_DEFAULT_REGION="$(bk_conf region us-east-1)" \
	aws ${_ep:+--endpoint-url "$_ep"} "$@"
}

# s3://bucket/some/prefix, as the two tools each want to see it.
bk_remote_set() {  # sets BK_TOOL, BK_BUCKET, BK_KEY; non-zero if not configured
	local _rem
	_rem="$(bk_conf remote)"
	BK_TOOL="$(bk_conf tool rclone)"
	[ -n "$_rem" ] && [ "$BK_TOOL" != none ] || return 1
	BK_BUCKET="$(printf '%s' "${_rem#s3://}" | cut -d/ -f1)"
	case "${_rem#s3://}" in
		*/*) BK_KEY="$(printf '%s' "${_rem#s3://}" | cut -d/ -f2-)" ;;
		*)   BK_KEY="" ;;
	esac
	return 0
}

bk_upload() {      # bk_upload <archive>
	bk_remote_set || {
		info "no upload target set — the archive is only on this machine."
		info "one disk holding both the site and its backups is not a backup."
		return 0
	}
	step "uploading $(basename "$1")"
	case "$BK_TOOL" in
	rclone)
		have rclone || { err "rclone is not installed — run: app-setup install backup"; return 1; }
		bk_rclone copy --s3-no-check-bucket "$1" "BK:$BK_BUCKET${BK_KEY:+/$BK_KEY}" ||
			{ err "upload failed — the archive is still in $BK_DIR"; return 1; }
		;;
	aws)
		have aws || { err "aws-cli is not installed — run: app-setup install backup"; return 1; }
		bk_aws s3 cp "$1" "s3://$BK_BUCKET${BK_KEY:+/$BK_KEY}/$(basename "$1")" >/dev/null ||
			{ err "upload failed — the archive is still in $BK_DIR"; return 1; }
		;;
	*) err "unknown upload tool: $BK_TOOL"; return 1 ;;
	esac
	ok "uploaded to $(bk_conf remote)"
}

# The half that makes uploading worth anything. The local copy is the one that
# gets pruned, or lost with the disk, so a restore has to be able to reach past
# it — otherwise the bucket is a place data goes and never comes back from.
bk_download() {    # bk_download <filename> <dest>
	bk_remote_set || return 1
	step "fetching $1 from $(bk_conf remote)"
	case "$BK_TOOL" in
	rclone)
		have rclone || return 1
		bk_rclone copyto "BK:$BK_BUCKET${BK_KEY:+/$BK_KEY}/$1" "$2" >/dev/null 2>&1 ;;
	aws)
		have aws || return 1
		bk_aws s3 cp "s3://$BK_BUCKET${BK_KEY:+/$BK_KEY}/$1" "$2" >/dev/null 2>&1 ;;
	*) return 1 ;;
	esac
}

# Names only, newest last, so `| tail -1` is the newest — the same ordering the
# fixed-width UTC stamp gives the local directory.
bk_remote_ls() {   # bk_remote_ls [prefix]
	bk_remote_set || return 1
	case "$BK_TOOL" in
	rclone)
		have rclone || return 1
		bk_rclone lsf "BK:$BK_BUCKET${BK_KEY:+/$BK_KEY}" 2>/dev/null ;;
	aws)
		have aws || return 1
		bk_aws s3 ls "s3://$BK_BUCKET${BK_KEY:+/$BK_KEY}/" 2>/dev/null | awk '{print $NF}' ;;
	*) return 1 ;;
	esac | grep "^${1:-}.*\.tgz$" | sort
}

# Local only. Deleting somebody's remote history on a schedule is a decision
# for their bucket's lifecycle rules, not for a shell script that might be
# running with the wrong prefix.
bk_prune() {       # bk_prune <prefix>
	local _f _keep _n
	_keep="$(bk_conf keep 7)"
	case "$_keep" in ''|*[!0-9]*) return 0 ;; esac
	[ "$_keep" -gt 0 ] || return 0
	_n=0
	# Newest first by name, which is why the stamp is fixed-width and UTC.
	for _f in $(ls -1 "$BK_DIR/${1}_"*.tgz 2>/dev/null | sort -r); do
		_n=$((_n + 1))
		[ "$_n" -gt "$_keep" ] || continue
		rm -f "$_f" && info "pruned $(basename "$_f")"
	done
}

# The newest archive for a prefix, which is what `restore` with no argument
# means and the only thing anybody wants at three in the morning.
bk_latest() {      # bk_latest <prefix>
	ls -1 "$BK_DIR/${1}_"*.tgz 2>/dev/null | sort -r | head -1
}

# Unpack an archive and set $BK_UNPACKED to the directory a recipe reads out of.
# Takes a full path, a bare filename in $BK_DIR, or nothing at all — with
# nothing it takes the newest, which is what `restore` means at three in the
# morning.
#
# It sets a variable rather than echoing the path, and that is not a style
# choice: `_d="$(bk_open mysql)"` runs all of this in a subshell, so BK_WORK
# never reaches the caller and the EXIT trap fires the moment the substitution
# closes — deleting the unpacked archive before the recipe can read a byte of
# it. Every progress line here goes to stderr for the same reason, so a caller
# who does capture output gets nothing surprising in it.
bk_open() {        # bk_open <prefix> [archive]; sets $BK_UNPACKED
	local _a _r
	_a="${2-}"
	if [ -z "$_a" ]; then
		_a="$(bk_latest "$1")"
		# Nothing local is the normal case after a disk is replaced, and it is
		# exactly when somebody needs this most — so look in the bucket before
		# giving up, rather than telling them their backups are gone.
		if [ -z "$_a" ]; then
			_r="$(bk_remote_ls "$1" 2>/dev/null | tail -1)"
			[ -n "$_r" ] || die "no backup for $1 in $BK_DIR and none in the bucket either"
			mkdir -p "$BK_DIR"
			bk_download "$_r" "$BK_DIR/$_r" || die "could not download $_r"
			_a="$BK_DIR/$_r"
		fi
	elif [ ! -f "$_a" ]; then
		if [ -f "$BK_DIR/$_a" ]; then
			_a="$BK_DIR/$_a"
		else
			mkdir -p "$BK_DIR"
			bk_download "$(basename "$_a")" "$BK_DIR/$(basename "$_a")" ||
				die "no such archive here or in the bucket: $_a"
			_a="$BK_DIR/$(basename "$_a")"
		fi
	fi
	[ -f "$_a" ] || die "no such archive: $_a"
	BK_WORK="$(tmp_dir)"
	trap 'bk_close' EXIT INT TERM
	tar xzf "$_a" -C "$BK_WORK" || die "$_a will not unpack — is it a complete download?"
	BK_UNPACKED="$BK_WORK/$1"
	[ -d "$BK_UNPACKED" ] || die "$_a does not look like a $1 backup"
	info "restoring from $(basename "$_a")" >&2
}

bk_close() {
	[ -n "${BK_WORK:-}" ] && rm -rf "$BK_WORK"
	BK_WORK=""; BK_UNPACKED=""
	trap - EXIT INT TERM
	return 0
}

# WordPress, Typecho and Nextcloud all keep one database and one directory,
# and all three would otherwise repeat the same twelve lines. The database is
# dumped through mysql_root, so it works whether or not the mysql recipe has
# written $MY_CNF yet.
# Said out loud at install time, because "can this machine take a backup at
# all" is worth knowing on the day you install the database rather than on the
# night you need one. A distro that splits its client package differently is
# the failure this catches.
dump_tool_check() {  # dump_tool_check <command> <sentence>
	if have "$1"; then
		ok "$1 is here — $2"
	else
		warn "$1 is missing; app-setup dump and backup will not work for this"
	fi
}

# Every database on the server to one file. Lives here rather than in mysql.sh
# because the LNMP and LAMP suites need exactly the same thing, and two
# implementations of "how do you dump this server" drift — the one that drifts
# is always the one on the timer that nobody watches.
mysql_dump_all() { # mysql_dump_all <file>
	if [ -r "$MY_CNF" ]; then
		mysqldump --defaults-file="$MY_CNF" --single-transaction --quick \
			--routines --events --all-databases > "$1"
	else
		mysqldump --protocol=socket -uroot --single-transaction --quick \
			--routines --events --all-databases > "$1"
	fi || die "mysqldump failed — is the server running, and is $MY_CNF still right?"
	[ -s "$1" ] || die "the dump came out empty; that is not a backup"
}

# One database to one file. `--databases` rather than a bare name so the dump
# carries its own CREATE DATABASE and USE, and loading it recreates the schema
# instead of needing one to exist first.
mysql_dump_db() {  # mysql_dump_db <database> <file>
	if [ -r "$MY_CNF" ]; then
		mysqldump --defaults-file="$MY_CNF" --single-transaction --quick \
			--routines --events --databases "$1" > "$2"
	else
		mysqldump --protocol=socket -uroot --single-transaction --quick \
			--routines --events --databases "$1" > "$2"
	fi || die "could not dump the $1 database"
	[ -s "$2" ] || die "the dump came out empty; that is not a backup"
}

mysql_load_file() { # mysql_load_file <file>
	[ -f "$1" ] || die "no such dump: $1"
	mysql_root < "$1" || die "the import failed"
}

bk_mysql_db() {    # bk_mysql_db <database>
	step "dumping the $1 database"
	mysql_dump_db "$1" "$(bk_path db.sql)"
}

bk_mysql_load() {  # bk_mysql_load <dir from bk_open>
	[ -f "$1/db.sql" ] || die "that archive has no database dump in it"
	step "loading the database back"
	mysql_load_file "$1/db.sql"
}

# The other half of bk_add: everything it saved goes back where it came from.
bk_restore_files() {   # bk_restore_files <dir from bk_open>
	[ -d "$1/files" ] || return 0
	step "putting the saved files back"
	cp -a "$1/files/." / || warn "some files could not be written back"
}

# ----------------------------------------------------------- default verbs --
# A recipe that wants different behaviour defines the same function after
# sourcing this file; the later definition wins.

is_installed() {
	local _bin _file _p _pkgs _pkg
	# CHECK_PKG before CHECK_BIN, because a binary on PATH does not prove the
	# package is there: busybox ships applets called unzip, ping, wget and less
	# in the *base* Alpine image, so `have unzip` is true on a box where
	# nothing has been installed at all. Ask the package manager when the
	# answer has to be exact.
	_pkg="$(pmv CHECK_PKG)"
	if [ -n "$_pkg" ]; then pkg_present "$_pkg" && return 0 || return 1; fi
	_bin="$(pmv CHECK_BIN)"
	if [ -n "$_bin" ]; then have "$_bin" && return 0 || return 1; fi
	_file="$(pmv CHECK_FILE)"
	if [ -n "$_file" ]; then [ -e "$_file" ] && return 0 || return 1; fi
	_pkgs="$(pmv PKGS)"
	if [ -n "$_pkgs" ]; then
		for _p in $_pkgs; do pkg_present "$_p" || return 1; done
		return 0
	fi
	return 1
}

version_line() { :; }        # recipes print one short line here

do_install()   { pkg_install $(pmv PKGS); _s="$(svc)"; [ -n "$_s" ] && { svc_enable "$_s"; svc_start "$_s"; }; return 0; }
do_uninstall() { _s="$(svc)"; [ -n "$_s" ] && { svc_stop "$_s"; svc_disable "$_s"; }; pkg_remove $(pmv PKGS); return 0; }
do_start()     { _s="$(svc)"; [ -n "$_s" ] || { warn "nothing to start: this software has no service"; return 0; }; step "starting $_s"; svc_start "$_s"; }
do_stop()      { _s="$(svc)"; [ -n "$_s" ] || return 0; step "stopping $_s"; svc_stop "$_s"; }
do_restart()   { do_stop; do_start; }
do_enable()    { _s="$(svc)"; [ -n "$_s" ] || return 0; svc_enable "$_s"; ok "$_s will start at boot"; }
do_disable()   { _s="$(svc)"; [ -n "$_s" ] || return 0; svc_disable "$_s"; ok "$_s will not start at boot"; }
do_help()      { echo "This source ships no documentation."; }

# Not every recipe has data. htop has nothing to save and saying so is a
# better answer than an empty archive that looks like a backup for a year and
# then turns out to be one at the worst possible moment.
do_backup()    { warn "this software has no backup in its recipe — nothing was saved"; return 0; }
do_restore()   { warn "this software has no restore in its recipe"; return 0; }
do_dump()      { warn "this software has no dump in its recipe"; return 0; }
do_load()      { warn "this software has no load in its recipe"; return 0; }

# The one function app-setup reads a value out of rather than an exit code.
#
#   exit 0  running, or — when there is no service — simply installed
#   exit 1  installed but stopped
#   exit 2  not installed
#   exit 3  installed and broken
#
# stdout is `key=value` lines: `detail=` is the sentence on the card, and
# `enabled=` fills the boot tick. It must be fast; app-setup kills it at eight
# seconds and shows the package as broken.
do_status() {
	local _s _v
	is_installed || exit 2
	_v="$(version_line 2>/dev/null || true)"
	[ -n "$_v" ] && echo "detail=$_v"
	_s="$(svc)"
	[ -n "$_s" ] || exit 0
	if svc_enabled "$_s"; then echo "enabled=1"; else echo "enabled=0"; fi
	if svc_running "$_s"; then exit 0; else exit 1; fi
}

app_main() {
	local _verb
	_verb="${1:-help}"
	case "$_verb" in
		install)            need_root; do_install ;;
		uninstall|remove)   need_root; do_uninstall ;;
		start)              need_root; do_start ;;
		stop)               need_root; do_stop ;;
		restart)            need_root; do_restart ;;
		enable)             need_root; do_enable ;;
		disable)            need_root; do_disable ;;
		status)             do_status ;;
		backup)             need_root; do_backup ;;
		# `shift` so a recipe run by hand can be handed one archive —
		# `sh /etc/app-setup/mysql.sh restore mysql_20210403123221.tgz`. With
		# no argument both this and `app-setup restore mysql` take the newest.
		restore)            need_root; shift; do_restore "$@" ;;
		# Same shift, same reason: `sh /etc/app-setup/mysql.sh dump /tmp/x.sql`
		# and `… load /tmp/x.sql` both name a file. With no argument, dump
		# picks a dated name and load takes the newest.
		dump)               need_root; shift; do_dump "$@" ;;
		load)               need_root; shift; do_load "$@" ;;
		help|docs|doc)      do_help ;;
		*)                  err "unknown verb: $_verb"; exit 64 ;;
	esac
}
