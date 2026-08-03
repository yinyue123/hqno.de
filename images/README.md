# The system images

Twenty systems, three Dockerfiles, one public package:

```
ghcr.io/yinyue123/hqnode:debian-13
ghcr.io/yinyue123/hqnode:almalinux-9
ghcr.io/yinyue123/hqnode:ubuntu-24.04
…
```

They are **system** images, not app images: an init runs as PID 1, so a
container built from one has services, cron, a package manager and a working
`top`. `/data` exists and is the path a reinstall keeps.

The list lives in [`systems.yml`](systems.yml) and nowhere else. Adding a
system is one entry there — pick the recipe whose package manager and init it
uses, and the release becomes the `BASE` build-arg:

| Recipe | Systems | Package manager | PID 1 |
|---|---|---|---|
| `systemd-deb/` | Debian, Ubuntu | apt | systemd |
| `systemd-rpm/` | AlmaLinux, Rocky, CentOS, Fedora | dnf, or yum on CentOS 7 | systemd |
| `openrc-alpine/` | Alpine | apk | busybox init + OpenRC |

## What an image must actually carry

Short, and worth knowing before writing a fourth recipe. The agent needs:

- **an entrypoint in the image config** — `CMD ["/sbin/init"]`. A container
  whose config carries neither entrypoint nor cmd is refused at start.
- **`/bin/sh`** — every SSH session is `sh -c` inside the namespace, and a
  login shell is `command -v bash || command -v sh`.
- **`su`**, only for containers given a non-root user: the gateway uses it so
  the login gets that user's shell, groups and environment from the
  container's own `/etc/passwd`.
- **something called `sftp-server` on PATH** — the gateway falls back to
  Debian's `/usr/lib/openssh/sftp-server`, so anything that puts it elsewhere
  needs a symlink or SFTP is a dead subsystem.
- **the right `STOPSIGNAL`** — see below. This is the one that silently
  turns "stop" into something else.

It does *not* need a running sshd: the gateway authenticates on the host and
enters the namespace, so nothing inside has to be in sync with it. It does not
need a `/etc/resolv.conf` either — the agent binds one in, creating the target
if the image has none.

**sshd is installed and switched off**, in all three recipes. Every one of them
used to boot with it running, and on the systemd two that was nobody's
decision: Debian's `openssh-server` postinst and the RPM family's systemd
preset both enable the unit on install. It was a few MB of a box sold with 128
and a socket listening for a login that never arrives that way. The package
stays — the gateway's SFTP subsystem runs the image's own `sftp-server`, and on
the RPM side that file is inside `openssh-server` itself — and a holder who
wants their own sshd on a port they own turns it on with one command:

| | |
|---|---|
| Debian, Ubuntu | `systemctl enable --now ssh` |
| AlmaLinux, Rocky, CentOS, Fedora | `systemctl enable --now sshd` |
| Alpine | `rc-update add sshd default && rc-service sshd start` |

Disabled rather than masked, so that stays one command. On Alpine the host-key
service is left in the default runlevel for the same reason: `ssh-keygen -A`
only makes what is missing, so it costs one boot and saves the holder a second
step.

## Things that bit, and how they are handled

- **`STOPSIGNAL` is not a detail on the Alpine side.** busybox init reads
  SIGTERM as *reboot*: it runs the shutdown scripts and then
  `reboot(RB_AUTOBOOT)`, which the kernel delivers to the agent as SIGHUP —
  and SIGHUP is exactly how the agent recognises "this container rebooted
  itself", so it starts it again. Every stop would be a restart. `SIGUSR2` is
  poweroff: same shutdown, then `RB_POWER_OFF`, which arrives as SIGINT and
  ends the container. Measured on 3.24, one container per signal:

  | signal | what happened | exit |
  |---|---|---|
  | `SIGUSR2` | clean shutdown, gone in 4s | 130 (SIGINT) |
  | `SIGTERM` | clean shutdown, gone in 4s — but as a *reboot* | 129 (SIGHUP) |
  | `SIGRTMIN+3` | ignored; would be SIGKILLed at the timeout | still running |

  systemd images are the mirror image of this and declare `SIGRTMIN+3`, which
  is also what the agent defaults to for a system container when an image
  declares nothing — so an Alpine image that forgets `STOPSIGNAL` hangs for
  thirty seconds on every stop.
