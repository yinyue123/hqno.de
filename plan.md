# Plan: three help pages, drawn step by step

**Status: built.** The pages are written and published, in English and 中文 —
see §8 for what changed on the way. This file stays because the brief below is
what the pages are held to, and the next page written has to meet it too.

Every figure below was the **draft of what went on the page**. One worked example
runs through all of it: an account called `ana`, a container called `wp-1` on a
machine at `hk-1.example.com`, and a domain `example.com` at `203.0.113.7`.

## The brief

These are the instructions the pages are written to. They outrank everything
else in this file, and anything below that breaks one of them is wrong.

1. **Three parts, for three moments.** What this is and how things are kept
   apart · a beginner's path from a share code to a working website · how
   somebody with hardware attaches it and hands a container out.
2. **English**, and written for **beginners**. Ordinary words. Avoid technical
   terms; where one cannot be avoided, gloss it in a clause the first time it
   appears — and never twice.
3. **How to use it, never how it is built.** No source, no file names, no
   internal names, no settings keys, no interfaces, no architecture. If a
   sentence only makes sense to somebody who has read the code, cut it.
4. **Do not teach the mechanism.** Part 1 goes exactly as far as *what keeps one
   person's things apart from another's* — enough to predict what happens.
   Nobody reading it cares how that is done; they care what they do.
5. **Explain with figures and examples, not paragraphs.** Text is tiring to
   read. Words are captions of a line or two under the picture.
6. **A figure for every step, showing the operation.** Not one example per part —
   one per step: the screen, the command with its answer, or a before/after.
   Detailed enough that somebody can follow it without reading around it.

How that is done on the page, which is mine to get right rather than yours:

- **Plain-text figures in code blocks**, under 60 columns. No plugin, identical
  on the site and on GitHub, cannot break the build, will not rot like a
  screenshot.
- **Real values, never `<your-thing>`** — somebody has to be able to compare
  their screen with ours, character by character.
- **Every step ends with what you should see**, and **each part ends with a
  symptom → fix table**.

---

## 1. The three pages

| Page | For | Leaves with |
|---|---|---|
| `how-it-works` | somebody who just got a container | can predict what is theirs |
| `quick-start` | somebody sent a share code | a website on their domain, over HTTPS |
| `running-a-machine` | somebody with a spare box | a machine attached, one container given away |

Sidebar grows to three groups, *Quick start* leads the top nav, the front page
gains a card for Part 3. Existing pages keep their addresses. Quick start owns
the *order*; `using-your-container` keeps owning the *consequences* and is linked
into, not repeated. Three things in it are out of date — §5.

---

## 2. Part 1 — How this works

Seven figures, almost no prose.

### 2.1 The whole thing on one page

```
  you ──sign in──▶ panel ──"do this"──▶ the machine
                                          │
   you, over ssh ─────────────────▶  ├─── your box
                                     ├─── Ana's box
   your visitors ─────────────────▶  └─── Wei's box
```

### 2.2 One machine, cut into pieces

```
        one machine, one Linux underneath
  ┌───────────┬───────────┬───────────┬──────────┐
  │  yours    │  Ana's    │  Wei's    │   ...    │
  │  1 core   │  ½ core   │  2 cores  │          │
  │  2 GB     │  1 GB     │  4 GB     │          │
  │  20 GB    │  10 GB    │  80 GB    │          │
  └───────────┴───────────┴───────────┴──────────┘
```

You administer your own column and cannot see into anybody else's. The numbers
are what your host sold you. Two words: the **host** owns the machine, the
**holder** was given a piece.

### 2.3 Your login is yours because of the username

```
  ssh u7k2m9p@hk-1.example.com  ─────▶  your box
  ssh u4b8x2q@hk-1.example.com  ─────▶  Ana's box
         └── the only difference
```

```
  change it in the panel   ──▶  changes how you get in
  passwd inside your box   ──▶  changes nothing
  rebuild your box         ──▶  login still works
```

### 2.4 Your website is yours because of the name

```
  a visitor types          and reaches
  ────────────────────     ──────────────────────
  shop.example.com   ───▶  your box,  port 80
  api.example.com    ───▶  your box,  port 3000
  blog.ana.dev       ───▶  Ana's box, port 80
```

One address for all of them; the **name** decides. No port number in your
address, and a name pointed here is yours while you hold it.

### 2.5 You do not have to know any commands

