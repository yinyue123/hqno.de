# How this works

Somebody sells a Linux machine in pieces. Each piece behaves like a small
computer of its own. This page says which parts of one are yours — first as
something most people have already rented, then as seven pictures of the real
thing.

**Or skip it — take whichever of these you are:**

<FigRows :arrow="0" :rows="[
  ['somebody gave you a code', 'Quick start'],
  ['you have a machine', 'Running a machine of your own'],
]" />

- [**Quick start**](quick-start.md) — you were sent a share code. Claim it, log
  in, install a website, point your domain at it, get the padlock. Twelve steps,
  each with a picture.
- [**Running a machine of your own**](running-a-machine.md) — you have hardware,
  or a rented server, and you want to cut it into containers and hand them out.

---

## It is a room, not a flat

You move to a city for work. A three-bedroom flat to yourself would be absurd:
you are out all day and you come back to sleep. So you rent **one room** in one,
and the kitchen is everybody's.

That is this entire product, with a computer instead of a flat. Six pictures,
and then the same thing again without the comparison.

**A whole one is more than one person needs.**

<svg class="fig" viewBox="0 0 660 190" role="img" aria-label="A whole flat with one person in it, beside a whole machine with one small site on it">
  <text class="t c" x="165" y="20">in a flat</text>
  <text class="t c" x="495" y="20">here</text>
  <path class="rule" d="M330,30 V174"/>
  <rect class="box" x="20" y="36" width="290" height="110" rx="6"/>
  <text class="s" x="34" y="58">3 bedrooms · kitchen · 2 baths</text>
  <rect class="mine" x="34" y="90" width="80" height="38" rx="4"/>
  <text class="c" x="74" y="114">you</text>
  <text class="s" x="126" y="114">empty all day</text>
  <text class="s c" x="165" y="170">you pay for the flat</text>
  <rect class="box" x="350" y="36" width="290" height="110" rx="6"/>
  <text class="s" x="364" y="58">8 cores · 32 GB · 1 TB · one address</text>
  <rect class="mine" x="364" y="90" width="80" height="38" rx="4"/>
  <text class="c" x="404" y="114">your site</text>
  <text class="s" x="456" y="114">idle most of the day</text>
  <text class="s c" x="495" y="170">you pay for the machine</text>
</svg>

Eight cores, 32 GB of memory, a terabyte of disk and an address of its own is
what a machine comes as. A small website uses a fraction of one core and a few
hundred megabytes, and spends most of the day asleep. Renting the whole thing is
renting a flat to keep one bed in.

**So somebody cuts it up.**

<svg class="fig" viewBox="0 0 660 210" role="img" aria-label="A flat divided into three rooms over a shared kitchen, beside a machine divided into three containers over one shared Linux">
  <text class="t c" x="165" y="20">in a flat</text>
  <text class="t c" x="495" y="20">here</text>
  <path class="rule" d="M330,30 V196"/>
  <rect class="mine" x="20" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="67" y="72">yours</text>
  <text class="s c" x="67" y="92">a bed, a desk</text>
  <rect class="box" x="118" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="165" y="80">bob's</text>
  <rect class="box" x="216" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="263" y="80">carol's</text>
  <rect class="box" x="20" y="116" width="290" height="36" rx="4"/>
  <text class="c" x="165" y="139">kitchen · bathroom · front door</text>
  <text class="s c" x="165" y="174">your door locks</text>
  <text class="s c" x="165" y="190">the kitchen is everybody's</text>
  <rect class="mine" x="350" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="397" y="68">yours</text>
  <text class="s c" x="397" y="88">1 core · 2 GB</text>
  <text class="s c" x="397" y="103">20 GB disk</text>
  <rect class="box" x="448" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="495" y="68">bob's</text>
  <text class="s c" x="495" y="88">½ core · 1 GB</text>
  <rect class="box" x="546" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="593" y="68">carol's</text>
  <text class="s c" x="593" y="88">2 cores · 4 GB</text>
  <rect class="box" x="350" y="116" width="290" height="36" rx="4"/>
  <text class="c" x="495" y="139">one Linux · one machine · one address</text>
  <text class="s c" x="495" y="174">your container is yours</text>
  <text class="s c" x="495" y="190">the machine is shared</text>
