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
      openssh-server sudo ca-certificates curl less nano tzdata; \
    rm -rf /var/lib/apt/lists/*

# Hardware-facing units are meaningless in a container and fail loudly at boot,
# which is how a working container ends up looking broken in `systemctl status`.
RUN systemctl mask systemd-udevd.service systemd-udevd-kernel.socket \
      systemd-udevd-control.socket systemd-modules-load.service \
      sys-kernel-debug.mount sys-kernel-config.mount \
      systemd-journald-audit.socket

# openssh-server enables itself — Debian's postinst does it, nobody here chose
# it — and an hqnode login never goes near it. The gateway is one SSH server on
# the host: it authenticates there and enters the container's namespaces
# (agent/internal/sshgw), so there is no network hop, no port, and nothing
# inside to keep in sync. What was left running was a few MB of a box sold with
# 128 and a listening socket the holder did not ask for.
#
# Disabled, not removed, and not masked. The package stays because the
# gateway's SFTP subsystem runs this image's `sftp-server` — on the RPM side
# that file is inside openssh-server itself — and because a holder who wants
# their own sshd on a port they own should get it with one command:
# `systemctl enable --now ssh`. Masking would make that two.
RUN systemctl disable ssh.service ssh.socket

# /data is the one path that survives a reinstall (frame.md §7.1). Shipping the
# mountpoint and a README in the image is what makes the panel's reinstall
# dialog true rather than aspirational.
RUN mkdir -p /data && printf 'Files here survive a reinstall. Everything else does not.\n' > /data/README

# systemd shuts down cleanly on SIGRTMIN+3, not SIGTERM. Declaring it here is
# what stops every stop from taking the full 30-second timeout and then SIGKILL.
STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
