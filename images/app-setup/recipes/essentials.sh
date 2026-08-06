#!/bin/sh
# app-setup: 1
# id: essentials
# name: Basic tools
# name.zh: 基础工具包
# category: system
# order: 1
# summary: The handful of commands that half the instructions on the internet assume you already have.
# summary.zh: 网上的教程默认你已经装了的那几个命令，一次装齐。
# includes: curl, wget, unzip, tar, xz, less, ps, ca-certificates
# includes.zh: curl、wget、unzip、tar、xz、less、ps、根证书
# disk: 25M
# memory: 0
. /usr/lib/app-setup/common.sh

# curl is deliberately missing from the RPM list: those bases ship
# curl-minimal, and asking for curl makes dnf stop on a conflict it will not
# resolve without --allowerasing. curl(1) is already there under the other
# package, which is what anybody typing `curl` actually wants.
PKGS="curl wget ca-certificates unzip tar gzip xz-utils bzip2 less procps"
PKGS_rpm="wget ca-certificates unzip tar gzip xz bzip2 less procps-ng"
PKGS_apk="curl wget ca-certificates unzip tar gzip xz bzip2 less procps-ng"
# Not CHECK_BIN="unzip": busybox provides unzip (and wget, and less) in the
# base Alpine image, so a fresh Alpine box read as "basic tools installed" and
# nobody ever installed them. The package named unzip exists on all three
# families; busybox cannot satisfy a package check.
CHECK_PKG="unzip"

version_line() {
	if have curl; then curl --version 2>/dev/null | head -1 | cut -c1-50
	else echo "wget, unzip, tar, less"; fi
}

# Half of this list is not an extra, it is the machine: dpkg unpacks with tar
# and gzip, https needs ca-certificates, and apt itself pulls in procps. The
# default do_uninstall asked apt to purge all ten, apt answered "impossible
# situation", removed *none* of them and said nothing — so Remove looked like
# it worked and changed nothing at all.
#
# Ask only for the ones that are genuinely additions, and say what stayed.
# Nobody who presses Remove on "Basic tools" means "take tar away".
KEEP="tar gzip less procps procps-ng ca-certificates"

do_uninstall() {
	local _p _want
	_want=""
	for _p in $(pmv PKGS); do
		case " $KEEP " in *" $_p "*) continue ;; esac
		_want="$_want $_p"
	done
	pkg_remove $_want
	info "tar, gzip, less, ps and the root certificates were left installed."
	info "They are part of this machine rather than part of this package —"
	info "removing them would break the package manager and https."
}

do_help() { cat <<'EOF'
Basic tools

  What it is
    Not one program — the small set of commands that almost every other
    instruction on this machine will assume exists. Install it first and the
    rest of the catalogue has fewer surprises.

  What you get
    curl, wget      download things
    unzip, tar      open the things you downloaded
    xz, gzip, bzip2 the three compressors you will meet
    less            read a file without opening an editor
    ps, top, free   see what is running (procps)
    ca-certificates why https works at all

  Notes
    On AlmaLinux, Rocky and CentOS the system already ships curl under the
    name curl-minimal, so this does not install a second one — `curl` still
    works.

  Removing it
    Uninstall takes these back off. Be aware that `less` and `ps` going away
    makes the machine feel broken; that is expected, not a fault.
EOF
}

app_main "$@"
