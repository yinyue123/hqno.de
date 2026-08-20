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

# ------------------------------------------------------------- data disk --
#
# A reinstall replaces this container's whole root filesystem and keeps /data.
# So everything a holder would be upset to lose — a database's tables, a
# document root full of uploads — belongs on /data, and the distro default
# (/var/lib/mysql and friends) is the one place it must not be.
#
# The check has to be for a *mount*, not for a directory. A data disk exists
# only when somebody asked for one; a container without one either has no /data
# at all or has an ordinary directory of that name sitting on the root
# filesystem, which looks identical from in here and dies with everything else.
# That is the false positive worth these lines, because it is the one that
# looks safe.
DATA_DIR="${DATA_DIR:-/data}"

data_disk() {
	[ -d "$DATA_DIR" ] || return 1
	if [ -r /proc/self/mountinfo ]; then
		# field 5 is the mount point
		awk -v p="$DATA_DIR" '$5 == p { f = 1 } END { exit !f }' /proc/self/mountinfo
		return
	fi
	# No /proc to read: a separate mount is a different device from /.
	[ "$(stat -c %d "$DATA_DIR" 2>/dev/null)" != "$(stat -c %d / 2>/dev/null)" ]
}

# Where a recipe's data should live: the data disk when there is one, the
# distro's own path when there is not. Recipes call this once and use the
# answer everywhere, so backup, restore and the help text cannot disagree with
# the config about where the files actually are.
data_path() {      # data_path <name> <distro default>
	if data_disk; then printf '%s/%s' "$DATA_DIR" "$1"; else printf '%s' "$2"; fi
}

# Said once per recipe, at install, when there is nowhere durable to put this.
# The second sentence is the useful one: the cheapest moment to fix it is now,
# while the database is still empty.
data_warn() {      # data_warn <path> <what>
	data_disk && return 0
	warn "this container has no data disk, so $1 is on the root filesystem —"
	warn "a reinstall replaces it and every $2 in it."
	warn "Set up a backup, or ask for a data disk and reinstall now, while"
	warn "there is nothing to lose."
	return 0
}

# Free kilobytes on whichever filesystem holds a path. The data disk is a
# second disk image with a size of its own, and it is routinely *smaller* than
# the root — so "will this fit" has to be asked about /data, not about /.
data_free_kb() {   # data_free_kb <path>
	df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4 }'
}

# Move an existing directory onto the data disk and leave a symlink behind, so
# nothing that hard-codes the old path has to be found first. Refuses rather
# than half-moves: a data directory that is partly in two places is worse than
# one that never moved.
data_relocate() {  # data_relocate <old dir> <new dir>
	local _need _room
	[ -d "$1" ] || return 1
	[ -L "$1" ] && { info "$1 is already a link to $(readlink "$1")"; return 0; }
	data_disk || { err "no data disk on this container — nothing to move to"; return 1; }
	_need="$(du -sk "$1" 2>/dev/null | awk '{print $1}')"
	_room="$(data_free_kb "$DATA_DIR")"
	if [ -n "$_need" ] && [ -n "$_room" ] && [ "$_need" -gt "$_room" ]; then
		err "$1 is $((_need / 1024))M and $DATA_DIR has $((_room / 1024))M free — not moving it"
		return 1
	fi
	mkdir -p "$(dirname "$2")" || return 1
	step "moving $1 to $2"
	if [ -e "$2" ] && [ -n "$(ls -A "$2" 2>/dev/null)" ]; then
		err "$2 already exists and is not empty — move or remove it first"
		return 1
	fi
	rm -rf "$2"
	mv "$1" "$2" || { err "could not move $1 — it has not been touched"; return 1; }
	ln -s "$2" "$1" || { err "moved, but could not link $1 -> $2"; return 1; }
	ok "$1 -> $2"
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

# ...and on a container with a data disk the bytes live on it, while the path
# stays exactly what every tutorial says. A symlink rather than a moved
# WEBROOT: change the variable and `cd /var/www/html` stops working, every
# nginx snippet somebody pasted stops matching, and the reason /var/www/html
# was chosen in the first place is gone. This way nothing above knows.
#
# Uploads are the half of a site nobody can download again, so this matters
# more than the database it sits beside.
web_root_on_data() {
	local _target
	data_disk || { data_warn "$WEBROOT" "file"; return 0; }
	_target="$DATA_DIR/www"
	[ -L "$WEBROOT" ] && [ "$(readlink "$WEBROOT")" = "$_target" ] && return 0
	if [ -d "$WEBROOT" ] && [ ! -L "$WEBROOT" ]; then
		if [ -n "$(ls -A "$WEBROOT" 2>/dev/null)" ]; then
			# Somebody's site is in there. Moving it is a decision, not a
			# side effect of installing a web server over the top.
			warn "$WEBROOT has files in it and is not on the data disk."
			warn "A reinstall would take them. Move them with:  app-setup movedata nginx"
			return 0
		fi
		rmdir "$WEBROOT" 2>/dev/null || return 0
	fi
	mkdir -p "$_target" || return 0
	ln -sfn "$_target" "$WEBROOT" && ok "$WEBROOT -> $_target (on the disk that survives a reinstall)"
}

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

# APP_PARAM_* is a flat namespace and param_export only ever *adds* to it, so a
# caller's settings leak into a callee that does not happen to declare the same
# name. Nothing collided while the composed recipes' parameter names were
# disjoint by luck; a backup job with `host`, `port`, `user` and `password`
# calling a store with the same four names collides on every one of them, and
# the failure is an archive rsync'd to port 3306. Same class of defect as the
# `_p` clobber in docs/app-setup.md §5: POSIX shell has no scope, and the
# symptom shows up three calls away from the cause.
param_reset() {
	local _v
	for _v in $(env | sed -n 's/^\(APP_PARAM_[A-Za-z0-9_]*\)=.*/\1/p'); do
		unset "$_v"
	done
}

# The search-path walk that recipe() and recipe_status() each held a copy of.
recipe_path() {    # recipe_path <id> -> path, or non-zero
	local _d _found _want
	_want="$1"; _found=""
	for _d in $(printf '%s' "${APP_SETUP_PATH:-/etc/app-setup:/etc/app-setup/local}" | tr ':' ' '); do
		[ -f "$_d/$_want.sh" ] && _found="$_d/$_want.sh"
	done
	[ -n "$_found" ] || return 1
	printf '%s' "$_found"
}

recipe() {         # recipe <id> <verb>
	local _found _verb _want
	_want="$1"; _verb="$2"
	_found="$(recipe_path "$_want")" ||
		die "this needs the '$_want' source, which is not on this machine"
	step "$_verb: $_want"
	( param_reset; param_export "$_want"; sh "$_found" "$_verb" )
}

recipe_status() {  # 0 running, 1 stopped, 2 absent — same codes as the verb
	local _found
	_found="$(recipe_path "$1")" || return 2
	( param_reset; param_export "$1"; sh "$_found" status ) >/dev/null 2>&1
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

# The credential file every mysql client below runs through. It is $MY_CNF —
# root's own, written by mysql.sh — for a database on this machine, and a job
# card on the Backup tab points it at a throwaway file holding the host, port,
# user and password somebody typed for a database that is not here.
#
# One variable, so there is exactly one mysqldump command line in this tree.
# The rule the whole Backup tab is judged on is that adding a job card must not
# add a second answer to "what is a correct dump of this database": the one
# that drifts is always the one on the timer that nobody watches.
MY_DEFAULTS="${MY_DEFAULTS:-$MY_CNF}"

# A throwaway my.cnf for one connection, written where the caller says and left
# for the caller to remove. A password on mysqldump's command line is in `ps`
# for every user on the box for as long as the dump runs, which on a real
# database is minutes; MYSQL_PWD avoids that and prints a deprecation warning
# into the middle of the output on some builds. A file is the one way that is
# neither.
#
# An empty password means *use the local credential file*, not *no password*:
# for a local server the secret is never copied into a second place, and only
# somebody connecting to another host ever types one.
mysql_conn_cnf() { # mysql_conn_cnf <dest> <host> <port> <user> <password> -> path to use
	local _h
	_h="${2:-127.0.0.1}"
	if [ -z "${5-}" ]; then
		case "$_h" in
			127.0.0.1|localhost|::1|'')
				[ -r "$MY_CNF" ] && { printf '%s' "$MY_CNF"; return 0; } ;;
		esac
	fi
	( umask 077; cat > "$1" <<EOF
[client]
host=$_h
port=${3:-3306}
user=${4:-root}
password=${5-}
EOF
	) || return 1
	chmod 600 "$1" 2>/dev/null || true
	printf '%s' "$1"
}

mysql_root() {
	if [ -r "$MY_DEFAULTS" ]; then
		# Authoritative once it exists: an error from here is a real error and
		# should be seen, not masked by a retry that gets access denied.
		mysql --defaults-file="$MY_DEFAULTS" "$@"
	else
		# A fresh install lets root in over the unix socket with no password.
		mysql --protocol=socket -uroot "$@" 2>/dev/null || mysql -uroot "$@"
	fi
}

mysql_wait() {     # the service is up before the socket is
	local _n
	_n=0
	while [ "$_n" -lt 30 ]; do
		if [ -r "$MY_DEFAULTS" ]; then
			mysqladmin --defaults-file="$MY_DEFAULTS" ping >/dev/null 2>&1 && return 0
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

# ------------------------------------------------------------------- cron --
# Two families of image, and two different places a timer actually lives.
#
# Debian and the RHEL rebuilds ship vixie cron / cronie, which read drop-in
# files from /etc/cron.d — one file per job, each line carrying the user it
# runs as. Alpine's crond is busybox, which has never read that directory: it
# reads one crontab per user out of /etc/crontabs, and those lines have no user
# field because the file is already the answer to "whose".
#
# Writing the Debian shape on an Alpine box is the worst outcome available,
# because it is not an error anybody sees. The file gets created, the install
# says it worked, and nothing ever reads it — a backup nobody knows is not
# running until the night they need it. On Alpine it was louder than that and
# still wrong: /etc/cron.d does not exist at all, so the redirect failed and
# `set -e` took the whole recipe down at "writing the schedule".
#
# The marker on the busybox side is a trailing `# app-setup:<name>` comment.
# The shell that runs the command treats it as a comment, so it costs nothing,
# and it gives grep one anchor to rewrite or remove the line by.

# dropin, crontab, or none. Checked rather than derived from $PM: what matters
# is which of the two a machine will actually read, and a container can have
# been given either.
cron_kind() {
	if [ -d /etc/cron.d ];  then printf 'dropin'
	elif have crontab;      then printf 'crontab'
	else                         printf 'none'
	fi
}

# cron_set <name> <five-field spec> <command>
# Idempotent. An empty spec removes the timer and succeeds: "installed with the
# schedule off" is a state a recipe is allowed to be in, and it is not this
# function's business to have an opinion about it.
cron_set() {
	local _n _when _cmd _f _mark _cur
	_n="$1"; _when="${2-}"; _cmd="${3-}"
	_mark="# app-setup:$_n"
	case "$(cron_kind)" in
	dropin)
		_f="/etc/cron.d/$_n"
		# Debian's cron ignores a file in cron.d whose name has a dot in it,
		# and silently: no log line, no error, the job simply never runs.
		case "$_n" in *.*) warn "cron.d ignores filenames containing a dot — '$_n' will never fire" ;; esac
		[ -n "$_when" ] || { rm -f "$_f"; return 0; }
		cat > "$_f" <<EOF || return 1
# app-setup — written by \`app-setup install $_n\`. Edit Settings rather than
# this file; a reinstall overwrites it.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/sh
$_when root $_cmd
EOF
		chmod 0644 "$_f"
		;;
	crontab)
		# Read, drop our old line, add the new one, write the lot back.
		# `crontab -` is stdin on busybox and on vixie alike.
		_cur="$(crontab -l 2>/dev/null | grep -v "$_mark\$" || true)"
		[ -z "$_when" ] || _cur="$(printf '%s\n%s %s %s' "$_cur" "$_when" "$_cmd" "$_mark")"
		printf '%s\n' "$_cur" | sed '/^[[:space:]]*$/d' | crontab - || {
			err "could not write root's crontab"
			return 1
		}
		;;
	*)
		return 1
		;;
	esac
	return 0
}

