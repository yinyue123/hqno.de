# The RPM half of the same idea: systemd as PID 1, so the container behaves
# like a small machine rather than a process in a jail. One Dockerfile covers
# AlmaLinux, Rocky, CentOS Stream, CentOS 7 and Fedora — the release is the
# BASE build-arg, and .github/workflows/images.yml is the list.
ARG BASE=almalinux:9
FROM ${BASE}

# curl is deliberately absent: these bases ship curl-minimal, and asking for
# curl makes dnf refuse on a conflict it cannot resolve without --allowerasing.
#
# CentOS 7 is past end of life, so mirror.centos.org no longer answers and its
# mirrorlists resolve to nothing. The packages are all still in vault, which is
# what the rewrite below points at — without it every yum call fails with
# "Could not resolve host".
RUN set -eux; \
    if command -v dnf >/dev/null 2>&1; then PM=dnf; else PM=yum; fi; \
    if [ "$PM" = yum ] && grep -q 'CentOS Linux 7' /etc/os-release; then \
      sed -i -e 's|^mirrorlist=|#mirrorlist=|' \
             -e 's|^#\?baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' \
             /etc/yum.repos.d/CentOS-*.repo; \
    fi; \
    $PM -y install \
      systemd dbus cronie rsyslog procps-ng iproute iputils \
      openssh-server sudo ca-certificates less nano tzdata; \
    # The gateway's SFTP subsystem execs whatever `command -v sftp-server`
    # finds, falling back to Debian's /usr/lib/openssh/sftp-server. This family
    # puts it in /usr/libexec/openssh, which is neither — so SFTP was a dead
    # subsystem on every image built here: the client got "subsystem request
    # failed" while the shell worked perfectly, which is the shape of a bug
    # nobody reports. /usr/local/bin is on the PATH the gateway hands a
    # session, so one symlink is the whole fix.
    ln -sf /usr/libexec/openssh/sftp-server /usr/local/bin/sftp-server; \
    # No index to prime, unlike apt and apk: dnf and yum both fetch repository
    # metadata the first time an install needs it, and expire it on their own
    # schedule after that. A `dnf install nginx` in a fresh container works
    # with nothing run beforehand — measured, not assumed.
    $PM clean all; \
    rm -rf /var/cache/dnf /var/cache/yum

# Hardware-facing units are meaningless in a container and fail loudly at boot,
# which is how a working container ends up looking broken in `systemctl status`.
RUN systemctl mask systemd-udevd.service systemd-udevd-kernel.socket \
      systemd-udevd-control.socket systemd-modules-load.service \
      sys-kernel-debug.mount sys-kernel-config.mount \
      systemd-journald-audit.socket

# openssh-server enables itself — the distribution's systemd preset does it,
# nobody here chose it — and an hqnode login never goes near it. The gateway is
# one SSH server on the host: it authenticates there and enters the container's
# namespaces (agent/internal/sshgw), so there is no network hop, no port, and
# nothing inside to keep in sync. What was left running was a few MB of a box
# sold with 128 and a listening socket the holder did not ask for.
#
# Disabled, not removed, and not masked. The package stays because the
# gateway's SFTP subsystem runs this image's `sftp-server`, and on this side of
# the family that file lives *inside* openssh-server — there is no separate
# package to keep. A holder who wants their own sshd on a port they own gets it
# with `systemctl enable --now sshd`; masking would make that two commands.
RUN systemctl disable sshd.service sshd.socket

# /data is the one path that survives a reinstall (frame.md §7.1). Shipping the
# mountpoint and a README in the image is what makes the panel's reinstall
# dialog true rather than aspirational.
RUN mkdir -p /data && printf 'Files here survive a reinstall. Everything else does not.\n' > /data/README

# systemd shuts down cleanly on SIGRTMIN+3, not SIGTERM. Declaring it here is
# what stops every stop from taking the full 30-second timeout and then SIGKILL.
STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
