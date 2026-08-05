#!/bin/sh
# app-setup: 1
# id: tmux
# name: tmux
# name.zh: tmux 会话保持
# category: system
# order: 11
# summary: Keeps what you were running alive after your connection drops. Split panes too.
# summary.zh: 断线之后你跑的东西还在。也能一个窗口切成几块。
# includes: tmux, a readable status bar, mouse scrolling
# includes.zh: tmux 主程序、易读的状态栏、鼠标滚动
# disk: 6M
# memory: 4M
. /usr/lib/app-setup/common.sh

PKGS="tmux"
CHECK_BIN="tmux"

version_line() { tmux -V 2>/dev/null; }

do_install() {
	pkg_install $(pmv PKGS)
	if [ ! -f /root/.tmux.conf ]; then
		cat > /root/.tmux.conf <<'EOF'
# written by app-setup; edit or delete it freely
set -g mouse on
set -g history-limit 20000
set -g base-index 1
setw -g pane-base-index 1
set -g status-style bg=colour236,fg=colour250
set -g status-left  ' #S '
set -g status-right ' %H:%M '
bind | split-window -h
bind - split-window -v
EOF
		ok "wrote a starter /root/.tmux.conf"
	fi
}

do_uninstall() {
	pkg_remove $(pmv PKGS)
	rm -f /root/.tmux.conf
}

do_help() { cat <<'EOF'
tmux

  Why you want it
    Start a long job inside tmux and close your laptop. The job keeps
    running. Log back in, type `tmux attach`, and you are looking at it
    again exactly where you left off. Without this, closing the connection
    kills whatever you were running.

  The whole thing in five commands
    tmux                 start a session
    tmux attach          go back to it later
    tmux ls              list sessions
    Ctrl-b d             leave it running and get your shell back
    Ctrl-b |  /  Ctrl-b -   split the window (configured here)

  Ctrl-b is the prefix: press and release it, then press the next key.
    Ctrl-b arrow keys    move between panes
    Ctrl-b c             new window,  Ctrl-b n / p  next / previous
    Ctrl-b [             scroll back, q to stop

  What was configured
    /root/.tmux.conf — mouse on (scroll and click panes), 20000 lines of
    scrollback, windows numbered from 1. Delete it for stock tmux.

  screen does the same job and is in this catalogue too. Pick one.
EOF
}

app_main "$@"