cron_clear() { cron_set "$1" "" ""; }

# The line that is actually in place, or nothing. Read back rather than
# remembered: what somebody is trying to find out here is whether the thing
# they asked for is really there, and a value this file kept for itself would
# answer a different question.
cron_line_of() {
	case "$(cron_kind)" in
	dropin)  sed -n 's/^\([0-9*][^ ]*\([ \t]\+[^ \t]\+\)\{4\}\).*/\1/p' "/etc/cron.d/$1" 2>/dev/null | head -1 ;;
	crontab) crontab -l 2>/dev/null | sed -n "s/^\(.*\) # app-setup:$1\$/\1/p" | head -1 ;;
	esac
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
# A job card on the Backup tab carries its own destination, folder and
# schedule; an engine recipe backed up from the machine-wide `backup` card
# carries none, and reads the same names out of `params/backup.conf` through
# `bk_conf`. Everything below asks the recipe first and falls back to that, so
# one pipeline serves both without either of them knowing about the other.
#
# One path under /data says *app-setup put this here*, the way /etc/app-setup
# does at the other end — and /data is the part that matters: it is the only
# directory that survives a container reinstall (docs/tenant_image.md). Each
# job then gets a directory of its own inside, so "the newest archive for this
# job" is `sort -r | head -1` over a directory rather than a glob over a shared
# pile that a prefix can match too much of.
BK_ROOT="${BK_ROOT:-/data/app-setup}"
BK_DIR="${BK_DIR:-$BK_ROOT/backups}"

# `dump` and `load` are the other half, and deliberately not the same thing as
# `backup` and `restore`. A backup is the whole pipeline — packed, dated,
# uploaded, pruned, on a timer. A dump is one plain file you can open, read,
# scp somewhere, mail to somebody who asked, or feed to a different server.
# Both exist because people want both, and a tool that only offers the
# packaged one gets worked around with a half-remembered mysqldump line.
DUMP_DIR="${DUMP_DIR:-$BK_ROOT/dumps}"

