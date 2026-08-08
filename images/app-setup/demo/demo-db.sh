#!/bin/sh
# app-setup: 1
# id: demo-db
# name: Demo Database
# name.zh: 演示 · 数据库
# category: demo
# order: 20
# summary: A pretend database. Slower than the web one and asks for more memory than a small container has, so the "this machine is too small" warning has something to fire on.
# summary.zh: 假的数据库。比上面那个慢，而且故意声明了很大的内存，好让"机器装不下"这个提示有东西可以触发。
# includes: a file under the state directory, and a made-up root password
# includes.zh: 状态目录下的一个文件，外加一个编出来的 root 密码
# disk: 250M
# memory: 400M
# ports: 3306
# service: demo-db
# param: port    | 3306    | Listen port     | 监听端口   | number
# param: datadir | /var/lib/demo-db | Data directory | 数据目录
# param: charset | utf8mb4 | Character set   | 字符集     | utf8mb4,utf8,latin1
# param: slowlog | on      | Slow query log  | 慢查询日志 | bool
. /usr/lib/app-setup/common.sh


STATE="$APP_SETUP_STATE/demo"
MARK="$STATE/demo-db.installed"
PID="$STATE/demo-db.running"

beat() { sleep "${DEMO_SPEED-1}"; }

do_install() {
	step_total 8

	step "checking free space"
	info "wants 250M, this machine has $(df -h / 2>/dev/null | awk 'NR==2{print $4}')"
	beat

	step "installing packages"
	info "The following NEW packages will be installed:"
	info "  demo-db demo-db-client demo-db-common"
	beat
	info "Setting up demo-db-common (11.4.2) ..."
	info "Setting up demo-db-client (11.4.2) ..."

	step "initialising the data directory"
	info "$(param datadir /var/lib/demo-db)"
	beat

	step "generating a root password"
	beat
	info "saved to $APP_SETUP_SECRETS/demo-db.txt"

	step "applying the character set"
	info "character-set-server = $(param charset utf8mb4)"
	beat

	step "tuning for this machine"
	info "memory profile: $(mem_profile), $(mem_total_mb)MB total"
	if param_on slowlog; then info "slow query log on"; else info "slow query log off"; fi
	beat

	step "writing the configuration"
	mkdir -p "$STATE"
	{
		echo "port=$(param port 3306)"
		echo "datadir=$(param datadir /var/lib/demo-db)"
		echo "charset=$(param charset utf8mb4)"
	} > "$MARK"
	beat

	step "starting the service"
	: > "$PID"
	ok "demo-db is listening on port $(param port 3306)"
	return 0
}

do_uninstall() {
	step_total 2
	step "stopping and removing"
	rm -f "$PID" "$MARK"
	beat
	step "keeping the data"
	ok "the data directory would have been kept, the way every real recipe here keeps it"
	return 0
}

do_start()   { step "starting demo-db"; beat; mkdir -p "$STATE"; : > "$PID"; ok "started"; }
do_stop()    { step "stopping demo-db"; beat; rm -f "$PID"; ok "stopped"; }
do_restart() { do_stop; do_start; }
do_enable()  { mkdir -p "$STATE"; : > "$STATE/demo-db.boot"; ok "will start at boot"; }
do_disable() { rm -f "$STATE/demo-db.boot"; ok "will not start at boot"; }

do_status() {
	[ -f "$MARK" ] || exit 2
	echo "detail=demo-db 11.4.2, port $(param port 3306)"
	if [ -f "$STATE/demo-db.boot" ]; then echo "enabled=1"; else echo "enabled=0"; fi
	[ -f "$PID" ] && exit 0
	exit 1
}

do_help() {
	if lang_zh; then
		cat <<'EOF'
演示 · 数据库

也是假的，什么都不装。它比"演示 · 网页服务器"多两件事：

  · 装的时间长一些（八步），进度条走得更完整
  · 它声明自己要 400M 内存、250M 磁盘。如果这台机器比这还小，
    卡片上的尺寸那行会变红，按"安装"时还会先弹一个框问你确定吗

参数里的"字符集"是可选项类型：光标停在那一行，用左右方向键换值。
EOF
	else
		cat <<'EOF'
Demo Database

Also not real, and installs nothing. It differs from the demo web server in
two ways:

  · it takes longer — eight steps, so the bar has more to show
  · it claims to want 400M of memory and 250M of disk. On a machine smaller
    than that the size line turns red, and pressing Install asks first

The character set field is the chooser kind: put the cursor on that row and
use Left and Right to change it.
EOF
	fi
}

app_main "$@"
