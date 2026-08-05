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
APP_SETUP_STATE=/var/lib/app-setup
APP_SETUP_SECRETS=/root/.app-setup

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
ok()   { printf '%b  ok%b %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%b  ! %b %s\n' "$C_Y" "$C_0" "$*" >&2; }
err()  { printf '%b  x %b %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

need_root() {
	[ "$(id -u)" = 0 ] || die "this needs root. Run app-setup as root, or with sudo."
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
	_n="$1"
	eval "_v=\${${_n}_${OS_KEY}-}"
	[ -n "$_v" ] || eval "_v=\${${_n}_${PM}-}"
	[ -n "$_v" ] || eval "_v=\${${_n}_${PMF}-}"
	[ -n "$_v" ] || eval "_v=\${${_n}-}"
	printf '%s' "$_v"
}

# --------------------------------------------------------------- packages --
# One refresh per hour, not one per recipe: installing LNMP is four recipes
# deep and `apt-get update` four times is three minutes of nothing.
pm_refresh() {
	_stamp="$APP_SETUP_STATE/pm-refreshed"
	mkdir -p "$APP_SETUP_STATE"
	if [ -f "$_stamp" ]; then
		_age=$(( $(date +%s) - $(stat -c %Y "$_stamp" 2>/dev/null || echo 0) ))
		[ "$_age" -lt 3600 ] && return 0
	fi
	step "refreshing the package index"
	case "$PM" in
		apt)    apt-get update -qq || warn "apt-get update reported a problem; carrying on" ;;
		dnf)    dnf -q makecache   || true ;;
		yum)    yum -q makecache   || true ;;
		apk)    apk update -q      || true ;;
		zypper) zypper -q refresh  || true ;;
		pacman) pacman -Sy --noconfirm >/dev/null || true ;;
	esac
	: > "$_stamp"
}

pkg_install() {
	[ $# -gt 0 ] || return 0
	need_root
	pm_refresh
	step "installing: $*"
	case "$PM" in
		apt)    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" ;;
		dnf)    dnf install -y "$@" ;;
		yum)    yum install -y "$@" ;;
		apk)    apk add --no-cache "$@" ;;
		zypper) zypper -n install "$@" ;;
		pacman) pacman -S --noconfirm "$@" ;;
		*)      die "no package manager found on this system" ;;
	esac
}

pkg_remove() {
	[ $# -gt 0 ] || return 0
	need_root
	step "removing: $*"
	case "$PM" in
		apt)    DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@" || true
		        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true ;;
		dnf)    dnf remove -y "$@" || true ;;
		yum)    yum remove -y "$@" || true ;;
		apk)    apk del "$@" || true ;;
		zypper) zypper -n remove "$@" || true ;;
		pacman) pacman -Rns --noconfirm "$@" || true ;;
	esac
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
	pm_refresh
	for _p in "$@"; do
		if pkg_exists "$_p"; then pkg_install "$_p"; return 0; fi
	done
	die "none of these packages exist here: $*"
}

# Best effort: extras that only some distros carry, and whose absence must not
# fail the install.
pkg_install_optional() {
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
	[ -n "${1:-}" ] || return 0
	case "$INIT" in
		systemd) systemctl start "$1" ;;
		openrc)  rc-service "$1" start ;;
		sysv)    service "$1" start || /etc/init.d/"$1" start ;;
		*)       warn "no init system here; start $1 yourself"; return 1 ;;
	esac
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
	_url="$1"; _dst="$2"
	ensure_downloader
	if have curl; then curl -fsSL --retry 3 --connect-timeout 20 -o "$_dst" "$_url"
	else wget -q -t 3 -T 20 -O "$_dst" "$_url"; fi
}

fetch_stdout() {
	ensure_downloader
	if have curl; then curl -fsSL --retry 3 --connect-timeout 20 "$1"
	else wget -q -t 3 -T 20 -O - "$1"; fi
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
		return 0
	fi
	err "the nginx config does not parse; nothing was reloaded:"
	nginx -t 2>&1 | sed 's/^/    /'
	return 1
}

# php-fpm's package name, service name and listening socket all differ per
# distro *and* per release, so all three are discovered rather than assumed.
php_service() {
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
	for _f in /etc/php/*/fpm/pool.d/www.conf /etc/php-fpm.d/www.conf \
	          /etc/php*/php-fpm.d/www.conf /etc/php*/php-fpm.conf; do
		[ -f "$_f" ] || continue
		_v="$(awk -F= '/^[[:space:]]*listen[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$_f")"
		[ -n "$_v" ] && { printf '%s' "$_v"; return 0; }
	done
	printf '127.0.0.1:9000'
}

php_fastcgi_pass() {
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

# Who should own the files under the document root. php-fpm's pool user is the
# authority when PHP is installed — it is the process that has to write uploads
# — and the guess list is ordered by how each distro names its web account.
web_user() {
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
	_u="$(web_user)"
	id -gn "$_u" 2>/dev/null || printf '%s' "$_u"
}

php_bin() {
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
recipe() {         # recipe <id> <verb>
	_want="$1"; _verb="$2"; _found=""
	for _d in $(printf '%s' "${APP_SETUP_PATH:-/etc/app-setup:/usr/local/etc/app-setup}" | tr ':' ' '); do
		[ -f "$_d/$_want.sh" ] && _found="$_d/$_want.sh"
	done
	[ -n "$_found" ] || die "this needs the '$_want' source, which is not on this machine"
	step "$_verb: $_want"
	sh "$_found" "$_verb"
}

recipe_status() {  # 0 running, 1 stopped, 2 absent — same codes as the verb
	_want="$1"; _found=""
	for _d in $(printf '%s' "${APP_SETUP_PATH:-/etc/app-setup:/usr/local/etc/app-setup}" | tr ':' ' '); do
		[ -f "$_d/$_want.sh" ] && _found="$_d/$_want.sh"
	done
	[ -n "$_found" ] || return 2
	sh "$_found" status >/dev/null 2>&1
}

# ---------------------------------------------------------------- secrets --
rand_pass() {
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
	_d="$(mktemp -d 2>/dev/null || echo "/tmp/app-setup.$$")"
	mkdir -p "$_d"
	printf '%s' "$_d"
}

# ----------------------------------------------------------- default verbs --
# A recipe that wants different behaviour defines the same function after
# sourcing this file; the later definition wins.

is_installed() {
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
	is_installed || exit 2
	_v="$(version_line 2>/dev/null || true)"
	[ -n "$_v" ] && echo "detail=$_v"
	_s="$(svc)"
	[ -n "$_s" ] || exit 0
	if svc_enabled "$_s"; then echo "enabled=1"; else echo "enabled=0"; fi
	if svc_running "$_s"; then exit 0; else exit 1; fi
}

app_main() {
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
		help|docs|doc)      do_help ;;
		*)                  err "unknown verb: $_verb"; exit 64 ;;
	esac
}
