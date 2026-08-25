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

# app-setup, the software manager a holder gets by typing `app-setup`. It is
# compiled here rather than committed as a binary. The stage is a fixed
# alpine:3 rather than ${BASE} so that this block is byte-identical in all
# three image recipes — the binary it produces is static and has no libc to
# match, so building it against the release we are about to ship would buy
# nothing and would mean three subtly different Dockerfiles.
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

# Something has to cut the logs, and nothing did.
#
# The binary is installed (see the apk list) and crond runs
# /etc/periodic/daily/logrotate at 02:00 — what was missing is a rule matching
# anything this image's model produces. Two things write to /var/log here and
# neither was covered:
#
#   /var/log/<service>.log   OpenRC's supervise-daemon redirects a service's
#                            stdout and stderr into one of these. Every image
#                            built on this one does it, because that is what
#                            `supervisor=supervise-daemon` means — and an app
#                            that logs a line per connection fills a holder's
#                            disk quota in days.
#   /var/log/messages        busybox syslogd's, and SYSLOGD_OPTS is "-t" with
#                            no -s or -b, so it never rotated either. The
#                            supervisor's own events are in there: what was
#                            started, stopped, signalled, respawned.
#
# A glob rather than a list, deliberately: an image built on this one adds
# services this file has never heard of, and they are covered the day they
# appear. /var/log/nginx/*.log and friends are left to the packages that ship
# them — a subdirectory does not collide with this glob.
#
# The three settings that are not taste:
#
#   copytruncate   supervise-daemon holds each file open and never reopens it.
#                  The default — rename, create a new one — leaves it writing
#                  into the renamed inode: the new file empty forever, the old
#                  one still growing where nobody looks. The opposite risk, a
#                  daemon whose fd is not O_APPEND writing at its old offset
#                  into a sparse hole, was checked on a running node rather
#                  than assumed.
#   dateformat     the global logrotate.conf says `dateext`, whose names are
#                  accurate to the day, so a second rotation on the same date
#                  fails with "destination … already exists" — and one failing
#                  rule takes the whole 02:00 run's exit code with it, which
#                  /etc/periodic/daily/logrotate reports into syslog as
#                  "ALERT exited abnormally". With the time in the name two
#                  forced rotations two seconds apart both exit 0.
#   daily/7        against the global weekly/4. A container's disk is a quota
#                  someone paid for, and a week of daily files is what you want
#                  when something broke on Tuesday.
#
# The distro's own two rules go for the same exit-code reason: logrotate
# refuses a file claimed twice — `duplicate log entry for /var/log/rc.log` —
# and skips the whole file it found that in. Both name files this glob already
# covers.
RUN set -eux; \
    printf '%s\n' \
      '/var/log/*.log' \
      '/var/log/messages {' \
      '	daily' \
      '	dateformat -%Y%m%d-%H%M%S' \
      '	rotate 7' \
      '	compress' \
      '	delaycompress' \
      '	missingok' \
      '	notifempty' \
      '	copytruncate' \
      '}' \
      > /etc/logrotate.d/hqnode; \
    chmod 0644 /etc/logrotate.d/hqnode; \
    rm -f /etc/logrotate.d/acpid /etc/logrotate.d/openrc; \
    # A rule logrotate cannot parse, or one that duplicates another, does
    # nothing at 02:00 and says so only in syslog. It says so here instead.
    logrotate -d /etc/logrotate.conf >/dev/null

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