```
  root@wp-1:~# app-setup
```

```
  ┌ Suites ─ Web ─ Databases ─ Dev ─ System ─────────┐
  │                                                  │
  │ ▸ LNMP           web server + database + PHP     │
  │   WordPress      the blog four sites in ten use  │
  │   MariaDB        a database on its own           │
  │   Node.js        ...                             │
  │                                                  │
  │ Disk 600M RAM 768M   ↑↓ move  Enter open  q quit │
  └──────────────────────────────────────────────────┘
```

Enter opens it, and that page is where things happen:

```
  ┌ WordPress ───────────────────────────────────────┐
  │ [Install] [Start] [At boot] [Settings] [Docs]    │
  │                                                  │
  │ Settings                                         │
  │   Listen port   [ 80       ]                     │
  │   Site folder   [ /var/www ]                     │
  │   Enable HTTPS  [x]                              │
  │                                                  │
  │      [ Save & Apply ]  [ Save ]  [ Cancel ]      │
  └──────────────────────────────────────────────────┘
```

```
  ordinary software, ordinary places ─▶ tutorials still fit
  every entry says its size          ─▶ red if it won't fit
  a form, not a config file          ─▶ port, folder, on/off
```

### 2.6 Two ways to get the padlock

```
  your own certificate
    visitor ══encrypted═════════════════▶ your box
             passed through unread; you get it
             and you renew it

  a certificate the host looks after
    visitor ══encrypted══▶ machine ──plain──▶ your box
             the machine holds it and renews it
```

| | Your own | The host's |
|---|---|---|
| What you do | get one, renew it | press a button, once |
| Can the host read your traffic | no | yes |
| Pick it when | you have one already, or that must be "no" | you want a padlock and no homework |

### 2.7 What the panel is

```
  you ─────▶ panel ──"restart it please"──▶ the machine

  a visitor ────────────────────────────▶ your website
```

The panel is not on the second line: when it is down, your site answers and your
login works — the buttons wait.

---

## 3. Part 2 — Quick start: from a share code to a website

```
  1  claim the code        5  add your domain
  2  the two passwords     6  point DNS at the machine
  3  log in                7  send each name to a service
  4  install a website     8  turn on HTTPS
                           9  read the logs when it breaks
```

### Step 1 — Claim it

What you were sent, either shape:

```
  https://hqno.de/redeem?code=HQ-7F3K-2M9P
  HQ-7F3K-2M9P
```

```
  ┌ Redeem a share code ─────────────────────────────┐
  │  Share code      [ HQ-7F3K-2M9P             ]    │
  │  Shell username  [ ana        ]  optional        │
  │  Shell password  [            ]  generated       │
  │                                   [ Claim it ]   │
  └──────────────────────────────────────────────────┘
```

**You should see:**

```
  ┌ It is yours ─────────────────────────────────────┐
  │  ssh u7k2m9p@hk-1.example.com                    │
  │  password   8Kd2-vQx7-mR        shown once       │
  │  Copy it now — the panel does not keep it.       │
  └──────────────────────────────────────────────────┘
```

Claiming rewrites the login, so whoever sent the code can no longer get in. A
code stops working after 14 days; an expired one is not a lost container.

### Step 2 — The two passwords

```
  panel password  ──▶  the website you sign in to
  shell password  ──▶  your box
```

```
  ┌ Account ─────────────────────────────────────────┐
  │  Username  ana                                   │
  │  Email     ana@example.com          [ Change ]   │
  │  Password  ••••••••                 [ Change ]   │
  └──────────────────────────────────────────────────┘

  ┌ Get in ──────────────────────────── on wp-1 ─────┐
  │  ssh u7k2m9p@hk-1.example.com                    │
  │  Shell username  [ u7k2m9p ]                     │
  │  New password    [          ]        [ Set it ]  │
  └──────────────────────────────────────────────────┘
```

Shown once, replaced rather than recovered. Keys instead of a password: no form
for that yet — ask your host.

### Step 3 — Log in

```
  $ ssh u7k2m9p@hk-1.example.com
  The authenticity of host 'hk-1.example.com' can't be
  established. Continue connecting? yes
  Password:                    ← paste it; nothing appears
  root@wp-1:~#
```

**You should see** a prompt ending in `#`. Then, to look around:

```
  root@wp-1:~# free -h        how much memory you have
  root@wp-1:~# df -h /        how much disk
  root@wp-1:~# systemctl      what is running
```

