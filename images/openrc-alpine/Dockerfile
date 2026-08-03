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
# real passwd files, openssh so a holder can run their own sshd on a port they
# own, and bash because a login shell that is not bash surprises people.
RUN set -eux; \
    apk add --no-cache \
      openrc busybox-openrc busybox-suid \
      openssh openssh-sftp-server \
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

# sshd is installed and *not* started, which is the one thing about it worth
# writing down: an hqnode login never goes near it. The gateway is one SSH
# server on the host — it authenticates there and enters the container's
# namespaces (agent/internal/sshgw), so there is no network hop, no port, and
# nothing inside to keep in sync. A booted sshd here is a few MB of a box sold
# with 128, and a listening socket the holder did not ask for.
#
# The package stays: the gateway's SFTP subsystem runs this image's
# `sftp-server`, and a holder who wants their own sshd on a port they own is a
# `rc-update add sshd default` away from having one. Which is why the key
# generation below stays in the default runlevel — `ssh-keygen -A` only makes
# what is missing, so it costs one boot, and it means turning sshd on is that
# one command and not two.

# sshd needs host keys and a place to chroot the privilege-separated child;
# generating the keys at build time would ship every container the same ones.
RUN set -eux; \
    mkdir -p /var/empty /run/sshd; \
    printf '#!/sbin/openrc-run\ndescription="one-time host key generation"\ndepend() { before sshd; }\nstart() { ssh-keygen -A; }\n' \
      > /etc/init.d/sshd-keygen; \
    chmod +x /etc/init.d/sshd-keygen; \
    rc-update add sshd-keygen default

# A holder who logs in and types `apk add nginx` should get nginx. With no
# index they got *nginx (no such package)*, which reads like the package does
# not exist rather than like nothing has been fetched yet. Shipping an index in
# the image would only move the problem: it is a snapshot of a mirror, and the
# versions it names are the ones that get superseded first.
#
# So it is fetched at boot, where it is current. It is a couple of MB and a
# second or two, and it is silent about failing: a container with no route out
# still boots, and `apk update` is one command away for whoever wants to retry.
# (dnf and yum need no equivalent — they fetch metadata when an install first
# asks for it. apt and apk do not.)
RUN set -eux; \
    printf '#!/sbin/openrc-run\ndescription="fetch the package index so a login can install things"\ndepend() { after net; }\nstart() { ebegin "Fetching the package index"; apk update >/dev/null 2>&1; eend 0; }\n' \
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
