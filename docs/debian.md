# Using Debian

Debian is the one with no learning curve. It boots systemd, installs with
`apt`, reads logs with `journalctl`, and every set of instructions you find on
the internet for "a Linux server" was written for a machine like this one.
Ubuntu is the same page — same `apt`, same `systemctl`, same file layout — so
if your container says Ubuntu 24.04, read on.

That is the whole pitch. It is a fine default, and if you are not sure which
system you want, this is the one to want.

The trade is size: a Debian container's filesystem is about **164 MB** before
you install anything, against **36 MB** for [Alpine](alpine.md), and it idles
on roughly ten megabytes of memory rather than one. On a container sold with a
generous disk that is noise. On one sold with 512 MB of disk it is a quarter
of everything you have, and [Using Alpine](alpine.md) is the page that makes
the case for the other side.

This page assumes you have read [using your container](using-your-container.md)
— how you got one, what a reinstall does, what the five limits are. Everything
here is the day-to-day.

---

## 1. Getting in, the password, and keys

Your container page shows the user, the host and the port. Together they are
the line you run:

```sh
ssh u7k2m9p@hk-1.example.com -p 22
```

You land in bash, as root, with your own prompt and your own `/etc/profile`.

### Setting a password

`passwd`, as root, at your own prompt:

```sh
passwd
```

That changes the container's own `/etc/shadow` **and** the password the SSH
gateway checks, in one step. It is not quite the stock tool —
`/usr/local/bin/passwd` runs the real one and then tells the machine — but
every flag behaves as it always did, and `passwd -S root`, `passwd someuser`
and a non-root user changing their own all fall through untouched.

The panel does it too, on the container page under
**Actions → Shell login → Reset password**. Either way the password is shown
once and kept only as a hash. Lost it? Set a new one; there is nothing to
recover.

### SSH keys

A key belongs to your **account**, not to a box. Add one at
**Account → SSH keys** in the panel and it lands on every container you hold
and on every one handed to you afterwards — which is the difference between
setting up a key once and setting it up again every time somebody gives you a
machine.

```sh
ssh-keygen -t ed25519                 # on your own machine, if you have no key
cat ~/.ssh/id_ed25519.pub             # paste this line into the panel
ssh-keygen -lf ~/.ssh/id_ed25519.pub  # the SHA256:… the panel shows back
```

**Copying a key into `~/.ssh/authorized_keys` inside the container does
nothing.** There is no sshd in here to read it — your login is answered by one
SSH server on the host, which then steps into this container's namespaces. The
list of keys that may act as you lives with that server, and the panel is the
door onto it.

A line carrying options (`command="…"`, `from="…"`, `restrict`) is refused
rather than stored, because the gateway cannot honour them and a stored key
without its restriction is a limit you would think you had.

If you want a real sshd of your own, on a port your host published for you,
that is a separate thing: `apt install openssh-server`.

---

## 2. Installing software

### The short version

```sh
apt update              # refresh the list of what exists
apt install nginx       # install it
apt remove nginx        # take it away, keep its config
apt purge nginx         # take the config too
apt search nginx        # find the name
apt show nginx          # what is this thing
apt list --installed    # everything you have
apt upgrade             # update everything, security fixes included
```

`apt update` has already been run for you — a job at boot refreshes the index,
at most once a day — so `apt install nginx` works on a container you have just
logged into for the first time.

**One trap, and it only happens in the first minute of a container's life.**
That boot job holds apt's lock while it runs, and `apt` does not wait for a
lock it cannot take. If your very first command answers *Unable to locate
package* or *Could not get lock*, wait thirty seconds and run it again.

### The shorter version

Type `app-setup`:

```
 ┌ Suites ─ Web servers ─ Databases ─ Dev ─ System ─┐
 │                                                  │
 │ ▸ LNMP                          · installed      │
 │   nginx, MariaDB, PHP-FPM                        │
 │   Disk 600M RAM 768M  Port 80, 3306              │
 │                                                  │
 │   WordPress                     · running        │
 │   WordPress, nginx, PHP-FPM, MariaDB             │
 │   Disk 800M RAM 768M  Port 80                    │
 │                                                  │
 │ ↑↓←→ move    Enter open    ↑ at the top is Back  │
 └──────────────────────────────────────────────────┘
```

A full-screen picker in five tabs — Suites, Web servers, Databases, Dev tools,
System. Arrow keys move, **Enter** opens the card under the cursor, `L`
switches between English and 中文, `q` quits, and the mouse works. Each card
carries Install, Uninstall, Start/Stop, start-at-boot, **How to use it** —
which names every file that package wrote — the log of the last run, and
Settings where the recipe has any.

Each card also says how much disk and memory the thing needs, **and turns that
line red when this container is too small for it** — the number nobody tells
you before an install dies four minutes in.

It works from a script too:

```sh
app-setup list                # everything, with sizes and current state
app-setup install lnmp        # nginx + MariaDB + PHP, wired together
app-setup install wordpress   # ...and WordPress on top, database and all
app-setup status nginx        # 0 running, 1 stopped, 2 not installed
app-setup docs wordpress      # what that recipe knows about itself
app-setup doctor              # what this container looks like to app-setup
```

Everything it installs is Debian's own package into Debian's own paths.
Nothing is a private build, so the next set of instructions you read still
applies and security updates keep arriving through `apt` the usual way.
Generated passwords go to `/etc/app-setup/secrets/`, mode 600, rather than
scrolling past in an install log.

Uninstalling never deletes your data: removing WordPress drops its database
and its files but moves your uploads to `/root/` first, and says so.

Adding your own software to the menu is one shell script dropped into
`/etc/app-setup/` — see [adding your own software](app-setup-sources.md).

### An editor, and the other things you assumed were there

The image ships lean, so a few things you reach for first are not in it:

| | Ships | Get it with |
|---|---|---|
| `nano` | yes | |
| `vim` `vi` | **no** | `apt install vim`, or `app-setup install vim` |
| `curl` `less` | yes | |
| `wget` `unzip` `xz` `bzip2` | no | `app-setup install essentials` |
| `ping` `ip` `ss` | yes | |
| `dig` `traceroute` `mtr` `tcpdump` `netstat` | no | `app-setup install nettools` |
| `htop` | no | `apt install htop`, or `app-setup install htop` |
| `git` | no | `apt install git`, or `app-setup install git` |
| `bash` `sudo` `cron` | yes | |

The two cards worth installing on any container you plan to live in:

```sh
app-setup install essentials   # curl wget unzip tar xz bzip2 less procps
app-setup install nettools     # ping dig traceroute mtr tcpdump netstat ss
```

---

## 3. Services

systemd is PID 1 here, so this is the ordinary thing you already know:

```sh
systemctl start nginx
systemctl stop nginx
systemctl restart nginx
systemctl reload nginx           # re-read config without dropping connections
systemctl status nginx           # state, recent log lines, and the pid
systemctl enable --now nginx     # start it, and start it at every boot
systemctl disable --now nginx
systemctl is-active nginx        # for scripts: exit 0 if running
```

What is running, and what is broken:

```sh
systemctl list-units --type=service --state=running
systemctl --failed
```

`systemctl reboot` works and restarts the container in place. If it is wedged
badly enough that you cannot reach it, **Restart** in the panel does the same
thing from outside.

### Writing your own service

One file, three sections. This runs a program of yours and restarts it if it
dies:

```sh
cat > /etc/systemd/system/myapp.service <<'EOF'
[Unit]
Description=my own program
After=network.target

[Service]
Type=simple
ExecStart=/data/myapp/run
WorkingDirectory=/data/myapp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now myapp
systemctl status myapp
```

`daemon-reload` after every edit to the file — systemd caches units, and
forgetting it is the reason a change appears to do nothing. `Type=simple`
means your program stays in the foreground; if it forks and exits, you want
`Type=forking` and a `PIDFile=`.

Anything under `ExecStart` writes its stdout and stderr straight into the
journal, so you get logs for free without redirecting anything.

If you would rather not write unit files, `app-setup install supervisor` gives
you Supervisor and a five-line stanza per program.

### Scheduled jobs

`cron` is running already:

```sh
crontab -e        # your own jobs; opens nano unless you set EDITOR
crontab -l
EDITOR=vim crontab -e
```

and the drop-a-file form, which survives `crontab -r` and reads better in a
backup: an executable file in `/etc/cron.daily/`, `/etc/cron.hourly/`,
`/etc/cron.weekly/`. **Executable** — a script with the bit unset is silently
skipped, which is the classic hour lost to this. Debian's `run-parts` also
ignores any filename with a dot in it, so `backup.sh` there never runs; call
it `backup`.

systemd timers work too, if you prefer them.

### Two lines in the logs that are not problems

`systemctl --failed` on a healthy container shows one entry:

```
● dev-mqueue.mount   loaded failed failed   POSIX Message Queue File System
```

and units you start log a line like:

```
Failed to get cgroup ID of cgroup /sys/fs/cgroup/system.slice/myapp.service,
ignoring: Operation not permitted
```

Both are systemd reaching for something only the host may touch, noticing it
cannot, and carrying on — which is exactly what should happen. Neither affects
anything you run. Ignore them.

---

## 4. Logs

Everything goes to the journal, and `journalctl` is how you read it:

```sh
journalctl -u nginx            # one service
journalctl -u nginx -f         # ...and follow it live
journalctl -u nginx -n 100     # the last hundred lines
journalctl -u nginx --since -1h
journalctl -p err -b           # errors only, this boot
journalctl -xe                 # the end of everything, with explanations
```

`rsyslog` is running as well, so the traditional files exist too and anything
that writes to syslog rather than to the journal lands in them:

| File | What is in it |
|---|---|
| `/var/log/syslog` | the system log |
| `/var/log/nginx/` | what a service writes itself, when it writes its own |
| `/var/log/apt/history.log` | every package you have installed or removed |

