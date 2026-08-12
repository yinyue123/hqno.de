# Using your container

You have been given a container on someone else's machine. It behaves like a
small virtual machine: it boots systemd, you SSH in as root, you install
packages and run services, and `top` shows you your own processes. This is
what you need to know to live in it.

If you run the machines rather than hold a container, you want
[operating the panel](https://github.com/yinyue123/hqnode/blob/main/docs/operating-the-panel.md)
instead.

---

## 1. Getting one

A container becomes yours in one of two ways, and both end at the same place —
it appears under **My containers** in the panel.

| How | What you do |
|---|---|
| Your host binds it to your username | Nothing. Sign in and it is there. |
| Your host gives you a **share code** | Redeem it at **Containers → Redeem a share code**. You choose the shell login while you do. |

Either way the container already exists and is already running before it
reaches you: your host picked the machine, the limits and the expiry, and
built it from one of the images below. If that is not the system you wanted,
reinstall it yourself — see below. Nothing about the limits changes when you
do.

**If the account was made for you**, you have a username but no password yet.
Use **Forgot password** with the email your host gave, and the reset link turns
it into an account you can sign in to. Your username never changes — it names
your directory in the panel's store — but your email and password are yours to
change at **Account**.

One account holds containers from as many hosts as you like. There is no
separate login per machine.

---

## 2. Getting in

The container page shows the user, the host and the port. Put together, they are
the line you run:

```sh
ssh u7k2m9p@hk-1.example.com -p 22
```

That login is **not** an account on the host and not a Unix user inside the
container. It is a name held by the SSH gateway on the machine: the gateway
authenticates you, then steps into your container's namespaces and hands you a
root shell in it. Two consequences worth knowing up front:

- **`passwd` inside the container does not change how you log in.** The
  password lives with the gateway, not in the container's `/etc/shadow`.
  Change it in the panel, on the container page, under
  *Actions → Shell login → Reset password*.
- **A reinstall does not cost you your login.** The gateway's copy is outside
  the filesystem being replaced.

The password is shown **once** — when the container was created, and again
whenever you set a new one. The panel does not keep it: it goes to the machine,
which stores only a hash, and to your screen that one time. Lost it? Set a new
one; there is nothing to recover.

**SSH keys.** The gateway can hold public keys, but the panel has no form for
them yet. If you want key-only access, ask your host to add one for you.

---

## 3. Living in it

It is a system container, so the things you would do on a VM work:

```sh
apt install nginx            # or dnf, depending on your image
systemctl enable --now nginx
journalctl -u nginx -f
crontab -e
top
```

systemd is PID 1. `systemctl reboot` works and restarts the container in
place. If it is wedged badly enough that you cannot reach it at all, use
**Restart** in the panel, which does the same thing from outside.

### Installing software without reading four blog posts

Type `app-setup`.

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

A full-screen picker, arranged in five tabs — Suites, Web servers, Databases,
Dev tools, System. Arrow keys move and **Enter** opens the one under the cursor;
its own page carries the buttons — Install, Uninstall, Start or Stop, whether it
comes back at boot, **How to use it** — which names every file that package
wrote — the log of the last run, and **Settings** for packages that declare any.
`L` switches between English and 中文, `q` quits, and the mouse works too.

Each card says how much disk and memory the thing needs, **and turns that line
red when this container is too small for it** — which is the number nobody
tells you before an install dies four minutes in.

It works from the command line as well, which is what you want in a script:

```sh
app-setup list                # everything, with sizes and current state
app-setup install lnmp        # nginx + MariaDB + PHP, wired together
app-setup install wordpress   # ...and WordPress on top of it, database and all
app-setup docs wordpress      # what that recipe knows about itself
app-setup status nginx        # exit 0 running, 1 stopped, 2 not installed
```

It installs your distribution's own packages into your distribution's own
paths. Nothing here is a private build, so the next set of instructions you
read still applies, and security updates arrive through `apt` or `dnf` the
usual way. Generated passwords go to `/root/.app-setup/`, mode 600, rather than
scrolling past in the install log.

Uninstalling never deletes your data. Removing WordPress drops its database and
its files but moves your uploads to `/root/` first, and says so.

Adding your own software to the menu is writing one shell script and dropping
it into `/etc/app-setup/` — see
[adding your own software](app-setup-sources.md).

**`/data` is the part that survives.** Everything else is the image plus your
changes to it, and a reinstall replaces exactly that. Databases, uploads,
anything you would be upset to lose: put it under `/data` and point your
services at it.

---

## 4. Restart and Reinstall

Two buttons on the container page, and they are not the same size of thing.

**Restart** is safe. It stops and starts the container. Your filesystem, your
packages and your services are untouched.

**Reinstall** wipes `/` and rebuilds it from an image, keeping `/data`. Every
package you installed, every service you configured, every file outside
`/data`: gone. It cannot be undone, which is why the dialog makes you type the
container's name. Your shell login and password survive it, and so does the
address you SSH to.

There are two places the new image can come from, and the dialog keeps them
apart because they behave differently.

**From this host** is the list your host has cached on that machine. Those
images are already unpacked there and shared by every container built from
one, so installing one downloads nothing, takes seconds, and costs you no
traffic. This is the ordinary case.

**My own image** is a full registry reference — `ghcr.io/you/thing:tag` — that
the *host* downloads, so it has to be reachable from the machine and not from
your laptop. It is unpacked into your container's own disk, which has three
consequences worth knowing before you pick it:

- it is yours alone; nobody else on that machine is offered it, and the host
  keeps no copy of it;
- because no copy is kept, it is downloaded again on **every** reinstall;
- **the download counts against your container's traffic**, every time.

If your host happens to already have that exact image, it uses its own copy
instead: nothing is downloaded and nothing is charged.

Two things can hide the second option. Your host may not have enabled it at
all, and a container with no disk size of its own has nowhere to keep an image
only it can see — the dialog says which of the two it is. See
[building your own image](building-your-own-image.md).

### The systems on offer

What your host has cached on that machine is what you can pick, and the list
below is what hqnode publishes for them to cache. Every one boots systemd and
behaves the same way; the difference is the package manager and how long the
release is supported.

| | Systems |
|---|---|
| **Debian** | 13, 12, 11 |
| **Ubuntu** | 26.04, 24.04, 22.04, 20.04, 18.04\*, 16.04\* |
| **AlmaLinux** | 10, 9, 8 |
| **Rocky** | 9, 8 |
| **CentOS** | Stream 10, Stream 9, 7\* |
| **Fedora** | 43 |

\* Past end of life. They are here because people still ask for them, and they
still boot — but nothing in them gets a security update again. Do not put
anything on the internet from one.

Your host caches these onto the machine before you can pick one, and they
unpack under `/var/lib/hqnode/images/` there — not inside your container,
which never sees them as files.

AlmaLinux 10 and CentOS Stream 10 need a host CPU from roughly 2015 or later
(x86-64-v3). On an older machine they fail at the first command with a glibc
error about the CPU; that is the distro's own requirement, and your host will
know whether their hardware clears it.

---

## 5. Limits, and what hitting them feels like

Your host sets five numbers. The container page shows each one against what
you are using.

| Limit | At the ceiling |
|---|---|
| **vCPU** | You are throttled, never killed. Everything just runs slower. It is a share rather than a wall: when the machine is quiet you may run faster than the number, and the number is what you are guaranteed when it is not. |
| **Memory** | The kernel squeezes you first and then OOM-kills the largest process. A service that keeps dying without an error in its log is usually this. |
| **Swap** | Pages you have not touched are moved out of memory rather than counted against it, up to this much. It buys you room, not speed: a container living in swap is a slow container. Zero means there is none, and memory is the whole of what you have. |
| **Disk** | Writes fail with "no space left on device". `/` and `/data` count together. |
| **Traffic** | See below — this one stops the container. |

**Your vCPU number is a floor, not a ceiling.** Cores nobody else wants are
yours to use, so a container sold half a core can run at two while its
neighbours idle, and drops back to its half when they wake up. That is why a
benchmark run twice gives two answers: the honest reading of "how fast is this
container" is the one taken when the machine is busy.

If your host sold you a **batch** container, the deal is different and simpler:
you get whatever is left over after everybody else, and nothing you run ever
delays them. Perfect for builds, scrapers and overnight jobs; wrong for
anything somebody is waiting on.

**Swap is not extra memory.** It is somewhere for the parts of your container
that are sitting still, and the host usually keeps it compressed in RAM, so
cold pages cost a fraction of what they claim. The container page prints how
much of yours is in swap beside the memory figure — a number that only appears
when it is not zero. A little is healthy on a small container. A lot, on
something that is also slow, means the working set does not fit and more swap
will not fix it.

**Traffic** is counted per month over a window that starts on a day your host
picks (often the 1st, but not always — the container page shows the date the
current window opened). Both directions count. At 80% the panel records a
warning; at 100% it **suspends the container**, which means it is stopped, not
deleted. It comes back when the window rolls over, or sooner if your host
raises the quota.

---

## 6. Expiry

Every container has an expiry date, and the panel warns you on the page for
the last week before it.

When the date passes, the container is stopped and its SSH login is disabled.
**Nothing is deleted.** Expiry is a switch, not a broom: the disk is exactly
as you left it. Ask your host to renew, and moving the date forward brings it
straight back — same data, same login.

---

## 7. Domains

You add your own names, on the container page, up to a limit your host sets
(ten unless they changed it). Adding one tells the machine the name is yours;
pointing its DNS at the machine is yours to do at your domain provider, and the
address to point at is on the same card.

Each name then carries its own settings: whether it serves **HTTP**, **HTTPS** or
both; **which container port** each of those reaches — 80 unless you change it, so
one container can serve several sites from several services; and, for HTTPS,
either *our certificate, issued for you* (the machine obtains it and renews it
before it expires) or *your certificate · SNI passthrough* (the machine splices
the encrypted bytes on and never holds your key). Checks run on a schedule and
show as badges on each name, so a name that is not working says which part is
wrong.

[Quick start](quick-start.md) walks all of that through, from adding the name to
the padlock, in four steps.

---

## 8. When something is wrong

| What you see | What it usually is |
|---|---|
| SSH is refused | The container is expired or suspended (traffic quota). The panel says which. |
| SSH asks again and again | Wrong password. Set a new one on the container page — the panel cannot show you the old one. |
| The page says the machine is offline | Your host's machine is not talking to the panel. Your container may still be running fine; nothing on the page can be changed until it is back. Ask your host. |
| Restart or Reinstall fails | Same thing: the panel could not reach the machine. |
| A service dies with no error | Usually memory. Check the memory figure on the container page while it runs. |
| "No space left on device" | Disk. `/` and `/data` share one quota. |
| Everything is slow | CPU throttling, or the host itself is busy. The graph on your page covers the last seven days. |

The panel is not in the path of anything you run. If it is down, your
container keeps running and SSH keeps working — you just cannot restart or
reinstall until it is back.
