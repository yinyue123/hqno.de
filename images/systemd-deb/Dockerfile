# A *system* container image, not an app image: it boots systemd as PID 1 so
# whoever holds the container gets `systemctl`, cron, package installs and a
# working `top`. One Dockerfile covers every Debian and Ubuntu release we
# publish — the release is the BASE build-arg, and .github/workflows/images.yml
# is the list.
ARG BASE=debian:13-slim
FROM ${BASE}

ENV DEBIAN_FRONTEND=noninteractive

# An end-of-life release eventually leaves the live mirrors for an archive
# host, and *when* it does is not something a Dockerfile can know: 16.04 and
# 18.04 are still on archive.ubuntu.com today under ESM, while 11 will move to
# archive.debian.org the moment its LTS window closes. So the fallback is
# tried rather than predicted — `apt-get update` reports success even when
# every index 404s, which is why the test is whether a package can actually be
# resolved afterwards.
RUN set -eux; \
    to_archive() { \
      sed -i -e 's|//archive.ubuntu.com|//old-releases.ubuntu.com|g' \
             -e 's|//security.ubuntu.com|//old-releases.ubuntu.com|g' \
             -e 's|//ports.ubuntu.com|//old-releases.ubuntu.com|g' \
             -e 's|//deb.debian.org|//archive.debian.org|g' \
             -e 's|//security.debian.org|//archive.debian.org|g' \
             /etc/apt/sources.list /etc/apt/sources.list.d/*.list \
             /etc/apt/sources.list.d/*.sources 2>/dev/null || true; \
      : > /etc/apt/apt.conf.d/90hqnode-archive; \
      echo 'Acquire::Check-Valid-Until "false";' >> /etc/apt/apt.conf.d/90hqnode-archive; \
    }; \
    echo 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/90hqnode-retries; \
    apt-get update || true; \
    if ! apt-get install -s systemd >/dev/null 2>&1; then to_archive; apt-get update || true; fi; \
    apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus cron rsyslog procps iproute2 iputils-ping \
      openssh-client openssh-sftp-server \
      sudo ca-certificates curl less nano tzdata logrotate; \
    rm -rf /var/lib/apt/lists/*

# Hardware-facing units are meaningless in a container and fail loudly at boot,
# which is how a working container ends up looking broken in `systemctl status`.
RUN systemctl mask systemd-udevd.service systemd-udevd-kernel.socket \
      systemd-udevd-control.socket systemd-modules-load.service \
      sys-kernel-debug.mount sys-kernel-config.mount \
      systemd-journald-audit.socket

# There is no sshd here, and that is the whole of it: an hqnode login never
# goes near one. The gateway is a single SSH server on the *host* — it
# authenticates there and enters the container's namespaces
# (agent/internal/sshgw), so there is no network hop, no port, and nothing
# inside to keep in sync. openssh-server was only ever here because it is what
# people install without thinking, and Debian's postinst then enabled it: a few
# MB of a box sold with 128, and a socket listening for a login that does not
# arrive that way.
#
# What is kept is the two halves that are actually used, and they are separate
# Debian packages, which is what makes dropping the daemon possible here:
#
#   openssh-sftp-server  the gateway execs this image's own `sftp-server` for
#                        the SFTP subsystem, which is also what `scp` speaks
#                        since OpenSSH 9.0. Without it, `sftp` and `scp` both
#                        fail with "subsystem request failed" while the shell
#                        works perfectly.
#   openssh-client       the outbound direction, which has nothing to do with
#                        logging in: `git clone git@…`, `rsync -e ssh`, and the
#                        remote half of a legacy `scp -O`, which runs `scp -t`
#                        inside the container rather than the subsystem.
#
# A holder who does want a listening sshd on a port they own installs
# openssh-server themselves. That is one command more than it used to be, and
# it is the right way round: nobody should pay for a daemon they did not ask
# for so that the few who want one are saved a step.

# A holder who logs in and types `apt install nginx` should get nginx. On a
# fresh container they got *Unable to locate package*, because the layer above
# deletes the package lists — and an image that shipped them instead would ship
# something worse: Debian's InRelease is valid for **seven days**, so a
# container started from a month-old image would answer `apt install` with
# *Release file is expired*, which is a harder thing to act on than an empty
# index. dnf and yum need none of this; they fetch metadata when an install
# first asks for it. apt and apk do not.
#
# So the index is fetched at boot instead, where it is always current — but
# *not on every boot*. A container that restarts twenty times an hour, or a
# host that reboots and brings thirty of them up at once, must not be thirty
# machines hitting deb.debian.org in the same second. So there is a stamp, and
# a window: run if the stamp is missing, and run if it is older than the window.
#
# The stamp has to be its own file. The obvious shortcut — look at how old the
# index is — does not work, because apt writes the *archive's* publish time onto
# the InRelease files it fetches, not the time it fetched them. A container that
# updated a minute ago carries files dated four hours earlier, and one that
# never updated at all would be indistinguishable from one that did.
#
# One day, not the week that a reading of "it barely changes" would suggest.
# InRelease is valid for seven days from its Date, so a seven-day window can
# leave a container carrying an index that expired minutes ago — and then
# `apt install` answers with *Release file is expired*, which is the exact
# failure this whole arrangement exists to avoid. One day is also what Debian's
# own apt-daily.timer uses. It is one number below if that judgement is wrong.
#
# Failure is not an error: a container with no route out still has to boot, and
# an update that half-failed leaves no stamp, so the next boot tries again.
RUN set -eux; \
    printf '%s\n' \
      '#!/bin/sh' \
      '# Refresh the package index, at most once per window. See the Dockerfile.' \
      'window_days=1' \
      'stamp=/var/lib/hqnode/package-index' \
      'if [ -e "$stamp" ] && [ -n "$(find "$stamp" -mtime -$window_days 2>/dev/null)" ]; then' \
      '    exit 0' \
      'fi' \
      'apt-get update -qq || exit 0' \
      'mkdir -p /var/lib/hqnode && touch "$stamp"' \
      > /usr/local/sbin/hqnode-package-index; \
    chmod +x /usr/local/sbin/hqnode-package-index; \
    printf '%s\n' \
      '[Unit]' \
      'Description=Fetch the package index, so a login can install things straight away' \
      'After=network.target' \
      '' \
      '[Service]' \
      'Type=oneshot' \
      'ExecStart=/usr/local/sbin/hqnode-package-index' \
      'TimeoutStartSec=180' \
      '' \
      '[Install]' \
      'WantedBy=multi-user.target' \
      > /etc/systemd/system/hqnode-package-index.service; \
    systemctl enable hqnode-package-index.service

# /data is the one path that survives a reinstall (frame.md §7.1). Shipping the
# mountpoint and a README in the image is what makes the panel's reinstall
# dialog true rather than aspirational.
RUN mkdir -p /data && printf 'Files here survive a reinstall. Everything else does not.\n' > /data/README

# systemd shuts down cleanly on SIGRTMIN+3, not SIGTERM. Declaring it here is
# what stops every stop from taking the full 30-second timeout and then SIGKILL.
STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
