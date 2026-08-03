# A *system* container image, the Alpine way: OpenRC under busybox init as PID
# 1, so whoever holds the container gets services, cron, package installs and a
# working `top` — the same promise the systemd images make, kept by a different
# init. One Dockerfile covers every Alpine release we publish; the release is
# the BASE build-arg and images/systems.yml is the list.
#
# Alpine is here because it is the cheap one. A booted container idles at a few
# MB of RSS against ~40 for a systemd one, which on an oversold host is the
# difference between twelve tenants and thirty.
ARG BASE=alpine:3.24
FROM ${BASE}

# What the agent actually requires of an image is short: an entrypoint, a
# /bin/sh (every SSH session is wrapped in one), and — only if SFTP is to work
# — something named sftp-server that `command -v` can find. Everything else in
# this list is the difference between "a container" and "a machine someone was
# handed": openrc for services, procps-ng so `top` and `free` print what a
# person expects rather than busybox's terser applets, shadow for useradd and
# real passwd files, and bash because a login shell that is not bash surprises
# people.
#
# The two openssh halves are named individually rather than taken as the
# `openssh` meta-package, because that one drags in a daemon nothing here uses:
# an hqnode login is the host's gateway entering this container's namespaces
# (agent/internal/sshgw), never a connection to an sshd inside it.
#
#   openssh-sftp-server     what the gateway execs for the SFTP subsystem —
#                           which is also what `scp` speaks since OpenSSH 9.0.
#   openssh-client-default  the outbound direction, nothing to do with logging
#                           in: `git clone git@…`, `rsync -e ssh`, and the
#                           remote half of a legacy `scp -O`, which runs
#                           `scp -t` in the container rather than a subsystem.
#
# A holder who wants a listening sshd on a port they own runs `apk add openssh`
# themselves.
RUN set -eux; \
    apk add --no-cache \
      openrc busybox-openrc busybox-suid \
      openssh-client-default openssh-sftp-server \
      bash shadow sudo procps-ng \
      iproute2 iputils curl ca-certificates less nano tzdata logrotate; \
    # The gateway looks for `sftp-server` on PATH and falls back to Debian's
    # /usr/lib/openssh/sftp-server. Alpine ships neither name, so SFTP is a
    # symlink away from working and a broken subsystem otherwise.
    ln -sf /usr/lib/ssh/sftp-server /usr/local/bin/sftp-server

# OpenRC in a container, which is three settings and a getty problem:
#   rc_sys=lxc      stops it starting the hardware services (mdev, modules,
#                   hwclock, keymaps) that fail loudly and make a working
#                   container look broken in `rc-status`.
#   rc_provide      the network exists before the container's first
#                   instruction — pasta configures it from the host side — so
#                   the services that want `net` must not wait for a network
#                   script we deliberately do not run.
#   no gettys       there are no consoles to put them on; left in, busybox
#                   respawns six failing processes for the life of the box.
RUN set -eux; \
    sed -i 's/^#\?rc_sys=.*/rc_sys="lxc"/' /etc/rc.conf; \
    printf 'rc_provide="loopback net"\nrc_logger="YES"\n' >> /etc/rc.conf; \
    sed -i '/^tty[0-9]*::/d; /^#ttyS0::/d' /etc/inittab; \
    # cgroups are the host's business here: the container is already inside the
    # one it was sold, and OpenRC mounting its own would fight the agent for it.
    sed -i 's/^rc_cgroup_mode=.*/rc_cgroup_mode="none"/' /etc/rc.conf 2>/dev/null || true; \
    rc-update add crond default; \
    rc-update add syslog boot

# There is no sshd here, so there is nothing to generate host keys for and no
# `sshd-keygen` service any more. Both went with it, and this comment is what
# is left of them: a container that grows one later (`apk add openssh`) gets
# Alpine's own init script, which is the distribution's problem to get right
# rather than a script written here.

# A holder who logs in and types `apk add nginx` should get nginx. With no
# index they got *nginx (no such package)*, which reads like the package does
# not exist rather than like nothing has been fetched yet. Shipping an index in
# the image would only move the problem: it is a snapshot of a mirror, and the
# versions it names are the ones that get superseded first.
#
# So it is fetched at boot, where it is current — but *not on every boot*. A
# container that restarts twenty times an hour, or a host that reboots and
# brings thirty of them up at once, must not be thirty machines hitting the
# Alpine mirror in the same second. A stamp file records the last run; the
# index is refreshed only if there is no stamp, or the stamp is older than the
# window. One day, the same number the systemd recipes use, and there is more
# reason for it there — see that Dockerfile.
#
# Silent about failing: a container with no route out still has to boot, and a
# failed update leaves no stamp, so the next boot tries again. (dnf and yum
# need no equivalent — they fetch metadata when an install first asks for it.
# apt and apk do not.)
RUN set -eux; \
    mkdir -p /usr/local/sbin; \
    printf '%s\n' \
      '#!/bin/sh' \
      '# Refresh the package index, at most once per window. See the Dockerfile.' \
      'window_days=1' \
      'stamp=/var/lib/hqnode/package-index' \
      'if [ -e "$stamp" ] && [ -n "$(find "$stamp" -mtime -$window_days 2>/dev/null)" ]; then' \
      '    exit 0' \
      'fi' \
      'apk update >/dev/null 2>&1 || exit 0' \
      'mkdir -p /var/lib/hqnode && touch "$stamp"' \
      > /usr/local/sbin/hqnode-package-index; \
    chmod +x /usr/local/sbin/hqnode-package-index; \
    printf '#!/sbin/openrc-run\ndescription="fetch the package index so a login can install things"\ndepend() { after net; }\nstart() { ebegin "Fetching the package index"; /usr/local/sbin/hqnode-package-index; eend 0; }\n' \
      > /etc/init.d/hqnode-package-index; \
    chmod +x /etc/init.d/hqnode-package-index; \
    rc-update add hqnode-package-index default

# /data is the one path that survives a reinstall (frame.md §7.1). Shipping the
# mountpoint and a README in the image is what makes the panel's reinstall
# dialog true rather than aspirational.
RUN mkdir -p /data && printf 'Files here survive a reinstall. Everything else does not.\n' > /data/README

# The signal that matters, and the one thing an Alpine image cannot inherit
# from the systemd ones. busybox init reads SIGTERM as *reboot*: it would run
# the shutdown scripts and then reboot(RB_AUTOBOOT), which the kernel turns
# into a SIGHUP to our parent, which the agent correctly reads as "the
# container rebooted itself" — and restarts it. Every stop would become a
# restart. SIGUSR2 is poweroff: same shutdown scripts, then RB_POWER_OFF,
# which arrives as SIGINT and ends the container for good.
STOPSIGNAL SIGUSR2

CMD ["/sbin/init"]