</svg>

Walls go up and the rooms are let one at a time. Your room is yours — your key,
your things, nobody else walks in. The kitchen, the bathroom and the front door
are shared, and they work perfectly well that way.

Your room here is called a **container**: your files, your software, your
services, and you are its administrator. Shared underneath are the Linux, the
machine and one address to the world. You cannot see into anybody else's and
nobody can see into yours.

**Your own key.**

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="Three keys opening three rooms, beside three ssh commands opening three containers">
  <defs><marker id="k1" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t c" x="156" y="20">in a flat</text>
  <text class="t c" x="485" y="20">here</text>
  <path class="rule" d="M310,30 V184"/>
  <circle class="lnA" cx="32" cy="56" r="7"/>
  <path class="lnA" d="M39,56 H64 M58,56 V62 M50,56 V62"/>
  <path class="ln" d="M74,56 H152" marker-end="url(#k1)"/>
  <rect class="mine" x="160" y="41" width="132" height="30" rx="4"/>
  <text class="c" x="226" y="61">your room</text>
  <circle class="ln" cx="32" cy="96" r="7"/>
  <path class="ln" d="M39,96 H64 M58,96 V102 M50,96 V102"/>
  <path class="ln" d="M74,96 H152" marker-end="url(#k1)"/>
  <rect class="box" x="160" y="81" width="132" height="30" rx="4"/>
  <text class="c" x="226" y="101">bob's room</text>
  <circle class="ln" cx="32" cy="136" r="7"/>
  <path class="ln" d="M39,136 H64 M58,136 V142 M50,136 V142"/>
  <path class="ln" d="M74,136 H152" marker-end="url(#k1)"/>
  <rect class="box" x="160" y="121" width="132" height="30" rx="4"/>
  <text class="c" x="226" y="141">carol's room</text>
  <text class="s c" x="156" y="176">one front door, three keys</text>
  <text class="m" x="326" y="61">ssh <tspan class="a">alice</tspan>@203.0.113.7</text>
  <path class="ln" d="M486,56 H528" marker-end="url(#k1)"/>
  <rect class="mine" x="536" y="41" width="109" height="30" rx="4"/>
  <text class="c" x="590" y="61">your box</text>
  <text class="m" x="326" y="101">ssh bob@203.0.113.7</text>
  <path class="ln" d="M486,96 H528" marker-end="url(#k1)"/>
  <rect class="box" x="536" y="81" width="109" height="30" rx="4"/>
  <text class="c" x="590" y="101">bob's box</text>
  <text class="m" x="326" y="141">ssh carol@203.0.113.7</text>
  <path class="ln" d="M486,136 H528" marker-end="url(#k1)"/>
  <rect class="box" x="536" y="121" width="109" height="30" rx="4"/>
  <text class="c" x="590" y="141">carol's box</text>
  <text class="s c" x="485" y="176">one machine: 203.0.113.7</text>
</svg>

Everybody walks in through the same front door, and the key in your hand decides
which room opens. Here the front door is the machine's address — `203.0.113.7`,
the same one for everybody on it — and the key is your username. The part before
the `@` is the whole of what decides which room you get.

**Your name on the door.**

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="A letter reaching the door with your name on it, beside a typed domain reaching your container">
  <defs><marker id="k2" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t c" x="165" y="20">in a flat</text>
  <text class="t c" x="495" y="20">here</text>
  <path class="rule" d="M330,30 V184"/>
  <rect class="box" x="20" y="78" width="76" height="46" rx="3"/>
  <path class="ln" d="M20,78 L58,106 L96,78"/>
  <text class="s c" x="58" y="142">addressed to you</text>
  <path class="ln" d="M104,101 H142" marker-end="url(#k2)"/>
  <rect class="box" x="150" y="42" width="160" height="34" rx="4"/>
  <text class="c" x="230" y="64">bob</text>
  <rect class="mine" x="150" y="84" width="160" height="34" rx="4"/>
  <text class="c" x="230" y="106">you</text>
  <rect class="box" x="150" y="126" width="160" height="34" rx="4"/>
  <text class="c" x="230" y="148">carol</text>
  <text class="s c" x="165" y="182">one street address; the name decides</text>
  <text class="s" x="350" y="82">a visitor types</text>
  <text class="m a" x="350" y="105">shop.example.com</text>
  <path class="ln" d="M472,101 H500" marker-end="url(#k2)"/>
  <rect class="box" x="508" y="42" width="132" height="34" rx="4"/>
  <text class="c" x="574" y="64">bob's box</text>
  <rect class="mine" x="508" y="84" width="132" height="34" rx="4"/>
  <text class="c" x="574" y="106">your box</text>
  <rect class="box" x="508" y="126" width="132" height="34" rx="4"/>
  <text class="c" x="574" y="148">carol's box</text>
  <text class="s c" x="495" y="182">one machine address; the name decides</text>
