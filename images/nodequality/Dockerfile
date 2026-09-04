# The image that turns a machine into a sales page.
#
# It runs the three xykt checks NodeQuality wraps, folds their JSON plus a
# price list into one document, pays the endpoint's proof of work and posts it.
# What comes back is a URL.
#
# Alpine, and not the Debian rootfs NodeQuality downloads, for one reason:
# NodeQuality chroots into a throwaway Debian so the tests leave no trace on
# the host. A container *is* that throwaway system — it has no host to dirty,
# and the chroot it would need (`mount -t proc`) wants CAP_SYS_ADMIN, which an
# app container does not get. So the sandbox is the container and the base can
# be the small one.
#
# The cost of musl is Geekbench: it is a prebuilt glibc binary and will not
# run here. The checks are therefore run in their fast mode, which measures
# CPU with sysbench instead and never downloads it. Everything else the xykt
# scripts want is an apk away, and all of it is baked in below so that a run
# on a metered box downloads test payloads and nothing else.

ARG BASE=alpine:3.22

FROM ${BASE} AS solver
RUN apk add --no-cache gcc musl-dev
COPY pow.c /tmp/pow.c
# Static, so the runtime stage carries one file and no toolchain.
RUN gcc -O3 -static -o /nq-pow /tmp/pow.c && strip /nq-pow

FROM ${BASE}

# Three package lists, taken from what IP.sh, Net.sh and Hardware.sh each
# install when they find themselves on Alpine. Pre-installing them is what
# keeps the scripts from running `apk add` mid-benchmark, which would both
# skew the disk numbers and fail on a box with no package mirror.
RUN apk add --no-cache \
      bash coreutils util-linux procps grep sed gawk findutils tar unzip zip \
      curl wget ca-certificates openssl jq bc \
      bind-tools iproute2 netcat-openbsd mtr iperf3 \
      dmidecode lm-sensors pciutils smartmontools fio sysbench \
      imagemagick gcompat libstdc++ tzdata \
 && update-ca-certificates \
 # ImageMagick 7 ships `magick`; Net.sh looks for `convert` and would try to
 # install the package it already has if it cannot find one.
 && { command -v convert >/dev/null || ln -s "$(command -v magick)" /usr/bin/convert; }

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
