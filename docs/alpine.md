# Using Alpine

Alpine is the small one. A container built from it carries a 36 MB filesystem
where Debian carries 164 MB, and idles on about a megabyte of memory — so on
the same box you sold or rented, more of the disk and more of the RAM is left
for the thing you actually came to run.

It costs you something for that, and the cost is real: **it is not the Linux
most instructions on the internet are written for.** No systemd, no `apt`, no
glibc. Every one of those has a straightforward replacement, and this page is
the whole list.

**If you do not want to learn anything new, stop reading and go to
[Using Debian](debian.md).** Reinstall onto it — it takes a minute, keeps
`/data`, and costs you nothing. `apt install`, `systemctl`, `journalctl`, and
every blog post you find works there as written. That is a perfectly good
answer, and §12 is how to take it.

This page assumes you have already read [using your container](using-your-container.md)
— how you got one, what a reinstall does, what the five limits are. Everything
here is the Alpine half.

---

## 1. Alpine or Debian

Measured on a fresh container of each, built from the images this panel
publishes:

| | Alpine 3.24 | Debian 13 |
|---|---|---|
| Filesystem, before you install anything | **36 MB** | 164 MB |
| Memory in use at an idle boot | **~1 MB** | ~10 MB |
| Package manager | `apk` | `apt` |
| Init | busybox init + OpenRC | systemd |
| C library | musl | glibc |
| Logs | files in `/var/log` | journald, and files |

What that buys, in the only terms that matter: on a container sold with 1 GB
of disk, Alpine leaves you **128 MB more of it**, and on one sold with 256 MB
of memory the difference at boot is a tenth of everything you have.

What it costs:

- **Some software has no Alpine build at all.** MongoDB and aaPanel are the
  two you are most likely to want; both publish glibc binaries only, and
  `app-setup` refuses them here with a sentence saying so rather than failing
  four minutes into an install.
- **Precompiled binaries you download yourself usually will not run.** A
  release tarball built for glibc dies with `no such file or directory` — a
  famously unhelpful message for a binary that is plainly right there.
  See §11.
- **`systemctl` does not exist.** Every service instruction you find has to be
  translated. §6 is the table.

Everything else — nginx, MariaDB, PostgreSQL, Redis, PHP, Python, Node, Go,
Rust, WordPress — is packaged and works, and `app-setup` installs all of it
here exactly as it does on Debian.

---

## 2. Getting in, the password, and keys

The login line is on your container page and looks like any other:

```sh
ssh u7k2m9p@hk-1.example.com -p 22
```

You land in **bash**, not busybox's `ash` — the gateway starts
`bash -l` when the container has it, and this image does. That matters later:
`/bin/sh` here is still busybox, so a script with `#!/bin/sh` and a bashism in
it fails even though your prompt is bash. Write `#!/bin/bash` when you mean
bash.

### Setting a password

`passwd`, as root, at your own prompt:

```sh
passwd
```

That changes the container's own `/etc/shadow` **and** the password the SSH
gateway checks, in one step. It is not the stock tool — `/usr/local/bin/passwd`
is a shim that runs the real one first and then tells the machine — but every
flag behaves the way it always did, and `passwd -S root`, `passwd someuser`
and a non-root user changing their own all fall through untouched.

The panel can do it too, on the container page under
**Actions → Shell login → Reset password**. Either way the password is shown
once and stored as a hash; there is nothing to recover if you lose it, only a
new one to set.

### SSH keys

Keys belong to your **account**, not to a box. Add one at
**Account → SSH keys** in the panel and it lands on every container you hold
and on every one handed to you afterwards.

```sh
ssh-keygen -t ed25519                 # on your own machine, if you have no key
cat ~/.ssh/id_ed25519.pub             # paste this line into the panel
ssh-keygen -lf ~/.ssh/id_ed25519.pub  # the SHA256:… the panel shows back
```

