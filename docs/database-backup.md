# Backing up your database

A backup is two things you set up once — **where it goes**, and **what it
is** — and after that it runs on a timer and you forget about it. Putting one
back is a single command. That is the whole of this page; everything below is
detail you only read once.

If you installed a database from the [quick start](/quick-start), it is already
running and already sized for your container. This page is what to do next so
that the day the disk dies is a bad hour and not a bad week.

## The short version

Two installs and it is running on a nightly timer:

```
root@box:~# app-setup install store-r2         # where backups go — a bucket
root@box:~# app-setup install backup-postgresql # what to back up — the database
```

Both open a form the first time. Fill the bucket and keys into the first, press
**✓ Test connection**; pick your database and press save in the second. That is
it — a dump goes to the bucket every night.

By hand, any time:

<FigRows :arrow="1" :rows="[
  [{ m: 'app-setup backup backup-postgresql' }, { t: 'make one now', tone: 'mute' }],
  [{ m: 'app-setup restore backup-postgresql' }, { t: 'put the newest one back', tone: 'mute' }],
  [{ m: 'app-setup archives backup-postgresql' }, { t: 'list what exists', tone: 'mute' }],
]" />

For MySQL / MariaDB it is the same two words with `backup-mysql` in place of
`backup-postgresql`. Everything on this page is written for both.

## The one idea: a store, and a job

There are two cards, not one, and knowing why is the whole of understanding
this feature. A **store** is *where backups go* — a bucket, a box with SSH on
it. A **job** is *what to back up and how often* — this database, nightly, keep
a fortnight. One store can hold many jobs; a job points at one store.

<FigRows :arrow="1" :head="['You set up', 'which answers']" :rows="[
  [{ t: 'a store', tone: 'strong' }, { t: 'where do backups go?', tone: 'mute' }],
  [{ t: 'a job', tone: 'strong' }, { t: 'what, how often, keep how many?', tone: 'mute' }],
]" />

You set up the store first because a job with nowhere to send its output will
not install. After that you never think about the store again.

## Step 1 — where backups go

Type `app-setup` and walk to the **Backup** tab. The stores are the top row:

<FigScreen :tabs="['Databases', 'Backup', 'Dev tools', 'System']" :lines="[
  { pack: true, cols: [{ tag: 'STORE-S3' }, { tag: 'STORE-R2' }, { tag: 'STORE-WEBDAV' }] },
  { pack: true, cols: [{ tag: 'STORE-FTP' }, { tag: 'STORE-SCP' }, { tag: 'STORE-RSYNC' }] },
  [{ t: 'Where backups go. Pick the one you already have somewhere to put them.', tone: 'mute', face: 'small' }],
]" />

| Pick | when you have |
|---|---|
| **store-r2** | a Cloudflare R2 bucket — the form is two boxes shorter than S3 |
| **store-s3** | AWS, MinIO, Aliyun OSS, Tencent COS, Backblaze — anything S3 |
| **store-scp** | any machine with `sshd` on it and nothing else |
| **store-rsync** | the same, where the far end also has `rsync` (resumes, sends only changes) |
| **store-webdav** / **store-ftp** | a Nextcloud share, or an FTP space |

Open **store-r2** and it asks for exactly what Cloudflare's dashboard hands you
— it works out the endpoint and region for you:

<FigScreen title="Cloudflare R2 · Settings" :lines="[
  [{ t: 'Cloudflare account id', tone: 'mute' }, { f: '', fw: 220 }],
  [{ t: 'Bucket', tone: 'mute' }, { f: '', fw: 220 }],
  [{ t: 'Base folder', tone: 'mute' }, { f: 'backups', fw: 220 }],
  [{ t: 'Access key', tone: 'mute' }, { f: '', fw: 220 }],
  [{ t: 'Secret key', tone: 'mute' }, { f: '', fw: 220 }],
  { align: 'right', cols: [{ b: 'Save & Apply' }, { b: 'Save' }, { b: 'Cancel' }] },
]" />

