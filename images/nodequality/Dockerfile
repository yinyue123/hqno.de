# The image that turns a machine into a sales page.
#
# It runs the three xykt checks NodeQuality wraps, folds their JSON plus a
# price list into one document, pays the endpoint's proof of work and posts it.
# What comes back is a URL.
#
# Debian, and for the same reason NodeQuality chroots into a Debian rootfs:
# two of the four tools these checks reach for are prebuilt glibc binaries.
# The earlier Alpine base cost the page four sections, because a check that
# cannot find its tool does not fail — it prints NoData and carries on:
#
#   nexttrace   the nine backhaul routes; without it every line reads
#               "Unknown -> NoData" and the route sections are empty
#   speedtest   Ookla's CLI, which is the domestic speedtest table
#   stun        NAT type, in the local-policy card
#   geekbench5  the CPU scores. This is the one that forces the base: it is
#               glibc and segfaults under musl even with gcompat installed
#
# All four are baked in below, along with everything the scripts would
# otherwise `apt-get` mid-benchmark — which would both skew the disk numbers
# and fail on a box with no package mirror. A run downloads test payloads and
# nothing else.

ARG BASE=debian:trixie-slim

FROM ${BASE} AS solver
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*
COPY pow.c /tmp/pow.c
# Static, so the runtime stage carries one file and no toolchain.
RUN gcc -O3 -static -o /nq-pow /tmp/pow.c && strip /nq-pow

FROM ${BASE}
ARG TARGETARCH

# Taken from what IP.sh, Net.sh and Hardware.sh each install when they find
# themselves on Debian — including `stun`, which only Net.sh's Debian branch
# asks for, and which is why the NAT row was blank.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash coreutils util-linux procps grep sed gawk findutils \
      tar unzip zip xz-utils \
      curl wget ca-certificates openssl jq bc \
      dnsutils iproute2 netcat-openbsd mtr-tiny iperf3 stun-client \
      dmidecode lm-sensors pciutils smartmontools fio sysbench \
      imagemagick tzdata \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
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

# Geekbench 5 is x86_64-only on Linux. Shipping it is necessary but not
# sufficient: Hardware.sh gates the whole test on privacy mode at the call
# site — `mode_privacy -eq 0 && test_cpu_gb5` — not on whether the binary is
# there. nq-shop is what drops -p for the hardware check; this only makes
# sure that when it does, nothing is downloaded mid-benchmark.
ARG GEEKBENCH_VERSION=5.5.1
RUN set -eux; \
    if [ "$TARGETARCH" = "amd64" ]; then \
      curl -fsSL -o /tmp/geekbench.tgz \
        "https://cdn.geekbench.com/Geekbench-${GEEKBENCH_VERSION}-Linux.tar.gz"; \
      tar xzf /tmp/geekbench.tgz -C /usr/local/bin; \
      rm /tmp/geekbench.tgz; \
      ln -s "/usr/local/bin/Geekbench-${GEEKBENCH_VERSION}-Linux/geekbench5" /usr/local/bin/geekbench5; \
      geekbench5 --version; \
    else \
      echo "Geekbench 5 has no $TARGETARCH build for Linux; the CPU tiles will be sysbench's"; \
    fi

COPY --from=solver /nq-pow /usr/local/bin/nq-pow
COPY nq-shop /usr/local/bin/nq-shop
COPY normalize.jq page.default.json /usr/share/nodequality/
RUN chmod +x /usr/local/bin/nq-shop \
 && bash -n /usr/local/bin/nq-shop \
 && jq -n --argjson ip '[]' --argjson hw '[]' --argjson net '[]' --argjson trace '[]' \
      --slurpfile shop /usr/share/nodequality/page.default.json \
      -f /usr/share/nodequality/normalize.jq > /dev/null

# /data is the path an hqnode container keeps across a reinstall, so the
# edited page and the token that lets it be edited again live there.
ENV NQ_HOME=/data/nodequality
VOLUME /data

ENTRYPOINT ["/usr/local/bin/nq-shop"]
CMD ["run"]
