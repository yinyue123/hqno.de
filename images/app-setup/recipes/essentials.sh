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
CHECK_BIN="unzip"

version_line() {
	if have curl; then curl --version 2>/dev/null | head -1 | cut -c1-50
	else echo "wget, unzip, tar, less"; fi
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
