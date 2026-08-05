#!/bin/sh
# app-setup: 1
# id: ncdu
# name: ncdu
# name.zh: ncdu 磁盘分析
# category: system
# order: 19
# summary: Finds what filled the disk. Arrow into the big directories and delete from inside it.
# summary.zh: 找出是什么把磁盘占满了。方向键点进大目录，直接在里面删。
# includes: ncdu
# includes.zh: ncdu 主程序
# disk: 1M
# memory: 0
. /usr/lib/app-setup/common.sh

PKGS="ncdu"
CHECK_BIN="ncdu"

version_line() { ncdu -v 2>/dev/null | head -1; }

do_install() {
	enable_epel
	pkg_install $(pmv PKGS)
}

do_help() { cat <<'EOF'
ncdu

  When the disk is full
    ncdu /                 scan everything (takes a while)
    ncdu -x /              stay on one filesystem — usually what you want

  Then
    arrows / Enter    walk into the biggest thing
    d                 delete the selected file or directory
    n / s             sort by name / size
    g                 toggle percentage and graph
    q                 quit

  The usual culprits on a container
    /var/log           logs nobody rotated
    /var/cache/apt     apt's downloaded .deb files — `apt-get clean` frees it
    /var/lib/docker    if you ran containers inside this one
    /tmp               things that were never cleaned up
    a deleted file a process still holds open — ncdu will not see this one.
    `lsof +L1` finds them, or just restart the service.

  Faster alternative for one number
    df -h /            how full the disk is
    du -sh /var/*      the top level, in one line each
EOF
}

app_main "$@"