**Copying a key into `~/.ssh/authorized_keys` inside the container does
nothing.** There is no sshd in here to read it. Your login is answered by one
SSH server on the host, which then steps into this container's namespaces —
so the list of keys that may act as you lives with that server, and the panel
is the door onto it. A line carrying options (`command="…"`, `from="…"`,
`restrict`) is refused rather than stored, because the gateway cannot honour
them and a stored key without its restriction is a limit you would think you
had.

If you *want* a real sshd of your own on a port your host published for you,
that is a different thing and you install it: `apk add openssh`.

---

## 3. `apk`, in one screen

`apk` is faster than `apt` and shorter to type. The index is already fetched
for you — a boot-time job refreshes it at most once a day — so `apk add nginx`
works on a container you have just logged into for the first time.

| What you want | Alpine | (Debian, for comparison) |
|---|---|---|
| Install | `apk add nginx` | `apt install nginx` |
| Remove | `apk del nginx` | `apt remove nginx` |
| Refresh the index | `apk update` | `apt update` |
| Upgrade everything | `apk upgrade` | `apt upgrade` |
| Search | `apk search nginx` | `apt search nginx` |
| What is this package | `apk info nginx` | `apt show nginx` |
| What files did it write | `apk info -L nginx` | `dpkg -L nginx` |
| Which package owns this file | `apk info -W /usr/sbin/nginx` | `dpkg -S /usr/sbin/nginx` |
| Everything installed | `apk list --installed` | `apt list --installed` |
| What is out of date | `apk version -l '<'` | `apt list --upgradable` |
| Where would this come from | `apk policy nginx` | `apt policy nginx` |

Two repositories are enabled, `main` and `community`, which between them are
everything Alpine ships. `main` is supported for the life of the release;
`community` is best-effort. `apk policy <name>` tells you which one a package
came from.

Names differ from Debian's in a few places that will catch you once each:

| Debian | Alpine |
|---|---|
| `build-essential` | `build-base` |
| `python3-dev` | `python3-dev`, and `py3-…` for library packages |
| `dnsutils` | `bind-tools` |
| `libfoo-dev` | `foo-dev` |
| `iputils-ping` | `iputils` |

**`--no-cache` is for Dockerfiles, not for you.** It skips writing the index
to disk, which is a win when you are building an image and a small loss when
you are living in one. Plain `apk add` is what you want at a prompt.

---

## 4. `app-setup`, which does all of this for you

Type it:

```
app-setup
```

A full-screen picker in five tabs — Suites, Web servers, Databases, Dev tools,
System. Arrow keys move, **Enter** opens the card under the cursor, `L`
switches between English and 中文, `q` quits, and the mouse works. Each card
carries Install, Uninstall, Start/Stop, start-at-boot, **How to use it** —
which names every file that package wrote — the log of the last run, and
Settings where the recipe has any.

Each card also says how much disk and memory the thing needs **and turns that
line red when this container is too small for it**, which is the number nobody
tells you before an install dies four minutes in. On Alpine you will see red
far less often, which is the point of being here.

From a script, or when you already know what you want:

```sh
app-setup list                # everything, with sizes and current state
app-setup install lnmp        # nginx + MariaDB + PHP, wired together
app-setup install wordpress   # ...and WordPress on top, database and all
app-setup status nginx        # 0 running, 1 stopped, 2 not installed
app-setup docs nginx          # what the recipe knows about itself
app-setup doctor              # what this container looks like to app-setup
```

`app-setup doctor` is the one worth running first on a machine you did not
build. On this image it answers:

```
system      Alpine Linux v3.24 (alpine)
init        openrc
packages    apk
```

Everything it installs is Alpine's own package into Alpine's own paths — no
private builds — so the next set of instructions you read still applies, and
security updates keep arriving through `apk` the ordinary way. It knows
OpenRC: `app-setup enable nginx` is `rc-update add nginx default`, and the
service it starts is the one Alpine's own `nginx-openrc` package shipped.

**The two it will not install here** are `mongodb` and `aapanel`, and it says
why rather than trying: both need glibc. Use PostgreSQL with `jsonb` columns
in place of the first, and the `lnmp` card in place of the second.

