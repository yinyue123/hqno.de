#!/bin/sh
# app-setup: 1
# id: screen
# name: GNU Screen
# name.zh: GNU Screen
# category: system
# order: 12
# summary: The older way to keep a job running after you disconnect. Simpler than tmux.
# summary.zh: 断线不中断任务的老办法，比 tmux 简单。
# includes: screen
# includes.zh: screen 主程序
# disk: 3M
# memory: 3M
. /usr/lib/app-setup/common.sh

PKGS="screen"
CHECK_BIN="screen"

version_line() { screen --version 2>/dev/null | head -1; }

# On the RHEL rebuilds screen left the base repos years ago and lives in EPEL.
do_install() {
	enable_epel
	pkg_install $(pmv PKGS)
}

do_help() { cat <<'EOF'
GNU Screen

  Why you want it
    Same reason as tmux: a job started inside screen survives your
    connection dropping. screen is older, plainer, and on many machines it
    is the one that is already installed.

  The whole thing
    screen               start
    screen -r            come back to it
    screen -ls           list sessions
    Ctrl-a d             detach — leaves it running
    Ctrl-a c             new window,  Ctrl-a n / p  next / previous
    Ctrl-a "             pick a window from a list
    Ctrl-a Esc           scroll back, Esc again to stop
    exit                 close the window; the last one ends the session

  Ctrl-a is the prefix. If you also use tmux, note that tmux uses Ctrl-b,
  and running one inside the other is a good way to confuse both.

  Notes
    On AlmaLinux, Rocky and CentOS this comes from EPEL, which the install
    enables for you.
EOF
}

app_main "$@"
