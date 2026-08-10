#!/bin/sh
# app-setup: 1
# id: demo-web
# name: Demo Web Server
# name.zh: 演示 · 网页服务器
# category: demo
# category.name: Demo
# category.name.zh: 演示
# order: 10
# summary: A pretend web server. Installs nothing, has a service you can start and stop, and takes about eight seconds so you can watch the bar.
# summary.zh: 假的网页服务器。什么都不装，但有一个可以启停的服务，装一次大约八秒，够看清进度条怎么走。
# includes: a file under the state directory, and nothing else
# includes.zh: 状态目录下的一个文件，除此之外什么都没有
# disk: 15M
# memory: 24M
# ports: 8080
# service: demo-web
# param: port    | 8080          | Listen port      | 监听端口   | number
# param: root    | /var/www/demo | Document root    | 网站目录
# param: ssl     | off           | Enable HTTPS     | 启用 HTTPS | bool
# param: workers | auto          | Worker processes | 工作进程数 | auto,1,2,4,8
#
# This is the demo half of app-setup: four recipes that exercise every screen
# without touching the machine. They are not copied into any image — the
# Dockerfiles take app-setup/recipes/, and this lives in app-setup/demo/.
#
# It is also the shortest complete example of the recipe contract. Read it
# beside help/docs/app-setup-sources.md, which is the full version.
. /usr/lib/app-setup/common.sh


STATE="$APP_SETUP_STATE/demo"
MARK="$STATE/demo-web.installed"
PID="$STATE/demo-web.running"

# Every pause goes through here so the whole demo can be run at speed:
# DEMO_SPEED=0 app-setup install demo-web
beat() { sleep "${DEMO_SPEED-1}"; }

do_install() {
	# One line, and the bar becomes a true fraction instead of a curve. Count
	# the `step` calls on the path actually taken, not the ones in the file.
	step_total 6

	step "checking what this machine already has"
	info "$OS_NAME, $PM packages, $INIT init, $ARCH"
	beat

	step "reading the settings"
	info "port      $(param port 8080)"
	info "root      $(param root /var/www/demo)"
	info "workers   $(param workers auto)"
	if param_on ssl; then info "https     on"; else info "https     off"; fi
	beat

	step "fetching packages"
	info "Get:1 https://example.invalid/demo demo-web 1.4.2 [812 kB]"
	beat
	info "Fetched 812 kB in 1s (812 kB/s)"

	step "unpacking"
	info "Selecting previously unselected package demo-web."
	info "Preparing to unpack demo-web_1.4.2_all.deb ..."
	info "Unpacking demo-web (1.4.2) ..."
	beat

	step "writing the configuration"
	mkdir -p "$STATE"
	{
		echo "port=$(param port 8080)"
		echo "root=$(param root /var/www/demo)"
		echo "workers=$(param workers auto)"
		param_on ssl && echo "ssl=on" || echo "ssl=off"
	} > "$MARK"
	info "wrote $MARK"
	beat

	step "starting the service"
	: > "$PID"
	ok "demo-web is listening on port $(param port 8080)"
	return 0
}

do_uninstall() {
	step_total 3
	step "stopping the service"
	rm -f "$PID"
	beat
	step "removing the package"
	rm -f "$MARK"
	beat
	step "done"
	ok "demo-web removed. Nothing was ever installed, so nothing was left behind."
	return 0
}

do_start()   { step "starting demo-web"; beat; mkdir -p "$STATE"; : > "$PID"; ok "started"; }
do_stop()    { step "stopping demo-web"; beat; rm -f "$PID"; ok "stopped"; }
do_restart() { do_stop; do_start; }
do_enable()  { mkdir -p "$STATE"; : > "$STATE/demo-web.boot"; ok "demo-web will start at boot"; }
do_disable() { rm -f "$STATE/demo-web.boot"; ok "demo-web will not start at boot"; }

do_status() {
	[ -f "$MARK" ] || exit 2
	echo "detail=demo-web 1.4.2, port $(param port 8080)"
	if [ -f "$STATE/demo-web.boot" ]; then echo "enabled=1"; else echo "enabled=0"; fi
	[ -f "$PID" ] && exit 0
	exit 1
}

do_help() {
	if lang_zh; then
		cat <<'EOF'
演示 · 网页服务器

这个软件是假的。它不下载任何东西，也不会改动这台机器上的任何配置，
只在状态目录下写一个文件来记住自己"装过了"。

它存在的理由是：让你在真的往容器里装东西之前，先把这个界面走一遍。

  · 装一次大约八秒，能看清进度条、当前步骤和下面的详细日志
  · 装完之后它会出现在左边"已安装"那一栏，可以启动、停止、重启
  · "参数设置"里有四种控件：数字、文本、开关、可选项，改完点
    "保存并应用"就直接生效，日志里能看到新的值；只点"保存"是存下来不生效

想看失败长什么样，装一下"演示 · 会失败的软件"。

删除它不会留下任何东西。
EOF
	else
		cat <<'EOF'
Demo Web Server

This software is not real. It downloads nothing and changes nothing on this
machine; it writes one file under the state directory to remember that it is
"installed".

It exists so you can walk through the whole interface before pointing it at a
container that matters.

  · an install takes about eight seconds — long enough to watch the bar, the
    step name and the log pane underneath
  · once installed it appears in the Installed column on the left, where it
    can be started, stopped and restarted
  · Settings has one of each kind of field: a number, a text box, a switch
    and a chooser. Change them and press Save & Apply and the new values show
    up in the log straight away; Save on its own writes them down without
    running anything

To see what a failure looks like, install "Demo Failing Install".

Removing it leaves nothing behind.
EOF
	fi
}

app_main "$@"
