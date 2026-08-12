# Quick start

Somebody sent you a share code. By the end of this page you have a website of
your own, on your own domain name, with a padlock in the address bar.

One example runs all the way through, so you can compare your screen with this
one line by line:

<FigRows :rows="[
  [{ t: 'account', tone: 'mute' }, { m: 'ana' }],
  [{ t: 'container', tone: 'mute' }, { m: 'wp-1' }, { t: 'on the machine', tone: 'mute' }, { m: 'hk-1.example.com' }],
  [{ t: 'domain', tone: 'mute' }, { m: 'example.com' }, { t: 'and', tone: 'mute' }, { m: 'www.example.com' }],
  [{ t: 'the machine', tone: 'mute' }, { m: '203.0.113.7' }],
]" />

Every value will be different for you, and nothing else will.

<FigRows :rows="[
  [{ t: '1', tone: 'accent' }, 'claim the code', { t: '5', tone: 'accent' }, 'add your domain'],
  [{ t: '2', tone: 'accent' }, 'the two passwords', { t: '6', tone: 'accent' }, 'point the name at the machine'],
  [{ t: '3', tone: 'accent' }, 'log in', { t: '7', tone: 'accent' }, 'send each name to a service'],
  [{ t: '4', tone: 'accent' }, 'install a website', { t: '8', tone: 'accent' }, 'turn on HTTPS'],
  [null, null, { t: '9', tone: 'accent' }, 'read the logs when it breaks'],
]" />

Steps 1 to 4 need nothing but the code. Steps 5 onwards need a domain name — buy
one anywhere; it costs about the price of a coffee a year.

---

## 1. Claim the code

What you were sent looks like one of these:

<FigRows :rows="[
  [{ m: 'https://hqno.de/redeem?code=HQ-7F3K-2M9P' }],
  [{ m: 'HQ-7F3K-2M9P' }],
]" />

Open the link, or go to **Containers → Redeem a share code**. If you are not
signed in it offers to sign you in or create an account first, then comes back to
the code. Signing up asks for a username, an email and a password, and nothing
else — there is one kind of account here, and one account holds containers from
as many people as you like.

<FigScreen title="Redeem a share code" :lines="[
  ['Share code', { f: 'HQ-7F3K-2M9P' }],
  ['Shell username', { f: 'ana', note: 'optional' }],
  ['Shell password', { f: '', note: 'generated' }],
  { align: 'right', cols: [{ b: 'Claim it' }] },
]" />

Leave the bottom two blank and they are made up for you. **You should see:**

<FigScreen title="It is yours" :lines="[
  [{ m: 'ssh u7k2m9p@hk-1.example.com' }],
  { cols: ['password', { t: '8Kd2-vQx7-mR', face: 'mono' }, { t: 'shown once', face: 'small', tone: 'bad' }] },
  [{ t: 'Copy it now — the panel does not keep it.', face: 'small', tone: 'mute' }],
]" />

Copy that password somewhere safe before you leave the page. It is shown once and
nowhere else; a lost one is replaced, not recovered (step 2).

Two things worth knowing now: claiming rewrites the login, so whoever sent you
the code can no longer get in. And a code stops working 14 days after it was
made — an expired code is not a lost container, so ask for a fresh one.

**If the account was made for you** rather than by you, you have a username and no
password yet. Use **Forgot password** with the email your host used, and the link
it sends turns it into an account you can sign in to.

---

## 2. The two passwords

The one thing everybody mixes up. You have two, and they open different things:

<FigRows :arrow="0" :rows="[
  [{ t: 'panel password', tone: 'strong' }, 'the website you sign in to'],
  [{ t: 'shell password', tone: 'strong' }, 'your box'],
]" />

Change the first under **Account**:

<FigScreen title="Account" :lines="[
  ['Username', { t: 'ana', face: 'mono' }],
  { cols: ['Email', { t: 'ana@example.com', face: 'mono' }, { b: 'Change' }] },
  { cols: ['Password', { t: '••••••••', face: 'mono' }, { b: 'Change' }] },
]" />

Change the second on your container's page, under **Actions → Shell login →
Reset password**:

<FigScreen title="Reset the shell login" :lines="[
  ['Shell username', { f: 'u7k2m9p' }],
  ['New password', { f: '', note: 'leave blank to generate one' }],
  { align: 'right', cols: [{ b: 'Set it' }] },
]" />

