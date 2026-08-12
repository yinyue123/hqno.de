# The RPM half of the same idea: systemd as PID 1, so the container behaves
# like a small machine rather than a process in a jail. One Dockerfile covers
# AlmaLinux, Rocky, CentOS Stream, CentOS 7 and Fedora — the release is the
# BASE build-arg, and .github/workflows/images.yml is the list.
ARG BASE=almalinux:9

# app-setup, the software manager a holder gets by typing `app-setup`. It is
# compiled here rather than committed as a binary, and compiled against musl in
# an Alpine stage rather than against this image's own libc, because one
# `cc -static` then produces a binary with no interpreter and no NSS lookups
# that runs unchanged on CentOS 7, AlmaLinux 10 and Alpine alike. It also keeps
# a compiler out of twenty shipped images, and off CentOS 7 in particular,
# where installing one now means talking to vault.centos.org.
#
# The stage inherits the *target* platform, so an arm64 build produces an arm64
# binary under emulation. It is one file, so that costs seconds.
#
# The build context is images/, not this directory: three Dockerfiles share the
# one app-setup tree. See .github/workflows/images.yml.
FROM alpine:3 AS app-setup-build
RUN apk add --no-cache gcc musl-dev
COPY app-setup/app-setup.c /app-setup.c
RUN cc -static -O2 -s -o /app-setup /app-setup.c && /app-setup --version

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
      openssh-server openssh-clients sudo ca-certificates less nano tzdata; \
    # `passwd` the *command* turns out to be its own package on this side of
    # the family, separate from shadow-utils (which only carries
    # useradd/groupadd and the backend logic) — confirmed live: AlmaLinux 9
    # and Rocky 8 both have shadow-utils installed and no /usr/bin/passwd at
    # all (`rpm -qf` on Rocky 9, where it *is* present, names the owning
    # package `passwd-0.80-12.el9`), which is exactly the failure that broke
    # four of eleven RPM images the first time docs/passwd.md's rename ran in
    # CI: `mv: cannot stat '/usr/bin/passwd': No such file or directory`. The
    # rename is gone now, but the requirement is not — an image with no passwd
    # command at all is a broken image, and app-setup's fallthrough (every
    # flag, every non-root change) execs /usr/bin/passwd by absolute path.
    # Asking every base for a package literally named `passwd` unconditionally
    # risks the opposite failure on whichever ones resolve the command some
    # other way (CentOS 7 predates this split entirely) — installing it only
    # when the binary isn't already there is what stays safe on both sides
    # without having to enumerate which bases are which. Tested by path, not
    # by `command -v`, so it cannot be fooled by anything on PATH.
    test -x /usr/bin/passwd || $PM -y install passwd; \
    # openssh-clients is a separate package on this side of the family and
    # openssh-server does not require it, so these images shipped with no
    # `ssh`, no `scp` and no `sftp` at all. That is the outbound direction and
    # nothing to do with logging in: `git clone git@…`, `rsync -e ssh`, copying
    # a file to another box — none of which a holder could do here while a
    # Debian or Alpine container could. Both of those get the client without
    # asking, which is exactly why the gap went unnoticed. 3 MB.
    #
    # openssh-server stays only because this family will not let it go: the
    # sftp-server the gateway needs lives *inside* that package, where Debian
    # and Alpine split it out. So the daemon is installed and switched off
    # below rather than absent — the one place the three recipes differ on
    # this, and not by choice.
    #
    # The gateway's SFTP subsystem is the other half, and had its own problem:
    # it execs whatever `command -v sftp-server` finds, falling back to
    # Debian's /usr/lib/openssh/sftp-server. This family puts it in
    # /usr/libexec/openssh, which is neither — so SFTP was a dead subsystem on
    # every image built here: the client got "subsystem request failed" while
    # the shell worked perfectly, which is the shape of a bug nobody reports.
    # /usr/local/bin is on the PATH the gateway hands a session, so one symlink
    # is the whole fix.
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

