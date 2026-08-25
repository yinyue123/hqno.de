# Using Alpine

Alpine is the small one. A container built from it carries a **36 MB**
filesystem where Debian carries **164 MB**, and boots three processes that
between them hold **168 KB** of memory where Debian boots seven holding
**6.5 MB** — so on the same box you were sold, more of the disk and more of
the RAM is left for the thing you actually came to run. §1 is the full
accounting, measured rather than claimed.

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

## 1. What the system itself costs

Every figure below was measured on a fresh container of each, built from the
images this panel publishes, sitting idle with nothing installed. Same host,
same limits, same minute.

| | Alpine 3.24 | Debian 13 |
|---|---|---|
| **Filesystem, nothing installed** | **36 MB** | **164 MB** |
| **Charged to your memory limit at idle** | **15 MB** | **105 MB** |
| — of that, page cache the kernel gives back under pressure | 14 MB | 94 MB |
| — of that, memory you do not get back | **0.9 MB** | **10 MB** |
| Processes running | 3 | 7 |
| Package manager | `apk` | `apt` |
| Init | busybox init + OpenRC | systemd |
| C library | musl | glibc |
| Logs | plain files | journald, plus files |

Two of those rows need a sentence, because "how much memory does an idle
container use" has two honest answers.

**105 MB is what the panel and `dashboard` show you.** It is `memory.current`
for your cgroup, and most of it is page cache — the binaries and files the
system has read, kept around in case they are read again. Under pressure the
kernel drops it without anybody noticing. **10 MB is what you actually lose**:
anonymous memory the daemons allocated, plus the kernel's own bookkeeping for
them. Both numbers are real; the first is what you will see, the second is
what you can never spend on something else.

### Where the memory goes

The private (anonymous) memory of every process on an idle container, which is
the part that cannot be reclaimed:

| Job | Alpine | Debian |
|---|---|---|
| PID 1 | busybox `init` — **52 KB** | `systemd` — **2,772 KB** |
| System log | busybox `syslogd` — **64 KB** | `systemd-journald` 1,132 KB + `rsyslogd` 636 KB — **1,768 KB** |
| Scheduled jobs | busybox `crond` — **52 KB** | `cron` — **200 KB** |
| Logins and sessions | *nothing running* | `systemd-logind` 1,116 KB + `dbus-daemon` 468 KB — **1,584 KB** |
| A console nobody is on | *nothing running* | `agetty` — **236 KB** |
| **Total** | **168 KB** | **6,560 KB** |

Alpine's three processes are **the same binary**. `init`, `syslogd` and
`crond` are all `/bin/busybox`, so the ~900 KB of program text behind them is
mapped once and shared three ways — which is why three daemons cost less than
one of Debian's.

Debian's list is longer because systemd's promise is larger. `logind` tracks
sessions and seats, `dbus` carries the messages between them, `journald` keeps
an indexed binary log you can query by unit and time. On a laptop those are
worth having. In a container you SSH into as root, `logind` and the console
getty are managing things that are not there.

### Where the disk goes

