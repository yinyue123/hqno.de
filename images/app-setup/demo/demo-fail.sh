#!/bin/sh
# app-setup: 1
# id: demo-fail
# name: Demo Failing Install
# name.zh: 演示 · 会失败的软件
# category: demo
# order: 40
# summary: A pretend install that fails on purpose, four steps in. This is the screen worth checking: the bar stops where it got to, the step turns red, and the log pane holds the reason.
# summary.zh: 故意在第四步失败的安装。这个屏幕最值得看一眼：进度条停在走到的地方，步骤名变红，下面的日志里留着失败的原因。
# includes: a failure, on purpose
# includes.zh: 一次故意的失败
# disk: 10M
# memory: 16M
. /usr/lib/app-setup/common.sh


beat() { sleep "${DEMO_SPEED-1}"; }

do_install() {
	step_total 6

	step "checking free space"
	beat
	step "fetching packages"
	info "Get:1 https://example.invalid/demo demo-fail 0.1 [4 kB]"
	beat
	step "unpacking"
	beat

	step "downloading the part that is not there"
	info "curl: (6) Could not resolve host: example.invalid"
	beat
	err "could not download demo-fail. Check this container has a route out:"
	err "  curl -I https://example.invalid/"
	return 1
}

do_uninstall() { ok "nothing to remove — it never finished installing"; return 0; }

do_status() { exit 2; }

do_help() {
	if lang_zh; then
		cat <<'EOF'
演示 · 会失败的软件

它一定会失败，这就是它的用途。

装一下，看看失败的时候界面是什么样：

  · 进度条停在第 4 步走到的位置，不会假装走完
  · 步骤那一行变成红色
  · 详细日志里留着失败原因，装完之后还能用上下方向键往回翻
  · 关掉窗口之后会弹一个框，告诉你日志文件在哪

真的软件失败时也是这一套，只是原因会具体得多。
EOF
	else
		cat <<'EOF'
Demo Failing Install

It always fails. That is the point of it.

Install it and look at what a failure does to the screen:

  · the bar stops where step 4 got to rather than pretending to finish
  · the step line turns red
  · the reason stays in the log pane, and the arrow keys scroll back through
    it after the run has ended
  · closing the window brings up a box naming the log file

A real recipe fails the same way. The reason is just more specific.
EOF
	fi
}

app_main "$@"
