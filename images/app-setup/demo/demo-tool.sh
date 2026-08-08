#!/bin/sh
# app-setup: 1
# id: demo-tool
# name: Demo Tool
# name.zh: 演示 · 命令行小工具
# category: demo
# order: 30
# summary: A pretend command-line tool. No service, so its menu has no start or stop in it — which is the case worth looking at, because most of the System tab is like this.
# summary.zh: 假的命令行工具。它没有服务，所以点进去之后菜单里不会有"启动/停止"——常用系统软件那一栏大部分都是这样。
# includes: nothing
# includes.zh: 什么都没有
# disk: 2M
. /usr/lib/app-setup/common.sh


STATE="$APP_SETUP_STATE/demo"
MARK="$STATE/demo-tool.installed"

beat() { sleep "${DEMO_SPEED-1}"; }

# No `service:` in the header and no step_total here, on purpose: this is the
# recipe that shows what the screen does when it has neither. The bar gets the
# curve rather than a fraction, and the action menu comes up without the
# service rows.
do_install() {
	step "installing demo-tool"
	info "Reading package lists... Done"
	info "Building dependency tree... Done"
	beat
	step "linking it onto the path"
	beat
	mkdir -p "$STATE"
	: > "$MARK"
	ok "demo-tool installed"
	return 0
}

do_uninstall() {
	step "removing demo-tool"
	rm -f "$MARK"
	beat
	ok "removed"
	return 0
}

do_status() {
	[ -f "$MARK" ] || exit 2
	echo "detail=demo-tool 0.9, no service"
	exit 0
}

do_help() {
	if lang_zh; then
		cat <<'EOF'
演示 · 命令行小工具

假的，什么都不装。

它和另外两个演示软件的区别是：头部没有写 service:，所以

  · 装完之后状态是"已安装"，不是"运行中"
  · 点进去的菜单里没有"启动 / 停止 / 重启 / 开机自启"
  · 它也没有声明 step_total，所以进度条走的是那条"越来越慢、
    但永远走不到头"的曲线——这是脚本没说自己有几步时的诚实画法

vim、htop、rsync 这类软件都属于这一类。
EOF
	else
		cat <<'EOF'
Demo Tool

Not real, installs nothing.

What makes it different from the other two demos is that its header has no
`service:` line, so:

  · it ends up "installed" rather than "running"
  · its menu has no Start, Stop, Restart or Start-at-boot rows
  · it declares no step_total either, so the bar follows the curve that slows
    down and never quite arrives — which is the honest drawing for a recipe
    that has not said how many steps it has

vim, htop and rsync are all this shape.
EOF
	fi
}

app_main "$@"
