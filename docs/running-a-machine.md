# Running a machine of your own

You have a spare box, or a rented server, and you want to cut it into containers
and hand them out. This page takes you from that to one container in a friend's
hands.

The other side of this — what your tenants see and do — is
[quick start](quick-start.md). Reading it once is the fastest way to understand
what you are selling.

---

## 1. What has to be reachable

The machine calls the panel and keeps that connection open, so the panel needs no
way in at all. Your tenants do:

```
  from the internet        to this machine
  ─────────────────       ───────────────────────
  port 80, 443     ───▶   your tenants' websites
  port 22          ───▶   your tenants' logins
  nothing at all   ───▶   the panel: it never
                          connects in. The machine
                          calls out and stays on.
```

Behind a home router that means three forwarded ports. On a rented server with a
public address it usually means nothing at all.

Otherwise the list is short:

```
  a reasonably current Linux      administrator access on it
  an outbound connection          no fixed address needed
```

The supporting software a container needs is installed for you, every time the
machine starts, and the machine's page in the panel says how that went.

---

## 2. Nothing to switch on

There is no separate host account and no application to make. Any account can
attach a machine, and the same login can hold somebody else's container at the
same time:

```
  your one account   ─▶ machines you run
                     ─▶ containers other people gave you
```

So the whole of this step is: sign in, and open **Machines**.

---

## 3. Attach the machine

**Machines → Add machine**, and it is two steps.

```
  ┌ Add a machine · step 1 of 2 ───────────────────────┐
  │  Run this on the machine, as root:                 │
  │    curl -fsSL http://panel.example.com/agent | sh  │
  │                            [ I've installed it ]   │
  └────────────────────────────────────────────────────┘
```

```
  ┌ Add a machine · step 2 of 2 ────────────────────────┐
  │  Then paste this into the same machine:             │
  │    hqnode enroll --panel http://panel.example.com   │
  │                  --code A1B2-C3D4                   │
  │  single use · expires in 15 minutes                 │
  │                          waiting for the agent ⟳    │
  └─────────────────────────────────────────────────────┘
```

The page fills in your panel's own address in both lines, so you copy rather than
type. If your panel can be reached at more than one address it asks which one the
*machine* should use and times each from your browser first — your route is not
necessarily the machine's.

**You should see** it appear on its own, within a few seconds of the second
command:

```
  ┌ Machines ────────────────────────────────────────┐
  │  hk-1   online    8 cores · 32 GB · 1.8 TB       │
  │         0 containers · CPU 3% · memory 11%       │
  └──────────────────────────────────────────────────┘
```

Two things to know now rather than later:

```
  the address tenants connect to  ─▶ chosen as it attaches
  detaching it later              ─▶ panel forgets; the
                                     machine keeps running
```

---

## 4. The settings, one at a time

On the machine's page:

```
  ┌ Host policy ─────────────────────────────────────┐
  │  Default vCPU       [ 50 % ] of one core         │
  │  Default memory     [ 1024 MB ]                  │
  │  Default swap       [ 512 MB ]                   │
  │  Default disk       [ 20480 MB ]                 │
  │  Default traffic / month  [ 500 GB ]             │
  │  Traffic reset day  [ 1 ]                        │
  │  [x] Let users bring their own images            │
  │                     [ Save host settings ]       │
  └──────────────────────────────────────────────────┘
```

```
  the defaults   ─▶ fill in the new-container form, and
                    never touch a container already given out
  reset day      ─▶ the day of the month every container
                    here starts counting traffic again
  own images     ─▶ a tenant may rebuild from an image of
                    their own; it costs them a download,
                    against their own traffic, every time
```

### The two numbers that are the whole product

```
  vCPU     sold ½ core ─▶ faster while the machine is quiet,
                          back to ½ when it is busy  (a floor)

  memory   sold 1 GB   ─▶ ask for more, get killed   (a wall)
```

Read that before you price anything. A processor share is a guarantee at the
bottom, not a ceiling at the top — so the same container benchmarks twice as fast
on a quiet night, and the honest answer to "how fast is this" is the busy one.
Memory has no such kindness: at the line, the biggest process in that container
is killed.

You do not have to guess how many containers fit. The machine refuses one it has
no room for and says so in a sentence, and its page tells you which way the wind
is blowing:

```
  Tenants are queueing — this host has sold what it has.
  Comfortable: there is still headroom to sell.
```

### The rest of the page, in one line each

```
  Ports      move the web or login doors somewhere else
  Storage    where containers keep their files
  Advanced   what is missing, and a button that installs it
  Images     keep a system ready so creating takes seconds
             and downloads nothing
```