Windows, macOS and Linux each get one line here. It asks the "authenticity"
question only the first time.

### Step 4 — Install a website

```
  root@wp-1:~# app-setup
```

Arrow keys to **LNMP**, Enter, then `[Install]`:

```
  ┌ Installing LNMP ─────────────────────────────────┐
  │  Reading package lists... done                   │
  │  Setting up nginx (1.24.0)                       │
  │  Setting up mariadb-server                       │
  │  Setting up php8.2-fpm                           │
  │  ████████████████████░░░░░  78%                  │
  └──────────────────────────────────────────────────┘
```

Read the size line before you press it:

```
  Disk 600M  RAM 768M      fits
  Disk 600M  RAM 768M      too big for this box   ← red
```

**You should see**, from inside the box:

```
  root@wp-1:~# curl -I http://127.0.0.1
  HTTP/1.1 200 OK
  Server: nginx/1.24.0
```

That is the site existing — before any domain or certificate.

### Step 5 — Change a setting, no config file

```
  before                      after Save & Apply
  ──────────────────          ──────────────────────
  Listen port [ 80   ]  ──▶   Listen port [ 8080 ]
                              nginx restarted on 8080
```

```
  [ Save & Apply ]   writes it and puts it into effect
  [ Save ]           writes it — "not in effect yet"
  [ Cancel ]         throws the edit away
```

### Step 6 — Add your domain

```
  ┌ Domains ──────────────────────────────── 0 of 10 ┐
  │  No domains yet.                                 │
  │                                 [ Add a domain ] │
  └──────────────────────────────────────────────────┘
```

Type `example.com`, then `www.example.com`:

```
  ┌ Domains ──────────────────────────────── 2 of 10 ┐
  │  example.com       DNS ·  HTTP ·  HTTPS ·     ⚙  │
  │  www.example.com   DNS ·  HTTP ·  HTTPS ·     ⚙  │
  │  Point them at 203.0.113.7                       │
  └──────────────────────────────────────────────────┘
```

This tells the machine the names are yours. It does not touch DNS and does not
get you a certificate.

### Step 7 — Point the name at the machine

At whoever sold you the domain:

```
  Type   Name   Value           makes this work
  ────   ────   ───────────     ─────────────────
  A      @      203.0.113.7     example.com
  A      www    203.0.113.7     www.example.com
```

Check it from your own computer, after a few minutes:

```
  $ nslookup example.com
  Name:     example.com
  Address:  203.0.113.7      ← the machine. Good.
```

The badges follow on their own — nothing to reload:

```
  DNS ·  HTTP ·  HTTPS ·   not checked yet
  DNS ✓  HTTP ✕  HTTPS ·   name arrives, nothing answers
  DNS ✓  HTTP ✓  HTTPS ·   answering — ask for HTTPS now
  DNS ✓  HTTP ✓  HTTPS ✓   done
```

Behind a home router, web traffic has to be forwarded to the machine or the name
resolves and nothing answers. Ask your host.

### Step 8 — Send each name to the right service

```
  example.com       ──▶  80     the web server you installed
  www.example.com   ──▶  80     the same one
  api.example.com   ──▶  3000   the app you wrote
```

The gear on a name:

```
  ┌ api.example.com ─────────────────────────────────┐
  │  DNS ✓   HTTP ✓   HTTPS ·                        │
  │  DNS     points here (203.0.113.7)               │
  │  HTTP    port [ 3000 ]              [ Test ]     │
  │  HTTPS   ( ) my certificate    port [ 443  ]     │
  │          (•) the host's        port [ 3000 ]     │
  │                       [ Request certificate ]    │
  │                          [ Save ]  [ Delete ]    │
  └──────────────────────────────────────────────────┘
```

What Test says, and what it means:

```
  ✓  answered in 3 ms
  ✕  nothing is listening on 3000   ← about your app
  ✕  the container is not running   ← start it first
```

Saving also opens that port for you, and says so:

```
  Publishing container port 3000 restarted this
  container's network for a moment.
```

### Step 9 — Turn on HTTPS

**The host's certificate** — press the button once:

```
  [ Request certificate ]
    HTTPS ⟳  requesting…                  under a minute
    HTTPS ✓  issued · renews 30 days before it expires
```

Refusals say why, and when to come back:

```
  ✕  example.com does not arrive here yet
  ✕  nothing answers on port 3000
  ✕  five requests this week already — try 18 Aug
```

