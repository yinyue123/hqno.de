#!/bin/sh
# app-setup: 1
# id: htop
# name: htop
# name.zh: htop 进程查看
# category: system
# order: 13
# summary: top, but you can read it. Sort by memory, find the process eating the box, kill it.
# summary.zh: 能看懂的 top。按内存排序，找出吃资源的进程，直接杀掉。
# includes: htop
# includes.zh: htop 主程序
# disk: 3M
# memory: 5M
. /usr/lib/app-setup/common.sh

PKGS="htop"
CHECK_BIN="htop"

version_line() { htop --version 2>/dev/null | head -1; }

do_install() {
	enable_epel
	pkg_install $(pmv PKGS)
}

do_help() { cat <<'EOF'
htop

  Run it
    htop

  Reading it
    The bars at the top are your CPUs and your memory. In a container these
    show the limits you were given, not the whole machine — if the memory
    bar is nearly full, that is your container's memory, and something is
    about to be killed.

  Keys that matter
    F6 or >     sort — pick MEM to find what is eating the box
    F4 or \     filter by name
    F9          kill the selected process (15 first, 9 only if that fails)
    F5 or t     tree view: see what started what
    F10 or q    quit

  If a process will not die
    F9 sends SIGTERM. Something stuck in disk I/O ignores it. Send 9
    (SIGKILL) instead — it cannot be ignored, but the program gets no chance
    to save anything.

  atop is in this catalogue too and answers a different question: not "what
  is happening now" but "what happened at 3am".
EOF
}

app_main "$@"