What that form saves is one small file — this is the whole of the store's
configuration, and it is the only place your keys live, at mode `600`:

```ini
# /etc/app-setup/params/store-r2.conf
account=<your 32-hex Cloudflare account id>
bucket=web3
prefix=backups
access_key=<R2 access key>
secret_key=<R2 secret key>
```

Then press **✓ Test connection**. It does not just log in — it makes a folder,
writes a file, lists it, reads it back and compares the bytes, then deletes it.
Five steps because each fails on its own, and a read-only key that connects and
then fails at the first real backup is exactly the trap this catches:

<FigScreen title="Cloudflare R2 · Test" :lines="[
  [{ t: '✓', tone: 'ok' }, { t: 'making a folder', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'writing a file into it', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'listing it', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'reading it back and comparing', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'deleting it', tone: 'mute' }],
  [{ t: 'folder, write, read and delete all worked', tone: 'ok' }],
]" />

A store that has never passed all five is one a job refuses to point at. From a
script, the same thing without the menu:

```
root@box:~# app-setup set store-r2 account=… bucket=web3 access_key=… secret_key=…
root@box:~# app-setup test store-r2
```

> **store-scp holds no password.** It logs in with a key it makes for itself.
> Press **Show the public key**, put that one line in `~/.ssh/authorized_keys`
> on the far end, and press Test. Nothing a stolen container could read gets it
> a shell — see the recipe's own `app-setup docs store-scp`.

## Step 2 — what to back up

Open **backup-postgresql** (or **backup-mysql**). Its form is grouped: the
database, how, where it goes, and when.

<FigScreen title="PostgreSQL · Settings" :lines="[
  [{ t: '▸ The database', tone: 'accent' }],
  [{ t: '   Host', tone: 'mute' }, { f: '', note: 'blank = the local socket' }],
  [{ t: '   Databases', tone: 'mute' }, { f: '', note: 'blank = all of them' }],
  [{ t: '▸ How', tone: 'accent' }],
  [{ t: '   Method', tone: 'mute' }, { r: 'dump', on: true }, { r: 'binary' }, { r: 'files' }],
  [{ t: '▸ Where it goes', tone: 'accent' }],
  [{ t: '   Destination', tone: 'mute' }, { r: 'r2', on: true }],
  [{ t: '▸ When, and how many to keep', tone: 'accent' }],
  [{ t: '   When', tone: 'mute' }, { r: 'daily', on: true }],
  { align: 'right', cols: [{ b: 'Save & Apply' }, { b: 'Save' }, { b: 'Cancel' }] },
]" />

Leave **Host** blank — that is the local socket, where the database trusts a
local login and no password is stored anywhere. Leave **Databases** blank to
take the whole cluster. Pick **dump** and set **Destination** to the store you
just tested. The defaults for everything else are already what most people want.

That form saves a second small file — the job, in full:

