#!/bin/sh
# app-setup: 1
# id: vim
# name: Vim
# name.zh: Vim 编辑器
# category: system
# order: 10
# summary: The editor that is on every server. Worth twenty minutes of learning once.
# summary.zh: 每台服务器上都有的编辑器。花二十分钟学一次，以后到哪都能用。
# includes: vim, syntax highlighting, a starter vimrc
# includes.zh: vim 主程序、语法高亮、一份入门配置
# disk: 45M
# memory: 0
. /usr/lib/app-setup/common.sh

PKGS="vim"
PKGS_rpm="vim-enhanced"
CHECK_BIN="vim"

version_line() { vim --version 2>/dev/null | head -1 | cut -c1-46; }

do_install() {
	pkg_install $(pmv PKGS)
	# A default vim shows no line numbers and pastes with cascading indent,
	# which is the single most common "why is my config file mangled" report.
	if [ ! -f /etc/vim/vimrc.local ] && [ ! -f /root/.vimrc ]; then
		cat > /root/.vimrc <<'EOF'
" written by app-setup; edit or delete it freely
syntax on
set number
set expandtab shiftwidth=4 tabstop=4
set hlsearch incsearch ignorecase smartcase
set mouse=
set pastetoggle=<F2>
set backspace=indent,eol,start
EOF
		ok "wrote a starter /root/.vimrc"
	fi
}

do_uninstall() {
	pkg_remove $(pmv PKGS)
	rm -f /root/.vimrc
}

do_help() { cat <<'EOF'
Vim

  The four things you need
    i           start typing
    Esc         stop typing
    :w          save
    :q          quit          (:q! quit and throw away, :wq save and quit)

  Slightly more
    /word       search, then n for the next hit
    dd          delete the line, u undo, Ctrl-r redo
    :set paste  before pasting from your laptop — otherwise every line
                indents further than the last. F2 toggles it here.
    :help       the manual, which is very good

  What was configured
    /root/.vimrc — line numbers, four-space indent, case-smart search, and
    the mouse left off so that selecting text in your terminal still copies
    it the way you expect. Delete the file to go back to stock vim.
EOF
}

app_main "$@"