One thing worth turning on early is in **Advanced**: without it, a container's
`free` and `top` show the whole machine's memory rather than its own. Limits are
enforced exactly as sold either way — it only changes what the numbers say — but
tenants read those numbers and file support requests about them.

---

## 5. Create a container

```
  ┌ New container ───────────────────────────────────┐
  │  Where           (•) hk-1                        │
  │  Who it is for   ( ) Mine   (•) A user's [ ana ] │
  │  Container name  [ wp-1 ]                        │
  │  Shell login     [ u7k2m9p ] [ ••••••••• ]       │
  │  Image           [ Debian 13 ▾ ] from this host  │
  │  Limits          1 core · 2 GB · 20 GB · 500 GB  │
  │  Expiry          never — or pick a date          │
  │  Domains         (optional)                      │
  │                                 [ Create it ]    │
  └──────────────────────────────────────────────────┘
```

**Who it is for** is the choice that decides what happens next:

```
  mine       ─▶ nobody attached. You get the login, and can
                hand it over whenever you like.
  a user's   ─▶ handed over as it is created. They change
                the login on their own page; you never see
                it again.
```

Pick an image the machine already has and the create downloads nothing and takes
seconds — one copy on the machine is shared by every container built from it.

**You should see:**

```
  ┌ wp-1 is running ─────────────────────────────────┐
  │  ssh u7k2m9p@hk-1.example.com                    │
  │  password  8Kd2-vQx7-mR         shown once       │
  │  ana holds this one                              │
  └──────────────────────────────────────────────────┘
```

Shown once means shown once: the panel does not keep it. If it is lost, reset it
from the container's page.

---

## 6. Hand it over

```
  mine      ─▶ you hold the login ─▶ Give it away ─┐
  a user's  ─▶ you type their username ────────────┤
                                                   ▼
                                 theirs — and the login is
                                 rewritten, so yours stops
```

**Give it away** produces a link and a code. Send either:

```
  ┌ Give it away ────────────────────────────────────┐
  │  https://hqno.de/redeem?code=HQ-7F3K-2M9P        │
  │  or the code alone:  HQ-7F3K-2M9P                │
  │  expires in 14 days                              │
  └──────────────────────────────────────────────────┘
```

Nothing changes until they claim it, and you can issue a fresh code from the
container's page whenever one runs out. The moment they do claim it, the shell
login is rewritten — so your copy stops working, which is the point.

Then send them to [quick start](quick-start.md). It begins exactly where your
share code leaves them.

---

## 7. Living with it

```
  change limits or expiry  ─▶ applies to the running box
  pause                    ─▶ stopped, kept, reversible
  expiry date passes       ─▶ stopped; nothing deleted, and
                              moving the date brings it back
  traffic 80% / 100%       ─▶ warning / paused
  delete a container       ─▶ destroyed; space returned
  detach a machine         ─▶ panel forgets it; containers
                              keep running on the machine
```

Because those last two differ: deleting the containers first is the tidy way to
retire a machine. Detaching alone leaves them running on hardware the panel no
longer knows about.

Keeping the machine's software current is driven from its page, and a bigger
account — more containers than your plan allows — is arranged by message rather
than by checkout; the Plans page says how.

---

## 8. When something is wrong

| What you see | What it usually is |
|---|---|
| The machine says offline | It cannot reach the panel. Check the machine is on and its outbound connection works; nothing on it needs an open port. |
| A create is refused | The machine has no room in memory or processor for that size, and says which. Sell smaller, or wait for load to drop. |
| A create from the market fails, and creating it again says the name is already used | The machine was still downloading the system when the panel stopped waiting — it finished building the container anyway, and the panel never recorded it. Cache the system first from **Images**, then create from *this host*, which downloads nothing. Clear the stray one on the machine itself with `hqnode rm <name>`. |
| A tenant cannot log in | Their container is stopped, out of time, or paused for traffic — or port 22 is not reaching the machine. |
| A tenant's name resolves but nothing answers | Either nothing is listening inside their container, or web traffic is not being forwarded to the machine. |
| Certificates fail for every tenant | The machine's secure door has been moved off its usual port. Requests are refused before the certificate issuer is ever contacted. |
| Containers show the machine's memory, not their own | The option in **Advanced** is not installed. Containers already running keep the old numbers until they restart. |
| Software missing right after attaching | It installs on its own at every start; the machine's page says what failed and what to run by hand if it cannot. |

---

## Where next

- [Quick start](quick-start.md) — what your tenants do, in order.
- [How this works](how-it-works.md) — the short version, for explaining it to
  somebody.
- [Building your own image](building-your-own-image.md) — offering a system that
  is not on the published list.
