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
    $PM clean all; \
    rm -rf /var/cache/dnf /var/cache/yum

# Hardware-facing units are meaningless in a container and fail loudly at boot,
# which is how a working container ends up looking broken in `systemctl status`.
RUN systemctl mask systemd-udevd.service systemd-udevd-kernel.socket \
      systemd-udevd-control.socket systemd-modules-load.service \
      sys-kernel-debug.mount sys-kernel-config.mount \
      systemd-journald-audit.socket

# /data is the one path that survives a reinstall (frame.md §7.1). Shipping the
# mountpoint and a README in the image is what makes the panel's reinstall
# dialog true rather than aspirational.
RUN mkdir -p /data && printf 'Files here survive a reinstall. Everything else does not.\n' > /data/README

# systemd shuts down cleanly on SIGRTMIN+3, not SIGTERM. Declaring it here is
# what stops every stop from taking the full 30-second timeout and then SIGKILL.
STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