One request an hour, five a week for one name: that is what the issuer allows,
and a sixth press would lock your own name out for days. Automatic renewals are
never refused.

**Your own certificate** — pick it, name the port your box handles secure
traffic on, then get and renew a certificate inside the box. Nothing outside it
will. There is nowhere to upload one to the panel.

**You should see:**

```
  in a browser:   example.com   ──▶  🔒  your site
  not proof:      curl http://example.com
```

### Step 10 — When it breaks, four places

```
  1  the badge         HTTP ✕ connection refused on 3000
  2  inside your box   systemctl status myapp
  3  the install log   /var/log/app-setup/wordpress.log
  4  the panel         this box's own history, newest first
```

```
  root@wp-1:~# systemctl status myapp
  ● myapp.service — failed (exit code 1)
  root@wp-1:~# journalctl -u myapp -n 20
```

```
  11 Aug 14:02  certificate issued for example.com
  11 Aug 13:58  api.example.com: http port 80 → 3000
  11 Aug 13:40  example.com added
```

Two failures leave no message at all:

```
  a service that keeps dying, log says nothing  ──▶ memory
  "no space left on device"                     ──▶ disk
```

### Step 11 — What survives a rebuild

```
  /etc/nginx/nginx.conf     gone
  /var/www/site             gone
  /root/notes.txt           gone
  /data/mysql               kept
  /data/uploads             kept
```

Traffic runs out → paused, not deleted. Time runs out → stopped, nothing
deleted. One line each, linked to the reference page.

### Step 12 — Symptom → fix

The table. Rows: cannot log in; asked for the password again and again; browser
shows somebody else's site; name not found; name found, nothing answers;
certificate warning; request refused with a date; a service that dies silently;
no space left; the panel says offline; everything slow.

---

## 4. Part 3 — Running a machine of your own

### 4.1 What has to be reachable

```
  your router                    the panel needs no way in:
    80, 443 ──▶ this machine     the machine calls out
    22      ──▶ this machine     and stays connected
       │                        │
       │            └───── logins
       └── your tenants' websites
```

Otherwise: a reasonably current Linux, administrator access, outbound network.
The supporting software installs itself.

### 4.2 Attach the machine

```
  ┌ Add a machine · step 1 of 2 ─────────────────────┐
  │  Run this on the machine, as root:               │
  │    curl -fsSL http://panel.example.com/agent | sh│
  │                                                  │
  │                          [ I've installed it ]   │
  └──────────────────────────────────────────────────┘

  ┌ Add a machine · step 2 of 2 ─────────────────────┐
  │  Then paste this into the same machine:          │
  │    hqnode enroll --panel http://panel.example.com│
  │                  --code A1B2-C3D4                │
  │  single use · expires in 15 minutes              │
  │                        waiting for the agent ⟳   │
  └──────────────────────────────────────────────────┘
```

**You should see:**

```
  ┌ Machines ────────────────────────────────────────┐
  │  hk-1   online    8 cores · 32 GB · 1.8 TB       │
  │         0 containers · CPU 3% · memory 11%       │
  └──────────────────────────────────────────────────┘
```

Detaching later makes the panel forget it and touches nothing on the machine.

### 4.3 The settings, one at a time

```
  ┌ Host settings ───────────────────────────────────┐
  │  Default processor  [ 50 % ] of one core         │
  │  Default memory     [ 1024 MB ]                  │
  │  Default swap       [ 512 MB ]                   │
  │  Default disk       [ 20480 MB ]                 │
  │  Default traffic    [ 500 GB / month ]           │
  │  Traffic reset day  [ 1 ]                        │
  │  [x] Let tenants bring their own system          │
  │                     [ Save host settings ]       │
  └──────────────────────────────────────────────────┘
```

```
  the defaults   ──▶ fill in the new-container form only
  reset day      ──▶ one traffic boundary for the machine
  own system     ──▶ they may rebuild from their own image,
                     and it costs them a download each time
```

The thing that *is* the product:

```
  processor  sold ½ core ─▶ faster while quiet, back to
                           ½ when busy         (a floor)

  memory     sold 1 GB   ─▶ ask for more, get killed (a wall)
```

The machine refuses a container it has no room for and says so, so there is no
number to keep by hand. Linked, not explained: which doors it listens on,
storage, the page that installs what is missing, keeping a system ready so
creating takes seconds.