</svg>

Post arrives at one street address, and the name on the door decides whose it is.
Here one machine answers on one address, and **the name your visitor typed**
decides which room answers. A name pointed at your room is yours for as long as
you hold the room, and nobody else on that machine can take it.

**The room comes furnished.**

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="A room with a bed, a desk and a lamp, beside a container with Linux running and a menu that installs the rest">
  <text class="t c" x="165" y="20">in a flat</text>
  <text class="t c" x="495" y="20">here</text>
  <path class="rule" d="M330,30 V184"/>
  <rect class="box" x="20" y="36" width="290" height="112" rx="6"/>
  <rect class="ln" x="36" y="66" width="86" height="46" rx="4"/>
  <rect class="ln" x="42" y="72" width="24" height="34" rx="3"/>
  <text class="s c" x="79" y="132">a bed</text>
  <path class="ln" d="M140,80 H216 M146,80 V112 M210,80 V112"/>
  <text class="s c" x="178" y="132">a desk</text>
  <path class="ln" d="M242,74 L274,74 L266,54 L250,54 Z M258,74 V114 M244,114 H272"/>
  <text class="s c" x="258" y="132">a lamp</text>
  <text class="s c" x="165" y="176">you bring your clothes</text>
  <rect class="box" x="350" y="36" width="290" height="112" rx="6"/>
  <text class="t" x="364" y="60">Alpine 3.24, already running</text>
  <rect class="box" x="364" y="74" width="64" height="26" rx="13"/>
  <text class="s c" x="396" y="91">nginx</text>
  <rect class="box" x="434" y="74" width="72" height="26" rx="13"/>
  <text class="s c" x="470" y="91">MariaDB</text>
  <rect class="box" x="512" y="74" width="52" height="26" rx="13"/>
  <text class="s c" x="538" y="91">PHP</text>
  <rect class="box" x="570" y="74" width="56" height="26" rx="13"/>
  <text class="s c" x="598" y="91">Node</text>
  <text class="s" x="364" y="126">one keypress installs any of them</text>
  <text class="s c" x="495" y="176">you bring your code</text>
</svg>

You are there for a year, or a few months. Nobody buys a bed for that, so the
room comes with one, and a desk, and a lamp. You bring your clothes.

Your container arrives with a working Linux already on it — Alpine, which is
small enough to leave the memory you are paying for to your own software — and a
menu that installs the rest: a web server, a database, WordPress, Node. You bring
your code.

**And a lock on the door.**

<svg class="fig" viewBox="0 0 660 196" role="img" aria-label="A lock you fitted yourself and the building's lock, beside the same padlock in a browser's address bar either way">
  <text class="t c" x="165" y="20">in a flat</text>
  <text class="t c" x="495" y="20">here</text>
  <path class="rule" d="M330,30 V180"/>
  <path class="ln" d="M28,62 a6,6 0 0 1 12,0"/>
  <rect class="ln" x="24" y="62" width="20" height="16" rx="3"/>
  <text class="t" x="58" y="74">a lock you fitted</text>
  <text class="s" x="58" y="94">you hold the only key</text>
  <path class="ln" d="M28,128 a6,6 0 0 1 12,0"/>
  <rect class="ln" x="24" y="128" width="20" height="16" rx="3"/>
  <text class="t" x="58" y="140">the building's lock</text>
  <text class="s" x="58" y="160">the desk downstairs has one too</text>
  <rect class="box" x="350" y="52" width="196" height="30" rx="15"/>
  <path class="lnA" d="M370,66 a5,5 0 0 1 10,0"/>
  <rect class="lnA" x="366" y="66" width="18" height="14" rx="3"/>
  <text class="m" x="394" y="72">example.com</text>
  <text class="s" x="350" y="102">your own certificate — nothing on the way opens it</text>
  <rect class="box" x="350" y="126" width="196" height="30" rx="15"/>
  <path class="lnA" d="M370,140 a5,5 0 0 1 10,0"/>
  <rect class="lnA" x="366" y="140" width="18" height="14" rx="3"/>
  <text class="m" x="394" y="146">example.com</text>
  <text class="s" x="350" y="176">the host's — the machine opens it, and renews it</text>