- **OpenRC needs to be told it is in a container.** `rc_sys="lxc"` in
  `/etc/rc.conf` stops it starting the hardware services that cannot work
  here, and `rc_provide="loopback net"` stops the services that want a network
  from waiting for a network script we deliberately do not run — pasta has
  already configured the interface before the container's first instruction.
  The getty lines come out of `/etc/inittab` for the same reason: there are no
  consoles, and busybox would respawn six failing processes forever.
- **Alpine is musl, not glibc.** Anything shipped as a prebuilt glibc binary —
  some vendor agents, some language runtimes, a good deal of proprietary
  software — will not run. That is the trade for the small idle footprint, and
  the blurb in `systems.yml` says so.

- **End of life moves the mirrors, and the date is not knowable in advance.**
  16.04 and 18.04 are still on `archive.ubuntu.com` under ESM; Debian 11 leaves
  `deb.debian.org` for `archive.debian.org` when its LTS window closes. So the
  deb Dockerfile *tries*: it updates, checks whether a package can actually be
  resolved, and only then rewrites to the archive host and retries. It does not
  guess from the codename, because that guess ages badly — and `apt-get update`
  exits 0 even when every index 404s, so the check has to be a resolve.
- **CentOS 7 is retired.** `mirror.centos.org` is gone; the rpm Dockerfile
  points its repo files at `vault.centos.org` before the first `yum` call.
- **`curl` is not installed on the RPM side.** These bases ship `curl-minimal`,
  and asking for `curl` makes dnf stop on a conflict it will not resolve
  without `--allowerasing`.
- **AlmaLinux 10 and CentOS Stream 10 need an x86-64-v3 CPU** — roughly Haswell
  and later. That is the distro's own baseline. On an older host they fail at
  the first glibc call with `Fatal glibc error: CPU does not support
  x86-64-v3`, which reads like a broken image and is not one.
- **arm64 is emulated** via QEMU. It is slow and it is fine — this runs weekly.
  CentOS 7, Ubuntu 16.04 and 18.04 are amd64-only on purpose: their arm64
  packages live on ports mirrors that have moved more than once.

## Building one by hand

```sh
podman build --build-arg BASE=debian:13-slim -t hqnode:debian-13 systemd-deb
podman build --build-arg BASE=almalinux:9    -t hqnode:almalinux-9 systemd-rpm
```

## catalog.json — how a panel learns about all this

The workflow's third job reads the digests back from the registry and writes
[`catalog.json`](catalog.json): id, name, ref, digest, arch, size and blurb per
system. A panel fetches that file at boot and every few hours and fills its
market from it, so a system added here shows up in every panel without anyone
running anything.

```json
{"schema": 1, "package": "ghcr.io/yinyue123/hqnode",
 "images": [{"id": "img_debian13", "name": "Debian 13",
             "ref": "ghcr.io/yinyue123/hqnode:debian-13",
             "digest": "sha256:…", "arch": ["amd64","arm64"],
             "size_bytes": 50232621, "blurb": "Trixie. …"}]}
```

Two rules it lives by:

- **Every entry carries a digest.** The panel never hands an agent a bare tag —
  a tag drifts between the panel deciding and the host pulling — so an entry
  without one is refused, and the whole document with it.
- **Digests are read back from the registry, not passed out of the build.** A
  build that failed leaves its tag pointing at last week's good image, and that
  is what the catalog should keep saying.

It is committed by the workflow. The push uses `GITHUB_TOKEN`, which does not
trigger workflows, so writing to `images/` from a job that watches `images/`
cannot loop.
