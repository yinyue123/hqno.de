# Building your own image

The reinstall dialog has a box that wants a full registry reference —
`ghcr.io/you/thing:tag` — and the question under it is *what do I put in
there*. The same box is on the new-container form, so it has two doors: the
owner of a machine can build a container from a reference, and whoever holds
one can bring a reference by reinstalling.

The answer is the same at both doors. You need **an image the machine can pull,
that boots as a system container**. That is one `Dockerfile`, one push, and one
paste, and the shortest version of it fits on a screen.

- [1. The five-minute version](#_1-the-five-minute-version)
- [2. What the machine actually requires](#_2-what-the-machine-actually-requires)
- [3. What our images already carry](#_3-what-our-images-already-carry)
- [4. Starting from something that is not ours](#_4-starting-from-something-that-is-not-ours)
- [5. Building it in GitHub Actions](#_5-building-it-in-github-actions)
- [6. Getting the machine to pull it](#_6-getting-the-machine-to-pull-it)
- [7. Installing it, and what it costs](#_7-installing-it-and-what-it-costs)
- [8. Driving it from GitHub Actions](#_8-driving-it-from-github-actions)
- [9. Checking it before you paste it](#_9-checking-it-before-you-paste-it)
- [10. When it does not boot](#_10-when-it-does-not-boot)
- [11. Getting an AI to write it for you](#_11-getting-an-ai-to-write-it-for-you)

---

## 1. The five-minute version

Start from the image your container is already running. Everything the machine
requires is in it, so your `Dockerfile` only has to add your own software.

```dockerfile
FROM ghcr.io/yinyue123/hqnode:alpine-3.24

RUN apk add --no-cache nodejs npm
COPY app/ /opt/app/
RUN cd /opt/app && npm ci --omit=dev

# A service, so it starts when the container boots. Your CMD would not —
# see §2.
RUN printf '%s\n' \
      '#!/sbin/openrc-run' \
      'description="my app"' \
      'command=/usr/bin/node' \
      'command_args="/opt/app/server.js"' \
      'command_background=yes' \
      'pidfile=/run/app.pid' \
      'output_log=/var/log/app.log' \
      'error_log=/var/log/app.log' \
      'depend() { need net; }' \
      > /etc/init.d/app; \
    chmod +x /etc/init.d/app; \
    rc-update add app default
```

Build it for the machine's architecture and push it somewhere the machine can
reach:

```sh
echo "$GHCR_TOKEN" | docker login ghcr.io -u you --password-stdin
docker buildx build --platform linux/amd64 -t ghcr.io/you/myapp:v1 --push .
```

Then paste `ghcr.io/you/myapp:v1` into **An image of my own** and confirm. A
minute later the container is running your image, with `/data` still where you
left it.

Everything after this is detail: what the machine requires (§2), what you
inherited by starting from ours (§3), how to build it in CI instead of on your
laptop (§5), and how to make a push to your repository end in a running
container (§8).

---

## 2. What the machine actually requires

Short list, and every line of it is enforced rather than assumed.

| What | Why |
|---|---|
| **`/sbin/init`**, executable, able to be PID 1 | Every container the panel creates is a *system* container, and its PID 1 is `/sbin/init`. This is the one people get wrong |
| **`/bin/sh`** | Every SSH session is `sh -c` inside the container. A login shell is `command -v bash \|\| command -v sh` |
| **the machine's architecture** in the image index | `linux/amd64` on an amd64 host. An index with no matching platform is refused, not silently substituted |
| **a `STOPSIGNAL` the init understands** | Otherwise every stop is a 30-second wait followed by a kill. See below |
| `su` | Only for a container whose shell login is not root: the gateway uses it so the login gets that user's shell, groups and environment |
| something named `sftp-server` on `PATH` | Only if you want SFTP and `scp`. The gateway falls back to Debian's `/usr/lib/openssh/sftp-server`, so anything that keeps it elsewhere needs a symlink |

And the things it does **not** need, each of which somebody has tried to put in
an image for us:

- **no sshd.** An hqnode login is the host's gateway entering your container's
  namespace, not a connection to a daemon inside it. Nothing in the image has
  to be in sync with the machine's SSH.
- **no `/etc/resolv.conf`** and no `/etc/hostname`. Both are bound in, and the
  target is created if the image has none.
- **no mountpoint for `/data`.** It is created if it is missing — shipping the
  directory is tidiness, not a requirement.
- **no users, no keys, no passwords.** The shell login is the machine's, and it
  survives a reinstall precisely because it was never in the image.

### Your `CMD` is not what runs

This is the trap. A container the panel creates is a system container, so its
entrypoint is `/sbin/init` **whatever your image's `CMD` or `ENTRYPOINT` says**,
and that is also recomputed on every reinstall. Two consequences:

- an image built the ordinary app-container way — `CMD ["node", "server.js"]`,
  no init — is downloaded, unpacked, and then fails to start, because there is
  no `/sbin/init` to exec. You get a container that exists and does not run;
- an image that *has* an init but starts your program only from `CMD` boots
  into a box where your program is not running.

So your program has to be started by the init: an OpenRC service on Alpine
(§1), a systemd unit on the others.

```dockerfile
# The systemd version of the same thing
RUN printf '%s\n' \
      '[Unit]' 'Description=my app' 'After=network.target' \
      '[Service]' 'ExecStart=/usr/bin/node /opt/app/server.js' 'Restart=always' \
      '[Install]' 'WantedBy=multi-user.target' \
      > /etc/systemd/system/app.service; \
    systemctl enable app
```

You *can* make `/sbin/init` your own program — it is only a path — but then it
is PID 1 with everything that implies: no services, no cron, no `systemctl`,
you reap your own zombies, and you handle the stop signal yourself or every
stop is a kill. The panel will still show the container as a system container,
because that is what it created. If that is what you want, declare
`STOPSIGNAL SIGTERM` and trap it.

### The platform

The agent resolves `linux/<the machine's architecture>` out of your image index
explicitly. It never takes the first manifest, and an index without a match is
an error rather than a surprise.

Most machines are amd64. If you do not know, the container page names the
architecture, and building both costs one line:
`--platform linux/amd64,linux/arm64`. On GitHub Actions arm64 is emulated
through QEMU — correct, and slow enough to notice.

### The stop signal

The init decides which signal means "shut down", and getting it wrong is
invisible until something takes 30 seconds to stop.

| Init | Signal | What the wrong one does |
|---|---|---|
| systemd | `SIGRTMIN+3` | `SIGTERM` reboots it |
| busybox init + OpenRC (Alpine) | `SIGUSR2` | `SIGTERM` is *reboot*: the container shuts down and is started again, so every stop is a restart |
| your own PID 1 | whatever you trap | Unhandled means a 30-second wait and a `SIGKILL` |

Our images declare theirs, so an image that starts `FROM` one of them inherits
it and there is nothing to do. If you build from a bare base, declare it:

```dockerfile
STOPSIGNAL SIGRTMIN+3    # systemd
STOPSIGNAL SIGUSR2       # busybox init / OpenRC
```

**One thing worth knowing before you mix families.** The stop signal is recorded
when the container is *created*, from the image it was created from, and a
reinstall does not rewrite it. So a container that was created on Debian and
reinstalled into an Alpine-based image of yours is still stopped with
`SIGRTMIN+3`, which busybox init ignores — every stop is then the 30-second
wait. Staying in the same family as the image the container was created from
avoids it; otherwise ask your host to recreate the container from your
reference, which does read the signal out of your image.

---

## 3. What our images already carry

Twenty systems, three recipes, one public package —
`ghcr.io/yinyue123/hqnode:<tag>`. The whole build is in
[the site's own repository](https://github.com/yinyue123/hqno.de/tree/main/images),
and it is the worked example this page keeps pointing at.

| Recipe | Systems | Package manager | PID 1 | Size |
|---|---|---|---|---|
| [`openrc-alpine`](https://github.com/yinyue123/hqno.de/blob/main/images/openrc-alpine/Dockerfile) | Alpine 3.24, 3.23 | apk | busybox init + OpenRC | ~13 MB |
| [`systemd-deb`](https://github.com/yinyue123/hqno.de/blob/main/images/systemd-deb/Dockerfile) | Debian, Ubuntu | apt | systemd | ~45–60 MB |
| [`systemd-rpm`](https://github.com/yinyue123/hqno.de/blob/main/images/systemd-rpm/Dockerfile) | AlmaLinux, Rocky, CentOS, Fedora | dnf, yum on CentOS 7 | systemd | ~90–125 MB |

What each of them adds on top of the distribution's own base image, and — the
question this page is here for — whether you actually need it:

| What is added | Needed? |
|---|---|
| an init: `systemd systemd-sysv dbus`, or `openrc busybox-openrc busybox-suid` | **Yes.** This is what `/sbin/init` is |
| `bash`, and `/bin/sh` from the base | `sh` yes, `bash` is comfort — but a login shell prefers it and people expect it |
| `openssh-sftp-server` (in `openssh-server` on the RPM side), plus a symlink so `sftp-server` is on `PATH` | Only for SFTP and `scp` |
| `shadow` / `passwd`, `sudo`, `su` | `su` only for a non-root login. `passwd` is what the password shim wraps |
| cron: `cron`, `cronie`, `crond` | No |
| `rsyslog` / `syslog`, `logrotate` | No |
| `procps` / `procps-ng`, `iproute2`, `iputils`, `curl`, `ca-certificates`, `less`, `nano`, `tzdata` | No. This is the difference between a container and something that feels like a machine — `top` and `free` printing what a person expects, a working `ping`, a `curl` that is there when you reach for it |
| `STOPSIGNAL` | **Yes** (§2) |
| container-shaped init settings: `rc_sys="lxc"`, `rc_provide="loopback net"`, no gettys in `/etc/inittab`; or systemd with the hardware units masked | **Effectively yes.** Without them the init tries to start hardware services that cannot work here, fails loudly, and a working container looks broken in `rc-status` or `systemctl status` |
| sshd installed and **switched off** | No. It is there so a holder who wants their own on a port they own is one command away |
| a boot-time package-index refresh, at most once a day | No. It is why `apk add nginx` works at a fresh login instead of saying the package does not exist |
| `app-setup` — the software manager, its recipes and `/etc/helppage` | No. §4 has how to take it with you anyway |
| the shims that answer to `passwd`, `poweroff`, `halt`, `dashboard`, `domain`, `reinstall`, `helppage` on `PATH` | No — but a password changed with the real `passwd` alone never reaches the SSH gateway, so dropping the shim means the shell password can only be changed from the panel |
| `/data` and a README in it | No. The disk is mounted whether or not the directory exists |

Everything in that table with a **No** is yours to drop. Nothing in it is
inspected by the panel: a container built from your image is a system container
because of how it was created, not because of anything the image declares.

---

## 4. Starting from something that is not ours

`FROM ghcr.io/yinyue123/hqnode:alpine-3.24` is the recommendation and §1 is why
— every requirement in §2 is already met and every convenience in §3 comes with
it. But it is not the only way, and there are two honest reasons to build from a
distribution base yourself: you want a system we do not publish, or you want to
know exactly what is in the box.

If that is you, read the recipe for the family you are on — they are three
files, heavily commented, and every comment in them is a thing that went wrong
once:

- [`openrc-alpine/Dockerfile`](https://github.com/yinyue123/hqno.de/blob/main/images/openrc-alpine/Dockerfile)
- [`systemd-deb/Dockerfile`](https://github.com/yinyue123/hqno.de/blob/main/images/systemd-deb/Dockerfile)
- [`systemd-rpm/Dockerfile`](https://github.com/yinyue123/hqno.de/blob/main/images/systemd-rpm/Dockerfile)

The minimum, on a Debian-family base, is about this much:

```dockerfile
FROM debian:13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-sftp-server \
 && rm -rf /var/lib/apt/lists/*

# Hardware units are meaningless in a container and fail loudly at boot.
RUN systemctl mask systemd-udevd.service systemd-udevd-kernel.socket \
      systemd-udevd-control.socket systemd-modules-load.service \
      sys-kernel-debug.mount sys-kernel-config.mount \
      systemd-journald-audit.socket

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
```

`CMD` there is documentation rather than instruction — the machine execs
`/sbin/init` regardless (§2) — but keeping it true means the image also does
the sensible thing under `docker run`, which is where you will test it.

**Taking `app-setup` with you.** It is one static binary and a directory of
shell scripts, so it copies cleanly out of any of our images:

```dockerfile
FROM ghcr.io/yinyue123/hqnode:alpine-3.24 AS hq

FROM debian:13-slim
COPY --from=hq /bin/app-setup       /bin/app-setup
COPY --from=hq /usr/lib/app-setup/  /usr/lib/app-setup/
COPY --from=hq /etc/app-setup/      /etc/app-setup/
RUN mkdir -p /etc/app-setup/local /etc/app-setup/params /etc/app-setup/secrets \
 && chmod 0700 /etc/app-setup/secrets \
 && app-setup doctor >/dev/null
```

The binary is built against musl and linked statically, which is exactly why
one copy runs on CentOS 7 and Alpine alike. Adding your own software to its
menu is a separate page: [adding your own software](app-setup-sources.md).

---

## 5. Building it in GitHub Actions

Nothing here needs a runner — `docker buildx build --push` from a laptop
produces the same image. CI is worth it for the reason it is always worth it:
the image that gets installed is the one that was built from what is on `main`,
by a job you can read afterwards.

This is a complete workflow for your own repository. Put it in
`.github/workflows/image.yml`:

```yaml
name: image

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write          # the only credential needed: GITHUB_TOKEN
    steps:
      - uses: actions/checkout@v4

      # Only needed if you build linux/arm64 on an amd64 runner.
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          push: true
          # Attestation manifests add an entry per platform whose own
          # platform is unknown/unknown. Nothing here needs them, and a
          # boring manifest is one less thing to resolve wrongly.
          provenance: false
          sbom: false
          tags: |
            ghcr.io/${{ github.repository_owner }}/myapp:latest
            ghcr.io/${{ github.repository_owner }}/myapp:${{ github.sha }}

      - run: echo "${{ steps.build.outputs.digest }}" >> $GITHUB_STEP_SUMMARY
```

Four things in there are worth keeping whatever else you change:

- **`packages: write` and `GITHUB_TOKEN`.** No secret to create, no token to
  rotate. It is enough to push to `ghcr.io/<your account>/…`.
- **`platforms`.** One line, and it is the difference between an image the
  machine boots and one it refuses (§2). Drop `setup-qemu-action` if you build
  amd64 only.
- **Two tags: a moving one and an immutable one.** `:latest` is convenient and
  `:<sha>` is what you paste when you want to know precisely what is installed
  — a tag can move between the panel deciding and the host pulling.
- **The digest in the summary.** `steps.build.outputs.digest` is the exact
  image. §8 installs by digest, which is the only way to be certain the box is
  running what this job built.

**Then make the package public, once, by hand.** A new package on GHCR is
private, and a private package is a `401` when the machine tries to pull it.
Go to the package's page → **Package settings** → **Change visibility** →
Public. Nothing in the workflow can do this for you. If it must stay private,
see §6.

### How the images on this site are built

If you want a pipeline rather than a Dockerfile, ours is worth reading: twenty
systems from three Dockerfiles and one list, in
[`.github/workflows/images.yml`](https://github.com/yinyue123/hqno.de/blob/main/.github/workflows/images.yml).

Three jobs, and the shape is reusable:

| Job | What it does |
|---|---|
| `list` | reads [`images/systems.yml`](https://github.com/yinyue123/hqno.de/blob/main/images/systems.yml) with `yq` and turns it into a build matrix, so adding a system is one entry in one file |
| `build` | one matrix leg per system, `fail-fast: false` so one distro's dead mirror does not take the other nineteen with it. Each leg pushes `:<tag>` and `:<tag>-<run number>` |
| `catalog` | reads the digests **back from the registry** and commits `images/catalog.json`, which every panel fetches to fill its market |

Two decisions in it are load-bearing and would be load-bearing in yours too.
The build context is `images/` rather than the recipe's own directory, because
all three Dockerfiles copy the same `app-setup` tree and a context cannot reach
above itself. And digests are read back from the registry instead of being
passed out of the build, because a build that failed leaves its tag pointing at
last week's good image — which is exactly what the catalog should keep saying.

It also runs weekly on a cron, so a tag picks up its distribution's security
updates. Containers already running are untouched: new bytes reach a holder
only on reinstall.

---

## 6. Getting the machine to pull it

**The machine pulls, not the panel and not your laptop.** The panel is one
process for a whole fleet and never carries image bytes; the reference you
paste is forwarded to the host, which fetches it directly from the registry. So
the test is not "can I pull this", it is "can that machine pull this".

| Where it lives | What happens |
|---|---|
| a public package on GHCR, Docker Hub, Quay… | it works, and this is the recommended case |
| a private registry the machine has credentials for | it works. Credentials live in `/etc/hqnode/registry.json` on the machine, which is its operator's file |
| a private registry nobody told the machine about | `401`/`403` at pull time, and the reinstall fails without touching your container |
| a registry only reachable from your own network | nothing to do — the machine is not on your network |

A holder cannot supply registry credentials: there is nowhere in the panel to
put them, deliberately, because they would be one tenant's secret sitting on
another person's machine. If your image has to stay private, ask whoever runs
the machine to add it to that file — for them it is one entry and a restart.

Reference syntax, since the panel checks it before anything else happens:

```
ghcr.io/you/myapp:v1                          a tag
ghcr.io/you/myapp@sha256:<64 hex characters>  pinned to exactly one image
docker.io/library/alpine:3.20                 Docker Hub, spelled in full
```

No scheme (`https://…` is refused with that sentence), no spaces or quotes, no
empty tag after the colon, and a pinned digest has to be `sha256:` plus 64 hex
characters. Whitespace around a reference pasted out of a terminal is trimmed.

---

## 7. Installing it, and what it costs

Three doors to the same thing. The reinstall dialog, standing on the tab that
takes a reference:

<FigScreen :tabs="['An image of my own', 'The market', 'An archive on this host']" :lines="[
  [{ t: 'Wipes /. /data is a separate disk and is kept.', tone: 'mute' }],
  ['Image reference', { f: 'ghcr.io/you/myapp:v1', fw: 260 }],
  [{ t: 'What it downloads counts against this container’s traffic.', tone: 'mute', face: 'small' }],
  ['Type web-1 to confirm', { f: '' }],
  { align: 'right', cols: [{ b: 'Cancel' }, { b: 'Reinstall, keep /data' }] },
]" />

or from a shell inside the container:

```
reinstall ref ghcr.io/you/myapp:v1
```

or from the API, which is §8:

```sh
curl -sS --fail-with-body -b jar.txt -X POST "$PANEL/me/containers/$CID/reinstall" \
  -H 'content-type: application/json' \
  -d '{"ref":"ghcr.io/you/myapp:v1","confirm":"web-1"}'
```

**Two things have to be true before the tab is even there.** The machine's
policy has to allow images tenants bring (`allow_user_images`), and the
container has to have a disk of its own — an image only one container can see
needs somewhere only that container can see, and a container sold without a
disk size has nowhere. The dialog says which of the two is missing, and both are
your host's to change.

Then what it costs, which the dialog can only say in one line:

| | |
|---|---|
| **Downloaded** | in full, by the machine, **every time you reinstall**. Nothing is cached between reinstalls — that is the price of it being private |
| **Charged** | every byte, as this container's inbound traffic. Exactly what crossed the wire, not what the manifest advertised |
| **Stored** | expanded into this container's own disk. Nobody else on the machine is offered it, and the host keeps no copy |
| **Free** | if the machine already holds that exact digest, it installs from its own copy: nothing downloads, nothing is charged, and the reply says so |
| **Kept** | `/data`, your shell login and password, the address and port you SSH to, your domains, your public ports, your traffic counter, your expiry date |
| **Lost** | everything else under `/`, including anything `app-setup` installed and the secrets it generated in `/etc/app-setup/secrets` |

The last row is the one that costs people an afternoon. Copy those out before
you reinstall, not after.

**The quota trap, which is worth one paragraph of its own.** The download is
charged after the reinstall succeeds. If it pushes the container over its
traffic quota, the container is suspended — and a suspended container refuses
to be reinstalled, so you cannot wipe your way back into service. It clears when
the quota window rolls over or when your host raises the limit. A 400 MB image
reinstalled a few times a day on a small quota gets there faster than people
expect, which is one more argument for §8's second recipe.

---

## 8. Driving it from GitHub Actions

Two different jobs, and picking the wrong one is the commonest waste on this
whole page.

| | Reinstall from your reference | Ship the program over SSH |
|---|---|---|
| What moves | the whole image, tens or hundreds of MB | your build output, usually kilobytes |
| Traffic | charged, every time | charged the same way — an upload is inbound traffic, and the gateway counts it — but it is kilobytes |
| What survives | `/data` and nothing else | everything; nothing is wiped |
| How long | a minute or two, with the box down for part of it | seconds |
| Right for | changing the *system*: a new distribution, new packages, a rebuilt base | changing the *program*: the thing you edit every day |

The rule of thumb: **an image is for the system, `rsync` is for the program.**
Reinstall on a release, deploy on a commit.

### Reinstall from your reference

Build the image, then install exactly what was built, by digest — so a tag that
moved between the job and the pull cannot install something else. These steps
go in the same job as §5's build and after it: `steps.build.outputs.digest` is
that step's output.

```yaml
      - name: Sign in to the panel
        run: |
          curl -sS --fail-with-body -c "$RUNNER_TEMP/jar" "$PANEL/auth/login" \
            -H 'content-type: application/json' \
            -d "$(jq -nc --arg u "${{ secrets.PANEL_USER }}" \
                         --arg p "${{ secrets.PANEL_PASSWORD }}" \
                         '{identifier:$u,password:$p}')" > /dev/null

      - name: Reinstall from what we just built
        run: |
          REF="ghcr.io/${{ github.repository_owner }}/myapp@${{ steps.build.outputs.digest }}"
          curl -sS --fail-with-body -b "$RUNNER_TEMP/jar" \
            -X POST "$PANEL/me/containers/$CID/reinstall" \
            -H 'content-type: application/json' \
            -d "$(jq -nc --arg r "$REF" --arg c "$NAME" '{ref:$r,confirm:$c}')"

      - name: Wait for it
        run: |
          for i in $(seq 1 60); do
            state=$(curl -sS -b "$RUNNER_TEMP/jar" "$PANEL/me/containers/$CID" \
                    | jq -r '.container.container.live.run_state')
            echo "run_state=$state"
            [ "$state" = "running" ] && exit 0
            sleep 10
          done
          echo "container did not come back"; exit 1

      - name: Sign out
        if: always()
        run: |
          curl -sS -b "$RUNNER_TEMP/jar" -X POST "$PANEL/auth/logout" > /dev/null
          rm -f "$RUNNER_TEMP/jar"
```

`PANEL` is `https://hqno.de/api/v1`, `CID` is the container id from its URL, and
`NAME` is the container's own name — `confirm` has to equal it, not `"yes"`.
Store the panel password as a secret and log in each run; never store the
cookie, which is a seven-day key whose age you cannot see. `--fail-with-body`
matters: plain `curl` exits 0 on a refusal, and a job that ignores the status
puts a green tick over a container that never came back. Watch a long download
with `GET /me/containers/{cid}/progress`. The whole reference is in the
[Panel REST API](api.md).

### Ship the program over SSH

Add a key on the account page — **Account → SSH keys** — and it lands on every
container the account holds, including ones you are given later. Put the
matching private key in a repository secret and the job is ordinary:

```yaml
      - name: Ship it
        env:
          HOST: hk-1.example.com
          PORT: '22'
          USER: u7k2m9p
        run: |
          install -m 600 /dev/null key
          printf '%s\n' "${{ secrets.DEPLOY_KEY }}" > key
          rsync -az --delete -e "ssh -i key -p $PORT -o StrictHostKeyChecking=accept-new" \
            build/ "$USER@$HOST:/opt/app/"
          ssh -i key -p $PORT "$USER@$HOST" \
            'rc-service app restart || systemctl restart app'
          rm -f key
```

**`rsync` has to be inside the container too**, and none of our images ship it.
Add it where it survives — one line in the `Dockerfile` you already have
(`RUN apk add --no-cache rsync`) — or install it once with
`app-setup install rsync`, remembering that a reinstall takes it away again. If
you would rather add nothing, `tar` over `ssh` needs only what is already
there:

```sh
tar czf - -C build . | ssh -i key -p "$PORT" "$USER@$HOST" 'tar xzf - -C /opt/app'
```

Nothing is wiped, nothing is redownloaded, and the container never goes down
for longer than the restart takes. Use `-o StrictHostKeyChecking=accept-new`
rather than disabling host-key checking outright, and prefer a key over
`sshpass` and a stored password.

**Do not call the panel API from inside the container.** A container holds no
panel credential on purpose. From in there the three things you would want are
already commands: `dashboard`, `app-setup domain add …` and `passwd`.

---

## 9. Checking it before you paste it

Five checks, each one a failure someone has already had:

```sh
# 1. Is the platform in the index at all?
docker buildx imagetools inspect ghcr.io/you/myapp:v1

# 2. Is there an init to be PID 1?
docker run --rm ghcr.io/you/myapp:v1 ls -l /sbin/init

# 3. Is the stop signal declared, and is it the right one?
docker image inspect ghcr.io/you/myapp:v1 \
  --format 'stop={{.Config.StopSignal}} cmd={{.Config.Cmd}}'

# 4. The two conveniences that are easy to lose
docker run --rm ghcr.io/you/myapp:v1 sh -c 'command -v sftp-server; command -v su'

# 5. How big is it? That is the traffic bill, every reinstall — compressed
#    layer bytes, which is what actually crosses the wire
docker buildx imagetools inspect ghcr.io/you/myapp:v1 --raw \
  | jq '[.layers[].size] | add'
```

A multi-platform index prints `null` on that last one, because the layers are
in its children: take the amd64 digest out of `.manifests` and ask the same
question about `ghcr.io/you/myapp@<that digest>`. It is exactly what our own
catalog job does to fill in the size the market shows.

Can it be booted locally first? Partly. `docker run --rm -it your-image sh`
proves the filesystem is sane, but running the init as PID 1 the way the
machine does needs a privileged container and is not worth the trouble for most
people — the honest test is a reinstall on a container you do not mind losing.

---

## 10. When it does not boot

The container is left stopped, on the new root, with `/data` intact. The panel
says the host's own words, and the history line names the image.

Reinstall again — from **the market** tab this time, so the machine installs
something it already holds and the box comes back in seconds. Then work out
what was wrong from §9. Nothing about a failed image damages the container: the
login, the ports, the domains and the traffic counter are all outside it.

Two exceptions to that calm:

- **The download is charged even when the image does not boot.** The bytes
  crossed the wire.
- **A container suspended for quota cannot be reinstalled at all** (§7). If a
  bad image and an exhausted quota arrive together, the box stays down until
  the window rolls over or your host raises the limit.

If the reinstall itself failed — a dead registry, a `401`, a blob that stopped
half way — nothing was replaced. The container is still running the old image
and nothing is charged.

---

## 11. Getting an AI to write it for you

This works well, because the requirements are short and unusual, and a model
that is *told* them gets them right. Left alone it will write an ordinary
app-container Dockerfile, which is exactly the thing that does not boot here.

Paste this, filled in:

```text
Write a Dockerfile and a GitHub Actions workflow for a container image that
runs on hqnode. hqnode runs SYSTEM containers, not app containers, so:

- PID 1 is always /sbin/init. My CMD and ENTRYPOINT are IGNORED by the host —
  it execs /sbin/init whatever the image says. So my program must be started
  by the init as a service, never by CMD.
- Base it on ghcr.io/yinyue123/hqnode:alpine-3.24 (busybox init + OpenRC,
  apk, musl — no glibc binaries). Write the service as an OpenRC init script
  in /etc/init.d and `rc-update add <name> default`.
- The base already declares STOPSIGNAL SIGUSR2 and CMD ["/sbin/init"]; do not
  override them.
- It must have /bin/sh. It does not need sshd, resolv.conf, or a /data
  mountpoint — the host provides those.
- Build for linux/amd64 and push to ghcr.io with docker/build-push-action,
  with provenance: false and sbom: false, tagged :latest and :<git sha>.
- Keep the image small; every reinstall downloads the whole thing and it is
  charged as the container's traffic.

What I am running: <e.g. a Node 20 HTTP server in ./app, listening on 3000,
its data under /data/app>.
Anything my program writes that must survive a reinstall goes under /data.
```

Swap the base and the service style if you are on a systemd system: `…:debian-13`,
a unit in `/etc/systemd/system`, `systemctl enable`, `STOPSIGNAL SIGRTMIN+3`.

Then check what comes back against this list, because these are the five
mistakes models actually make here:

1. **`CMD ["node", "server.js"]` and no service.** The image boots and your
   program does not run. This is the big one.
2. **A slim or distroless base** — `node:20-alpine`, `gcr.io/distroless/…`.
   No init, sometimes no shell: the container does not start and you cannot log
   into it to find out why.
3. **`EXPOSE`, `HEALTHCHECK`, `USER`, `VOLUME`.** Harmless, and all four are
   ignored. Ports come from your host, not from the image.
4. **No `platforms:` in the workflow**, so the runner builds whatever it is and
   the machine refuses an index with no match.
5. **A `STOPSIGNAL` that does not match the init** — `SIGTERM` on Alpine turns
   every stop into a restart.

Two more things worth handing the model: the URL of this page, and the recipe
your image starts from —
[`openrc-alpine/Dockerfile`](https://github.com/yinyue123/hqno.de/blob/main/images/openrc-alpine/Dockerfile)
is 150 lines and every comment in it is a mistake somebody already made.

And if what you actually want is *software in the menu* rather than a new
image, that is a smaller job with its own page and its own contract, which an
AI handles just as well from one file:
[adding your own software](app-setup-sources.md).

---

## Where next

- [Using your container](using-your-container.md) — what a reinstall keeps, and
  the rest of living in one
- [Adding your own software](app-setup-sources.md) — one shell file, no image
  to build
- [Panel REST API](api.md) — every call §8 makes, in full