The new one is shown once, and the old one stops working immediately — so do this
when you are not in the middle of something. Your username never changes in the
panel; the shell username above is a different name and you may change it as
often as you like.

Prefer a key to a password? The machine's door can hold public keys, but the
panel has no form for them yet — ask your host to add yours.

---

## 3. Log in

Your container's page shows the three parts you need — **User**, **Host** and the
port beside it. Put them together like this:

<FigRows :rows="[
  [{ m: 'ssh u7k2m9p@hk-1.example.com' }, { t: 'port 22', tone: 'mute' }],
  [{ m: 'ssh u7k2m9p@hk-1.example.com -p 2222' }, { t: 'any other port', tone: 'mute' }],
]" />

Then open a terminal:

<FigRows :rows="[
  [{ t: 'Windows 10 or later', tone: 'strong' }, 'PowerShell, or Terminal'],
  [{ t: 'macOS', tone: 'strong' }, 'Terminal'],
  [{ t: 'Linux', tone: 'strong' }, 'any terminal'],
]" />

```
  $ ssh u7k2m9p@hk-1.example.com
  The authenticity of host 'hk-1.example.com' can't be
  established. Continue connecting? yes
  Password:                    ← paste it; nothing appears
  root@wp-1:~#
```

Nothing appears while you type or paste the password. That is on purpose, not a
broken keyboard. The *authenticity* question comes up only the first time.

**You should see** a prompt ending in `#`. You are the administrator of your own
system now:

```
  root@wp-1:~# free -h        how much memory you have
  root@wp-1:~# df -h /        how much disk
  root@wp-1:~# systemctl      what is running
  root@wp-1:~# reboot         restarts your box, safely
```

If it refuses you, jump to [step 10](#_10-when-something-is-wrong) — the usual
reasons are a wrong password and a container that is stopped.

---

## 4. Install a website

Type one word:

```
  root@wp-1:~# app-setup
```

<FigScreen :tabs="['Suites', 'Web servers', 'Databases', 'Dev', 'System']" :lines="[
  [{ t: '▸', tone: 'accent' }, { t: 'LNMP', tone: 'accent' }, { t: 'web server + database + PHP', tone: 'mute' }],
  ['', 'WordPress', { t: 'the blog four sites in ten use', tone: 'mute' }],
  ['', 'MariaDB', { t: 'a database on its own', tone: 'mute' }],
  ['', 'Node.js', { t: '…', tone: 'mute' }],
  [{ t: 'Disk 600M   RAM 768M', face: 'small', tone: 'mute' }],
  [{ t: '↑↓←→ move     Enter open     ↑ at the top is Back', face: 'small', tone: 'mute' }],
]" />

<FigRows :rows="[
  [{ t: '↑ ↓ ← →' }, 'move', { t: 'L', tone: 'accent' }, 'English / 中文'],
  [{ t: 'Enter' }, 'open it', { t: 'q', tone: 'accent' }, 'quit'],
  [{ t: '↑ at the top' }, 'go back', null, { t: 'the mouse works too', tone: 'mute' }],
]" />

For a first website, pick one of these two and press Enter, then `[Install]`:

<FigRows :rows="[
  [{ t: 'LNMP', tone: 'strong' }, 'a web server, a database and PHP, wired up'],
  [{ t: 'WordPress', tone: 'strong' }, 'the same, plus WordPress and its database'],
]" />

Before you press it, read the size line on the entry — it turns **red** when your
box is too small for that package, which is the one number nobody tells you
before an install dies four minutes in:

<FigRows :rows="[
  [{ t: 'Disk 600M   RAM 768M' }, { t: 'fits', tone: 'ok' }],
  [{ t: 'Disk 600M   RAM 768M', tone: 'bad' }, { t: 'too big for this box — shown in red', tone: 'bad' }],
]" />

Then it runs, and you watch it:

<FigScreen title="Installing LNMP" :lines="[
  [{ t: 'Reading package lists... done', face: 'mono', tone: 'mute' }],
  [{ t: 'Setting up nginx (1.24.0)', face: 'mono', tone: 'mute' }],
  [{ t: 'Setting up mariadb-server', face: 'mono', tone: 'mute' }],
  [{ t: 'Setting up php8.2-fpm', face: 'mono', tone: 'mute' }],
  [{ bar: 0.78, label: '78%' }],
]" />