```ini
# /etc/app-setup/params/backup-postgresql.conf
host=                 # blank = the local socket (no password stored)
port=5432
user=postgres
password=
databases=            # blank = every database, roles and all
method=dump           # dump | binary | files
store=r2              # the store you set up in step 1
folder=
schedule=daily        # off | hourly | daily | weekly | monthly
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

The three **methods**, shortest useful first:

<FigRows :rows="[
  [{ t: 'dump', tone: 'strong' }, { t: 'pg_dumpall / mysqldump — text you can read. The default, and the one to use.', tone: 'mute' }],
  [{ t: 'binary', tone: 'strong' }, { t: 'a physical copy over the replication protocol. The only one that backs up a remote host properly.', tone: 'mute' }],
  [{ t: 'files', tone: 'strong' }, { t: 'stop the database, copy its data directory, start it. This machine only, always with downtime.', tone: 'mute' }],
]" />

The **retention** numbers are a ladder, not a count: keep the newest in each
hour, day, week and month, as long as that period is still inside its budget.
`0 / 7 / 4 / 6` — the default — is a week of dailies, a month of weeklies, half
a year of monthlies, out of a handful of files.

## Backing up, and putting it back

Open the job and its buttons are the four verbs:

<FigScreen title="PostgreSQL" :lines="[
  { pack: true, cols: [{ b: '▶ Back up now' }, { b: '▤ List backups' }, { b: '✓ Verify' }, { b: '⟲ Restore' }] },
  { pack: true, cols: [{ b: 'Settings' }, { b: 'Log' }, { b: 'How to use it' }] },
  [{ t: 'Needs a store on the Backup tab, set up and tested.', tone: 'mute', face: 'small' }],
]" />

The same four from a script — this is what the nightly timer runs, and what you
run to check on it:

<FigRows :head="['Command', 'does']" :rows="[
  [{ m: 'app-setup backup backup-postgresql' }, { t: 'pack a backup and upload it', tone: 'mute' }],
  [{ m: 'app-setup archives backup-postgresql' }, { t: 'list what exists, here and in the bucket', tone: 'mute' }],
  [{ m: 'app-setup verify backup-postgresql' }, { t: 'open the newest and check it loads', tone: 'mute' }],
  [{ m: 'app-setup restore backup-postgresql' }, { t: 'put the newest one back', tone: 'mute' }],
]" />

**Restore of a dump is one button.** It pulls the newest archive from the store,
opens it, and loads it. A `dump` and the physical `binary`/`files` methods
restore differently, and the tool does the right one for whatever the archive
turns out to be.

**Restore of a physical (`binary`) backup is deliberately not one button.**
Putting a `pg_basebackup` back means deciding whether this is a restore or a new
replica and writing the right signal file — a thing that changed at PostgreSQL
12 and is different again for a cluster taking WAL archives. Guess it and you
get a server that starts and is quietly missing the last hour. So Restore on a
physical archive unpacks it beside the data directory, prints the exact steps
for your version, and stops. If you only ever use `dump` — and you should, for
one database on one box — you never meet this.

There is also a store-free pair, for a quick copy you keep yourself:

```
root@box:~# app-setup dump postgresql    # one .sql into /data/app-setup/dumps/
root@box:~# app-setup load postgresql    # feed the newest one back in
```

## Making the database as small as possible

A database ships sized for a machine whose *only* job is being a database. On a
container it is sharing memory with everything else, and left alone it reserves
hundreds of megabytes before it has served a single query. **app-setup sizes it
down for you, at install, from the RAM your container actually has** — you do
not have to do anything for the common case. This section is for when you want
it smaller still.

Every database recipe asks one question — how much memory is here — and answers
it the same way, so MariaDB and PostgreSQL never disagree about what "small"
means:

<FigRows :head="['Your container', 'profile', 'what happens']" :rows="[
  [{ t: 'under 512M' }, { t: 'tiny', tone: 'strong' }, { t: 'every default is wrong and gets cut hard', tone: 'mute' }],
  [{ t: '512M – 1G' }, { t: 'small', tone: 'strong' }, { t: 'the worst of them are trimmed', tone: 'mute' }],
  [{ t: '1G and up' }, { t: 'normal', tone: 'strong' }, { t: 'left alone — the defaults are right by then', tone: 'mute' }],
]" />

Below 1G it writes one extra config file with sizes scaled to the machine, and
it tells you it did. For **MariaDB** the file is
`/etc/mysql/mariadb.conf.d/90-app-setup.cnf`, and the three lines that matter
are the three caches that are 128M *each* by default:

```ini
# /etc/mysql/mariadb.conf.d/90-app-setup.cnf  — on a 512M container
[mysqld]
innodb_buffer_pool_size    = 64M    # an eighth of RAM (default 128M)
aria_pagecache_buffer_size = 16M    # a legacy cache charged even if unused
key_buffer_size            = 16M
max_connections            = 64
tmp_table_size             = 16M
max_heap_table_size        = 16M
```

For **PostgreSQL** it appends a block to the cluster's own `postgresql.conf`.
The two that carry the weight are `shared_buffers` (reserved once, up front) and
`work_mem` (charged *per sort, per connection* — the real ceiling is this times
the sorts in flight, which is why it stays tiny):

```ini
# appended to /data/postgresql/postgresql.conf  — on a 512M container
shared_buffers = 32MB     # an eighth of RAM (default 128MB)
work_mem = 1MB            # per sort, per connection — kept small on purpose
maintenance_work_mem = 16MB
max_connections = 16
effective_cache_size = 64MB
max_parallel_workers_per_gather = 0   # parallelism costs more than it returns here
max_parallel_workers = 0
autovacuum_max_workers = 1
jit = off
```

The measured difference is not small: a stock PostgreSQL comes up over 100MB
resident having served nothing; sized for a 512M box it reserves a fraction of
that. MariaDB's three 128M caches — 384M before a connection — become a few tens
of megabytes.

**To force it smaller than your RAM would suggest** — a 1G box where the
database is a bit part and something else wants the memory — set the profile
when you install:

```
root@box:~# APP_SETUP_PROFILE=tiny app-setup install postgresql
```

`tiny` writes the hardest cuts regardless of the actual RAM. The config file
carries a header saying what wrote it and why, and deleting it and restarting
the service goes back to the distro's own defaults. Give the machine more memory
and run the install again and the file is rewritten to match — above 1G it is
removed entirely.

Two more knobs, if the tuning is not enough:

<FigRows :rows="[
  [{ t: 'Fewer connections', tone: 'strong' }, { t: 'every connection is a process (PostgreSQL) or a set of buffers (MariaDB). max_connections is a memory setting, not just a limit.', tone: 'mute' }],
  [{ t: 'Move the data to /data', tone: 'strong' }, { t: 'not memory, but disk — and the one that survives a reinstall. The recipe offers to do it for you.', tone: 'mute' }],
]" />

## Every config file, in full

There are only ever these, all under one path — `/etc/app-setup` — and all
plain text you can read and edit. `params/` is what the forms saved; `secrets/`
is generated passwords, `0700`, one file each `0600`.

```ini
# /etc/app-setup/params/store-r2.conf        — a Cloudflare R2 destination
account=<32-hex account id>
bucket=web3
prefix=backups
access_key=<R2 access key>
secret_key=<R2 secret key>
```

```ini
# /etc/app-setup/params/store-scp.conf        — an SSH box (key auth, no password)
target=backup@nas.local:/volume1/backups
port=22
```

```ini
# /etc/app-setup/params/backup-postgresql.conf  — the PostgreSQL job
host=                 # blank = local socket
port=5432
user=postgres
password=
databases=            # blank = all
method=dump
store=r2
folder=
schedule=daily
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

