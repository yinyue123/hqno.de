# Backing up your database

A backup is two things you set up once — **where it goes**, and **what it
is** — and after that it runs on a timer and you forget about it. Putting one
back is a single command.

This page walks it through end to end with a real example: **PostgreSQL, to a
free Cloudflare R2 bucket, in about ten minutes.** The same steps work for the
other databases — you only change one word:

| Your database | Install it | Back it up |
|---|---|---|
| **PostgreSQL** | `app-setup install postgresql` | `app-setup install backup-postgresql` |
| **MySQL / MariaDB** | `app-setup install mysql` | `app-setup install backup-mysql` |
| **MongoDB** | `app-setup install mongodb` | `app-setup install backup-mongodb` |
| **Redis** | `app-setup install redis` | `app-setup install backup-redis` |

The worked example below uses `backup-postgresql`. For MySQL, read
`backup-mysql` everywhere it appears; the forms and buttons are identical.

---

## A worked example: PostgreSQL → free R2

### Step 0 — you have a database running

If you followed the [quick start](/quick-start) you already do. If not:

```
root@box:~# app-setup install postgresql
```

It comes up already sized for your container (see
[making it small](#making-the-database-as-small-as-possible)).

### Step 1 — get a free R2 bucket

Cloudflare R2 is where the backups will live, and its free tier is generous —
this is the free lunch worth taking:

<FigRows :head="['R2 free tier', 'each month']" :rows="[
  [{ t: 'Storage', tone: 'strong' }, { t: '10 GB — years of nightly database dumps', tone: 'mute' }],
  [{ t: 'Uploads (Class A)', tone: 'strong' }, { t: '1,000,000 operations', tone: 'mute' }],
  [{ t: 'Downloads (Class B)', tone: 'strong' }, { t: '10,000,000 operations', tone: 'mute' }],
  [{ t: 'Egress / bandwidth', tone: 'strong' }, { t: 'free, always — R2 never charges to download', tone: 'ok' }],
]" />

That last row is the point of R2: an S3 bucket at AWS charges you to *pull a
backup back*, R2 does not. A database dump is small, so you will not come close
to the 10 GB either way.

To make the bucket:

1. Sign in at **dash.cloudflare.com** and click **R2** in the left sidebar.
   (Enabling R2 the first time asks for a card, but the free tier above bills
   nothing.)
2. **Create bucket**. Give it a name — `my-backups` — leave Location on
   **Automatic**, and create it.

That is the bucket done. Now the keys.

### Step 2 — get the three values app-setup needs

app-setup asks for a **bucket**, an **account id**, and an **access key /
secret key** pair. You have the bucket. The other three:

1. On the R2 page, the **Account ID** is on the right-hand side — a 32-character
   hex string. Copy it. (It is also the front of your S3 endpoint,
   `https://<account id>.r2.cloudflarestorage.com`.)
2. Click **Manage R2 API Tokens** → **Create API Token**.
3. Set **Permissions** to **Object Read & Write**, and under **Specify
   bucket(s)** choose the one bucket you just made — a token scoped to one
   bucket is the safe kind. Create it.
4. The next screen shows, **once**, an **Access Key ID** and a **Secret Access
   Key**. Copy both now — the secret is never shown again.

You now have four values that look like this:

```ini
account id   a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4     # 32 hex, from the R2 page
bucket       my-backups
access key   1234567890abcdef1234567890abcdef     # from the token screen
secret key   fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
```

### Step 3 — put them into app-setup

```
root@box:~# app-setup install store-r2
```

It opens a form — fill in the four values (the endpoint and region it works out
for you, so there is no box for them):

<FigScreen title="Cloudflare R2 · Settings" :lines="[
  [{ t: 'Cloudflare account id', tone: 'mute' }, { f: 'a1b2c3d4e5f6…', fw: 210 }],
  [{ t: 'Bucket', tone: 'mute' }, { f: 'my-backups', fw: 210 }],
  [{ t: 'Base folder', tone: 'mute' }, { f: 'backups', fw: 210 }],
  [{ t: 'Access key', tone: 'mute' }, { f: '1234567890abcdef…', fw: 210 }],
  [{ t: 'Secret key', tone: 'mute' }, { f: '••••••••••••••••', fw: 210 }],
  { align: 'right', cols: [{ b: 'Save & Apply' }, { b: 'Save' }, { b: 'Cancel' }] },
]" />