**You should see** a working web server from inside your own box:

```
  root@wp-1:~# curl -I http://127.0.0.1
  HTTP/1.1 200 OK
  Server: nginx/1.24.0
```

That is the site existing — before any domain name or certificate is involved. If
this does not answer, no amount of domain work will help, so fix it here.

Two more things it does for you: passwords it generates are written into
`/root/.app-setup/` instead of scrolling past, and removing something never
deletes your data — it moves what you would miss into `/root/` first and says so.

The same thing works without the menu, which is what you want in a script:

```
  root@wp-1:~# app-setup list
  root@wp-1:~# app-setup install lnmp
  root@wp-1:~# app-setup status nginx
  root@wp-1:~# app-setup docs wordpress
```

Something you want that is not in the list? You can write one entry of your own:
[adding your own software](app-setup-sources.md).

---

## 5. Change how it is configured

Open your software with Enter. The buttons are on that page, and so is the answer
to "where do I change things?":

<FigScreen title="Nginx" :lines="[
  { pack: true, cols: [{ b: 'Uninstall' }, { b: 'Stop' }, { b: 'Start at boot' }, { b: 'Settings' }] },
  { pack: true, cols: [{ b: 'How to use it' }, { b: 'Log' }] },
  [{ t: 'Settings', tone: 'strong' }],
  [{ t: 'This software has no settings to change.', tone: 'mute' }],
]" />

Almost everything that ships today is configured in its own file rather than in a
form — and **How to use it** names the files, so you never have to go looking:

```
  root@wp-1:~# app-setup docs nginx
  Nginx

    Where things are
      /var/www/html                     your site's files
      /etc/nginx/conf.d/app-setup.conf  the default site
      /var/log/nginx/error.log          read this first
```

So a change is three commands, and the middle one is the important one — it
refuses to reload a broken config instead of taking your site down:

```
  root@wp-1:~# nano /etc/nginx/conf.d/app-setup.conf
  root@wp-1:~# nginx -t
  nginx: ... test is successful
  root@wp-1:~# systemctl reload nginx
```

**When a package does have settings**, the form is filled in with its own fields
and has three buttons:

<FigRows :rows="[
  [{ b: 'Save & Apply' }, 'writes them and puts them into effect'],
  [{ b: 'Save' }, { t: 'writes them — “not in effect yet”', tone: 'mute' }],
  [{ b: 'Cancel' }, { t: 'throws the edit away', tone: 'mute' }],
]" />

```
  root@wp-1:~# app-setup set myapp port=8080   scripted
```

Anything you add to the menu yourself can declare those fields —
[adding your own software](app-setup-sources.md) shows how.

---

## 6. Add your domain

On your container's page, find **Domains**:

<FigScreen title="Domains" right="0 of 10" :lines="[
  [{ t: 'No domains yet. Add one and this container', tone: 'mute' }],
  [{ t: 'answers it on :80 and :443.', tone: 'mute' }],
  { align: 'right', cols: [{ b: 'Add domain' }] },
]" />

Add `example.com`, then `www.example.com` — each name is its own row:

<FigScreen title="Domains" right="2 of 10" :lines="[
  [{ m: 'example.com' }, { t: 'DNS ·', tone: 'mute' }, { t: 'HTTP ·', tone: 'mute' }, { t: 'HTTPS ·', tone: 'mute' }, { t: '⚙', tone: 'mute' }],
  [{ m: 'www.example.com' }, { t: 'DNS ·', tone: 'mute' }, { t: 'HTTP ·', tone: 'mute' }, { t: 'HTTPS ·', tone: 'mute' }, { t: '⚙', tone: 'mute' }],
]" />

This tells the machine the names are yours. It does **not** change anything at
your domain provider, and it does **not** get you a certificate. Those are the
next two steps.

A new name starts on HTTP port 80 and HTTPS by SNI passthrough; its badges fill
in on their own within a few seconds. Ten names is the usual allowance — the card
counts them, and your host can change the number. The card's own **?** says which
address to point at, and **Docs** on an open name comes back to this page.

---

## 7. Point the name at the machine

The card above shows the address to point at — `203.0.113.7` in our example. Go to
whoever sold you the domain, find the DNS or *records* page, and add:

<FigRows :head="['Type', 'Name', 'Value', 'makes this work']" :rows="[
  [{ m: 'A' }, { m: '@' }, { m: '203.0.113.7' }, { m: 'example.com' }],
  [{ m: 'A' }, { m: 'www' }, { m: '203.0.113.7' }, { m: 'www.example.com' }],
]" />

`@` means the bare domain. If your provider shows what the panel gave you as a
name rather than four numbers, use a `CNAME` with that name as the value instead.

Check it from your own computer after a few minutes:

```
  $ nslookup example.com
  Name:     example.com
  Address:  203.0.113.7      ← the machine. Good.
```

Meanwhile the badges on the card fill in by themselves. There is nothing to
reload and nothing to press:

<FigRows :rows="[
  [{ t: 'DNS ·', tone: 'mute' }, { t: 'HTTP ·', tone: 'mute' }, { t: 'HTTPS ·', tone: 'mute' }, { t: 'not checked yet', tone: 'mute' }],
  [{ t: 'DNS ✓', tone: 'ok' }, { t: 'HTTP ✕', tone: 'bad' }, { t: 'HTTPS ·', tone: 'mute' }, { t: 'the name arrives, nothing answers' }],
  [{ t: 'DNS ✓', tone: 'ok' }, { t: 'HTTP ✓', tone: 'ok' }, { t: 'HTTPS ·', tone: 'mute' }, { t: 'answering — ask for HTTPS now' }],
  [{ t: 'DNS ✓', tone: 'ok' }, { t: 'HTTP ✓', tone: 'ok' }, { t: 'HTTPS ✓', tone: 'ok' }, { t: 'done' }],
]" />

The machine checks a new name every few minutes until it resolves, then less
often. **Test**, inside a name's settings, checks one right now.

**One trap.** If the machine sits behind a home or office router, that router has
to send web traffic to it. Otherwise your name resolves perfectly and nothing
ever answers. Only your host can arrange that, so ask them.

---

## 8. Send each name to the right service

This is what turns one container into several websites:

<FigRows :arrow="0" :rows="[
  [{ m: 'example.com' }, { t: '80', face: 'mono' }, { t: 'the web server you installed', tone: 'mute' }],
  [{ m: 'www.example.com' }, { t: '80', face: 'mono' }, { t: 'the same one', tone: 'mute' }],
  [{ m: 'api.example.com' }, { t: '3000', face: 'mono' }, { t: 'the app you wrote', tone: 'mute' }],
]" />

Press the gear on a name:

<FigScreen title="api.example.com" :lines="[
  { cols: [{ t: 'DNS', tone: 'strong' }, { t: 'Does the name resolve to this host?' }] },
  { cols: ['', { b: 'Test' }, { t: 'DNS ✓', tone: 'ok' }] },
  { cols: [{ r: 'Enable HTTP', on: true }, { t: 'Container port' }, { f: '3000' }] },
  { cols: ['', { b: 'Test' }, { t: 'HTTP ✓', tone: 'ok' }] },
  { cols: [{ r: 'Enable HTTPS', on: true }, { t: 'HTTPS ·', tone: 'mute' }] },
  { cols: ['', { r: 'Your certificate · SNI passthrough' }] },
  { cols: ['', { t: 'Backend HTTPS port' }, { f: '443' }] },
  { cols: ['', { r: 'Our certificate · issued for you', on: true }] },
  { cols: ['', { t: 'Forwards to HTTP port' }, { f: '3000' }] },
  { pack: true, cols: [{ b: 'Test backend' }, { b: 'Request certificate' }] },
  { pack: true, cols: [{ b: 'Save' }, { b: 'Delete' }, { b: 'Docs' }, { b: 'Close' }] },
]" />

**Container port** is the port inside your box that visitors to this name reach.
Leave it at 80 for an ordinary website; set 3000 for something you wrote
yourself. The two switches are per name: a name can serve HTTP only, HTTPS only,
or both.

**Test** dials it from the machine and puts the answer beside the badge:

<FigRows :rows="[
  [{ t: 'HTTP ✓', tone: 'ok' }, { t: 'Port open, HTTP responded' }],
  [{ t: 'HTTP ✕', tone: 'bad' }, { t: 'Port closed' }, { t: 'your app, not the panel', face: 'small', tone: 'mute' }],
  [{ t: 'HTTP ✕', tone: 'bad' }, { t: 'Port open, no HTTP response' }],
  [{ t: 'DNS ✓', tone: 'ok' }, { t: 'Resolves to this host' }],
  [{ t: 'DNS ✕', tone: 'bad' }, { t: 'Resolves to 198.51.100.9 — not this host' }],
]" />