</svg>

Fit your own lock and you hold the only key. Use the building's and the desk
downstairs fits it, replaces it when it wears out, and can open your door. Here
the lock is a **certificate** — what puts the padlock in a browser's address bar
— and you choose per name which of the two you want. Your visitor sees the same
padlock either way.

**The whole comparison at once:**

| In the flat | Here |
|---|---|
| the landlord who split it up | your **host** |
| your room | your **container** |
| a bed, a desk, a lamp | a Linux already running, and a menu that installs the rest |
| your key | your ssh username and password |
| the name on your door | your domain |
| the kitchen and the front door | the Linux underneath, and the machine's one address |
| a lock you fitted yourself | your own certificate |
| the building's lock | a certificate your host looks after |
| the lease | the expiry date on your container |
| the water and the electricity | your traffic allowance for the month |

Where the comparison stops: a wall in a flat is a wall. Here it is the Linux
underneath that keeps the rooms apart, and the host owns that — a landlord with
a master key can open any door in the building, and this is no different.

The rest of this page is the same thing again, drawn as what it actually is.

---

## The whole thing on one page

<FigRows :arrow="0" :rows="[
  [{ t: 'you', tone: 'strong' }, { t: 'the panel' }, { t: '\u201cdo this\u201d → the machine', tone: 'mute' }],
  [{ t: 'you, over ssh', tone: 'strong' }, { t: 'your box', tone: 'accent' }, { t: 'on that machine', tone: 'mute' }],
  [{ t: 'your visitors', tone: 'strong' }, { t: 'your box', tone: 'accent' }, { t: 'bob\u2019s and carol\u2019s are there too', tone: 'mute' }],
]" />

Three words this site uses for the rest of your life here: the **panel** is the
website you sign in to, the **machine** is the computer your box runs on, and the
**host** is whoever owns that machine. You are a **holder** — one box on it is
yours.

---

## One machine, cut into pieces

<FigScreen title="one machine, one Linux underneath" :lines="[
  [{ t: 'yours', tone: 'accent' }, { t: 'bob\u2019s', tone: 'mute' }, { t: 'carol\u2019s', tone: 'mute' }, { t: '…', tone: 'mute' }],
  ['1 core', '½ core', '2 cores', ''],
  ['2 GB', '1 GB', '4 GB', ''],
  ['20 GB', '10 GB', '80 GB', ''],
]" />

Your piece is called a **container**, and it behaves like a small computer of its
own: its own files, its own installed software, its own services. You are its
administrator. You cannot see into anybody else's, and nobody can see into
yours.

The numbers are what your host sold you — processor, memory, disk, and a traffic
allowance for the month. What happens when you reach one of them is on
[using your container](using-your-container.md).

---

## Your login is yours because of the username

<FigRows :arrow="0" :rows="[
  [{ m: 'ssh alice@203.0.113.7', hi: 'alice' }, 'your box'],
  [{ m: 'ssh bob@203.0.113.7', hi: 'bob' }, 'bob\u2019s box'],
  [{ t: 'the only difference is that one word', face: 'small', tone: 'mute' }, null],
]" />

Same address, same door, different room. The name in front of the `@` is the
whole of what decides which room you get.

