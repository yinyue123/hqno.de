# How this works

You have been given a piece of somebody else's machine. Seven pictures, and you
will know which parts of it are yours.

If you would rather start doing than reading, go to the
[quick start](quick-start.md) — it takes you from the code somebody sent you to a
website with a padlock on it.

---

## The whole thing on one page

```
  you ──sign in──▶ panel ──"do this"──▶ the machine
                                          │
   you, over ssh ─────────────────▶  ├─── your box
                                     ├─── Ana's box
   your visitors ─────────────────▶  └─── Wei's box
```

Three words this site uses for the rest of your life here: the **panel** is the
website you sign in to, the **machine** is the computer your box runs on, and the
**host** is whoever owns that machine. You are a **holder** — one box on it is
yours.

---

## One machine, cut into pieces

```
        one machine, one Linux underneath
  ┌───────────┬───────────┬───────────┬──────────┐
  │  yours    │  Ana's    │  Wei's    │   ...    │
  │  1 core   │  ½ core   │  2 cores  │          │
  │  2 GB     │  1 GB     │  4 GB     │          │
  │  20 GB    │  10 GB    │  80 GB    │          │
  └───────────┴───────────┴───────────┴──────────┘
```

Your piece is called a **container**, and it behaves like a small computer of its
own: its own files, its own installed software, its own services. You are its
administrator. You cannot see into anybody else's, and nobody can see into
yours.

The numbers are what your host sold you — processor, memory, disk, and a traffic
allowance for the month. What happens when you reach one of them is on
[using your container](using-your-container.md).

---

## Your login is yours because of the username

```
  ssh u7k2m9p@hk-1.example.com  ─────▶  your box
  ssh u4b8x2q@hk-1.example.com  ─────▶  Ana's box
         └── the only difference
```

Same address, same door, different room. The name in front of the `@` is the
whole of what decides which room you get.

```
  change the password in the panel  ─▶ changes how you get in
  change it inside your box         ─▶ changes nothing
  rebuild your box from scratch     ─▶ your login still works
```

The password is checked at the machine's front door rather than inside your box.
That is why the panel is where you change it, and why wiping your box does not
cost you the way in.

---

## Your website is yours because of the name

```
  a visitor types          and reaches
  ────────────────────     ──────────────────────
  shop.example.com   ───▶  your box,  port 80
  api.example.com    ───▶  your box,  port 3000
  blog.ana.dev       ───▶  Ana's box, port 80
```

One machine can serve any number of websites, and **the name the visitor typed**
is what decides which box answers. Two things follow:

- your site has an ordinary address, with no port number stuck on the end;
- a name pointed at your box is yours while you hold it — nobody else on that
  machine can take it.

Inside your box you can run as many services as you like, and each name can be
sent to a different one.

---

## You do not have to know any commands

Most people have never typed a command, and nobody wants to learn which package
names their particular Linux uses this year. So there is a menu. Type one word:

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

Enter opens the one under the cursor, and its own page is where things happen:

```
  ┌ WordPress ───────────────────────────────────────┐
  │ [Install] [Start] [At boot] [Settings] [Docs]    │
  │                                                  │
  │ The blog and site software four sites in ten     │
  │ run on. Installs its own database.               │
  │                                                  │
  │ Disk 800M  RAM 768M  Port 80                     │
  │ Log  /var/log/app-setup/wordpress.log            │
  └──────────────────────────────────────────────────┘
```

```
  ordinary software, ordinary places ─▶ tutorials still fit
  every entry says its size          ─▶ red if it won't fit
  Docs names every file it wrote     ─▶ nothing to hunt for
```

It installs the same software the same way a person following a blog post would,
so the next set of instructions you read still applies, and updates keep arriving
the ordinary way. Anything you would rather do by hand, you still can.

[Quick start](quick-start.md) drives it, step by step.

---

## Two ways to get the padlock

```
  your own certificate
    visitor ══encrypted═════════════════▶ your box
             passed through unread; you get it
             and you renew it

  a certificate the host looks after
    visitor ══encrypted══▶ machine ──plain──▶ your box
             the machine holds it and renews it
```

A **certificate** is what puts the padlock in the address bar. You have two ways
to have one, and you pick per name:

| | Your own | The host's |
|---|---|---|
| What you do | get one and renew it yourself | press a button, once |
| Can the host read your traffic | no | yes |
| Pick it when | you already have one, or that answer has to be "no" | you want a padlock and no homework |

Both need the same thing first: the name has to point at the machine. That is why
the quick start sorts out the domain before it asks for a certificate.

---

## The panel is not in the way

```
  you ─────▶ panel ──"restart it please"──▶ the machine

  a visitor ────────────────────────────▶ your website
```

The panel is not on the second line. When it is down your website keeps
answering, your login keeps working, and everything you have installed carries on
— only its buttons have to wait.

---

## Where next

- [Quick start](quick-start.md) — a share code to a working website.
- [Using your container](using-your-container.md) — limits, expiry, rebuilds:
  what happens when, and what it costs.
- [Running a machine of your own](running-a-machine.md) — the other side of all
  of this.