Prefer the command line? The same thing, no menu:

```
root@box:~# app-setup set store-r2 \
    account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4 \
    bucket=my-backups \
    access_key=1234567890abcdef1234567890abcdef \
    secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
```

Either way it lands in one small file — this is the whole of the store's
configuration, and the only place your keys live, at mode `600`:

```ini
# /etc/app-setup/params/store-r2.conf
account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
bucket=my-backups
prefix=backups
access_key=1234567890abcdef1234567890abcdef
secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
```

### Step 4 — verify it (this is the step people skip and regret)

Press **✓ Test connection** in the form, or:

```
root@box:~# app-setup test store-r2
```

It does not just log in. It makes a folder, writes a file, lists it, reads it
back and compares the bytes, then deletes it — five steps, because a key with
the wrong permissions can connect and list and *then* fail at the first real
backup, and this is what catches that before it costs you:

<FigScreen title="Cloudflare R2 · Test" :lines="[
  [{ t: '✓', tone: 'ok' }, { t: 'making a folder', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'writing a file into it', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'listing it', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'reading it back and comparing', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'deleting it', tone: 'mute' }],
  [{ t: 'folder, write, read and delete all worked — s3://my-backups/backups', tone: 'ok' }],
]" />

If any line comes back red, fix that before going on — usually the token was
scoped wrong or read-only. A store that has never passed all five is one the
next step refuses to use, on purpose.

### Step 5 — turn the backup on

```
root@box:~# app-setup install backup-postgresql
```

It opens the job form. You only touch three things: leave **Host** blank (that
is the local socket — no password to store), leave **Databases** blank (all of
them), and set **Destination** to **r2**. Save.

<FigScreen title="PostgreSQL · Settings" :lines="[
  [{ t: '▸ The database', tone: 'accent' }],
  [{ t: '   Host', tone: 'mute' }, { f: '', note: 'blank = the local socket' }],
  [{ t: '   Databases', tone: 'mute' }, { f: '', note: 'blank = all of them' }],
  [{ t: '▸ How', tone: 'accent' }],
  [{ t: '   Method', tone: 'mute' }, { r: 'dump', on: true }, { r: 'binary' }, { r: 'files' }],
  [{ t: '▸ Where it goes', tone: 'accent' }],
  [{ t: '   Destination', tone: 'mute' }, { r: 'r2', on: true }],
  [{ t: '▸ When', tone: 'accent' }],
  [{ t: '   When', tone: 'mute' }, { r: 'daily', on: true }],
  { align: 'right', cols: [{ b: 'Save & Apply' }, { b: 'Save' }, { b: 'Cancel' }] },
]" />

From here a dump goes to R2 every night on its own. Done — the rest of this
step is proving it.

### Step 6 — prove it, right now

Do not wait until tonight to find out it works:

```
root@box:~# app-setup backup backup-postgresql
  ==> dumping every database, role and tablespace
  ==> packing backup-postgresql_20260822T140038Z.tgz  (4.0K)
  ==> uploading to r2:backups
  ok  uploaded

root@box:~# app-setup archives backup-postgresql
  backup-postgresql_20260822T140038Z.tgz   4.0K   just now   r2
```

There it is, in the bucket. You are backed up.

### Step 7 — the day you need it back

```
root@box:~# app-setup restore backup-postgresql
```

It pulls the newest archive from R2, opens it, and loads it. One command, and
the database is back where it was.

That is the whole thing. Everything below is reference — read it when you want
to change something.

---

## The one idea behind it: a store, and a job

You set up two cards, not one, and knowing why is the whole of understanding
this. A **store** is *where backups go* — the R2 bucket you just made, or a box
with SSH on it. A **job** is *what to back up and how often* — this database,
nightly, keep a fortnight. One store can hold many jobs; a job points at one
store.

<FigRows :arrow="1" :head="['You set up', 'which answers']" :rows="[
  [{ t: 'a store', tone: 'strong' }, { t: 'where do backups go?', tone: 'mute' }],
  [{ t: 'a job', tone: 'strong' }, { t: 'what, how often, keep how many?', tone: 'mute' }],
]" />

