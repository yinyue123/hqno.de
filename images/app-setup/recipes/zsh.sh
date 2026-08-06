#!/bin/sh
# app-setup: 1
# id: zsh
# name: Zsh + Oh My Zsh
# name.zh: Zsh + Oh My Zsh
# category: system
# order: 18
# summary: A shell that completes paths, corrects typos and shows the git branch you are on.
# summary.zh: 会补全路径、纠正拼写、还能显示 git 分支的 shell。
# includes: zsh, Oh My Zsh, git-aware prompt
# includes.zh: zsh、Oh My Zsh 框架、带 git 提示的命令行
# disk: 40M
# memory: 0
. /usr/lib/app-setup/common.sh

PKGS="zsh"
CHECK_BIN="zsh"
OMZ=/root/.oh-my-zsh

version_line() {
	_v="$(zsh --version 2>/dev/null | cut -d' ' -f1,2)"
	[ -d "$OMZ" ] && printf '%s, Oh My Zsh' "$_v" || printf '%s' "$_v"
}

do_install() {
	pkg_install $(pmv PKGS)
	pkg_install_optional git curl

	# Oh My Zsh needs the network. A shell that works is the deliverable; the
	# framework is the nice-to-have, so a failure here is a warning.
	if [ ! -d "$OMZ" ]; then
		step "fetching Oh My Zsh"
		if fetch_stdout https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh > /tmp/omz.sh 2>/dev/null; then
			# raw.githubusercontent.com answering does not mean github.com
			# will: a firewall that drops one and not the other is normal, and
			# install.sh's `git fetch` then hangs with no timeout of its own.
			# Bound it, and tell git to give up on a stalled transfer too.
			GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30 \
			RUNZSH=no KEEP_ZSHRC=no CHSH=no \
				run_bounded 180 sh /tmp/omz.sh --unattended >/dev/null 2>&1 ||
				warn "Oh My Zsh did not install; zsh itself is fine"
			rm -f /tmp/omz.sh
		else
			warn "could not reach github; installed plain zsh without Oh My Zsh"
		fi
	fi

	if [ -d "$OMZ" ] && [ -f /root/.zshrc ]; then
		sed -i 's/^ZSH_THEME=.*/ZSH_THEME="robbyrussell"/' /root/.zshrc 2>/dev/null || true
	fi

	step "making zsh the login shell for root"
	chsh -s "$(command -v zsh)" root 2>/dev/null ||
		sed -i "s|^root:\(.*\):[^:]*$|root:\1:$(command -v zsh)|" /etc/passwd 2>/dev/null ||
		warn "could not change the login shell; type zsh yourself, or edit /etc/passwd"
	ok "log out and back in to land in zsh"
}

do_uninstall() {
	step "putting the login shell back to sh"
	_sh=/bin/bash
	[ -x "$_sh" ] || _sh=/bin/sh
	chsh -s "$_sh" root 2>/dev/null || true
	rm -rf "$OMZ" /root/.zshrc /root/.zshrc.pre-oh-my-zsh /root/.zsh_history
	pkg_remove $(pmv PKGS)
}

do_help() { cat <<'EOF'
Zsh + Oh My Zsh

  What changes
    Tab completion that completes command options and remote paths, not just
    filenames. A prompt that shows the git branch and whether it is dirty.
    Typo correction. Shared history across your open sessions.

  Using it
    Log out and back in — root's login shell was changed. To try it without
    logging out, just type: zsh

  Worth knowing
    cd ..../dir          zsh expands the dots
    take newdir          mkdir and cd in one (Oh My Zsh)
    Ctrl-r               search your history
    ..                   on its own means cd ..

  Changing the look
    Edit /root/.zshrc, set ZSH_THEME="agnoster" (or any of the ~150 in
    ~/.oh-my-zsh/themes), then: source ~/.zshrc
    agnoster and its relatives want a Nerd Font installed on *your laptop*,
    not here; without one the prompt shows boxes.

  Plugins
    In /root/.zshrc, the plugins=(git) line. Adding docker, kubectl, pip and
    so on turns on completion for them. Keep the list short — each one costs
    startup time on a small container.

  If it went wrong
    Uninstalling puts root's shell back to bash or sh and removes the config.
    If you are ever locked out of a shell that will not start, log in and run:
      chsh -s /bin/bash root
EOF
}

app_main "$@"