### 4.4 Create one

```
  ┌ New container ───────────────────────────────────┐
  │  Machine       (•) hk-1                          │
  │  Who it is for ( ) mine    (•) a user's [ ana ]  │
  │  Name          [ wp-1 ]                          │
  │  Shell login   [ u7k2m9p ]  [ ••••••••• ]        │
  │  System        [ Debian 13 ▾ ]  on this host     │
  │  Size          1 core · 2 GB · 20 GB · 500 GB    │
  │  Expires       [ 2027-08-11 ]                    │
  │                                 [ Create it ]    │
  └──────────────────────────────────────────────────┘
```

**You should see:**

```
  ┌ wp-1 is running ─────────────────────────────────┐
  │  ssh u7k2m9p@hk-1.example.com                    │
  │  password  8Kd2-vQx7-mR         shown once       │
  │  ana holds this one                              │
  └──────────────────────────────────────────────────┘
```

### 4.5 Hand it over

```
  mine      ─▶ you hold the login ─▶ Give it away ─┐
  a user's  ─▶ you type their username ────────────┤
                                                   ▼
                                 theirs — and the login is
                                 rewritten, so yours stops
```

```
  ┌ Give it away ────────────────────────────────────┐
  │  https://hqno.de/redeem?code=HQ-7F3K-2M9P        │
  │  or the code alone:  HQ-7F3K-2M9P                │
  │  expires in 14 days                              │
  └──────────────────────────────────────────────────┘
```

Then point them at Part 2 — it starts exactly there.

### 4.6 Living with it

```
  change size or expiry   ──▶ takes effect on the box
  pause                   ──▶ stopped, kept, reversible
  time runs out           ──▶ stopped, nothing deleted
  traffic 80% / 100%      ──▶ warning / paused
  delete a container      ──▶ destroyed, space returned
  detach a machine        ──▶ panel forgets, box keeps running
```

### 4.7 Symptom → fix

Machine offline; create refused; a tenant cannot log in; a tenant's name
resolves but nothing answers; certificates fail for everybody; software missing
after a fresh install.

---

## 5. Three fixes to `using-your-container` this includes

1. it calls the code a **bind code** and sends you to the wrong page — the panel
   says **share code**, elsewhere;
2. it says adding a domain is the host's job; holders do it themselves now, and
   that section also predates per-name ports and certificates — it becomes a
   short section linking to steps 5–8;
3. its installer drawing shows buttons on the cards; today the card is a summary
   and **Enter** opens the page that has them.

---

## 6. Said plainly as missing

A form for SSH keys (ask your host); uploading a certificate to the panel (it
belongs in your box); a log viewer in the panel (logs are read inside the box).
Part 3 makes no claim that a host can switch the automatic certificates off,
because there is no such switch, and says in one line that a bigger account is
arranged by message rather than checkout.

---

## 7. Order of work

1. **How this works** — it defines the words.
2. **Quick start.**
3. The three fixes in §5.
4. **Running a machine.**
5. Sidebar, nav, front page last, so the site advertises only what exists.

Every page built and every link followed once before it is committed.

---

## 8. Done since, and how

Written and published: `how-it-works`, `quick-start`, `running-a-machine`, the
three fixes in §5, and the sidebar, nav and front page.

Then **中文**, as VitePress locales: English stays the root so its addresses do
not move, Chinese is `docs/zh/` with its own nav, sidebar and search words, and
the three pages plus the front page are translated. The rest is linked at in
English and labelled `（英文）` rather than hidden.

One thing the figures had to learn: a browser does not render Chinese at exactly
twice the width of a Latin character, so a box that is square in a terminal is
ragged on the page. The Chinese figures keep the left border and drop the right
one, every column boundary sits before the first Chinese character on the line,
and the one wide grid became a markdown table. `README.md` carries that rule for
whoever adds the next language.

---

## 9. Questions

1. **Enough figures now?** Roughly thirty across the three pages, one per step
   with its own before/after or output. Say if any step still reads as prose.
2. **The panel mock-ups are drawn, not photographed** — they show the fields and
   the buttons, not the styling. Fine, or do you want them to match the real
   layout more closely (wider boxes, exact wording)?
3. **Part 3's home** — here, or with the host-side notes in the product repo?
   Recommendation: here.
4. **Addresses** — `/how-it-works`, `/quick-start`, `/running-a-machine`.