Adding your own software to the menu is one shell script dropped into
`/etc/app-setup/` — see [adding your own software](app-setup-sources.md).

---

## 5. An editor, and the other things you assumed were there

The image ships small on purpose, so some of what you reach for first is not
in it:

| | Ships | Get it with |
|---|---|---|
| `vi` | yes — busybox's, which is terse but real | |
| `nano` | yes | |
| `vim` | no | `apk add vim`, or `app-setup install vim` |
| `curl` `wget` `less` | yes | |
| `tar` `gzip` `bzip2` `unzip` | yes — busybox's | |
| `xz` | no | `app-setup install essentials` |
| `ping` `ip` `ss` `netstat` | yes | |
| `dig` `traceroute` `mtr` `tcpdump` | no | `app-setup install nettools` |
| `htop` | no | `apk add htop`, or `app-setup install htop` |
| `git` | no | `apk add git`, or `app-setup install git` |
| `bash` | yes, and it is your login shell | |
| `sudo` | yes | |

Alpine is ahead of Debian on several rows of that table, which is not what
anybody expects from the smaller image: busybox ships `vi`, `unzip`, `bzip2`
and `netstat` as applets that cost a few kilobytes each, and the Debian image
has none of the four.

The two cards worth installing on any container you plan to live in:

```sh
app-setup install essentials   # curl wget unzip tar xz bzip2 less procps-ng
app-setup install nettools     # ping dig traceroute mtr tcpdump netstat ss
```

`vi` being busybox's is the one that surprises people. It opens, it edits, it
saves; it has no syntax highlighting, no split windows and a much smaller set
of commands. If you type `vim` and get *not found*, that is why.

---

## 6. Services: OpenRC instead of systemd

This is the part that is genuinely different, and it is smaller than its
reputation.

### The translation table

| systemd | OpenRC |
|---|---|
| `systemctl start nginx` | `rc-service nginx start` |
| `systemctl stop nginx` | `rc-service nginx stop` |
| `systemctl restart nginx` | `rc-service nginx restart` |
| `systemctl reload nginx` | `rc-service nginx reload` |
| `systemctl status nginx` | `rc-service nginx status` |
| `systemctl enable nginx` | `rc-update add nginx default` |
| `systemctl disable nginx` | `rc-update del nginx default` |
| `systemctl is-enabled nginx` | `rc-update show default` |
| `systemctl list-units --state=running` | `rc-status` |
| `systemctl list-unit-files` | `rc-status -a`, or `ls /etc/init.d` |
| `systemctl daemon-reload` | nothing — scripts are read each time |
| `journalctl -u nginx` | `tail -f /var/log/nginx/error.log` (§7) |

`/etc/init.d/nginx restart` works too, and is the same thing `rc-service`
does. There is no `service` command here; that is Debian's.

**Start and enable are two separate acts on Alpine**, where systemd folds them
into `enable --now`. Starting something does not make it come back after a
reboot, and adding it to a runlevel does not start it now. Do both:

```sh
rc-service nginx start
rc-update add nginx default
```

### Reading the board

```sh
rc-status               # what is in the default runlevel, and its state
rc-status -a            # every runlevel
rc-status --servicelist # everything that exists, running or not
```

On a container with nothing added, a healthy board is short:

```
Runlevel: default
 hqnode-package-index   [  started  ]
 crond                  [  started  ]
```

`hqnode-package-index` is the job that keeps `apk add` working on a fresh
container. Leave it alone.

**Runlevels here are `sysinit`, `boot`, `default` and `shutdown`, and you want
`default`.** `boot` is for things that must run before everything else;
`syslog` is in it. Almost nothing you add belongs anywhere but `default`.

### Writing your own service

An OpenRC script is a handful of variables, not a file format. This is a
complete one, and it supervises a program that does not daemonise itself —
which is what almost everything you write does:

```sh
cat > /etc/init.d/myapp <<'EOF'
#!/sbin/openrc-run
name="myapp"
description="my own program"
command="/data/myapp/run"
command_args=""
command_user="root"
command_background=true
directory="/data/myapp"
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/${RC_SVCNAME}.log"
error_log="/var/log/${RC_SVCNAME}.log"

depend() {
	need net
}
EOF
chmod +x /etc/init.d/myapp
rc-update add myapp default
rc-service myapp start
```

Four lines carry all the weight. `command_background=true` is what makes
OpenRC supervise a foreground program at all — without it, `rc-service start`
hangs. `pidfile` is how it finds the process again to stop it, and it is
required whenever `command_background` is set. `output_log`/`error_log` are
where the program's own stdout and stderr go, since there is no journal to
catch them. `depend() { need net }` orders it after the network.

If you would rather not write one, `app-setup install supervisor` gives you
Supervisor, and every program you add to it is a five-line stanza with the
same effect.

### Two bits of noise that are not errors

The first time OpenRC rebuilds its dependency cache — after you add a script
— it prints:

```
Service 'machine-id' needs non existent service 'dev'
Service 'watchdog' needs non existent service 'dev'
```

Both refer to hardware services that a container correctly does not run. The
image already tells OpenRC it is in a container (`rc_sys="lxc"` in
`/etc/rc.conf`), which is what keeps the rest of them out of `rc-status`.
Ignore these two.

Second: `rc-service nginx status` answers **`starting`** for a second or two
after a start, not `started`. A script that starts something and immediately
checks it needs to wait; that is not a failure.

### Scheduled jobs

busybox `crond` is running already and `crontab -e` works as you expect. It
opens `vi` unless you say otherwise:

```sh
EDITOR=nano crontab -e
crontab -l
```

There is also the drop-a-file form, which survives a `crontab -r` and reads
better in a backup:

```
/etc/periodic/15min/   /etc/periodic/hourly/   /etc/periodic/daily/
/etc/periodic/weekly/  /etc/periodic/monthly/
```

Any executable file in one of those runs on that schedule. **Executable** —
a script with the bit unset is silently skipped, which is the classic hour
lost to this.

For one command at every boot rather than on a schedule, there is
`/etc/local.d`:

```sh
printf '#!/bin/sh\n/data/myapp/warmup\n' > /etc/local.d/warmup.start
chmod +x /etc/local.d/warmup.start
rc-update add local default      # once — `local` is not in a runlevel by default
```

---

## 7. Logs

There is **no journald and no `journalctl`**. Everything is a file, which is
either a relief or a nuisance depending on where you came from.

| File | What is in it |
|---|---|
| `/var/log/messages` | the system log — busybox `syslogd`, and what most daemons write to |
| `/var/log/rc.log` | what OpenRC did at boot, and every start and stop since |
| `/var/log/apk.log` | every package you have installed or removed, with timestamps |
| `/var/log/<service>/` | what that service writes itself — `nginx/access.log`, `nginx/error.log` |
| `/var/log/<name>.log` | the `output_log` of a service you wrote (§6) |

```sh
tail -f /var/log/messages           # follow the system log
grep -i error /var/log/messages     # the first thing to try
tail -100 /var/log/rc.log           # why a service did not come up at boot
logger "a line of my own"           # write into it from a script
```

`logrotate` is installed and runs from cron, so these do not grow into your
disk quota. A service you add yourself is not rotated unless you drop a file
into `/etc/logrotate.d/` for it — on a small container that is worth doing the
day you add it, not the day the disk fills:

```sh
cat > /etc/logrotate.d/myapp <<'EOF'
/var/log/myapp.log {
	weekly
	rotate 4
	compress
	missingok
	notifempty
	copytruncate
}
EOF
```

`copytruncate` rather than `create` because an OpenRC-supervised program holds
its log file open and will not reopen it on a signal.

---

## 8. Processes, memory, disk

The image ships `procps-ng` rather than leaving these to busybox, so `top`,
`ps`, `free` and `uptime` print what you expect from a Linux box:

```sh
top                     # interactive; `q` quits
ps aux                  # every process
ps -ef --forest         # the tree, which shows what init started
free -m                 # memory, in MB
df -h /                 # disk
du -sh /* 2>/dev/null   # where the disk went
uptime                  # load average
```

**These numbers are yours, not the machine's.** The host maps per-container
`/proc` files in, so `free` reports the memory you were sold and `nproc`
reports your cores — not the 64-core host you are a tenant of. That is worth
knowing before you size a database from them.

Two exceptions worth remembering: the *load average* in `top` and `uptime` is
the host's, because the kernel has no per-container one; and the `%CPU` in
`top` is against your own cores.

For everything the container itself cannot see — your traffic against the
quota, your expiry date, your domains, your public ports — type `dashboard`
(§10).

---

## 9. Putting a website on the internet

### There is no firewall, and you do not need one

You can install `iptables`. It will not work:

```
iptables v1.8.13 (nf_tables): Could not fetch rule set generation id:
Permission denied (you must be root)
```

You *are* root — but a container is not given `CAP_NET_ADMIN`, so the kernel
refuses. `nft` ends the same way, and so does every wrapper built on either of
them.

This is not something taken from you, because there is nothing here for a
firewall to close. **Nothing inside this container is reachable from the
internet unless one of exactly two things is true:**

1. a **domain** points at it — which you add yourself, and which only ever
   reaches ports 80 and 443 on the machine; or
2. a **public port** is mapped to it — which only your host can open, one
   number at a time, and which is listed on your container page.

A service listening on port 3000 with no domain and no mapping is visible to
this container and to nothing else. That is the firewall.

The corollary: **a public port is on the machine's public address, so anything
behind one is on the internet.** Put a password on it. See
[public ports](ports.md).

### Bind `0.0.0.0`, never `127.0.0.1`

This is the single most common way a working service looks broken here.

Inbound traffic — a domain's, or a published port's — is delivered to the
container's own network interface, `tap0`. It is *not* delivered to the
container's loopback. So a service bound to `127.0.0.1` accepts nothing from
outside: the connection is established and then answers with nothing, which
reads as a broken application rather than a wrong address.

```
listen 127.0.0.1:3000   →  connects, empty reply, no error anywhere
listen 0.0.0.0:3000     →  works
```

Binding `0.0.0.0` exposes nothing extra, because the only ways in are the two
above. Configs copied from a machine where the app sat behind a local nginx
almost always carry `127.0.0.1`, and that is the line to change.

Keep `127.0.0.1` only for things whose one caller lives in this same
container.

### Adding a domain

Either on the container page in the panel, or from your own prompt:

```sh
domain add example.com 80          # HTTP and HTTPS, certificate handled for you
domain add *.example.com 3000      # a wildcard, at a Node app
domain ls                          # what this container answers for
domain del example.com
domain help                        # the full syntax
```

`domain add example.com 80` gives you both: `example.com:443` with a
certificate the machine obtains and renews for you, and `example.com:80`,
both forwarded to port 80 in here. You do not run certbot and you do not
copy a key anywhere.

Pointing the name's DNS at the machine is the half you do at your domain
provider; the address to point at is on the same card in the panel. Checks
run on a schedule and show as badges on each name, so a name that is not
working tells you which part is wrong.

If you would rather terminate TLS yourself — you have a certificate, or you
are running something that insists on holding its own key — add the
`self-hosted` keyword and the machine splices the encrypted bytes straight
through without ever holding your key:

```sh
domain add example.com 8443 self-hosted        # your TLS on 8443, nothing on :80
domain add example.com 8443 self-hosted 8080   # ...and plain HTTP on 8080 too
```

[Quick start](quick-start.md) walks the whole thing — name, DNS, padlock — in
four steps.

### The shortest path to a working site

```sh
app-setup install lnmp      # nginx + MariaDB + PHP-FPM, tuned for this box
domain add example.com 80
```