<FigRows :arrow="0" :rows="[
  ['change the password in the panel', 'changes how you get in'],
  ['change it inside your box', { t: 'changes nothing', tone: 'mute' }],
  ['rebuild your box from scratch', 'your login still works'],
]" />

The password is checked at the machine's front door rather than inside your box.
That is why the panel is where you change it, and why wiping your box does not
cost you the way in.

---

## Your website is yours because of the name

<FigRows :arrow="0" :head="['a visitor types', 'and reaches']" :rows="[
  [{ m: 'shop.example.com' }, 'your box, port 80'],
  [{ m: 'api.example.com' }, 'your box, port 3000'],
  [{ m: 'blog.bob.dev' }, 'bob\u2019s box, port 80'],
]" />

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

<FigScreen :tabs="['Suites', 'Web servers', 'Databases', 'Dev', 'System']" :lines="[
  [{ t: '▸', tone: 'accent' }, { t: 'LNMP', tone: 'accent' }, { t: 'web server + database + PHP', tone: 'mute' }],
  ['', 'WordPress', { t: 'the blog four sites in ten use', tone: 'mute' }],
  ['', 'MariaDB', { t: 'a database on its own', tone: 'mute' }],
  ['', 'Node.js', { t: '…', tone: 'mute' }],
  [{ t: 'Disk 600M   RAM 768M', face: 'small', tone: 'mute' }],
  [{ t: '↑↓←→ move     Enter open     ↑ at the top is Back', face: 'small', tone: 'mute' }],
]" />

Enter opens the one under the cursor, and its own page is where things happen:

<FigScreen title="WordPress" :lines="[
  { pack: true, cols: [{ b: 'Install' }, { b: 'Start' }, { b: 'Start at boot' }, { b: 'Settings' }] },
  { pack: true, cols: [{ b: 'How to use it' }, { b: 'Log' }] },
  [{ t: 'The blog and site software four sites in ten run on. Installs its own database.', tone: 'mute' }],
  [{ t: 'Disk 800M   RAM 768M   Port 80', face: 'small', tone: 'mute' }],
]" />

<FigRows :arrow="0" :rows="[
  ['ordinary software, ordinary places', 'tutorials still fit'],
  ['every entry says its size', 'red if it will not fit'],
  ['Docs names every file it wrote', 'nothing to hunt for'],
]" />

It installs the same software the same way a person following a blog post would,
so the next set of instructions you read still applies, and updates keep arriving
the ordinary way. Anything you would rather do by hand, you still can.

[Quick start](quick-start.md) drives it, step by step.

---

## Two ways to get the padlock

<FigRows :arrow="0" :rows="[
  [{ t: 'your own certificate', tone: 'strong' }, null, null],
  [{ t: 'a visitor', face: 'small' }, { t: 'encrypted the whole way to your box', tone: 'accent' }],
  [null, { t: 'passed through unread; you get it and renew it', face: 'small', tone: 'mute' }],
  [{ t: 'a certificate the host looks after', tone: 'strong' }, null, null],
  [{ t: 'a visitor', face: 'small' }, { t: 'encrypted to the machine, plain to your box' }],
  [null, { t: 'the machine opens it, holds it and renews it', face: 'small', tone: 'mute' }],
]" />

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

<FigRows :arrow="0" :rows="[
  [{ t: 'you', tone: 'strong' }, { t: 'the panel' }, { t: '\u201crestart it please\u201d → the machine', tone: 'mute' }],
  [{ t: 'a visitor', tone: 'strong' }, { t: 'your website', tone: 'accent' }, { t: 'the panel is not on this line', tone: 'mute' }],
]" />

The panel is not on the second line. When it is down your website keeps
answering, your login keeps working, and everything you have installed carries on
— only its buttons have to wait.

---

## Where next

- [Quick start](quick-start.md) — a share code to a working website.
- [Running a machine of your own](running-a-machine.md) — the other side of all
  of this.

**Advanced** is everything you read later, if at all:
[using your container](using-your-container.md) for what a limit feels like when
you reach it and what a rebuild takes away,
[building your own image](building-your-own-image.md) if the system you want is
not on the published list, and [adding your own software](app-setup-sources.md)
if you want your own entry in the install menu. The quick start gets you a
working site without any of it.
