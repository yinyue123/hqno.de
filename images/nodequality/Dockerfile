# The image that turns a machine into a sales page.
#
# It runs the three xykt checks NodeQuality wraps, folds their JSON plus a
# price list into one document, pays the endpoint's proof of work and posts it.
# What comes back is a URL.
#
# Alpine, after a spell on Debian. The four tools that drove that move were
# each dealt with rather than worked around, because a check that cannot find
# its tool does not fail — it prints NoData and the page arrives short:
#
#   nexttrace   static Go. It always worked on musl; what did not was Net.sh's
#               auto-installer, which serves a glibc build. Baked in below from
#               the release asset instead, so the installer never runs.
#   speedtest   Ookla ship an `x86_64-linux-musl` static build. Baked in.
#   stun        cut. It filled one row, the NAT type, and that row measured the
#               host rather than the container — see ../../../shop/dmit.test.md.
#   geekbench5  cut. 129 MB, glibc-only, and the single reason for Debian. The
#               CPU tiles come from nq-bench now: sysbench, 7-Zip, openssl and
#               stress-ng, all in Alpine's repositories and all musl.
#
# What that costs is one thing and it is not small: Geekbench published to
# browser.geekbench.com and the page linked the result, so a buyer could check
# the score against the machine. Nothing in nq-bench has a public result page.
# The numbers are comparable between two pages made by this image and to
# nothing else.
#
# Everything the scripts would otherwise install mid-benchmark is baked in —
# it would both skew the disk numbers and fail on a box with no package
# mirror. A run downloads test payloads and nothing else.

# 3.24 rather than 3.22: `7zip` is not packaged before it.
ARG BASE=alpine:3.24

FROM ${BASE} AS solver
RUN apk add --no-cache gcc musl-dev
COPY pow.c /tmp/pow.c
# Static, so the runtime stage carries one file and no toolchain.
RUN gcc -O3 -static -o /nq-pow /tmp/pow.c && strip /nq-pow

FROM ${BASE}
ARG TARGETARCH

# What IP.sh, Net.sh and Hardware.sh each look for, by their Alpine names.
# Two things they ask for are deliberately absent:
#
#   stun        the NAT row, and it was cut. It measured the *host* — the
#               STUN request leaves through pasta and comes back from the
#               machine's public address — while the page printed it as a
#               fact about the container, whose reachability is decided by
#               which ports the host published and nothing else. Alpine has
#               no stun package and xykt's own fallback binary is glibc, so
#               keeping it would have meant writing one to print a number
#               that was misleading anyway.
#   geekbench5  glibc-only, 129 MB, and the reason this image was Debian.
#               The CPU tiles come from nq-bench now.
#
# Everything else here is what a check would otherwise `apk add` in the
# middle of a benchmark, which would both skew the disk numbers and fail on
# a box with no package mirror.
RUN apk add --no-cache \
      bash coreutils util-linux procps-ng grep sed gawk findutils \
      tar unzip zip xz \
      curl wget ca-certificates openssl jq bc \
      bind-tools iproute2 netcat-openbsd mtr iperf3 \
      dmidecode lm-sensors pciutils smartmontools fio sysbench \
      7zip stress-ng \
      imagemagick tzdata \
 && update-ca-certificates \
 # Net.sh looks for `convert`; ImageMagick 7 ships it as `magick` and would
 # try to install the package it already has if it cannot find one.
 && { command -v convert >/dev/null || ln -s "$(command -v magick)" /usr/bin/convert; }

# NextTrace is a static Go binary, so the same file works on either libc; it
# is pinned because a route name guessed wrong is worse than no route section.
ARG NEXTTRACE_VERSION=v1.3.7
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) arch=amd64 ;; \
      arm64) arch=arm64 ;; \
      *) echo "no nexttrace build for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/nexttrace \
      "https://github.com/nxtrace/NTrace-core/releases/download/${NEXTTRACE_VERSION}/nexttrace_linux_${arch}"; \
    chmod +x /usr/local/bin/nexttrace; \
    nexttrace --version

# Ookla's CLI. Net.sh will fetch this itself if it is missing, mid-run, over
# the link it is about to measure.
ARG SPEEDTEST_VERSION=1.2.0
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) arch=x86_64 ;; \
      arm64) arch=aarch64 ;; \
      *) echo "no speedtest build for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/speedtest.tgz \
      "https://install.speedtest.net/app/cli/ookla-speedtest-${SPEEDTEST_VERSION}-linux-${arch}.tgz"; \
    tar xzf /tmp/speedtest.tgz -C /usr/local/bin speedtest; \
    rm /tmp/speedtest.tgz; \
    speedtest --version

