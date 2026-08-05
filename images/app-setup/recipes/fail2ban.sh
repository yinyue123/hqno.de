#!/bin/sh
# app-setup: 1
# id: fail2ban
# name: Fail2ban
# name.zh: Fail2ban 防爆破
# category: system
# order: 20
# summary: Watches the logs and blocks addresses that keep guessing passwords.
# summary.zh: 盯着日志，谁一直猜密码就把谁的 IP 封掉。
# includes: fail2ban, an sshd jail turned on
# includes.zh: fail2ban 主程序，已开启的 sshd 规则
# disk: 12M
# memory: 40M
# service: fail2ban
. /usr/lib/app-setup/common.sh

PKGS="fail2ban"
SERVICE="fail2ban"
CHECK_BIN="fail2ban-client"

version_line() {
	_v="$(fail2ban-client --version 2>/dev/null | head -1)"
	_n="$(fail2ban-client status 2>/dev/null | awk -F: '/Jail list/{print $2}' | tr -d ' \t')"
	[ -n "$_n" ] && printf '%s, jails: %s' "$_v" "$_n" || printf '%s' "$_v"
}

do_install() {
	enable_epel
	pkg_install $(pmv PKGS)

	# The shipped jail.conf is overwritten on upgrade; jail.local is not.
	if [ ! -f /etc/fail2ban/jail.local ]; then
		_backend=auto
		# Alpine and the RPM images have no /var/log/auth.log, and on systemd
		# machines the log is in the journal rather than a file.
		[ "$INIT" = systemd ] && _backend=systemd
		cat > /etc/fail2ban/jail.local <<EOF
# written by app-setup; edit freely, it is not replaced on upgrade
[DEFAULT]
backend  = $_backend
bantime  = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
EOF
		ok "wrote /etc/fail2ban/jail.local with the sshd jail on"
	fi

	svc_enable "$(svc)"
	svc_start "$(svc)" || warn "fail2ban did not start — see: fail2ban-client -d"

	if ! have iptables && ! have nft; then
		warn "no iptables or nft here, so fail2ban has nothing to ban with."
		warn "install iptables, or rely on the panel's own SSH gateway instead."
	fi
}

do_uninstall() {
	svc_stop "$(svc)"
	svc_disable "$(svc)"
	pkg_remove $(pmv PKGS)
	rm -f /etc/fail2ban/jail.local
}

do_help() { cat <<'EOF'
Fail2ban

  What it does
    Reads the authentication log. When one address fails to log in five
    times in ten minutes, it is blocked for an hour. That is the whole idea,
    and it removes essentially all of the background password guessing.

  Check it is working
    fail2ban-client status              which jails are on
    fail2ban-client status sshd         who is banned right now

  Unban yourself
    fail2ban-client set sshd unbanip 203.0.113.9
    Add your own address to ignoreip in /etc/fail2ban/jail.local so it
    cannot happen again.

  Tuning
    /etc/fail2ban/jail.local — bantime, findtime, maxretry. Restart after
    editing: systemctl restart fail2ban   (or rc-service fail2ban restart)

  Read this before relying on it
    In a hqnode container, SSH usually does not reach a local sshd at all:
    the panel's gateway authenticates on the host and steps into the
    namespace. Attempts stopped outside never appear in your log, so this
    jail will look idle. It is still worth having if you run your own sshd
    on your own port, and it does nothing useful if you do not.

    It also needs iptables or nftables to do the banning. A container
    without NET_ADMIN cannot install firewall rules, and fail2ban will start
    and then fail every ban action. `fail2ban-client status sshd` showing
    bans that never take effect is that symptom.
EOF
}

app_main "$@"