# The archives that are already on disk from before the move, brought across by
# `mv` and not by copy — the disk that cannot hold two copies is exactly the one
# this matters on. Runs once, only when the old directory is there, and leaves
# anything it does not recognise where it is rather than sweeping a stranger's
# files into a new tree. Nothing is uploaded again: a migration that re-uploads
# a year of archives to prove a point is a migration that runs up somebody's
# bill.
bk_migrate() {
	local _f _n _pfx _old
	_old="${1:-/data/backups}"
	[ -d "$_old" ] || return 0
	[ "$_old" != "$BK_DIR" ] || return 0
	_n=0
	for _f in "$_old"/*.tgz; do
		[ -f "$_f" ] || continue
		_pfx="$(basename "$_f")"
		# <prefix>_<14 digits>.tgz and nothing else. A file that does not match
		# is not ours to move.
		case "$_pfx" in
			*_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].tgz) : ;;
			*) continue ;;
		esac
		_pfx="${_pfx%_*}"
		mkdir -p "$BK_DIR/$_pfx" || continue
		mv "$_f" "$BK_DIR/$_pfx/" && _n=$((_n + 1))
	done
	[ "$_n" -gt 0 ] && info "moved $_n archive(s) from $_old into $BK_DIR/<job>/"
	# Only if it is empty. Somebody else's file in there is somebody else's.
	rmdir "$_old" 2>/dev/null || true
	return 0
}

# This job's directory under $BK_DIR. Made on demand, 700, because an archive
# of a database is the database.
bk_jobdir() {      # bk_jobdir <prefix>
	mkdir -p "$BK_DIR/$1" 2>/dev/null || true
	chmod 700 "$BK_DIR" 2>/dev/null || true
	chmod 700 "$BK_DIR/$1" 2>/dev/null || true
	printf '%s' "$BK_DIR/$1"
}

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
	# One lock for every backup on the machine, taken here because this is the
	# one line every do_backup has in common. Two mysqldumps of the same server
	# at once is the case it exists for, and a box with one CPU is where it
	# matters.
	bk_lock || die "another backup is still running — nothing was done"
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
	bk_unlock
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
	# One rule rather than two: everything app-setup writes under /data lives
	# in one directory, so excluding that directory stays correct when
	# something else is put under it.
	_ex="--exclude=${BK_ROOT#/}"
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
	bk_migrate
	_arch="$(bk_jobdir "$BK_PREFIX")/$BK_ARCHIVE"
	[ -d "$(dirname "$_arch")" ] || die "cannot write to $BK_DIR/$BK_PREFIX"
	step "packing $BK_ARCHIVE"
	tar czf "$_arch" -C "$BK_WORK" "$BK_PREFIX" || die "could not pack the archive"
	chmod 600 "$_arch"
	# The service goes back up before the upload, not after: a slow or broken
	# remote must not be the reason a site is down for another two minutes.
	bk_resume
	rm -rf "$BK_WORK"; BK_WORK=""
	# Narrowed rather than cleared. Everything after this point — upload,
	# prune — can still fail under `set -e`, and a run that dies there must
	# not leave the lock behind for the six-hour breaker to find: that is a
	# whole night of backups silently skipped for one failed upload.
	trap 'bk_unlock' EXIT INT TERM
	_sz="$(du -h "$_arch" 2>/dev/null | awk '{print $1}')"
	ok "$_arch${_sz:+  ($_sz)}"
	bk_upload "$_arch"
	bk_prune "$BK_PREFIX"
	bk_prune_remote "$BK_PREFIX"
	bk_unlock
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

# ----------------------------------------------------------- the stores --
#
# A store is an ordinary recipe that answers five questions about a remote
# directory: make this folder, put this file in it, get that one back, what is
# in there, delete that one. It knows a protocol and nothing else — no
# schedule, no databases — so adding a seventh kind is one file in
# /etc/app-setup/local/ and no change here.
#
# Which store, and which folder inside it, are settings on the `backup` recipe.

# Which recipe is this? common.sh has never needed to know — a recipe passes
# its own id to bk_begin as a literal — and the folder default does, on the
# paths where bk_begin never ran (restore, prune). Derived the way the C
# derives it when a recipe omits `# id:`, so the two cannot disagree.
BK_ID="${BK_ID:-$(basename "$0" .sh)}"

# Which store, and which folder in it. A job card on the Backup tab declares
# both as its own `# param:`; an engine recipe run from the machine-wide
# `backup` card declares neither and gets them out of params/backup.conf. Asked
# in that order, so a job that sets nothing still inherits the machine's
# destination and a job that sets one is never overruled by it.
#
# `none` counts as nothing set, and it has to: the binary exports every
# declared parameter, and for one that has never been saved it exports the
# header's *default* — so a job card whose Destination has never been touched
# arrives here as store=none, not as an empty string. Without this line the
# inheritance the paragraph above describes could never happen even once, and
# `app-setup set backup store=webdav; app-setup install backup-mysql` — the two
# lines every store's own help text ends with — failed with "this job has
# nowhere to send its backups" directly under "Set up already: webdav".
# It is not a value anybody loses by this: a job pointed at `none` is refused
# by bk_need_store, so the dropdown's first entry means "not chosen yet"
# everywhere else already.
bk_setting() {     # bk_setting <key> [default]
	local _v
	_v="$(param "$1")"
	[ "$_v" = none ] && _v=""
	[ -n "$_v" ] || _v="$(bk_conf "$1")"
	[ -n "$_v" ] || _v="${2-}"
	printf '%s' "$_v"
}

# The folder this job writes into, under the store's own base. The hostname is
# what keeps two containers sharing one destination from pruning each other's
# history — silently, on a timer, and discovered by the second one to need a
# restore.
bk_folder() {
	local _f
	_f="$(bk_setting folder)"
	[ -n "$_f" ] || _f="$(hostname 2>/dev/null || echo unknown)/$BK_ID"
	printf '%s' "$_f"
}

# Run a verb on the configured store. The folder is resolved *here*, in the
# caller's environment, because param_reset is about to take every APP_PARAM_*
# away and `folder` belongs to the backup settings rather than to the store.
bk_store() {       # bk_store <verb> [args…]
	local _s _f _folder _verb
	_s="$(bk_setting store)"
	[ -n "$_s" ] && [ "$_s" != none ] || return 1
	_f="$(recipe_path "store-$_s")" || { err "no store-$_s recipe on this machine"; return 1; }
	_folder="$(bk_folder)"
	_verb="$1"; shift
	( param_reset; param_export "store-$_s"; BK_ID="$BK_ID" sh "$_f" "$_verb" "$_folder" "$@" )
}

bk_store_set() { [ -n "$(bk_setting store)" ] && [ "$(bk_setting store)" != none ]; }

# Where a store's Test button leaves its stamp. Read rather than probed:
# do_status is killed at eight seconds and a card grid that opened six network
# connections on every redraw would spend that budget on the first one.
BK_STATE="${BK_STATE:-$APP_SETUP_STATE/backup}"

# Has the configured store ever passed all five steps of its own Test? This is
# the difference between "a destination is named" and "a destination works",
# and it is the question install and `backup` both have to ask before they
# promise anybody anything.
bk_store_ready() {
	local _s
	_s="$(bk_setting store)"
	[ -n "$_s" ] && [ "$_s" != none ] || return 1
	[ -f "$BK_STATE/store-$_s.ok" ]
}

# The stores that have passed, as a list — which turns "set one up first" from
# an instruction into a choice as soon as there is one.
bk_stores_ready() {
	local _f _out
	_out=""
	for _f in "$BK_STATE"/store-*.ok; do
		[ -f "$_f" ] || continue
		_f="$(basename "$_f" .ok)"
		_out="$_out ${_f#store-}"
	done
	printf '%s' "${_out# }"
}

# A stamp back to seconds since the epoch, using the same integer arithmetic
# the retention ladder does and for the same reason: `date -d` is GNU-only in
# the form this wants and busybox's takes a different subset.
bk_stamp_epoch() { # bk_stamp_epoch <YYYYMMDDHHMMSS>
	local _s _n
	_s="$1"
	case "$_s" in
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) : ;;
		*) return 1 ;;
	esac
	_n="$(bk_daynum "$(printf '%s' "$_s" | cut -c1-4)" \
	                "$(printf '%s' "$_s" | cut -c5-6)" \
	                "$(printf '%s' "$_s" | cut -c7-8)")"
	printf '%s' $(( _n * 86400 \
		+ $(bk_num "$(printf '%s' "$_s" | cut -c9-10)")  * 3600 \
		+ $(bk_num "$(printf '%s' "$_s" | cut -c11-12)") * 60 \
		+ $(bk_num "$(printf '%s' "$_s" | cut -c13-14)") ))
}

# "3h ago". Round numbers on purpose: a card is read at a glance and the
# question behind it is "recently, or ages ago", never "how many minutes".
bk_ago() {         # bk_ago <YYYYMMDDHHMMSS>
	local _t _n _d
	_t="$(bk_stamp_epoch "$1")" || { printf 'at %s' "$1"; return 0; }
	_n="$(date -u +%s 2>/dev/null)" || { printf 'at %s' "$1"; return 0; }
	_d=$((_n - _t))
	[ "$_d" -ge 0 ] || { printf 'just now'; return 0; }
	if   [ "$_d" -lt 90 ];    then printf 'just now'
	elif [ "$_d" -lt 5400 ];  then printf '%sm ago' $((_d / 60))
	elif [ "$_d" -lt 172800 ];then printf '%sh ago' $((_d / 3600))
	else                           printf '%sd ago' $((_d / 86400))
	fi
}

# ------------------------------------------------ the store's own contract --
#
# Five operations, because each one fails on its own, and a store that has
# never passed all five is not a destination anybody should rely on:
# credentials that can PutObject and not ListBucket are the single most common
# half-working S3 configuration, an FTP account often lands you in a directory
# you cannot write to, and a `rm` that is refused is not discovered until the
# first prune — a month later, on a timer, in a log nobody opens.
#
# It probes into a folder rather than into the base, because that is what a job
# does, and the two permissions are not the same one: a WebDAV share or an FTP
# account that lets you write files into the directory it gave you and refuses
# to let you create a subdirectory under it is a normal configuration. Testing
# at the base would pass, and then every backup would fail at its first mkdir.
#
# One implementation, called by all six stores. A conformance test with six
# copies is a conformance test that means six different things by the third
# time somebody fixes one of them.
bk_probe_cleanup() { :; }   # a store that can remove a directory overrides this

# Un-bless, before anything can go wrong. Every do_test calls this as its first
# statement, ahead of its own "is this even filled in" checks — because those
# checks `die`, and a die before bk_probe would leave last week's passing stamp
# sitting there. The card reads correctly either way (do_status exits 2 when
# the settings are gone), but bk_store_ready reads only the stamp, so a job
# would pass bk_need_store and go looking for a bucket whose name had been
# deleted. A store is blessed by a test that passed, not by one that once did.
bk_unbless() { rm -f "$BK_STATE/$1.ok"; return 0; }

bk_probe() {       # bk_probe <store id> <what to call the destination>
	local _f _d _rc
	_f=".app-setup-probe-$(date -u +%Y%m%dT%H%M%SZ)"
	# The stamp is what keeps two machines testing the same store from
	# deleting each other's probe.
	_d="$(tmp_dir)"
	printf 'app-setup backup reachability check\n' > "$_d/probe"
	_rc=0

	step "making a folder"
	do_mkdir "$_f" || _rc=1
	if [ "$_rc" = 0 ]; then
		step "writing a file into it"
		do_put "$_f" "$_d/probe" || _rc=1
	fi
	if [ "$_rc" = 0 ]; then
		step "listing it"
		do_ls "$_f" | grep -q '^probe$' ||
			{ err "the file was written and does not appear in the listing"; _rc=1; }
	fi
	if [ "$_rc" = 0 ]; then
		step "reading it back"
		do_get "$_f" probe "$_d/back" || _rc=1
		cmp -s "$_d/probe" "$_d/back" || { err "what came back is not what went out"; _rc=1; }
	fi
	if [ "$_rc" = 0 ]; then
		step "deleting it"
		do_rm "$_f" probe || _rc=1
	fi
	# Whether it passed or failed, the probe does not stay behind.
	do_rm "$_f" probe >/dev/null 2>&1 || true
	bk_probe_cleanup "$_f" >/dev/null 2>&1 || true
	rm -rf "$_d"

	mkdir -p "$BK_STATE"
	if [ "$_rc" = 0 ]; then
		date -u +%Y%m%d%H%M%S > "$BK_STATE/$1.ok"
		ok "folder, write, read and delete all worked — $2"
	else
		# Un-blessed, so nothing offers it as a working destination. A store
		# that fails today and passed last week must not keep the old stamp.
		rm -f "$BK_STATE/$1.ok"
		err "this destination is not usable yet. Nothing above should be relied on until it is."
	fi
	return "$_rc"
}

# The card, in three states, and never over the network: do_status is killed at
# eight seconds and a grid that opened six connections on every redraw would
# spend that budget on the first one. Both files were written by something that
# had already paid for the round trip.
bk_store_card() {  # bk_store_card <store id> <one line describing the settings>
	local _st _up
	_st="$BK_STATE/$1.ok"
	if [ -f "$_st" ]; then
		_up="$(cat "$BK_STATE/$1.state" 2>/dev/null || true)"
		if [ -n "$_up" ]; then
			_up=" · last upload $(bk_ago "${_up%% *}"), ${_up##* }"
		fi
		echo "detail=$2 — tested $(bk_ago "$(cat "$_st")")$_up"
		exit 0
	fi
	echo "detail=$2 — never tested. Press ✓ Test connection."
	exit 3
}

# One sentence, three callers. `install`, `do_status` and ▶ Back up now are
# each somewhere a person arrives at with nowhere to send a backup, and the
# error they get should be the one that says where to go — the same one, so
# nobody has to work out whether they are two different problems.
bk_need_store() {
	local _r
	bk_store_set || {
		err "this job has nowhere to send its backups."
		info "Open Backup → pick a store (S3, R2, WebDAV, FTP, rsync or SCP), fill it"
		info "in and press ✓ Test connection. Then set Destination on this card."
		_r="$(bk_stores_ready)"
		info "Set up already: ${_r:-(none)}"
		return 1
	}
	bk_store_ready || {
		err "the $(bk_setting store) store has never passed a connection test."
		info "Open Backup → $(bk_setting store), fill it in and press ✓ Test connection."
		_r="$(bk_stores_ready)"
		info "Set up already: ${_r:-(none)}"
		return 1
	}
	return 0
}

bk_upload() {      # bk_upload <archive>
	if bk_store_set; then
		step "uploading $(basename "$1") to $(bk_setting store):$(bk_folder)"
		bk_store mkdir >/dev/null 2>&1 || true
		bk_store put "$1" || { err "upload failed — the archive is still in $BK_DIR"; return 1; }
		ok "uploaded to $(bk_setting store):$(bk_folder)"
		# What the store's card reports, written by the one thing that has just
		# paid for a round trip. The stamp is stored rather than a rendered
		# "3h ago", because the card is read at some other time than this and
		# a frozen "3h ago" is worse than no line at all.
		mkdir -p "$BK_STATE"
		printf '%s %s\n' "$(date -u +%Y%m%d%H%M%S)" \
			"$(du -h "$1" 2>/dev/null | awk '{print $1}')" \
			> "$BK_STATE/store-$(bk_setting store).state" 2>/dev/null || true
		return 0
	fi
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
	if bk_store_set; then
		step "fetching $1 from $(bk_setting store):$(bk_folder)"
		bk_store get "$1" "$2"
		return
	fi
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
	if bk_store_set; then
		bk_store ls | grep "^${1:-}.*\.tgz$" | sort
		return
	fi
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

# ------------------------------------------------------------- retention --
#
#   Sort the archives for one job newest first. Keep an archive if it is the
#   newest one in its hour, day, week or month, and that hour, day, week or
#   month is inside the corresponding budget. Delete the rest.
#
# Three properties fall out of writing it that way round, and each is why it is
# written that way round:
#
#   The newest archive is always kept. It is trivially the newest of its own
#   hour, day, week and month, so no combination of settings can delete the
#   backup that was taken thirty seconds ago.
#
#   A completed period's representative never changes. Once August is over the
#   newest August archive is fixed forever, so nothing is deleted and then
#   re-promoted, and nothing has to be uploaded twice.
#
#   It is a pure function of the filenames. No index, no state file, no .keep
#   marker, nothing to fall out of step with the directory. A prune after a
#   crash, after a manual rm, or over a directory written by an older version
#   gives the same answer.

# Leading zeros off, before any of this reaches $(( )). $((08)) is an invalid
# octal constant, so August and September crash a prune written the obvious way
# — and they are the two months nobody is testing in January.
#
# The documented fix for that is $((10#$m)), and it is not usable here: base#n
# is a ksh extension that bash and busybox ash took and **dash did not**, and
# dash is /bin/sh on every Debian and Ubuntu image we ship. `10#08` there is a
# syntax error, which trades a crash in August for a crash all year round.
bk_num() {         # bk_num <digits> -> the same number, base ten
	local _n
	_n="$1"
	while : ; do
		case "$_n" in
			0[0-9]*) _n="${_n#0}" ;;
			*) break ;;
		esac
	done
	printf '%s' "${_n:-0}"
}

# days_from_civil — 1970-01-01 is day 0. Pure integer arithmetic, because the
# bucket a stamp falls in has to be computed on busybox, dash and bash without
# `date -d`: the GNU form we would want is GNU-only and Alpine's busybox date
# accepts a different subset again.
bk_daynum() {      # bk_daynum <Y> <M> <D>
	local _y _m _d _era _yoe _doy _doe
	_y="$(bk_num "$1")"; _m="$(bk_num "$2")"; _d="$(bk_num "$3")"
	[ "$_m" -le 2 ] && _y=$((_y - 1))
	if [ "$_y" -ge 0 ]; then _era=$((_y / 400)); else _era=$(((_y - 399) / 400)); fi
	_yoe=$((_y - _era * 400))
	if [ "$_m" -gt 2 ]; then _doy=$(((153 * (_m - 3) + 2) / 5 + _d - 1))
	else                     _doy=$(((153 * (_m + 9) + 2) / 5 + _d - 1)); fi
	_doe=$((_yoe * 365 + _yoe / 4 - _yoe / 100 + _doy))
	printf '%s' $((_era * 146097 + _doe - 719468))
}

# The four bucket keys for one archive name, as one space-separated line:
# hour day week month. Non-zero if the name carries no stamp we recognise,
# which is what keeps a stranger's file out of the walk entirely.
bk_buckets() {     # bk_buckets <name> -> "<hour> <day> <week> <month>"
	local _s _y _mo _d _h _n
	_s="${1##*_}"; _s="${_s%.tgz}"
	case "$_s" in
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) : ;;
		*) return 1 ;;
	esac
	_y="$(bk_num "${_s%??????????}")"
	_mo="$(bk_num "$(printf '%s' "$_s" | cut -c5-6)")"
	_d="$(printf '%s' "$_s" | cut -c7-8)"
	_h="$(bk_num "$(printf '%s' "$_s" | cut -c9-10)")"
	_n="$(bk_daynum "$_y" "$_mo" "$_d")"
	# The +3 is the whole of the week handling: day 0 is Thursday 1970-01-01,
	# so adding three puts Monday 1969-12-29 at the start of bucket 0 and every
	# boundary thereafter lands on a Monday. No ISO week table, no year-end
	# special case, and a Sunday belongs to the week that began six days back.
	printf '%s %s %s %s' \
		$((_n * 24 + _h)) "$_n" $(((_n + 3) / 7)) $((_y * 12 + _mo - 1))
}

# The walk. Reads names on stdin, newest first, and prints the ones to delete —
# it deletes nothing itself, because the same walk has to run over a local
# directory and over `bk_store ls`, and the two do not remove a file the same
# way. Names, not paths: that is what the driver contract's do_ls is for, and
# it is the whole reason one prune serves both places.
#
# Budgets are measured back from the newest archive rather than from the clock.
# A machine that was off for six weeks otherwise comes back and deletes its
# entire daily rung on the first prune, at exactly the moment somebody is most
# likely to want it. Retention is how much history to keep, not how old it is.
bk_prune_gfs() {   # bk_prune_gfs <keep_h> <keep_d> <keep_w> <keep_m>  <names on stdin
	local _kh _kd _kw _km _name _b _hour _day _week _month
	local _h0 _d0 _w0 _m0 _ph _pd _pw _pm _why
	_kh="${1:-0}"; _kd="${2:-0}"; _kw="${3:-0}"; _km="${4:-0}"
	case "$_kh$_kd$_kw$_km" in *[!0-9]*) return 0 ;; esac
	# All four at zero keeps everything. That is a real thing to want and it
	# must not read as "no rungs, so nothing is worth keeping".
	[ $((_kh + _kd + _kw + _km)) -gt 0 ] || return 0
	_h0=""; _ph=""; _pd=""; _pw=""; _pm=""
	while IFS= read -r _name; do
		[ -n "$_name" ] || continue
		_b="$(bk_buckets "$_name")" || continue
		_hour="${_b%% *}"; _b="${_b#* }"
		_day="${_b%% *}";  _b="${_b#* }"
		_week="${_b%% *}"; _month="${_b#* }"
		[ -n "$_h0" ] || { _h0=$_hour; _d0=$_day; _w0=$_week; _m0=$_month; }
		# Because the list is sorted, "the newest in its bucket" is "the first
		# one whose bucket differs from the previous archive's" — one
		# comparison, and no set of kept names to carry along.
		_why=""
		[ "$_hour"  != "$_ph" ] && [ $((_h0 - _hour))  -lt "$_kh" ] && _why=hourly
		[ -z "$_why" ] && [ "$_day"   != "$_pd" ] && [ $((_d0 - _day))   -lt "$_kd" ] && _why=daily
		[ -z "$_why" ] && [ "$_week"  != "$_pw" ] && [ $((_w0 - _week))  -lt "$_kw" ] && _why=weekly
		[ -z "$_why" ] && [ "$_month" != "$_pm" ] && [ $((_m0 - _month)) -lt "$_km" ] && _why=monthly
		_ph=$_hour; _pd=$_day; _pw=$_week; _pm=$_month
		[ -n "$_why" ] || printf '%s\n' "$_name"
	done
	return 0
}

# The four budgets, from the job's own settings or the machine's. `keep` is
# what the old single-number setting was called; somebody who has one gets it
# read as the daily rung, which is what it was doing.
bk_keep() {        # bk_keep -> "<h> <d> <w> <m>"
	printf '%s %s %s %s' \
		"$(bk_setting keep_hourly 0)" \
		"$(bk_setting keep_daily "$(bk_setting keep 7)")" \
		"$(bk_setting keep_weekly 4)" \
		"$(bk_setting keep_monthly 6)"
}

bk_prune() {       # bk_prune <prefix>
	local _d _f _n
	_d="$BK_DIR/$1"
	[ -d "$_d" ] || return 0
	_n=0
	# Newest first by name, which is why the stamp is fixed-width and UTC.
	# shellcheck disable=SC2046  # bk_keep is our own four numbers, split on purpose
	for _f in $(ls -1 "$_d" 2>/dev/null | grep '\.tgz$' | sort -r |
	            bk_prune_gfs $(bk_keep)); do
		rm -f "$_d/$_f" && { info "pruned $_f"; _n=$((_n + 1)); }
	done
	[ "$_n" -gt 0 ] && info "$(ls -1 "$_d" 2>/dev/null | grep -c '\.tgz$') kept in $_d"
	return 0
}

# The same ladder, on the far end — off unless somebody turned it on, and
# fenced four ways, because this is the one operation here that destroys
# something it cannot get back.
bk_prune_remote() {   # bk_prune_remote <prefix>
	local _list _f _n _cap _kept _stray
	param_on prune_remote || return 0
	bk_store_set || return 0
	_list="$(bk_store ls 2>/dev/null)" || {
		warn "could not list $(bk_setting store):$(bk_folder) — nothing was deleted there"
		return 0
	}
	# "I could not see what is there" and "there is nothing there" must not
	# produce the same action. An empty listing deletes nothing, ever.
	[ -n "$_list" ] || return 0

	# Guard 3, and the folder is what makes it absolute rather than a judgement
	# call: this job created that folder and is its only writer, so a stranger's
	# file in it means the folder is not what this job thinks it is — somebody
	# reused the path, two machines collided on a hand-edited folder, or the
	# base is wrong. Every one of those is a reason to stop, not to delete
	# carefully.
	_stray=""
	for _f in $_list; do
		case "$_f" in
			"$1"_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].tgz) : ;;
			*) _stray="$_f"; break ;;
		esac
	done
	[ -z "$_stray" ] || {
		warn "$(bk_setting store):$(bk_folder) holds something this job did not write — '$_stray'."
		warn "nothing was deleted there. Point Folder somewhere this job owns, or clear it out."
		return 0
	}

	# Guard 4: at most one ladder's worth in a single run. A misconfiguration
	# that would otherwise clear a bucket clears seventeen files and then
	# complains, which is a thing somebody can still recover from.
	# shellcheck disable=SC2046
	_cap=$(( $(bk_setting keep_hourly 0) + $(bk_setting keep_daily 7) +
	         $(bk_setting keep_weekly 4) + $(bk_setting keep_monthly 6) ))
	[ "$_cap" -gt 0 ] || _cap=17
	_n=0
	step "pruning $(bk_setting store):$(bk_folder)"
	# shellcheck disable=SC2046
	for _f in $(printf '%s\n' "$_list" | grep '\.tgz$' | sort -r | bk_prune_gfs $(bk_keep)); do
		if [ "$_n" -ge "$_cap" ]; then
			warn "stopped after $_cap deletions — that is more than one ladder's worth."
			warn "check Folder and the keep_* numbers before running this again."
			break
		fi
		bk_store rm "$_f" && { info "pruned $(bk_setting store):$(bk_folder)/$_f"; _n=$((_n + 1)); }
	done
	_kept="$(printf '%s\n' "$_list" | grep -c '\.tgz$')"
	info "$((_kept - _n)) kept there"
	# The folder itself is never removed. An empty folder that stays is a
	# record that a job used to write here; one that disappears with the last
	# archive is a job that looks like it never ran.
	return 0
}

# ------------------------------------------------------------ the schedule --
#
# One file, rewritten from every job's settings whenever any of them changes,
# because `cat /etc/cron.d/app-setup-backup` is then the whole answer to "what
# runs, and when". install, uninstall and every manual run call this, so the
# file is derived from the settings rather than remembered alongside them.
BK_CRON=app-setup-backup

# The minute is the sum of the id's bytes mod 60: deterministic, needs no
# setting, and it keeps four jobs from waking at once on a box with one CPU.
# backup-mysql 41, backup-postgresql 43, backup-redis 10, backup-mongodb 37,
# files 51.
#
# awk rather than `od -An -tu1`, because busybox's od and GNU's disagree about
# which -t specifiers exist and this has to give the same minute on both — a
# schedule that moves when the image changes is a schedule nobody can reason
# about. awk's sprintf("%c", n) is the one primitive all three awks share.
bk_cron_minute() { # bk_cron_minute <id>
	awk -v s="$1" 'BEGIN{
		for (i = 32; i < 127; i++) T[sprintf("%c", i)] = i
		t = 0
		for (j = 1; j <= length(s); j++) t += T[substr(s, j, 1)]
		print t % 60
	}'
}

bk_cron_spec() {   # bk_cron_spec <schedule> <minute>
	case "$1" in
		off|'')  printf '' ;;
		hourly)  printf '%s *  * * *' "$2" ;;
		weekly)  printf '%s 4  * * 0' "$2" ;;
		monthly) printf '%s 4  1 * *' "$2" ;;
		*)       printf '%s 4  * * *' "$2" ;;
	esac
}

# Every backup job on the machine, in the order the tab shows them: the
# `backup-*` cards plus `files`, whichever of them are actually installed here.
bk_cron_jobs() {
	local _d _f _id _seen _out
	_out=""; _seen=" "
	for _d in $(printf '%s' "${APP_SETUP_PATH:-$APP_SETUP_CONF:$APP_SETUP_CONF/local}" | tr ':' ' '); do
		for _f in "$_d"/backup-*.sh "$_d"/files.sh; do
			[ -f "$_f" ] || continue
			_id="$(basename "$_f" .sh)"
			case "$_seen" in *" $_id "*) continue ;; esac
			_seen="$_seen$_id "
			_out="$_out $_id"
		done
	done
	printf '%s' "${_out# }"
}

bk_cron_rebuild() {
	local _id _sch _spec _body _cur _mark _n
	_body=""; _n=0
	for _id in $(bk_cron_jobs); do
		_sch="$( (param_reset; param_export "$_id"; param schedule off) 2>/dev/null )"
		_spec="$(bk_cron_spec "$_sch" "$(bk_cron_minute "$_id")")"
		[ -n "$_spec" ] || continue
		_body="$_body$_spec  root  app-setup --no-color backup $_id  >/dev/null 2>&1
"
		_n=$((_n + 1))
	done
	case "$(cron_kind)" in
	dropin)
		# cron.d ignores a filename containing a dot, silently and forever.
		# This one has none and the check that keeps it that way lives in
		# cron_set; the name is a constant here for the same reason.
		if [ "$_n" = 0 ]; then rm -f "/etc/cron.d/$BK_CRON"; return 0; fi
		cat > "/etc/cron.d/$BK_CRON" <<EOF || { warn "could not write /etc/cron.d/$BK_CRON"; return 0; }
# /etc/cron.d/$BK_CRON — written by app-setup, edit Settings not this file.
# Rebuilt from every backup job's own \`schedule\` whenever one of them changes.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/sh
$_body
EOF
		chmod 0644 "/etc/cron.d/$BK_CRON"
		;;
	crontab)
		# busybox crond reads one crontab per user and its lines carry no user
		# field, so the same schedule is a different shape here. The trailing
		# marker is a comment to the shell that runs the command and an anchor
		# to us.
		_mark="# app-setup:$BK_CRON"
		_cur="$(crontab -l 2>/dev/null | grep -v "$_mark\$" || true)"
		for _id in $(bk_cron_jobs); do
			_sch="$( (param_reset; param_export "$_id"; param schedule off) 2>/dev/null )"
			_spec="$(bk_cron_spec "$_sch" "$(bk_cron_minute "$_id")")"
			[ -n "$_spec" ] || continue
			_cur="$(printf '%s\n%s app-setup --no-color backup %s >/dev/null 2>&1 %s' \
				"$_cur" "$_spec" "$_id" "$_mark")"
		done
		printf '%s\n' "$_cur" | sed '/^[[:space:]]*$/d' | crontab - ||
			warn "could not write root's crontab — the ▶ button still works, the timer will not"
		;;
	*)
		[ "$_n" = 0 ] ||
			warn "no cron on this machine — the ▶ button still works, the timer will not"
		;;
	esac
	return 0
}

# One lock for all backups. The derived minutes keep jobs from waking at the
# same second and not from overlapping — 41 and 43 is two minutes and a
# mysqldump of anything real takes longer — so a second job waits rather than
# failing, and says what it is waiting for.
#
# mkdir rather than flock: mkdir is atomic on every filesystem here and flock
# is not on Alpine's base image.
BK_LOCK="${BK_LOCK:-/var/lock/app-setup-backup}"
BK_LOCK_HELD=""

bk_lock() {
	local _i _age _who
	mkdir -p "$(dirname "$BK_LOCK")" 2>/dev/null || true
	_i=0
	while ! mkdir "$BK_LOCK" 2>/dev/null; do
		_who="$(cat "$BK_LOCK/job" 2>/dev/null || echo 'another backup')"
		# A stale lock from a killed run must not silence every backup on the
		# machine for good. Six hours is longer than any real job here and
		# short enough that the next night's run recovers by itself.
		_age="$(bk_lock_age)"
		if [ "$_age" -gt 21600 ]; then
			warn "breaking a stale backup lock left by $_who — it is $((_age / 3600))h old"
			rm -rf "$BK_LOCK"
			continue
		fi
		[ "$_i" = 0 ] && step "waiting for $_who to finish"
		_i=$((_i + 1))
		# An hour, then give up. A job that never gets the lock says so in the
		# log rather than sitting there until the next one queues behind it.
		if [ "$_i" -gt 360 ]; then
			err "gave up after an hour waiting for $_who"
			return 1
		fi
		sleep 10
	done
	printf '%s' "${BK_ID:-backup}" > "$BK_LOCK/job" 2>/dev/null || true
	BK_LOCK_HELD=1
	return 0
}

bk_lock_age() {
	local _n _t
	_n="$(date -u +%s 2>/dev/null || echo 0)"
	_t="$(date -u -r "$BK_LOCK" +%s 2>/dev/null || echo "$_n")"
	printf '%s' $((_n - _t))
}

bk_unlock() {
	[ -n "$BK_LOCK_HELD" ] || return 0
	rm -rf "$BK_LOCK"
	BK_LOCK_HELD=""
	return 0
}

# The newest archive for a prefix, which is what `restore` with no argument
# means and the only thing anybody wants at three in the morning. One
# directory holding exactly this job's archives, so it is a sort and not a
# search — a restore that picks the wrong archive because a prefix matched too
# much is not a failure mode this can have.
bk_latest() {      # bk_latest <prefix>
	local _f
	_f="$(ls -1 "$BK_DIR/$1" 2>/dev/null | grep '\.tgz$' | sort -r | head -1)"
	[ -n "$_f" ] || return 0
	printf '%s/%s/%s' "$BK_DIR" "$1" "$_f"
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
	local _a _r _dir
	bk_migrate
	_dir="$(bk_jobdir "$1")"
	_a="${2-}"
	if [ -z "$_a" ]; then
		_a="$(bk_latest "$1")"
		# Nothing local is the normal case after a disk is replaced, and it is
		# exactly when somebody needs this most — so look in the bucket before
		# giving up, rather than telling them their backups are gone.
		if [ -z "$_a" ]; then
			_r="$(bk_remote_ls "$1" 2>/dev/null | tail -1)"
			[ -n "$_r" ] || die "no backup for $1 in $_dir and none on the remote either"
			bk_download "$_r" "$_dir/$_r" || die "could not download $_r"
			_a="$_dir/$_r"
		fi
	elif [ ! -f "$_a" ]; then
		# A name typed into `Which one` is looked for locally first and
		# downloaded if it is only on the remote — the local copy is the one
		# that gets pruned hardest, and the remote is the one that survives
		# the disk.
		if [ -f "$_dir/$_a" ]; then
			_a="$_dir/$_a"
		else
			bk_download "$(basename "$_a")" "$_dir/$(basename "$_a")" ||
				die "no such archive here or on the remote: $_a"
			_a="$_dir/$(basename "$_a")"
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

# ------------------------------------------------------- the job's install --
#
# The ask was specific: read what is already configured, then let it be
# changed. The `dflt` in a `# param:` line is a static string in a header and
# cannot do that, so the seeding happens at install — and only ever into a file
# that does not exist. An install that has already been configured re-reads
# nothing and overwrites nothing, which is what keeps `install` idempotent;
# docs/app-setup.md §5 calls the second install the thing that breaks recipes.
bk_seed() {        # bk_seed <id>  <<EOF key=value… EOF
	local _f
	_f="$APP_SETUP_CONF/params/$1.conf"
	if [ -f "$_f" ]; then
		# Drain stdin so the caller's heredoc does not end up on the terminal.
		cat > /dev/null
		info "$_f is already here — nothing was re-read and nothing overwritten"
		return 1
	fi
	mkdir -p "$APP_SETUP_CONF/params"
	( umask 077; cat > "$_f" ) || return 1
	chmod 600 "$_f"
	ok "wrote $_f, mode 600"
	return 0
}

# Is the database this job points at on this machine? Everything that reads a
# local install, stops a local service or copies a local directory has to ask,
# and the answer is not "did somebody type a host" — the default is 127.0.0.1.
bk_job_local() {   # bk_job_local [host]
	case "${1:-$(param host 127.0.0.1)}" in
		''|127.0.0.1|localhost|::1|/*) return 0 ;;
	esac
	return 1
}

# Said at install rather than at 05:17. Both of these are settings that look
# reasonable, do something surprising, and are only ever discovered by somebody
# counting archives that are no longer there.
bk_keep_warn() {
	local _h _d _w _m
	_h="$(param keep_hourly 0)"; _d="$(param keep_daily 7)"
	_w="$(param keep_weekly 4)"; _m="$(param keep_monthly 6)"
	case "$_h$_d$_w$_m" in *[!0-9]*) return 0 ;; esac
	if [ $((_h + _d + _w + _m)) = 0 ]; then
		warn "every keep_* is 0, so nothing is ever pruned. Archives will pile up"
		warn "until the disk is full. That is allowed; it is rarely meant."
		return 0
	fi
	if [ "$(param schedule daily)" = hourly ] && [ "$_h" = 0 ]; then
		warn "an hourly schedule with keep_hourly 0 throws away 23 of every 24"
		warn "archives the moment they are taken. Set keep_hourly to 24 unless"
		warn "that is really what you want."
	fi
	if [ "$(param schedule daily)" = weekly ] && [ "$_d" -gt 1 ]; then
		info "note: keep_daily is seven *days*, not seven backups. On a weekly"
		info "schedule at most one archive is ever inside it."
	fi
	return 0
}

# What a job card says. Three states, and the middle one is the point: a job
# with nowhere to send its output is visibly in error rather than looking
# configured and quietly saving nothing.
bk_job_card() {    # bk_job_card <prefix> <what it is backing up>
	local _n _sch
	_n="$(ls -1 "$BK_DIR/$1" 2>/dev/null | grep -c '\.tgz$' || true)"
	if ! bk_store_set; then
		echo "detail=no destination — set up a store first"
		exit 3
	fi
	if ! bk_store_ready; then
		echo "detail=$(bk_setting store) has never passed a connection test"
		exit 3
	fi
	_sch="$(param schedule daily)"
	if [ "$_sch" = off ]; then
		# Installed and not running. The schedule is this card's service.
		echo "detail=off · ${2:+$2 · }$_n kept here"
		exit 1
	fi
	echo "detail=$_sch → $(bk_setting store) · $_n kept here"
	exit 0
}

# ▤ List backups. Both sides, labelled, because they are not the same set: the
# local one is pruned hardest and the remote is the one that survives the disk.
#
# The right control for picking an archive is a chooser filled with the ones
# that exist, which needs the form to run a recipe per field — a real feature
# with a real cost, and not one this waits for. So the names are printed and
# the one you want goes in `Which one`. It is ugly, it works today, and
# restoring *yesterday's* backup instead of last night's broken one is the
# entire reason anybody has backups.
bk_list() {        # bk_list <prefix>
	local _d _f _n _r _rn
	bk_migrate
	_d="$BK_DIR/$1"
	printf '\n  on this machine   %s/\n' "$_d"
	_n=0
	for _f in $(ls -1 "$_d" 2>/dev/null | grep '\.tgz$' | sort -r); do
		printf '    %-44s %8s   %s\n' "$_f" \
			"$(du -h "$_d/$_f" 2>/dev/null | awk '{print $1}')" \
			"$(bk_when "$_f")"
		_n=$((_n + 1))
	done
	[ "$_n" -gt 0 ] || printf '    (nothing here)\n'

	_rn=0
	if bk_store_set; then
		printf '\n  on %-14s %s/\n' "$(bk_setting store)" "$(bk_folder)"
		for _r in $(bk_remote_ls "$1" 2>/dev/null | sort -r); do
			printf '    %-44s %8s   %s\n' "$_r" "" "$(bk_when "$_r")"
			_rn=$((_rn + 1))
		done
		[ "$_rn" -gt 0 ] || printf '    (nothing there, or it could not be listed)\n'
	else
		printf '\n  no destination set — there is no off-machine copy of any of these.\n'
	fi

	printf '\n  %s here, %s there.  To put a particular one back, copy its name into\n' "$_n" "$_rn"
	printf '  Settings → Which one, then press ⟲ Restore. Or, from a shell:\n\n'
	printf '      sh %s/%s.sh restore <name>\n\n' "$APP_SETUP_CONF" "$BK_ID"
	return 0
}

# The stamp, read back out of the name. `date -d` is GNU-only in the form this
# would want and busybox's takes a different subset, so the archive says when
# it was taken by being named for it — which is the same property that makes
# `sort` a sort by time.
bk_when() {        # bk_when <name>
	local _s
	_s="${1##*_}"; _s="${_s%.tgz}"
	case "$_s" in
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) : ;;
		*) printf '?'; return 0 ;;
	esac
	printf '%s-%s-%s %s:%s UTC' \
		"$(printf '%s' "$_s" | cut -c1-4)" "$(printf '%s' "$_s" | cut -c5-6)" \
		"$(printf '%s' "$_s" | cut -c7-8)" "$(printf '%s' "$_s" | cut -c9-10)" \
		"$(printf '%s' "$_s" | cut -c11-12)"
}

# ✓ Verify. docs/app-setup.md says a backup nobody has restored is a hope
# rather than a backup, and then gives nobody a way to check short of
# performing one. This downloads the archive if it is not here, unpacks it into
# a temporary directory, and looks at what came out.
#
# It never touches the database, so it is safe to press on a running site. It
# answers the two ways an archive is silently useless — a truncated upload, and
# a dump that ran but produced nothing because the credential was wrong — and
# it deliberately does not claim more than that. Only a real restore proves a
# restore.
bk_verify() {      # bk_verify <prefix> [archive]
	local _d _f _sz _lines _n _ok _files
	bk_open "$1" "${2-}"
	_d="$BK_UNPACKED"
	_ok=0; _files=0
	step "unpacked"
	for _f in "$_d"/*; do
		[ -e "$_f" ] || continue
		case "$(basename "$_f")" in
		files)
			# A `files` job's whole payload is this directory, so a non-empty
			# one *is* the backup. For a database job it is the config that
			# travelled alongside the dump and proves nothing on its own —
			# hence _ok only when there is nothing else in the archive, which
			# is decided after the loop.
			_n="$(find "$_f" -type f 2>/dev/null | wc -l | tr -d ' ')"
			if [ "${_n:-0}" -gt 0 ]; then
				ok "files/  $_n file(s), $(du -sh "$_f" 2>/dev/null | awk '{print $1}')"
				_files="$_n"
			else
				err "files/ is empty — nothing was actually copied"
			fi ;;
		*.sql)
			_sz="$(du -h "$_f" 2>/dev/null | awk '{print $1}')"
			_lines="$(grep -c '^CREATE TABLE' "$_f" 2>/dev/null || echo 0)"
			# A dump that was cut off mid-statement unpacks perfectly well.
			# What it does not do is end where mysqldump and pg_dumpall both
			# end, which is the one cheap check that catches a truncated
			# upload without reading the whole file twice.
			if tail -c 4096 "$_f" 2>/dev/null | grep -qE 'Dump completed|PostgreSQL database dump complete|^\)|;[[:space:]]*$'; then
				ok "$(basename "$_f")  $_sz, $_lines CREATE TABLE, ends in a complete statement"
				_ok=1
			else
				err "$(basename "$_f")  $_sz — does not end in a complete statement. Truncated."
			fi ;;
		*.rdb)
			# An RDB's last eight bytes are a CRC64 preceded by the EOF opcode;
			# the five-byte magic at the front is REDIS. Both ends present is
			# as much as can be said without loading it.
			_sz="$(du -h "$_f" 2>/dev/null | awk '{print $1}')"
			if head -c 5 "$_f" 2>/dev/null | grep -q REDIS; then
				ok "$(basename "$_f")  $_sz, REDIS magic present"; _ok=1
			else
				err "$(basename "$_f")  $_sz — no REDIS magic. That is not a snapshot."
			fi ;;
		*.archive)
			_sz="$(du -h "$_f" 2>/dev/null | awk '{print $1}')"
			ok "$(basename "$_f")  $_sz"; _ok=1 ;;
		*)
			info "$(basename "$_f")" ;;
		esac
	done
	bk_close
	if [ "$_ok" = 1 ]; then
		ok "this archive opens and contains a dump. It has not been loaded anywhere."
		return 0
	fi
	# A `files` job has no dump and never will — its payload is the directory
	# tree, and a non-empty one is the whole of a correct backup. Demanding a
	# dump here failed every `files` archive ever taken.
	if [ "$_files" -gt 0 ]; then
		ok "this archive opens and holds $_files saved file(s). Nothing has been written back."
		return 0
	fi
	err "nothing in this archive looks like a backup of $1."
	return 1
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
# The one mysqldump command line. Everything else here chooses what to point
# it at; nothing else in the tree builds one.
#
# --single-transaction takes the whole dump from one consistent snapshot
# without locking a running site out, --quick streams row by row instead of
# buffering a large table into memory, and --routines/--triggers/--events carry
# the parts of a schema that are not tables — a dump missing its triggers
# restores clean and behaves wrong, which is the worst shape a restore can
# take.
mysql_dumpcmd() {  # mysql_dumpcmd <what to dump…>
	if [ -r "$MY_DEFAULTS" ]; then
		mysqldump --defaults-file="$MY_DEFAULTS" --single-transaction --quick \
			--routines --triggers --events "$@"
	else
		mysqldump --protocol=socket -uroot --single-transaction --quick \
			--routines --triggers --events "$@"
	fi
}

mysql_dump_all() { # mysql_dump_all <file> [database…]
	local _f _rc
	_f="$1"; shift
	_rc=0
	if [ "$#" -gt 0 ]; then
		# --databases rather than bare names, so the dump carries its own
		# CREATE DATABASE and USE and loading it recreates the schema instead
		# of needing one to exist first.
		mysql_dumpcmd --databases "$@" > "$_f" || _rc=$?
	else
		mysql_dumpcmd --all-databases > "$_f" || _rc=$?
	fi
	[ "$_rc" = 0 ] ||
		die "mysqldump failed — is the server running, and is $MY_DEFAULTS still right?"
	[ -s "$_f" ] || die "the dump came out empty; that is not a backup"
}

# One database to one file, through the same command line.
mysql_dump_db() {  # mysql_dump_db <database> <file>
	local _rc
	_rc=0
	mysql_dumpcmd --databases "$1" > "$2" || _rc=$?
	[ "$_rc" = 0 ] || die "could not dump the $1 database"
	[ -s "$2" ] || die "the dump came out empty; that is not a backup"
}

mysql_load_file() { # mysql_load_file <file>
	[ -f "$1" ] || die "no such dump: $1"
	mysql_root < "$1" || die "the import failed"
}

# ------------------------------------------- the other three, same rule --
#
# One command line per engine, here, parameterised by a connection. The engine
# recipe on the Databases tab passes the local one and the job card on the
# Backup tab passes the form's; nothing else in the tree builds a dump command.

# PostgreSQL. Empty PG_CONN is the local unix socket as the postgres user,
# which is peer auth and needs no password stored anywhere at all — the reason
# the local case is the good case here.
PG_CONN=""

# A .pgpass rather than PGPASSWORD: the environment of a process is readable
# out of /proc for as long as it runs, and libpq has a file format for exactly
# this. host:port:database:user:password, mode 600, and libpq refuses to read
# it at any other mode — which is a check worth having rather than working
# around.
pg_conn_file() {   # pg_conn_file <dest> <host> <port> <user> <password>
	( umask 077; printf '%s:%s:*:%s:%s\n' "$2" "$3" "$4" "$5" > "$1" ) || return 1
	chmod 600 "$1"
	PG_CONN="-h $2 -p $3 -U $4 -w"
	PGPASSFILE="$1"; export PGPASSFILE
	printf '%s' "$1"
}

pg_dumpcmd() {     # pg_dumpcmd <pg_dumpall arguments…>
	if [ -n "$PG_CONN" ]; then
		# shellcheck disable=SC2086  # PG_CONN is our own flag list
		pg_dumpall $PG_CONN "$@"
	else
		# su rather than sudo: sudo is not on a minimal Debian image and this
		# has to work on one.
		su postgres -c "pg_dumpall $*"
	fi
}

pg_psqlcmd() {     # pg_psqlcmd <psql arguments…>
	if [ -n "$PG_CONN" ]; then
		# shellcheck disable=SC2086
		psql $PG_CONN "$@"
	else
		su postgres -c "psql $*"
	fi
}

# Redis. Empty REDIS_CONN is "read the password out of the local redis.conf",
# which is what redis.sh has always done.
REDIS_CONN=""

# -a puts the password in argv, where every process on the box can read it for
# as long as the command runs. redis-cli reads REDISCLI_AUTH out of the
# environment instead, and has since 6.0; older ones fall back to -a with
# --no-auth-warning, which is the case where there is nothing better available.
redis_cli_at() {   # redis_cli_at <host> <port> <password> <redis-cli arguments…>
	local _h _p _pw
	_h="${1:-127.0.0.1}"; _p="${2:-6379}"; _pw="${3-}"; shift 3
	if [ -n "$_pw" ]; then
		REDISCLI_AUTH="$_pw" redis-cli -h "$_h" -p "$_p" --no-auth-warning "$@" 2>/dev/null ||
			redis-cli -h "$_h" -p "$_p" -a "$_pw" --no-auth-warning "$@"
	else
		redis-cli -h "$_h" -p "$_p" "$@"
	fi
}

# MongoDB. --archive rather than --out: one file instead of a directory of
# BSON, so a dump is something you can scp, and the backup and the dump are
# the same call with a different destination.
mongo_dumpcmd() {  # mongo_dumpcmd <uri or empty> <mongodump arguments…>
	local _uri
	_uri="$1"; shift
	have mongodump || die "mongodump is not installed — it ships in mongodb-database-tools"
	if [ -n "$_uri" ]; then mongodump --quiet --uri="$_uri" "$@"
	else                    mongodump --quiet "$@"; fi
}

mongo_restorecmd() {  # mongo_restorecmd <uri or empty> <mongorestore arguments…>
	local _uri
	_uri="$1"; shift
	have mongorestore || die "mongorestore is not installed — it ships in mongodb-database-tools"
	if [ -n "$_uri" ]; then mongorestore --quiet --uri="$_uri" "$@"
	else                    mongorestore --quiet "$@"; fi
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
# Restore is not one button, because at the moment somebody needs it they are
# asking three different questions — what have I got, is it any good, and put
# it back. One button answers the third and leaves the other two to a shell
# nobody is in a state to be typing into.
do_list()      { warn "this software keeps no archives to list"; return 0; }
do_verify()    { warn "this software has no archive format to check"; return 0; }
do_dump()      { warn "this software has no dump in its recipe"; return 0; }
do_load()      { warn "this software has no load in its recipe"; return 0; }
do_movedata()  { info "this software keeps nothing that a reinstall would take"; return 0; }
# A recipe that is not a store answers these rather than dying on an unknown
# verb, which is what `app-setup ls nginx` would otherwise do.
do_mkdir()     { err "$BK_ID is not a backup destination"; return 1; }
do_put()       { err "$BK_ID is not a backup destination"; return 1; }
do_get()       { err "$BK_ID is not a backup destination"; return 1; }
do_ls()        { err "$BK_ID is not a backup destination"; return 1; }
do_rm()        { err "$BK_ID is not a backup destination"; return 1; }
do_test()      { err "$BK_ID is not a backup destination"; return 1; }
do_showkey()   { info "$BK_ID uses no key"; return 0; }

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
		# A store's verbs. Every path is relative to the store's own base and
		# the folder is always the first argument, so a store never invents a
		# location of its own.
		mkdir)              need_root; shift; do_mkdir "$@" ;;
		put)                need_root; shift; do_put   "$@" ;;
		get)                need_root; shift; do_get   "$@" ;;
		ls)                           shift; do_ls    "$@" ;;
		rm)                 need_root; shift; do_rm    "$@" ;;
		test)                         shift; do_test  "$@" ;;
		# A store that needs a key installed on the far end has to be able to
		# print it. The step between "app-setup made a key" and "the NAS accepts
		# it" is the one people stop at, and it is not a step we can take for them.
		showkey)                      do_showkey ;;
		# Moving a populated data directory is stop, move, relink, start, and
		# it needs both copies to fit at once. It is never done as a side
		# effect of an install — a recipe that has data in the wrong place
		# says so, and this is the verb that acts on it.
		movedata)           need_root; do_movedata ;;
		# `shift` so a recipe run by hand can be handed one archive —
		# `sh /etc/app-setup/mysql.sh restore mysql_20210403123221.tgz`. With
		# no argument both this and `app-setup restore mysql` take the newest.
		restore)            need_root; shift; do_restore "$@" ;;
		# The other two thirds of restoring. `list` reads only, so it does not
		# need root; `verify` downloads and unpacks into a temp directory and
		# does, on an archive that is mode 600.
		list)                         shift; do_list   "$@" ;;
		verify)             need_root; shift; do_verify "$@" ;;
		# Same shift, same reason: `sh /etc/app-setup/mysql.sh dump /tmp/x.sql`
		# and `… load /tmp/x.sql` both name a file. With no argument, dump
		# picks a dated name and load takes the newest.
		dump)               need_root; shift; do_dump "$@" ;;
		load)               need_root; shift; do_load "$@" ;;
		help|docs|doc)      do_help ;;
		*)                  err "unknown verb: $_verb"; exit 64 ;;
	esac
}