The store comes first because a job with nowhere to send its output will not
install. After that you never think about the store again.

## A store other than R2

R2 is the easy one, but any of these work — pick whatever you already have
somewhere to put files:

| Store | when you have |
|---|---|
| **store-r2** | a Cloudflare R2 bucket — the example above |
| **store-s3** | AWS, MinIO, Aliyun OSS, Tencent COS, Backblaze — anything S3 |
| **store-scp** | any machine with `sshd` on it and nothing else |
| **store-rsync** | the same, where the far end also has `rsync` (resumes, sends only changes) |
| **store-webdav** / **store-ftp** | a Nextcloud share, or an FTP space |

They all present the same five-step Test, and a job points at any of them the
same way. `store-scp` is worth a note:

```ini
# /etc/app-setup/params/store-scp.conf   — an SSH box, key auth, no password
target=backup@nas.local:/volume1/backups
port=22
```

It logs in with a key it makes for itself — press **Show the public key**, put
that one line in `~/.ssh/authorized_keys` on the far end, press Test. Nothing a
stolen container could read gets it a shell.

## The backup job, in detail

The job form saves a second small file — this is all of it:

```ini
# /etc/app-setup/params/backup-postgresql.conf
host=                 # blank = the local socket (no password stored)
port=5432
user=postgres
password=
databases=            # blank = every database, roles and all
method=dump           # dump | binary | files
store=r2              # the store you set up
folder=
schedule=daily        # off | hourly | daily | weekly | monthly
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

The three **methods**, simplest-and-best first:

<FigRows :rows="[
  [{ t: 'dump', tone: 'strong' }, { t: 'pg_dumpall / mysqldump — text you can read. The default, and the one to use.', tone: 'mute' }],
  [{ t: 'binary', tone: 'strong' }, { t: 'a physical copy over the replication protocol. The only one that backs up a remote host properly.', tone: 'mute' }],
  [{ t: 'files', tone: 'strong' }, { t: 'stop the database, copy its data directory, start it. This machine only, always with downtime.', tone: 'mute' }],
]" />

The **retention** numbers are a ladder, not a count: keep the newest in each
hour, day, week and month, as long as that period is still inside its budget.
`0 / 7 / 4 / 6` — the default — is a week of dailies, a month of weeklies, half
a year of monthlies, out of a handful of files.

## The four verbs, from the menu or a script

Open the job and its buttons are the four things you ever do:

<FigScreen title="PostgreSQL" :lines="[
  { pack: true, cols: [{ b: '▶ Back up now' }, { b: '▤ List backups' }, { b: '✓ Verify' }, { b: '⟲ Restore' }] },
  { pack: true, cols: [{ b: 'Settings' }, { b: 'Log' }, { b: 'How to use it' }] },
]" />

<FigRows :head="['Command', 'does']" :rows="[
  [{ m: 'app-setup backup backup-postgresql' }, { t: 'pack a backup and upload it', tone: 'mute' }],
  [{ m: 'app-setup archives backup-postgresql' }, { t: 'list what exists, here and in the bucket', tone: 'mute' }],
  [{ m: 'app-setup verify backup-postgresql' }, { t: 'open the newest and check it loads', tone: 'mute' }],
  [{ m: 'app-setup restore backup-postgresql' }, { t: 'put the newest one back', tone: 'mute' }],
]" />

**Restore of a `dump` is one button** — that is Step 7 above.

**Restore of a physical (`binary`) backup is deliberately not one button.**
Putting a `pg_basebackup` back means deciding whether this is a restore or a new
replica and writing the right signal file — a thing that changed at PostgreSQL
12. Guess it and you get a server that starts and is quietly missing the last
hour. So Restore on a physical archive unpacks it beside the data directory,
prints the exact steps for your version, and stops. Use `dump` — for one
database on one box you never meet this.

There is also a store-free pair, for a quick copy you keep yourself:

```
root@box:~# app-setup dump postgresql    # one .sql into /data/app-setup/dumps/
root@box:~# app-setup load postgresql    # feed the newest one back in
```

## Making the database as small as possible

A database ships sized for a machine whose *only* job is being a database. On a
container it shares memory with everything else, and left alone it reserves
hundreds of megabytes before serving a single query. **app-setup sizes it down
for you, at install, from the RAM your container actually has** — you do not
have to do anything for the common case. This section is for wanting it smaller
still.

Every database recipe asks one question — how much memory is here — and answers
it the same way, so PostgreSQL and MariaDB never disagree about what "small"
means:

<FigRows :head="['Your container', 'profile', 'what happens']" :rows="[
  [{ t: 'under 512M' }, { t: 'tiny', tone: 'strong' }, { t: 'every default is wrong and gets cut hard', tone: 'mute' }],
  [{ t: '512M – 1G' }, { t: 'small', tone: 'strong' }, { t: 'the worst of them are trimmed', tone: 'mute' }],
  [{ t: '1G and up' }, { t: 'normal', tone: 'strong' }, { t: 'left alone — the defaults are right by then', tone: 'mute' }],
]" />

Below 1G it writes one extra config file, scaled to the machine, and tells you
it did. For **PostgreSQL** it appends a block to `postgresql.conf`. The two that
carry the weight are `shared_buffers` (reserved once, up front) and `work_mem`
(charged *per sort, per connection* — the real ceiling is this times the sorts
in flight, which is why it stays tiny):

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

For **MariaDB** the file is `/etc/mysql/mariadb.conf.d/90-app-setup.cnf`, and
the three lines that matter are the three caches that are 128M *each* by
default:

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

The measured difference is not small: a stock PostgreSQL comes up over 100MB
resident having served nothing; sized for a 512M box it reserves a fraction of
that. MariaDB's three 128M caches — 384M before a connection — become a few tens
of megabytes.

**To force it smaller than your RAM would suggest** — a 1G box where the
database is a bit part — set the profile when you install:

```
root@box:~# APP_SETUP_PROFILE=tiny app-setup install postgresql
```

`tiny` writes the hardest cuts regardless of the actual RAM. The file carries a
header saying what wrote it; delete it and restart the service to go back to the
distro's own defaults. Give the machine more memory and install again and it is
rewritten to match — above 1G it is removed entirely.

Two more knobs, if the tuning is not enough:

<FigRows :rows="[
  [{ t: 'Fewer connections', tone: 'strong' }, { t: 'every connection is a process (PostgreSQL) or a set of buffers (MariaDB). max_connections is a memory setting, not just a limit.', tone: 'mute' }],
  [{ t: 'Move the data to /data', tone: 'strong' }, { t: 'not memory, but disk — and the one that survives a reinstall. The recipe offers to do it for you.', tone: 'mute' }],
]" />

## Every config file, in full

There are only ever these, all under one path — `/etc/app-setup` — and all
plain text you can read and edit. `params/` is what the forms saved; `secrets/`
is generated passwords, `0700`, one file each `0600`. The job files for MongoDB
and Redis (`backup-mongodb.conf`, `backup-redis.conf`) have the same shape as
the two below with a different port.

```ini
# /etc/app-setup/params/store-r2.conf          — a Cloudflare R2 destination
account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
bucket=my-backups
prefix=backups
access_key=1234567890abcdef1234567890abcdef
secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
```

```ini
# /etc/app-setup/params/backup-postgresql.conf   — the PostgreSQL job
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
# /etc/app-setup/params/backup-mysql.conf         — the MySQL / MariaDB job
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

Edit one and the change takes effect on the next run. Nothing here is hidden
state — a password sitting in one file at mode `600` is a thing you can reason
about.

## Is this actually simple?

For the common case — one database, on one box, dumped to a bucket every night —
yes: it is the seven steps above, most of which are one command, and after them
it runs itself. The one idea you have to hold is the **store and the job**, and
it is one idea.

The places it is deliberately *not* one button are the places where a wrong
button would quietly lose data: a store that has never passed its five-step test
will not accept a job, and a physical backup will not restore itself by
guessing. Both refusals are the feature working.

The shortest possible path, all of it:

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
- `app-setup docs backup-postgresql` — the recipe explaining itself, on the box
  (swap in `backup-mysql`, `backup-mongodb` or `backup-redis` for the others).