# The Debian and Alpine recipes have no sshd at all; this one cannot do that,
# because `sftp-server` lives inside openssh-server here. So the daemon is
# present and switched off — which is not the same promise, and is worth
# knowing when comparing a RHEL container to the other two.
#
# It enables itself on install (the distribution's systemd preset does it,
# nobody here chose it), and an hqnode login never goes near it: the gateway is
# one SSH server on the *host*, authenticating there and entering the
# container's namespaces (agent/internal/sshgw). What was left running was a
# few MB of a box sold with 128 and a socket listening for a login that does
# not arrive that way.
#
# Disabled rather than masked, so a holder who does want a listening sshd on a
# port they own gets it with one command: `systemctl enable --now sshd`.
RUN systemctl disable sshd.service sshd.socket

# The software manager. Three parts, and the split is the point: the binary
# knows nothing about nginx, and adding software is dropping a file into
# /etc/app-setup rather than rebuilding anything.
#
#   /bin/app-setup              the picker
#   /usr/lib/app-setup/         the helpers every recipe sources
#   /etc/app-setup/*.sh         one file per package — a holder may edit these,
#                               and their own go here too
#
# Last, and in its own layer, because a wording fix in one recipe should not
# invalidate the package installs above it.
COPY --from=app-setup-build /app-setup /bin/app-setup
COPY app-setup/lib/     /usr/lib/app-setup/
COPY app-setup/recipes/ /etc/app-setup/
#
# app-setup answers to `passwd` too (docs/passwd.md): the real tool is left
# exactly where it is and app-setup is put *in front of it on PATH*, so every
# existing invocation — flags, a non-root user's own change, all of it — still
# runs exactly as it always has. app-setup only adds a step after it succeeds:
# the same new password also reaches the SSH gateway (agent/internal/sshgw),
# which otherwise never reads this container's own /etc/shadow.
#
# /usr/local/bin rather than /usr/bin, because rpm owns /usr/bin/passwd: the
# first version of this renamed the real binary to .passwd and put a symlink
# in its place, and any later upgrade of the package that owns that path (the
# `passwd` package here — see the install block above) writes the real binary
# straight back over the symlink, silently restoring the bug this is here to
# fix. (Alpine has the same failure on a much shorter fuse — every single apk
# transaction; see that Dockerfile.) Nothing owns /usr/local/bin, and it
# precedes /usr/bin in the login PATH and in sudo's secure_path.
RUN set -eux; \
    chmod 0755 /bin/app-setup /etc/app-setup/*.sh; \
    chmod 0644 /usr/lib/app-setup/*.sh; \
    mkdir -p /var/log/app-setup /var/lib/app-setup /usr/local/bin; \
    test -x /usr/bin/passwd; \
    ln -sf /bin/app-setup /usr/local/bin/passwd; \
    app-setup doctor >/dev/null

# How anybody finds out it exists. The gateway starts a login shell, so
# /etc/profile.d is read on every interactive login — and only on interactive
# ones, which is what the $- test is for: a line printed here would otherwise
# land in the middle of an `ssh host command` and corrupt whatever is reading
# it.
RUN printf '%s\n' \
      '# One line, so somebody who has just been handed a container knows what' \
      '# to type. Delete this file if you would rather it stayed quiet.' \
      'case $- in' \
      '  *i*)' \
      '    case "${LANG-}${LC_ALL-}" in' \
      '      zh*|*zh_CN*) printf "\033[2m输入 \033[0m\033[1mapp-setup\033[0m\033[2m 安装软件（LNMP、WordPress、数据库、开发环境）\033[0m\n" ;;' \
      '      *)           printf "\033[2mType \033[0m\033[1mapp-setup\033[0m\033[2m to install software — web servers, databases, WordPress, dev tools.\033[0m\n" ;;' \
      '    esac' \
      '    ;;' \
      'esac' \
      > /etc/profile.d/app-setup.sh; \
    chmod 0644 /etc/profile.d/app-setup.sh

# /data is the one path that survives a reinstall (frame.md §7.1). Shipping the
# mountpoint and a README in the image is what makes the panel's reinstall
# dialog true rather than aspirational.
RUN mkdir -p /data && printf 'Files here survive a reinstall. Everything else does not.\n' > /data/README

# systemd shuts down cleanly on SIGRTMIN+3, not SIGTERM. Declaring it here is
# what stops every stop from taking the full 30-second timeout and then SIGKILL.
STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