```sh
tail -f /var/log/syslog
grep -i error /var/log/syslog
```

`logrotate` is installed and runs daily, so none of this grows into your disk
quota — but a log file your own program writes is not rotated unless you drop
a config for it into `/etc/logrotate.d/`. The journal caps itself, so it does
not need one.

A service you wrote does not need a log file at all: write to stdout, let
systemd catch it, and read it with `journalctl -u`.

---

## 5. Processes, memory, disk

```sh
top                     # interactive; `q` quits
ps aux                  # every process
ps -ef --forest         # the tree, which shows what systemd started
free -m                 # memory, in MB
df -h /                 # disk
du -sh /* 2>/dev/null   # where the disk went
uptime                  # load average
systemd-cgtop           # the same, grouped by service
```

**These numbers are yours, not the machine's.** The host maps per-container
`/proc` files in, so `free` reports the memory you were sold and `nproc`
reports your cores — not the 64-core host you are a tenant of. Size your
database from these, not from the host's figures.

Two exceptions: the *load average* in `top` and `uptime` is the host's,
because the kernel has no per-container one; and `%CPU` in `top` is against
your own cores.

For what the container cannot see on its own — traffic against the quota,
expiry, domains, public ports — type `dashboard` (§7).

---

## 6. Putting a website on the internet

### There is no firewall, and you do not need one

`iptables` can be installed and does not work: a container is not given
`CAP_NET_ADMIN`, so the kernel refuses every rule with *Permission denied*
even though you are root. `nft` and every wrapper built on it end the same
way.

Nothing was taken from you, because there is nothing here for a firewall to
close. **Nothing inside this container is reachable from the internet unless
one of exactly two things is true:**

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

Inbound traffic — a domain's or a published port's — is delivered to the
container's own network interface, not to its loopback. So a service bound to
`127.0.0.1` accepts nothing from outside: the connection is established and
then answers with nothing, which reads as a broken application rather than a
wrong address.

```
listen 127.0.0.1:3000   →  connects, empty reply, no error anywhere
listen 0.0.0.0:3000     →  works
```

Binding `0.0.0.0` exposes nothing extra, because the only ways in are the two
above. Configs copied from a machine where the app sat behind a local nginx
almost always carry `127.0.0.1`, and that is the line to change.

Keep `127.0.0.1` for things whose only caller lives in this same container —
a PHP-FPM socket, a database that nothing outside talks to.

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
both forwarded to port 80 in here. You do not run certbot and you do not copy
a key anywhere.

Pointing the name's DNS at the machine is the half you do at your domain
provider; the address to point at is on the same card in the panel. Checks run
on a schedule and show as badges on each name, so a name that is not working
tells you which part is wrong.

If you would rather hold your own certificate, add the `self-hosted` keyword
and the machine splices the encrypted bytes through without ever seeing your
key:

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

For a static site or your own app, `apt install nginx` and put a server block
in `/etc/nginx/sites-available/`, then symlink it into
`/etc/nginx/sites-enabled/` and `systemctl reload nginx`. `nginx -t` first —
it checks the config and tells you the line number, and a reload with a broken
config leaves the old one running rather than taking your site down.

---

## 7. Traffic, limits and expiry, from inside

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

The same numbers print at every SSH login, above the prompt:

```
  System   Debian GNU/Linux 13 (trixie)
  Uptime   6d 4h
  CPU      4% of 2 cores
  Memory   734.0M of 2.0G (36%)
  Disk     11.0G of 40.0G (28%)
  Traffic  318.0G of 1.0T (29%) · 706.0G left
  Expires  2026-09-30 (in 41 days)
```

You can also read the kernel's own counters for the container's interface with
`ip -s link show tap0`. Those are honest bytes, but they are **not** the
meter: they reset when the container restarts and they say nothing about which
billing window you are in. Use them for "is something transferring right
now"; use `dashboard net` for "how much have I got left".

`helppage` is the guide, in here, with no browser: ports and domains,
installing software, backups, what each limit does, and what a reinstall
keeps. `helppage --list` names the pages and `helppage --text limits` prints
one as plain text.

---

## 8. `/data`, and reinstalling

**`/data` is the part that survives.** Everything else is the image plus your
changes to it, and a reinstall replaces exactly that. Databases, uploads,
anything you would be upset to lose: put it under `/data` and point your
services at it. `app-setup` already does this for the software it installs
when the container has a data disk.

```sh
reinstall                  # what this container can be rebuilt from
reinstall debian-13        # part of the name is enough
reinstall alpine-3.24      # ...or try the small one
```

It tells you what it would install and what you are about to lose, then asks
you to type the container's name. Your SSH session ends part-way through the
rebuild — that is what is supposed to happen. Log back in a minute later, same
address, same password.

Nothing about your limits, your domains or your public ports changes.

If the 164 MB of filesystem is more than you want to spend, or the container
is small enough that it matters, [Using Alpine](alpine.md) is the same set of
answers for a system a quarter the size — with an honest account of what it
costs.
