#!/bin/sh
# app-setup: 1
# id: supervisor
# name: Supervisor
# name.zh: Supervisor 进程守护
# category: system
# order: 21
# summary: Keeps your own program running and restarts it when it dies. Simpler than writing a unit.
# summary.zh: 让你自己的程序一直跑着，挂了自动拉起来。比写服务文件简单。
# includes: supervisord, supervisorctl, a config directory
# includes.zh: supervisord、supervisorctl、配置目录
# disk: 25M
# memory: 30M
# service: supervisor
. /usr/lib/app-setup/common.sh

PKGS="supervisor"
SERVICE="supervisor"
SERVICE_rpm="supervisord"
SERVICE_apk="supervisord"
CHECK_BIN="supervisord"

version_line() {
	_v="$(supervisord -v 2>/dev/null)"
	_n="$(supervisorctl status 2>/dev/null | grep -c RUNNING || true)"
	printf 'supervisor %s, %s running' "$_v" "${_n:-0}"
}

do_install() {
	enable_epel
	pkg_install $(pmv PKGS)

	# Where the include directory lives differs by distro; make sure the one
	# the shipped config points at actually exists.
	for d in /etc/supervisor/conf.d /etc/supervisord.d; do
		[ -d "$(dirname "$d")" ] && mkdir -p "$d"
	done

	svc_enable "$(svc)"
	svc_start "$(svc)" || warn "supervisord did not start; check its log"
	show_note supervisor
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove $(pmv PKGS)
}

do_help() { cat <<'EOF'
Supervisor

  What it is for
    You have a program — a Python bot, a Node script, a Go binary — that
    should keep running and come back after a crash or a reboot. Supervisor
    does that without you learning systemd unit files.

  Add a program
    Put a file in the include directory. On Debian and Ubuntu that is
    /etc/supervisor/conf.d/, on AlmaLinux and Alpine /etc/supervisord.d/
    (with a .ini or .conf name — check the files already there).

      [program:mybot]
      command=/usr/bin/python3 /opt/mybot/main.py
      directory=/opt/mybot
      user=nobody
      autostart=true
      autorestart=true
      stderr_logfile=/var/log/mybot.err.log
      stdout_logfile=/var/log/mybot.out.log

    Then:
      supervisorctl reread          notice the new file
      supervisorctl update          apply it
      supervisorctl status          see it running

  Day to day
    supervisorctl status
    supervisorctl restart mybot
    supervisorctl stop mybot
    supervisorctl tail -f mybot stderr

  command= must not daemonise
    Supervisor watches the process it started. If your program forks into
    the background, supervisor thinks it exited and restarts it forever.
    Nearly every server has a flag for this — nginx -g 'daemon off;',
    celery worker, gunicorn without --daemon.

  Or use the init directly
    On the systemd images, `systemctl edit --force --full mything.service`
    does the same job with no extra package. Supervisor earns its place when
    you have several small programs, or when you are on the Alpine image.
EOF
}

app_main "$@"
