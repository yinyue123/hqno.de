# Using your container

You have been given a container on someone else's machine. It behaves like a
small virtual machine: you SSH in as root, install packages, run services, and
`top` shows you your own processes.

**This page is the map.** Almost everything you will want to do is written up
properly somewhere else — this says where. What is left here is the handful of
things that are about the *container* rather than about the system inside it:
what a reinstall does, what your limits do when you hit them, and what to look
at when something is wrong.

If you run the machines rather than hold a container, you want
[operating the panel](https://github.com/yinyue123/hqnode/blob/main/docs/operating-the-panel.md)
instead.

---

## Which system do you want

| If you want | Pick |
|---|---|
| **To squeeze the most out of a small box** | **[Alpine](alpine.md)** — 36 MB of filesystem and 15 MB of memory at an idle boot, against Debian's 164 MB and 105 MB. No systemd, no `apt`, no glibc, so instructions written for anything else have to be translated. That page is the translation, and it is honest about what it costs. |
| **An ordinary Linux, nothing to learn** | **[Debian](debian.md)** — bigger, and `apt`, `systemctl`, `journalctl`. Every blog post you find works as written. Pick this one if you are not sure. |

Ubuntu reads exactly like the Debian page. AlmaLinux, Rocky, CentOS and Fedora
read like it too, with `dnf` in place of `apt`. The full list of what you can
install is in §2, and [Alpine §1](alpine.md) breaks the two footprints down line by line — where the memory goes, where the disk goes, and which size of container each one suits.

You are not stuck with what you were handed: reinstalling onto another system
takes a minute and keeps `/data`.

---

## Where everything is

| I want to | It is here |
|---|---|
| Log in the first time, set a password | [Alpine §2](alpine.md) · [Debian §1](debian.md) |
| Add an SSH key | the same sections. The key goes in the panel at **Account → SSH keys**, never into the container |
| Install software | [Alpine §3–4](alpine.md) · [Debian §2](debian.md) |
| Start something at boot, or write a service of my own | [Alpine §3 and §6](alpine.md) · [Debian §2 and §4](debian.md) |
| Get an editor, `git`, `htop`, network tools | [Alpine §5](alpine.md) · [Debian §3](debian.md) |
| Read logs, processes, memory, disk | [Alpine §7–8](alpine.md) · [Debian §5–6](debian.md) |
| Put a website on my own domain, with HTTPS | [Quick start](quick-start.md) — four steps, from the name to the padlock |
| Open a raw port — game server, database, VPN | [Public ports](ports.md) |
| Back up and restore a database | [Backing up PostgreSQL](backup-postgresql.md) |
| Back up files and folders | [Backing up files](backup-files.md) |
| Build my own image and install it | [Building your own image](building-your-own-image.md) |
| Add my own software to the `app-setup` menu | [Adding your own software](app-setup-sources.md) |
| Read my container's numbers from a script or a monitor | [Panel REST API](api.md) |

**Three words to type on your first day**, all of them inside the container:

```sh
app-setup     # install software from a menu: LNMP, WordPress, databases, dev tools
dashboard     # what this box is, is allowed, and is using
helppage      # this guide, in here, with no browser
```

---

## 1. Getting one

A container becomes yours in one of two ways, and both end at the same place —
it appears under **My containers** in the panel.

| How | What you do |
|---|---|
| Your host binds it to your username | Nothing. Sign in and it is there. |
| Your host gives you a **share code** | Redeem it at **Containers → Redeem a share code**. You choose the shell login while you do. |

Either way it already exists and is already running before it reaches you:
your host picked the machine, the limits and the expiry, and built it from one
of the images in §2.

**If the account was made for you**, you have a username but no password yet.
Use **Forgot password** with the email your host gave you. Your username never
changes — it names your directory in the panel's store — but your email and
password are yours to change at **Account**.

One account holds containers from as many hosts as you like. There is no
separate login per machine.

The **password for the shell** is a different thing from your panel password,
and it is shown **once** — when the container was created, and again whenever
you set a new one. The panel keeps only a hash. Lost it? Set a new one, on the
container page or with `passwd` inside; there is nothing to recover.

---

## 2. Restart and Reinstall

Two buttons on the container page, and they are not the same size of thing.

**Restart** is safe. It stops and starts the container. Your filesystem, your
packages and your services are untouched.

**Reinstall** wipes `/` and rebuilds it from an image, **keeping `/data`**.
Every package you installed, every service you configured, every file outside
`/data`: gone. It cannot be undone, which is why the dialog makes you type the
container's name. Your shell login, your password and the address you SSH to
all survive it, and so do your domains and your limits.

That is also what makes `/data` worth using. Databases, uploads, anything you
would be upset to lose: put it under `/data` and point your services at it.

The same thing from a shell you are already sitting in:

```
reinstall                  what this container can be rebuilt from
reinstall debian-13        one of those images — part of the name is enough
reinstall ref ghcr.io/you/thing:tag
reinstall archive box.tar
```

Bare `reinstall` only ever prints the list. When you confirm, **your SSH
session ends** — the container is stopped part-way through the rebuild. That
is what is supposed to happen; log back in a minute later.

### Where the new image comes from

**From this host** is the list your host has cached on that machine. Those are
already unpacked there and shared by every container built from one, so
installing one downloads nothing, takes seconds and costs you no traffic. This
is the ordinary case.

**My own image** is a registry reference — `ghcr.io/you/thing:tag` — that the
*host* downloads. It is kept in your container's own disk, nobody else's, which
means it is downloaded again on **every** reinstall and **the download counts
against your traffic** each time. Your host may not have enabled this at all,
and a container with no disk of its own has nowhere to keep such an image; the
dialog says which. See [building your own image](building-your-own-image.md).

Some hosts also offer an **archive** on the machine, which is how a host whose
network cannot carry a 200 MB pull hands you an image anyway.

### The systems on offer

What your host has cached is what you can pick, and this is what hqnode
publishes for them to cache. Every one boots an init, so every one has
services, cron, a package manager and a working `top`.

| | Systems | Manager | Init |
|---|---|---|---|
| **Alpine** | 3.24, 3.23 | `apk` | OpenRC |
| **Debian** | 13, 12, 11 | `apt` | systemd |
| **Ubuntu** | 26.04, 24.04, 22.04, 20.04, 18.04\*, 16.04\* | `apt` | systemd |
| **AlmaLinux** | 10, 9, 8 | `dnf` | systemd |
| **Rocky** | 9, 8 | `dnf` | systemd |
| **CentOS** | Stream 10, Stream 9, 7\* | `dnf`, `yum` on 7 | systemd |
| **Fedora** | 43 | `dnf` | systemd |

\* Past end of life. They are here because people still ask for them, and they
still boot — but nothing in them gets a security update again. Do not put
anything on the internet from one.

AlmaLinux 10 and CentOS Stream 10 need a host CPU from roughly 2015 or later
(x86-64-v3). On an older machine they fail at the first command with a glibc
error about the CPU; your host will know whether their hardware clears it.

---

## 3. Your limits

Your host sets five numbers. The container page shows each against what you
are using, and **so does every SSH login**:

```
  System   Debian GNU/Linux 13 (trixie)
  Uptime   6d 4h
  CPU      4% of 2 cores
  Memory   734.0M of 2.0G (36%)
  Disk     11.0G of 40.0G (28%)
  Traffic  318.0G of 1.0T (29%) · 706.0G left
  Expires  2026-09-30 (in 41 days)
```

`dashboard` prints the rest — public ports, domains, how to log back in — and
`dashboard net` or `dashboard cpu mem` prints just a part of it.

| Limit | What hitting it feels like |
|---|---|
| **vCPU** | You are throttled, never killed. Everything just runs slower. |
| **Memory** | The kernel squeezes you, then OOM-kills the largest process. A service that keeps dying with nothing in its log is usually this. |
| **Swap** | Untouched pages move out of memory instead of counting against it. It buys room, not speed. Zero means memory is all you have. |
| **Disk** | Writes fail with "no space left on device". `/` and `/data` count together. |
| **Traffic** | At 80% the panel warns; at 100% it **suspends** the container — stopped, not deleted. |

Three of those are worth a sentence more:

**Your vCPU number is a floor, not a ceiling.** Cores nobody else wants are
yours, so a container sold half a core can run at two while its neighbours
idle, and drops back when they wake. A benchmark run twice gives two answers;
the honest one is taken when the machine is busy. If your host sold you a
**batch** container the deal is simpler: you get what is left over, and nothing
you run ever delays anyone — right for builds and overnight jobs, wrong for
anything somebody is waiting on.

**Swap is not extra memory.** The host usually keeps it compressed in RAM, so
cold pages cost a fraction of what they claim. A little is healthy on a small
container; a lot, on something that is also slow, means the working set does
not fit and more swap will not fix it.

**Traffic** is counted per month over a window starting on a day your host
picks — often the 1st, not always; the container page shows the date the
current window opened. Both directions count. A suspended container comes back
when the window rolls over, or sooner if your host raises the quota.

---

## 4. Expiry

Every container has an expiry date, and the panel warns you on the page for
the last week before it.

When the date passes, the container is stopped and its SSH login is disabled.
**Nothing is deleted.** Expiry is a switch, not a broom: the disk is exactly
as you left it. Ask your host to renew, and moving the date forward brings it
straight back — same data, same login.

---

## 5. When something is wrong

| What you see | What it usually is |
|---|---|
| SSH is refused | The container is expired or suspended (traffic quota). The panel says which. |
| SSH asks for the password again and again | Wrong password. Set a new one on the container page — the panel cannot show you the old one. |
| The page says the machine is offline | Your host's machine is not talking to the panel. Your container may still be running fine; nothing on the page can be changed until it is back. Ask your host. |
| Restart or Reinstall fails | Same thing: the panel could not reach the machine. |
| A service dies with no error | Usually memory. Watch the memory figure while it runs. |
| "No space left on device" | Disk. `/` and `/data` share one quota. |
| A domain or a published port connects but answers nothing | The service is bound to `127.0.0.1`. It has to be `0.0.0.0` — [Alpine §9](alpine.md) · [Debian §7](debian.md). |
| Everything is slow | CPU throttling, or the host itself is busy. The graph on your page covers the last seven days. |

The panel is not in the path of anything you run. If it is down, your
container keeps running and SSH keeps working — you just cannot restart or
reinstall until it is back.
