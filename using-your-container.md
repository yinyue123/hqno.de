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
| Your host gives you a **bind code** | Redeem it at **/bind**. You choose the shell login while you do. |

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

The container page shows the exact line. It looks like this:

```sh
ssh u7k2m9p@hk-1.example.com -p 22
```

That login is **not** an account on the host and not a Unix user inside the
container. It is a name held by the SSH gateway on the machine: the gateway
authenticates you, then steps into your container's namespaces and hands you a
root shell in it. Two consequences worth knowing up front:

- **`passwd` inside the container does not change how you log in.** The
  password lives with the gateway, not in the container's `/etc/shadow`.
  Change it in the panel, on the container page, under *Get in*.
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

You pick the image from the list your host offers on that machine. Some hosts
also allow **your own image reference** — a `ghcr.io/you/thing:tag` the *host*
pulls, so it has to be reachable from the machine, not from your laptop. If
the option is not there, your host has not enabled it.

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
| **vCPU** | You are throttled, never killed. Everything just runs slower. |
| **Memory** | The kernel squeezes you first and then OOM-kills the largest process. A service that keeps dying without an error in its log is usually this. |
| **Swap** | Pages you have not touched are moved out of memory rather than counted against it, up to this much. It buys you room, not speed: a container living in swap is a slow container. Zero means there is none, and memory is the whole of what you have. |
| **Disk** | Writes fail with "no space left on device". `/` and `/data` count together. |
| **Traffic** | See below — this one stops the container. |

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

If your host points a domain at your container, requests for it arrive at
your ports 80 and 443 — by SNI for TLS, by the Host header for plain HTTP.
Serve on those ports inside the container and it works; there is no separate
proxy for you to configure.

The names pointed at you are listed on the container page. Adding one is your
host's job: it needs both a DNS record and a route on the machine, and only
they can make the second.

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