```ini
# /etc/app-setup/params/backup-mysql.conf       — the MySQL / MariaDB job
host=                 # blank = local socket
port=3306
user=root
password=
databases=            # blank = all
method=dump
store=r2
folder=
schedule=daily
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

Edit one and the change takes effect on the next run; a service that reads it
picks it up on restart. Nothing here is hidden state — a password sitting in one
file at mode `600` is a thing you can reason about.

## Is this actually simple?

For the common case — one database, on one box, dumped to a bucket every night —
yes: it is two installs and it runs itself, and putting it back is one command.
The one idea you have to hold is the **store and the job**, and it is one idea.

The places it is deliberately *not* one button are the places where a wrong
button would quietly lose data: a store that has never passed its five-step test
will not accept a job, and a physical backup will not restore itself by
guessing. Both refusals are the feature working.

If you want the shortest possible path and nothing else, it is this:

```
root@box:~# app-setup install store-r2          # fill in the bucket, press Test
root@box:~# app-setup install backup-postgresql # pick the database, press Save
root@box:~# app-setup backup backup-postgresql  # once now, to be sure
root@box:~# app-setup restore backup-postgresql # the day you need it
```

## See also

- [Quick start](/quick-start) — installing the database in the first place.
- [Using your container](/using-your-container) — what `/data` is, and why the
  database belongs on it.
- `app-setup docs backup-postgresql` — the recipe explaining itself, on the box.