# The software manager. Three parts, and the split is the point: the binary
# knows nothing about nginx, and adding software is dropping a file into
# /etc/app-setup rather than rebuilding anything.
#
#   /bin/app-setup              the picker
#   /usr/lib/app-setup/         the helpers every recipe sources
#   /etc/app-setup/*.sh         one file per package — a holder may edit these
#   /etc/app-setup/local/*.sh   a holder's own, overriding ours by id
#   /etc/app-setup/params/      what the Settings form saved, one file per id
#   /etc/app-setup/secrets/     generated passwords, 0700 and each file 0600
#
# The three subdirectories sit next to the recipes on purpose: one directory
# answers "where is the config on this machine", and the answer is /etc, the
# same as it is for nginx or MariaDB. They are created empty here and filled
# at run time, so an image carries no holder's recipe, port or password.
#
# Last, and in its own layer, because a wording fix in one recipe should not
# invalidate the package installs above it.
COPY --from=app-setup-build /app-setup /bin/app-setup
COPY app-setup/lib/     /usr/lib/app-setup/
COPY app-setup/recipes/ /etc/app-setup/
# The guide `helppage` reads. Plain .txt, one file per page per language,
# scanned at startup the same way the recipes above are — a host who drops
# their own page in here gets a chapter with no rebuild of anything.
COPY helppage/          /etc/helppage/
#
# app-setup answers to `passwd` too (docs/passwd.md): the real tool is left
# exactly where it is and app-setup is put *in front of it on PATH*, so every
# existing invocation — flags, a non-root user's own change, all of it — still
# runs exactly as it always has. app-setup only adds a step after it succeeds:
# the same new password also reaches the SSH gateway (agent/internal/sshgw),
# which otherwise never reads this container's own /etc/shadow.
#
# /usr/local/bin rather than /usr/bin, and on Alpine this is not a preference.
# The first version of this renamed the real binary to .passwd and put a
# symlink at /usr/bin/passwd, which survived exactly until the container's
# holder installed anything: apk fires the busybox trigger on *every*
# transaction, `bbsuid --install` recreates /usr/bin/passwd -> /bin/bbsuid
# whenever it finds a symlink at that path, and the container silently went
# back to busybox's passwd — the exact bug docs/passwd.md exists to fix,
# reintroduced by app-setup's own `apk add`. A regular file it leaves alone,
# which is why the `shadow` package's binary is safe sitting at /usr/bin/passwd
# and a symlink there never was. Nothing owns /usr/local/bin, and it precedes
# /usr/bin in the login PATH and in sudo's secure_path — the same reason
# sftp-server is installed there above.
#
# poweroff/halt answer to app-setup too now (docs/passwd.md §11), so a tenant
# leaving their own container off actually stays a tenant decision instead of
# restart_policy=always silently undoing it. They live under sbin here, not
# bin — /sbin/poweroff -> /bin/busybox, confirmed live, and usrmerge does not
# reach /sbin on this base — so the shim goes in /usr/local/sbin, which
# precedes /sbin in the same PATH and is just as unowned by apk.
RUN set -eux; \
    chmod 0755 /bin/app-setup /etc/app-setup/*.sh; \
    chmod 0644 /usr/lib/app-setup/*.sh /etc/helppage/*.txt; \
    mkdir -p /var/log/app-setup /var/lib/app-setup /usr/local/bin /usr/local/sbin; \
    mkdir -p /etc/app-setup/local /etc/app-setup/params /etc/app-setup/secrets; \
    chmod 0700 /etc/app-setup/secrets; \
    test -x /usr/bin/passwd; \
    ln -sf /bin/app-setup /usr/local/bin/passwd; \
    test -x /sbin/poweroff; \
    ln -sf /bin/app-setup /usr/local/sbin/poweroff; \
    test -x /sbin/halt; \
    ln -sf /bin/app-setup /usr/local/sbin/halt; \
    # domain, dashboard and reinstall answer to app-setup too, bare, the
    # same multicall way — no real system binary behind any of those names
    # to fall through to, so unlike poweroff/halt there is nothing to guard
    # with test -x.
    ln -sf /bin/app-setup /usr/local/bin/domain; \
    ln -sf /bin/app-setup /usr/local/bin/dashboard; \
    ln -sf /bin/app-setup /usr/local/bin/reinstall; \
    ln -sf /bin/app-setup /usr/local/bin/helppage; \
    app-setup doctor >/dev/null

# How anybody finds out it exists. The gateway starts a login shell, and
# Alpine's /etc/profile sources /etc/profile.d/*.sh the same way Debian's does.
# The $- test keeps the line off non-interactive sessions, where it would land
# in the middle of an `ssh host command` and corrupt whatever is reading it.
RUN mkdir -p /etc/profile.d && printf '%s\n' \
      '# What somebody wants on the way in: how much of their box is left, and' \
      '# the two words that do something about it. Delete this file to stay quiet.' \
      'case $- in' \
      '  *i*)' \
      '    # The usage block is the daemon'"'"'s answer, and is silent when it cannot' \
      '    # be reached: a login must never wait on it, or report to somebody' \
      '    # holding a shell prompt a thing they cannot do anything about.' \
      '    app-setup dashboard --brief 2>/dev/null' \
      '    case "${LANG-}${LC_ALL-}" in' \
      '      zh*|*zh_CN*)' \
      '        printf "\033[2m装软件：\033[0m\033[1mapp-setup\033[0m\033[2m — LNMP、WordPress、数据库、开发环境\033[0m\n"' \
      '        printf "\033[2m看状态：\033[0m\033[1mdashboard\033[0m\033[2m — 配额、流量、端口、域名、到期\033[0m\n"' \
      '        printf "\033[2m看文档：\033[0m\033[1mhelppage\033[0m\033[2m — 端口与域名、装软件、限额、重装\033[0m\n" ;;' \
      '      *)' \
      '        printf "\033[2mInstall software: \033[0m\033[1mapp-setup\033[0m\033[2m — web servers, databases, WordPress, dev tools.\033[0m\n"' \
      '        printf "\033[2mCheck this box:   \033[0m\033[1mdashboard\033[0m\033[2m — allowances, traffic, ports, domains, expiry.\033[0m\n"' \
      '        printf "\033[2mRead the guide:   \033[0m\033[1mhelppage\033[0m\033[2m — ports and domains, installing, limits, reinstall.\033[0m\n" ;;' \
      '    esac' \
      '    ;;' \
      'esac' \
      > /etc/profile.d/app-setup.sh; \
    chmod 0644 /etc/profile.d/app-setup.sh

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
