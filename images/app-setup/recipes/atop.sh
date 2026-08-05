#!/bin/sh
# app-setup: 1
# id: atop
# name: atop
# name.zh: atop 资源记录
# category: system
# order: 14
# summary: Records what the machine was doing, so you can look at 3am after the fact.
# summary.zh: 把机器的负载记录下来，事后能翻出凌晨三点发生了什么。
# includes: atop, and its logging service if you turn it on
# includes.zh: atop 主程序，以及可选的后台记录服务
# disk: 6M
# memory: 12M
. /usr/lib/app-setup/common.sh

PKGS="atop"
CHECK_BIN="atop"

version_line() { atop -V 2>/dev/null | head -1; }

do_install() {
	enable_epel
	pkg_install $(pmv PKGS)
	info "the logging daemon stays off; the docs button says how to turn it on"
}

do_help() { cat <<'EOF'
atop

  What it is for
    htop tells you what is happening now. atop can tell you what was
    happening an hour ago — which is the question you actually have after
    something went wrong overnight.

  Run it live
    atop            refreshes every 10 seconds
    atop 2          every 2 seconds
    m               sort by memory,  c  by CPU,  d  by disk,  n  by network
    q               quit

  Reading history
    Turn the recorder on first — it is a service, off by default here
    because it writes a few MB a day and a small container may not want it:

      systemctl enable --now atop        (Debian, Ubuntu, AlmaLinux, Rocky)
      rc-update add atop default && rc-service atop start     (Alpine)

    Then, after the fact:

      atop -r                            today's recording
      atop -r /var/log/atop/atop_20260804
      t / T                              step forward / back in time
      b                                  jump to a time, e.g. 03:00

  Note
    Inside a container atop shows the container's own processes. Numbers for
    the disks and the kernel come from the host and will look larger than
    anything you are responsible for.
EOF
}

app_main "$@"
