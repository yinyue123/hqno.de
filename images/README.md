# The system images

Eighteen systems, two Dockerfiles, one public package:

```
ghcr.io/yinyue123/hqnode:debian-13
ghcr.io/yinyue123/hqnode:almalinux-9
ghcr.io/yinyue123/hqnode:ubuntu-24.04
…
```

They are **system** images, not app images: systemd is PID 1, so a container
built from one has `systemctl`, cron, a package manager and a working `top`.
`/data` exists and is the path a reinstall keeps.

The list lives in [`../.github/workflows/images.yml`](../.github/workflows/images.yml)
and nowhere else. Adding a system is one row in that matrix — pick the family
whose package manager it uses, and the release becomes the `BASE` build-arg:

| Dockerfile | Family | Package manager |
|---|---|---|
| `systemd-deb/` | Debian, Ubuntu | apt |
| `systemd-rpm/` | AlmaLinux, Rocky, CentOS, Fedora | dnf, or yum on CentOS 7 |

## Things that bit, and how they are handled

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

## The panel's side

The panel offers these under **Images → Market**, and `panel catalog seed`
writes the starter list by resolving each tag's digest from the registry. The
panel never hands an agent a bare tag — a tag drifts between the panel deciding
and the host pulling — so what a container is actually built from is always
`ghcr.io/yinyue123/hqnode@sha256:…`.

That means the two lists have to agree by hand: a system added here is a row in
the workflow *and* an entry in `server/cmd/panel/systems.go` over in the
product repo. When they disagree, the seed writes the entry as `pending` with
the resolution error on it, rather than pretending it is ready.