Saving also opens that port for you when it was not open already, and says so:

<FigRows :rows="[
  [{ t: '⚠', tone: 'bad' }, { t: 'Publishing container port 3000 restarted this' }],
  [null, { t: 'container’s network for a moment.' }],
]" />

That is exactly what it sounds like: connections in flight drop, everything
reconnects, and it does not happen again for that port.

---

## 9. Turn on HTTPS

Two ways, and you choose per name. Both are in the settings you just opened.

### Our certificate, issued for you — one button

Pick **Our certificate · issued for you** and press the button:

<FigRows :rows="[
  [{ b: 'Request certificate' }, null],
  [{ t: 'HTTPS ⟳', tone: 'accent' }, { t: 'Requesting a certificate…' }, { t: 'under a minute', face: 'small', tone: 'mute' }],
  [{ t: 'HTTPS ✓', tone: 'ok' }, { t: 'Issued, renewing automatically' }, { t: 'Managed', face: 'small', tone: 'mute' }],
]" />

Nothing to install and nothing to remember afterwards — renewal happens on its
own, well before it runs out. Note that the port box is **locked to your HTTP
port**: this mode ends the encryption at the machine and forwards plain traffic
to one port inside your box, so there is only one port to name. Change it in the
HTTP box above.

Two conditions, and the badge says which one is missing:

<FigRows :rows="[
  [{ t: '✕', tone: 'bad' }, { t: 'Issuance failed. Check that the name resolves to this host.' }, { t: '→ step 7', face: 'small', tone: 'mute' }],
  [{ t: '✕', tone: 'bad' }, { t: 'Port closed' }, { t: '→ step 8', face: 'small', tone: 'mute' }],
]" />

Once a name has a certificate the button becomes **Reissue certificate**, and it
goes quiet for a while after each one:

<FigRows :rows="[
  [{ b: 'Reissue in 47 min' }, { t: 'the authority limits how often a name may be issued', tone: 'mute' }],
]" />

You get **one request an hour and five a week for the same name**, because that
is what the certificate authority allows, and a sixth press would lock your own
name out for days. Automatic renewals are never refused, so this only ever bites
while you are setting up.

### Your certificate — you hold it

Pick **Your certificate · SNI passthrough** and set **Backend HTTPS port** to the
port inside your box that handles secure traffic:

<FigRows :arrow="0" :rows="[
  [{ t: 'a visitor', tone: 'strong' }, { t: 'encrypted, and the machine does not open it', tone: 'accent' }],
  [null, { t: 'straight through to your box on port 443', face: 'small', tone: 'mute' }],
]" />

The machine passes the traffic through without opening it, so nothing outside
your box has your certificate — and nothing outside your box will renew it
either. Get one inside your container the usual way, keep it renewed, and the
badge tells you what your box is actually serving:

<FigRows :rows="[
  [{ t: 'HTTPS ✓', tone: 'ok' }, { t: 'Port open, certificate valid' }],
  [{ t: 'HTTPS ✓', tone: 'ok' }, { t: 'Certificate valid, 63 days left' }],
  [{ t: 'HTTPS ✕', tone: 'bad' }, { t: 'Certificate expired' }],
  [{ t: 'HTTPS ✕', tone: 'bad' }, { t: 'Port open, no TLS' }],
]" />

There is nowhere to upload a certificate to the panel. In this mode it belongs
inside your box, where the traffic is opened.

**You should see**, either way:

<FigRows :arrow="0" :rows="[
  [{ t: 'in a browser', tone: 'strong' }, { m: 'example.com' }, { t: '🔒 your site', tone: 'ok' }],
  [{ t: 'not proof', tone: 'mute' }, { m: 'curl http://example.com' }, { t: 'plain, so it tests nothing', tone: 'mute' }],
]" />

Type the bare name into a browser. A browser tries the secure version first,
which is the thing you are testing; a plain unencrypted request proves nothing
about it.

---

## 10. When something is wrong

Four places, in this order:

<FigRows :rows="[
  [{ t: '1', tone: 'accent' }, 'the badge', { t: 'HTTP ✕ connection refused on 3000', tone: 'mute' }],
  [{ t: '2', tone: 'accent' }, 'inside your box', { m: 'systemctl status myapp' }],
  [{ t: '3', tone: 'accent' }, 'the install log', { m: '/var/log/app-setup/wordpress.log' }],
  [{ t: '4', tone: 'accent' }, 'the panel', { t: 'your container’s history, newest first', tone: 'mute' }],
]" />

The badges name which half is broken — the name, the port, or the certificate —
and cost nothing to read. Then, inside your box:

```
  root@wp-1:~# systemctl status myapp
  ● myapp.service — failed (exit code 1)
  root@wp-1:~# journalctl -u myapp -n 20
  root@wp-1:~# journalctl -xe          everything, recent
```

Anything you installed from the menu also keeps its own log, and the path is
printed on screen whenever something fails:

<FigRows :rows="[
  [{ t: '✕', tone: 'bad' }, { t: 'WordPress failed — exit 1.' }],
  [null, { m: 'The log is /var/log/app-setup/wordpress.log' }],
]" />

And the panel remembers what was done to your container, newest first:

<FigRows :rows="[
  [{ t: '11 Aug 14:02', face: 'small', tone: 'mute' }, 'certificate issued for example.com'],
  [{ t: '11 Aug 13:58', face: 'small', tone: 'mute' }, 'api.example.com: http port 80 → 3000'],
  [{ t: '11 Aug 13:40', face: 'small', tone: 'mute' }, 'example.com added'],
]" />

Two failures leave no message anywhere, so recognise them by shape:

<FigRows :arrow="0" :rows="[
  ['a service that keeps dying, log says nothing', { t: 'memory', tone: 'bad' }],
  [{ m: 'no space left on device' }, { t: 'disk', tone: 'bad' }],
]" />

| What you see | What it usually is |
|---|---|
| Login refused | The container is stopped, out of time, or paused for traffic. The panel says which. |
| Asked for the password again and again | Wrong password. Set a new one (step 2) — nobody can show you the old one. |
| The browser cannot find the name | DNS. Check the records in step 7 from your own computer. |
| The name is found but nothing answers | Either nothing is listening on that port inside your box (step 8), or the machine's router is not forwarding web traffic (step 7). |
| The browser shows somebody else's site | The name is not pointed at this machine, or you added it in the panel but never changed the DNS. |
| A certificate warning | The name does not match the certificate, or it expired. In *Managed* mode, request it again; in your own mode, renew it inside your box. |
| The certificate request is refused with a date | You have used this week's five for that name. Wait for the date given. |
| A service dies with nothing in its log | Memory. Watch the memory figure on your container's page while it runs. |
| "No space left on device" | Disk. Everything in your box shares one allowance. |
| The panel says the machine is offline | Your host's machine is not reporting in. Your box may well be running fine; the buttons wait. Ask your host. |
| Everything is slow | Your processor share, or a busy machine. The graph on your container's page covers the last week. |

---

## 11. Keep what you cannot lose

One folder survives a rebuild. Everything else is the system plus your changes to
it, and a rebuild replaces exactly that:

<FigRows :arrow="0" :rows="[
  [{ m: '/etc/nginx/nginx.conf' }, { t: 'gone', tone: 'bad' }],
  [{ m: '/var/www/site' }, { t: 'gone', tone: 'bad' }],
  [{ m: '/root/notes.txt' }, { t: 'gone', tone: 'bad' }],
  [{ m: '/data/mysql' }, { t: 'kept', tone: 'ok' }],
  [{ m: '/data/uploads' }, { t: 'kept', tone: 'ok' }],
]" />

So put databases, uploads and anything you would be upset to lose under `/data`,
and point your services at it.

Three more things that stop your website without deleting anything, one line
each:

<FigRows :arrow="0" :rows="[
  ['traffic used up', 'paused; back next month'],
  ['expiry date passes', 'stopped; your host can renew'],
  ['you press Rebuild', 'a fresh system, /data kept'],
]" />

What each of those does in detail — and what your limits feel like when you reach
them — is on [using your container](using-your-container.md).

---

## Where next

- [Using your container](using-your-container.md) — limits, expiry, rebuilds.
- [Adding your own software](app-setup-sources.md) — put your own entry in the
  menu.
- [How this works](how-it-works.md) — the picture behind all of the above.