| | Alpine | Debian |
|---|---|---|
| Package index — the list of what exists | **2.9 MB** (`/var/cache/apk`) | **20.5 MB** (`/var/lib/apt/lists`) |
| Package database — what you have installed | **0.1 MB** (`/lib/apk/db`) | **5.9 MB** (`/var/lib/dpkg`) |
| Logs, two minutes after first boot | **0 MB** | **8.1 MB** (the journal's first file) |
| The init system's own files | ~1 MB | 5.5 MB (`/usr/lib/systemd`) |
| Everything else — the programs | ~32 MB | ~124 MB |

That 20.5 MB of `apt` index is worth knowing about: it is not something you
installed, it is refreshed rather than deleted, and on a container sold with
1 GB of disk it is 2% of everything you have, permanently.

**The journal is the one that can surprise you.** It sizes itself at 10% of
the filesystem — on the container measured here that is a cap of **1.9 GB**,
and it starts at 8 MB before you have done anything. Capping it is one file;
see [Debian §5](debian.md).

### So which one, for what

| Your container | Take |
|---|---|
| **Disk under about 2 GB** | **Alpine.** 128 MB is 13% of a 1 GB disk and you have not installed anything yet. This is the argument that does not go away. |
| **Memory 256 MB or less** | **Alpine.** The 9 MB of unreclaimable difference is 4% of a 256 MB box, and the 80 MB of cache Debian wants is memory your own program is not getting. |
| **1 GB of memory and 10 GB of disk or more** | Either. The difference is a rounding error; take [Debian](debian.md) for the ecosystem. |
| **You were handed a compiled program to run** — a vendor agent, a game server, a trading bot, anything that arrived as a binary rather than as source | **Check §11 first.** Half of them run here untouched and half do not, and the answer depends on how it was built, not on what it does. MongoDB and aaPanel are known noes. |
| **You are running many containers on one machine** | Alpine, and the argument compounds: thirty idle Alpine containers is under half a gigabyte of memory and a gigabyte of disk. |

One thing the table cannot show, and it matters: **Alpine does not make your
software smaller.** nginx uses about 9 MB of private memory on either system —
measured, master plus four workers, same configuration. What Alpine gives you
is a smaller box underneath it. If the thing you run needs 400 MB, it needs
400 MB on both.

### What it costs

None of the above is free, and the bill is not paid in megabytes:

- **Some software has no Alpine build at all.** MongoDB and aaPanel are the
  two you are most likely to want; both publish glibc binaries only, and
  `app-setup` refuses them here with a sentence saying so rather than failing
  four minutes into an install.
- **A compiled binary somebody else built may not run** — one built against
  glibc dies with `not found`, a famously unhelpful message for a file that is
  plainly right there. This does **not** apply to PHP, Python, Node, Java or
  shell, which do not care what libc is underneath; nor to most Go binaries,
  which carry no libc at all. **§11 is a table of what you were handed and
  whether it runs**, and it is the section to read first if you rented this
  box to run somebody else's software.
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

## 3. Managing packages

`apk` is Alpine's package manager. It is faster than `apt` and shorter to
type. The index is already fetched for you — a boot-time job refreshes it at
most once a day — so `apk add nginx` works on a container you have just logged
into for the first time.

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

### After it installs: start it, and start it at boot

Installing something does not run it, and running it does not bring it back
after a reboot. Those are three separate commands here:

```sh
apk add nginx                 # install it
rc-service nginx start        # run it now
rc-update add nginx default   # run it at every boot
```

**The last two are not one command.** systemd folds them into
`systemctl enable --now`; OpenRC does not. Starting a service does not add it
to a runlevel, and adding it to a runlevel does not start it. This is the
single most common way something "installed and working" is gone after the
first restart.

Check either of them:

```sh
rc-service nginx status    # is it running right now
rc-update show default     # what comes back at boot
```

`app-setup` does both for you when it installs something, so a package from
the menu is already running and already in the runlevel. §6 is the full
service chapter — stopping, disabling, writing one of your own.

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

## 5. The everyday tools

The image ships small on purpose. Most of what you reach for is in it anyway,
because busybox carries a lot of small programs for very little disk — this is
what a fresh container has, and what to type when it does not:

| For | Already there | Worth adding |
|---|---|---|
| Editing a file | `vi` (busybox's), `nano` | `vim` — `app-setup install vim` |
| Reading and searching | `less` `grep` `find` `awk` `sed` `tail` `watch` `xxd` | |
| Archives | `tar` `gzip` `bzip2` `unzip` | `xz` — `app-setup install essentials`; `zip` — `apk add zip` |
| Downloading | `curl` `wget` | |
| Network trouble | `ping` `ip` `ss` `netstat` `nslookup` `traceroute` `nc` | `dig` `mtr` `tcpdump` — `app-setup install nettools` |
| Processes and usage | `top` `ps` `free` `df` `du` `lsof` `killall` `tree` | `htop` `ncdu` `atop` — `app-setup install htop` |
| Reaching another box | `ssh` `scp` `sftp` | `rsync` — `app-setup install rsync` |
| Building things | | `git` `make` `gcc` — `app-setup install git`, then `buildtools` |
| A session that survives a dropped SSH | | `tmux` or `screen` — `app-setup install tmux` |
| Shell | `bash` (your login shell), `sudo`, `crontab` | `zsh` + Oh My Zsh — `app-setup install zsh` |

Alpine is ahead of Debian on several rows of that table, which is not what
anybody expects from the smaller image: busybox ships `vi`, `wget`, `unzip`,
`bzip2`, `netstat`, `nslookup`, `traceroute`, `nc`, `killall`, `lsof` and
`tree` as applets costing a few kilobytes each, and the Debian image has none
of the eleven.

The two cards worth installing on any container you plan to live in:

```sh
app-setup install essentials   # curl wget unzip tar xz bzip2 less procps-ng
app-setup install nettools     # ping dig traceroute mtr tcpdump netstat ss
```

Two rows come with a catch worth knowing before you hit it:

- **`vi` is busybox's.** It opens, it edits, it saves; no syntax
  highlighting, no split windows, a much smaller set of commands. If you type
  `vim` and get *not found*, that is why.
- **Busybox applets take fewer flags than the real programs.** The common
  ones are there — `netstat -tlnp` prints what you expect — but an obscure
  switch copied off a blog post may simply not exist. `ps`, `top`, `free` and
  `watch` are the exception: the image installs real `procps-ng` for those,
  so `ps aux` and `ps -ef --forest` behave the way they do everywhere else.
  When something refuses a flag, `<tool> --help` here is short, and reading
  it is faster than guessing.

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

As §3 said: **start and enable are two separate acts**, where systemd folds
them into `enable --now`. Whenever you start something you meant to keep, add
it to the runlevel in the same breath.

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
| `/var/log/<name>.log-20260825-021500.gz` | yesterday's, and the six days before it |

```sh
tail -f /var/log/messages           # follow the system log
grep -i error /var/log/messages     # the first thing to try
tail -100 /var/log/rc.log           # why a service did not come up at boot
logger "a line of my own"           # write into it from a script
zcat /var/log/myapp.log-2026*.gz | grep -i error    # the same, in last week's
```

### They are cut for you

A program that writes a line per request will fill a container's disk, and a
full disk stops everything on it. So the image ships a rule and `crond` runs
`logrotate` at 02:00:

```
/var/log/*.log
/var/log/messages {
	daily            rotate 7            # a week, then it is gone
	compress         copytruncate
}
```

It is a **glob on purpose**: a service you add tomorrow writes
`/var/log/<name>.log` like everything else and is cut from the day it appears,
with nothing to write and nothing to remember. `/etc/logrotate.d/hqnode` is the
file, if you want to change the seven days or the schedule.

`copytruncate` rather than the usual rename-and-create, because a supervised
program holds its log file open and never reopens it: renamed out from under
it, it goes on writing into the old file — the new one stays empty forever and
the disk fills anyway, from a file you are no longer looking at.

To see what it would do, or to make it do it now:

```sh
logrotate -d /etc/logrotate.conf    # dry run: what it would cut, and any errors
logrotate -f /etc/logrotate.conf    # do it now
```

### What is not covered, which is the part that bites

**A program that logs somewhere else.** The glob is `/var/log/*.log` and
nothing more. Something writing to `/app/logs/app.log`, `~/output.log`, or its
own directory is not cut by anything, and that is the usual way a disk fills.
Two fixes, and the first is better:

```sh
# 1. make it log where everything else does — in a service script (§6):
output_log="/var/log/myapp.log"
error_log="/var/log/myapp.log"

# 2. or, if it insists on its own path, give that path a rule:
cat > /etc/logrotate.d/myapp <<'EOF'
/app/logs/*.log {
	daily
	rotate 7
	compress
	missingok
	notifempty
	copytruncate
}
EOF
logrotate -d /etc/logrotate.conf    # check it before trusting it
```

**Subdirectories.** `/var/log/nginx/*.log` is not in the glob either — packages
that use a directory ship their own rule for it, and nginx's is a good example.

**Do not write a rule for a file that is already inside `/var/log/*.log`.**
logrotate refuses a file claimed by two rules, and it does not just skip the
duplicate — it skips **the whole file it found it in** and the run exits
non-zero:

```
error: myapp:1 duplicate log entry for /var/log/myapp.log
error: found error in file myapp, skipping
```

Since the daily wrapper reports a non-zero run into syslog as `ALERT exited
abnormally`, you get a complaint every night for a rule that was not needed in
the first place. Anything under `/var/log/*.log` is already handled.

### When the disk is already filling

```sh
df -h /                             # how bad it is
du -sh /var/log/* | sort -h | tail  # the biggest logs
du -xsh /* 2>/dev/null | sort -h | tail   # or it is not the logs at all
```

To reclaim space from a file a running program is writing, **empty it, do not
delete it**:

```sh
: > /var/log/greedy.log             # right: the space comes back at once
rm /var/log/greedy.log              # wrong: the program still holds the fd,
                                    # the space stays gone until it restarts,
                                    # and its output goes nowhere
```

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

## 11. Running somebody else's program

Alpine uses musl where nearly every other distribution uses glibc. If you
rented this box to run something you did not write, that one sentence is the
only thing on this page that can stop you — so here is the whole answer,
sorted by what you were actually handed.

| What you were given | Here |
|---|---|
| A **shell script** | **Yes.** Mind the shebang: `#!/bin/sh` is busybox here, so a script full of bashisms needs `#!/bin/bash`. |
| A **PHP** application — WordPress, Typecho, a folder of `.php` | **Yes**, no difference whatsoever. `app-setup install lnmp`, copy it in, done. |
| A **Python** program — `.py` files and a `requirements.txt` | **Yes.** See the note below about wheels. |
| A **Node.js** program — source and a `package.json` | **Yes.** See the note below about native modules. |
| A **Java** `.jar` | **Yes.** The JVM is a distro package here (`app-setup install java`), and a `.jar` does not care what is underneath it. |
| A **Go** binary from a releases page | **Almost always yes.** Go links statically by default, so most published Go binaries carry no libc at all and run anywhere. |
| A **Rust** binary from a releases page | **The `-musl` build yes, the `-gnu` build no.** The file name tells you which one you downloaded. |
| Any other **compiled binary** — C, C++, or Go built with cgo | **Check before you commit.** Statically linked: yes. Linked against glibc: not without help — read on. |
| A **`.deb` or `.rpm`** | **No.** `apk` cannot read either format. Look for the project's own tarball, or its Alpine package. |
| A **Docker image** | **No — and not on Debian either.** Running a container inside your container is not supported here: a tenant gets no `CAP_NET_ADMIN` and there is no `/dev/net/tun`, so a nested runtime has no way to give it a network. What you *can* do is become it — reinstall this container **from** that image. See [building your own image](building-your-own-image.md). |
| A **`curl … \| sh` installer** | **Depends on what it downloads**, which is usually a glibc binary. Read the script first, or just run it and find out. |

The short version: **anything that runs on an interpreter or a virtual
machine — PHP, Python, Node, Java, Ruby, shell — does not care which libc is
underneath, and Alpine costs you nothing.** The question only arises for a
compiled binary that somebody else built, and half of those are statically
linked and fine too.

Two interpreter cases that do come up, both about compiling rather than about
running:

- **Python.** `pip install` on a package with no pure-Python version
  downloads a ready-made wheel on Debian and compiles from source here,
  unless the project publishes `musllinux` wheels (many now do). Compiling
  needs headers, which is exactly why `app-setup install python` pulls
  `python3-dev` and `build-base` in with it. Install it that way and `pip`
  behaves.
- **Node.** Alpine's own `nodejs` package is current, so
  `app-setup install nodejs` gives you a musl build and `npm install` works.
  What falls back to compiling is a package shipping a prebuilt `.node`, and
  that wants `build-base` too.

### Checking a binary before you trust it

Two commands, before you build anything around it:

```sh
file ./some-tool
ldd  ./some-tool
```

| What they say | What it means |
|---|---|
| `statically linked` | runs anywhere, including here. Nothing to think about. |
| `interpreter /lib64/ld-linux-x86-64.so.2` | built for glibc — read the next section |
| `interpreter /lib/ld-musl-x86_64.so.1` | built for musl — it is already yours |
| `ldd` says `Not a valid dynamic program` | static, same as the first row |

### The error, if you skip the check

```
./some-tool: not found
```

The file is right there and `ls` proves it. What is missing is
`/lib64/ld-linux-x86-64.so.2` — the glibc loader the binary asks the kernel
for — and the kernel reports that absence as if the program itself were
absent. It is the single most confusing message on this system, and this is
all it ever means.

### What to do about a glibc binary, in order

1. **Look for the package.** `apk search <name>` — Alpine packages far more
   than people expect, and a distribution package is built against musl by
   definition.
2. **Try `apk add gcompat`.** It is 87 KB and it makes glibc binaries load.
   Measured: a glibc `echo` copied in from a Debian container answers
   `not found` on a stock image and runs correctly the moment `gcompat` is
   installed. **It is not a guarantee** — it supplies libc and nothing else,
   so a binary that also wants `libselinux.so.1` or glibc's `libstdc++` still
   fails, now with a message naming the library it could not find. One
   command, worth the try.
3. **Look for a musl or static build** on the project's releases page. Go and
   Rust projects almost always publish one, and a static binary needs no
   loader at all.
4. **Build it from source.** `apk add build-base` gets you a compiler.
5. **Use Debian for that one thing.** A perfectly good answer; the reinstall
   costs a minute and keeps `/data`. §12.

Go, Rust, PHP, Java, nginx, PostgreSQL, MariaDB, Redis: no trouble at all.
Rust here even produces fully static binaries by default, which is a small
bonus.

### And what it does not cost you: memory

The two libraries manage memory differently, and it is worth knowing which of
those differences shows up on your bill and which just looks alarming.

**A program uses the same memory on both.** nginx, master plus four workers,
same configuration: about 9 MB of private memory on Alpine and about 9 MB on
Debian. Allocating 250 MB and freeing it again returns all of it to the kernel
on both. Alpine shrinks the system around your program; it does not shrink
your program.

**Where they really differ is address space, which is not memory.** glibc
gives every thread an 8 MB stack and lets it have its own malloc arena; musl
is far more frugal. The same Python script holding twenty idle threads,
measured on both:

| | Alpine (musl) | Debian (glibc) |
|---|---|---|
| Virtual size, 0 threads | 10 MB | 15 MB |
| Virtual size, 20 threads | **52 MB** | **1,490 MB** |
| Resident, 0 → 20 threads | 7.2 → 7.6 MB | 9.2 → 9.7 MB |

A gigabyte and a half of address space, and under half a megabyte of actual
memory behind it. **Your limit counts resident memory, not address space**, so
none of that 1.5 GB is charged to you and none of it can OOM you. What it does
mean is that `top`'s **VIRT** column on a threaded Debian program is a number
to ignore; **RES** is the one your quota is about.

**The one place musl's frugality can hurt** is that smaller stack. Measured
with the same interpreter on both, a thread gets 2 MB of stack here against
Debian's 8 MB. Code that recurses deeply, or puts a large array on the stack
instead of the heap, has a quarter of the room and overflows where it would
not have on Debian — and a stack overflow arrives as a bare segfault with
nothing in any log. If a threaded program of yours dies that way here and
nowhere else, that is the first thing to suspect, and setting an explicit
stack size where you create the thread is the fix.

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