or, for a static site or your own app, `apk add nginx` and edit
`/etc/nginx/http.d/`. Note the directory: Alpine puts server blocks in
`/etc/nginx/http.d/`, not Debian's `sites-available` / `sites-enabled` pair.

---

## 10. Traffic, limits and expiry, from inside

```sh
dashboard              # everything: box, cpu, memory, disk, traffic,
                       # public ports, domains, and how to log back in
dashboard net          # just the traffic meter
dashboard cpu mem      # just those two
```

The traffic section is the one nothing inside the container can answer on its
own, because the quota belongs to a billing window the panel keeps:

```
Network
  Allowance   1.0T monthly
  Used        318.0G (29%) — 210.0G in, 108.0G out
  Left        706.0G
  Window      counting since 2026-08-01
```

Both directions count. At 80% the panel records a warning; at 100% the
container is **suspended** — stopped, not deleted — and comes back when the
window rolls over or your host raises the quota.

The same numbers print at every SSH login, above the prompt, so you rarely
have to ask.

You can also read the kernel's own counters for the container's interface:

```sh
ip -s link show tap0
```

Those are honest bytes, but they are **not** the meter: they reset when the
container restarts, they count ethernet framing and DNS, and they say nothing
about which billing window you are in. Use them to answer "is something
transferring right now"; use `dashboard net` to answer "how much have I got
left".

`helppage` is the guide, in here, with no browser: ports and domains,
installing software, backups, what each limit does, and what a reinstall
keeps. `helppage --list` names the pages and `helppage --text limits` prints
one as plain text.

---

## 11. What musl actually costs you

Alpine uses musl where nearly every other distribution uses glibc. Source you
compile here is fine. Binaries somebody else compiled are the problem.

**The error you will see**, and it is a bad one:

```
./some-tool: not found
```

The file is right there and `ls` proves it. What is missing is
`/lib64/ld-linux-x86-64.so.2` — the glibc loader the binary asks for — and the
kernel reports that absence as if the program itself were absent.

```sh
file ./some-tool        # "dynamically linked, interpreter /lib64/ld-linux-…"  → glibc
ldd ./some-tool         # "Not a valid dynamic program"                        → glibc
```

What to do, in the order worth trying:

1. **Look for the package.** `apk search <name>` — Alpine packages far more
   than people expect, and a distribution package is built against musl by
   definition.
2. **Look for a musl or static build** on the project's releases page. Go and
   Rust projects almost always publish one; a statically linked binary needs
   no loader at all and runs anywhere.
3. **Build it from source.** `apk add build-base` gets you a compiler.
4. **Give up and use Debian** for that one thing. This is a legitimate answer,
   and reinstalling costs you a minute.

Two specific cases worth naming, because they come up constantly:

- **Python.** `pip install` on a package with no pure-Python version
  downloads a ready-made wheel on Debian and compiles from source here,
  unless the project publishes `musllinux` wheels (many now do). That needs a
  compiler and headers, which is exactly why `app-setup install python` pulls
  `python3-dev` and `build-base` in with it. Install it that way and `pip`
  behaves.
- **Node.** Alpine's own `nodejs` package is current, so `app-setup install
  nodejs` gives you a musl build and `npm install` works. What breaks is an
  npm package shipping a prebuilt `.node` binary; those fall back to
  compiling, which again wants `build-base`.

Go, Rust, PHP, Java, nginx, PostgreSQL, MariaDB, Redis: no trouble at all.
Rust here even produces fully static binaries by default, which is a small
bonus.

---

## 12. When you have had enough

Reinstalling onto Debian keeps `/data`, your login, your password and your
address. It destroys everything else — every package, every service, every
file outside `/data`.

```sh
reinstall                  # what this container can be rebuilt from
reinstall debian-13        # part of the name is enough
```

It asks you to type the container's name, and then your SSH session ends
part-way through the rebuild, which is what is supposed to happen. Log back in
a minute later, same address, same password, and read
[Using Debian](debian.md).

Going the other way is the same command with a different name. Nothing about
your limits, your domains or your public ports changes either way.