# The names for every AS on earth, so a hop through a network nobody
# hand-curated still says who it belongs to. RIPE publishes it as one plain
# text file, free and unauthenticated: 122,000 lines of "<asn> <name>, <cc>".
#
# It is kept gzipped and never parsed whole — `nq-shop build` greps out only
# the dozen or so AS numbers a run's traces actually touched. 6.2 MB of text
# for two in the image, and no 122,000-entry table anywhere near the renderer.
ARG ASNAMES_URL=https://ftp.ripe.net/ripe/asnames/asn.txt
RUN set -eux; \
    mkdir -p /usr/share/nodequality; \
    curl -fsSL -o /tmp/asn.txt "$ASNAMES_URL"; \
    test "$(wc -l < /tmp/asn.txt)" -gt 50000; \
    grep -q "^4134 " /tmp/asn.txt; \
    gzip -9 -c /tmp/asn.txt > /usr/share/nodequality/asn.txt.gz; \
    rm /tmp/asn.txt; \
    ls -l /usr/share/nodequality/asn.txt.gz

COPY --from=solver /nq-pow /usr/local/bin/nq-pow
COPY nq-shop nq-bench nq-wizard /usr/local/bin/
COPY normalize.jq page.default.json /usr/share/nodequality/

# What an SSH login lands on. The gateway execs `bash -l`, a login shell reads
# /etc/profile, and Alpine's /etc/profile sources this directory — so this is
# where the wizard gets to be the first thing a seller sees. The guards inside
# it are what keep SFTP, `ssh host command` and `hqnode exec` unaffected.
COPY profile-wizard.sh /etc/profile.d/nq-wizard.sh

RUN chmod +x /usr/local/bin/nq-shop /usr/local/bin/nq-bench /usr/local/bin/nq-wizard \
 && bash -n /usr/local/bin/nq-shop \
 && bash -n /usr/local/bin/nq-bench \
 && bash -n /usr/local/bin/nq-wizard \
 && sh -n /etc/profile.d/nq-wizard.sh \
 # The wizard is the whole user interface, so the one thing it cannot do is
 # fail to start. It reads shop.json through jq and nothing else, and a login
 # that lands on a stack trace is worse than one that lands on a shell.
 && grep -q 'nq-wizard' /etc/profile.d/nq-wizard.sh \
 # Every --argjson here has to match what normalize.jq binds. This check has
 # now caught three mismatches, in both directions; it is the cheapest test in
 # the image and the only one that runs at build time.
 && jq -n --argjson ip '[]' --argjson hw '[]' --argjson net '[]' --argjson route '[]' \
      --argjson bench '[]' --argjson asnames '{}' \
      --slurpfile shop /usr/share/nodequality/page.default.json \
      -f /usr/share/nodequality/normalize.jq > /dev/null

# hqnode execs /sbin/init and ignores ENTRYPOINT, so a container needs one to
# boot at all. Alpine has a /sbin/init — busybox — but its inittab hands off
# to OpenRC, which is not installed here and is not wanted: this image runs
# benchmarks, it is not a general-purpose box. So busybox's symlink is
# replaced by something that does the three things PID 1 must do here and
# nothing else. Under podman the ENTRYPOINT below still wins and this file is
# never reached.
#
# The link has to go before the file arrives. Alpine's /sbin/init is a symlink
# to /bin/busybox and COPY *follows* a symlink destination, so copying onto it
# writes through and overwrites busybox itself — which is /bin/sh, ls, and
# everything else in the image. The next RUN then fails with
# `exec: "/bin/sh": permission denied`, which does not sound like what it is.
RUN rm -f /sbin/init
COPY init /sbin/init
RUN chmod +x /sbin/init && sh -n /sbin/init && [ ! -L /sbin/init ] \
 && [ -x /bin/busybox ] && busybox true

# /data is the path an hqnode container keeps across a reinstall, so the
# edited page and the token that lets it be edited again live there.
ENV NQ_HOME=/data/nodequality

# What makes a reinstall the whole user interface: /sbin/init reads this on
# first boot, runs the benchmark and publishes, once. It has to be baked in
# because `hqnode run` has no --env and `hqnode exec` cannot reach a container
# that has not started yet. Overriding it means driving the run by hand.
ENV NQ_ENDPOINT=https://shop.hqno.de

VOLUME /data

ENTRYPOINT ["/usr/local/bin/nq-shop"]
CMD ["run"]
