#!/bin/sh
# app-setup: 1
# id: git
# name: Git
# name.zh: Git 版本控制
# category: system,dev
# order: 16
# summary: Clone code onto this machine and keep track of what you changed.
# summary.zh: 把代码拉到这台机器上，并且记得住你改了什么。
# includes: git, git-lfs where the distro has it
# includes.zh: git 主程序，以及可用的 git-lfs
# disk: 40M
# memory: 0
. /usr/lib/app-setup/common.sh

PKGS="git"
CHECK_BIN="git"

version_line() { git --version 2>/dev/null; }

do_install() {
	pkg_install $(pmv PKGS)
	pkg_install_optional git-lfs
	# Git 2.35 and later refuse to work in a directory owned by another user,
	# which is exactly what a bind-mounted /data looks like from in here.
	git config --global --add safe.directory '*' 2>/dev/null || true
	if ! git config --global user.email >/dev/null 2>&1; then
		info "before your first commit, tell git who you are:"
		info "  git config --global user.name  'Your Name'"
		info "  git config --global user.email 'you@example.com'"
	fi
}

do_help() { cat <<'EOF'
Git

  Getting code onto this machine
    git clone https://github.com/someone/project.git
    cd project
    git pull                       get later changes

  Before your first commit
    git config --global user.name  "Your Name"
    git config --global user.email "you@example.com"

  The everyday loop
    git status                     what have I changed
    git add -A                     stage all of it
    git commit -m "what I did"
    git log --oneline -10          the last ten commits

  Pushing to GitHub over https
    A password will not work; GitHub wants a personal access token. Make one
    at github.com/settings/tokens and paste it when git asks for a password.
    To stop it asking every time:
      git config --global credential.helper 'store'
    That writes the token to ~/.git-credentials in plain text — fine on a
    machine only you use, not on a shared one.

  What was configured
    safe.directory '*' — without it, git refuses to touch a repository whose
    files are owned by a different user id, which is what a mounted /data
    looks like from inside a container.
EOF
}

app_main "$@"
