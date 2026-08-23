# Backing up files

A database has a recipe. The program you wrote does not — and neither does the
one that keeps everything in files. The **`files`** recipe is for those: you
name the directories, it saves them on a timer, and `restore` puts them back.

Most machines hold two kinds of thing, and they want opposite treatment. This
page is one half each:

<FigRows :head="['', 'Part 1 — config', 'Part 2 — images']" :rows="[
  [{ t: 'example', tone: 'mute' }, { t: '/etc/myapp, /data/code.yaml', tone: 'strong' }, { t: '/data/store/uploads', tone: 'strong' }],
  [{ t: 'size', tone: 'mute' }, { t: 'a few MB', tone: 'mute' }, { t: 'tens of GB', tone: 'mute' }],
  [{ t: 'how', tone: 'mute' }, { t: 'full backup, every night', tone: 'ok' }, { t: 'incremental mirror', tone: 'ok' }],
  [{ t: 'where', tone: 'mute' }, { t: 'an S3 bucket (R2)', tone: 'mute' }, { t: 'your own machine, over SSH', tone: 'mute' }],
  [{ t: 'history', tone: 'mute' }, { t: '15 copies, ~5 months', tone: 'mute' }, { t: '1 copy, or a snapshot a day', tone: 'mute' }],
  [{ t: 'tool', tone: 'mute' }, { t: 'the files job', tone: 'mute' }, { t: 'rsync, driven by you', tone: 'mute' }],
]" />

**Read the half you need.** They share one idea — a *store* is where backups go,
a *job* is what to save — and nothing else.

---

# Part 1 — Config files: full backups to R2

Small, precious, and you want to be able to go back months. A full copy every
night is exactly right here: the archives are a few KB.

## Step 0 — what you are saving

Four things, on a machine running a program called `myapp`:

```
/etc/myapp/app.conf          listen 5080
/etc/myapp/log.conf          level=info
/data/code.yaml              port: 5080
/data/store/settings.json    {"device":"laptop"}
```

## Step 1 — a free R2 bucket

Backups have to leave this machine. Cloudflare R2 is free to a level you will
not reach with config files — 10 GB stored, and **downloads are never charged**,
which is the part that matters on the day you restore.

1. **dash.cloudflare.com** → **R2** → **Create bucket**. Name it `my-backups`,
   leave Location on **Automatic**.
2. Copy the **Account ID** from the right-hand side — 32 hex characters.
3. **Manage R2 API Tokens** → **Create API Token** → permission **Object Read &
   Write**, scoped under **Specify bucket(s)** to `my-backups`.
4. The next screen shows the **Access Key ID** and **Secret Access Key** once.
   Copy both now.

You end up with exactly four values:

```ini
account id   a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
bucket       my-backups
access key   1234567890abcdef1234567890abcdef
secret key   fedcba0987654321fedcba0987654321fedcba0987654321fedcba09
```

## Step 2 — put them in

```
root@box:~# app-setup install store-r2
root@box:~# app-setup set store-r2 \
    account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4 \
    bucket=my-backups \
    prefix=backups \
    access_key=1234567890abcdef1234567890abcdef \
    secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba09
```

That writes one file, and it is the only place the keys live:

```ini
# /etc/app-setup/params/store-r2.conf
account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
bucket=my-backups
prefix=backups
access_key=1234567890abcdef1234567890abcdef
secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba09
```

> **Any other S3 works the same** — MinIO, Aliyun OSS, Tencent COS, Backblaze,
> AWS itself. Use `store-s3` instead of `store-r2` and give it the endpoint:
>
> ```
> root@box:~# app-setup set store-s3 \
>     bucket=my-backups endpoint=http://192.0.2.10:9000 region=us-east-1 \
>     prefix=backups access_key=… secret_key=…
> ```

## Step 3 — test it before you trust it

```
root@box:~# app-setup test store-r2
==> making a folder
==> writing a file into it
==> listing it
==> reading it back
==> deleting it
  ok folder, write, read and delete all worked — s3://my-backups/backups
```

Five steps, not one, because a key that can write but not list is a normal
misconfiguration that looks fine until the first real backup. **A store that has
never passed all five is one the next step refuses to use.**

## Step 4 — say what to save

Note the third entry — **a glob**, because `myapp` has more than one conf file:

```
root@box:~# app-setup set files \
    paths='/data/code.yaml, /data/store, /etc/myapp/*.conf' \
    store=r2 schedule=daily
root@box:~# app-setup install files
  ==> measuring
  ok  3 paths, 16.0K
  ok  scheduled daily, minute 51
  ok  ready — press ▶ Back up now to take one
```

## Step 5 — take one now

```
root@box:~# app-setup backup files
  ==> backing up files
  ==> copying /data/code.yaml
  ==> copying /data/store
  ==> copying /etc/myapp/app.conf
  ==> copying /etc/myapp/log.conf
  ==> packing files_20260823055612.tgz
  ok  /data/app-setup/backups/files/files_20260823055612.tgz  (4.0K)
  ==> uploading files_20260823055612.tgz to s3:box/files
  ok  uploaded

root@box:~# app-setup archives files
  on this machine   /data/app-setup/backups/files/
    files_20260823055612.tgz    4.0K   2026-08-23 05:56 UTC
  on s3             box/files/
    files_20260823055612.tgz           2026-08-23 05:56 UTC
  1 here, 1 there.
```

The glob expanded — two `copying` lines for `/etc/myapp/*.conf`. Check the
count: **3 paths in, 4 files saved.**

Worth doing once, before you need it for real:

```
root@box:~# app-setup verify files
  ok  this archive opens and holds 4 saved file(s). Nothing has been written back.
```

## Step 6 — the day you need it back

The real test is with nothing left locally — no files, and no local archive
either, so it has to come from the bucket:

```
root@box:~# rm -rf /etc/myapp /data/code.yaml /data/store
root@box:~# rm -rf /data/app-setup/backups/files

root@box:~# app-setup restore files
  ==> fetching files_20260823055612.tgz from s3:box/files
  This puts back, overwriting what is there now:
      /data
      /data/store
      /etc/myapp
  ==> putting the saved files back
  ok  restored

root@box:~# cat /etc/myapp/app.conf /data/code.yaml
listen 5080
workers 4
port: 5080
name: code
```

> **Restoring overwrites in place**, and the *command* does not stop to ask —
> only the panel's **⟲ Restore** button confirms. `app-setup restore files`
> prints the list of paths above and then does it. Read that list before you
> press Enter, not after.

## Keeping months of history

Four numbers, and they are a ladder, not a count — keep the newest of each hour,
day, week and month. Fed a year of nightly backups they settle here:

| Setting | Archives kept | Oldest one |
|---|---|---|
| `0 / 7 / 4 / 6` (the default) | **15** | ~5 months back |
| `0 / 7 / 4 / 12` | **21** | ~11 months back |
| `0 / 7 / 0 / 0` | 7 | 6 days back |
| `0 / 2 / 0 / 0` | 2 | yesterday |

The rungs overlap — last night's archive is the newest daily *and* weekly *and*
monthly — so you get fewer files than the four numbers added up. For a year of
config history, one number changes:

```
root@box:~# app-setup set files keep_daily=7 keep_weekly=4 keep_monthly=12
```

Two behaviours worth knowing before you rely on it:

**It counts back from the newest archive, not from the clock.** A machine that
was off for six weeks comes back with its whole daily rung intact.

**`prune_remote=off` is the default, and it means the bucket is never
pruned at all.** The ladder above trims this machine's disk; every archive ever
uploaded stays in R2. For a few KB a night that is free history. Turned on, it
deletes at most one ladder's worth per run:

```
root@box:~# app-setup set files prune_remote=on
root@box:~# app-setup backup files
  ==> pruning s3:box/files
  !   stopped after 17 deletions — that is more than one ladder's worth.
      287 kept there
```

So a bucket with three hundred old archives comes down over several nights, not
in one go. That is the guard working.

## More than one thing to save

`paths` is a comma-separated list and globs expand, so this is all one job:

```ini
paths=/etc/myapp/*.conf, /data/code.yaml, /data/store, /opt/thing, /var/lib/thing
```

Three rules that save time:

```ini
# A path that is not on this machine is WARNED about, not skipped silently:
#   ! listed but not on this machine: /etc/typo
# because a typo and a working backup look identical until the day they do not.

# Skip is applied WHILE copying, not after:
exclude=*.log, *.tmp, node_modules, .git

# /data/app-setup is always excluded, so backing up /data does not pack every
# previous archive into the new one. /, /proc, /sys, /dev and /run are refused.
```

**There is only one `files` job per machine** — one `files.conf`, one path list,
one schedule, one ladder. That is fine for any number of config directories.
It is not fine when one of them is 40 GB of images, and that is Part 2.

---

# Part 2 — Images and uploads: incremental over SSH

## Why not just add it to Part 1

Because **every `files` backup is a full one.** It packs a fresh dated `.tgz`
and uploads the whole thing; there is no delta against last night. Add a 40 GB
uploads directory to that job and you store and send 40 GB every night, times
however many copies the ladder keeps.

Measured on a 100-file, 9.8 MB tree — the same tree, two ways:

| | Per night after the first |
|---|---|
| `files` job (full tarball) | **9.8 MB** — the whole tree, packed and sent again |
| rsync mirror | **104,217 bytes** — only the one file that changed |

So the split is: **config goes in the `files` job; images stay out of it and
are mirrored with rsync directly.**

## Step 1 — a machine to send them to

Any box with `sshd`. A NAS, a VPS, another container. Two store cards:

| Card | When the far end has |
|---|---|
| **store-rsync** | `rsync` — resumes a transfer that died at 90% |
| **store-scp** | only `sshd`, nothing to install — but see the note in the reference |

```
root@box:~# app-setup install store-rsync
root@box:~# app-setup set store-rsync target=root@192.0.2.10:/backups port=36000
```

`port` matters. Many boxes do not run sshd on 22 — this example is a real one
on **36000**, and everything below picks that up on its own.

## Step 2 — the key onto the far end

Installing made `/etc/app-setup/secrets/backup_ed25519`. No password is stored
anywhere; the one time you use one is now, putting the key across:

```
root@box:~# app-setup showkey store-rsync
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFaPoXIBQczYNhTI5LQ... app-setup backup

# on the far end:
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA…' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

> `chmod 600` on the **directory** is the trap. Without the execute bit sshd
> cannot read the file inside it, and key auth fails with nothing in the
> client's output to say why. `700` on `~/.ssh`, `600` on the file.

Then the same five-step test as Part 1:

```
root@box:~# app-setup test store-rsync
  ok  folder, write, read and delete all worked — root@192.0.2.10:/backups
```

> **Post-quantum warnings are not a failure.** A current OpenSSH client against
> an older `sshd` prints `WARNING: connection is not using a post-quantum key
> exchange algorithm` on every connection — so this test prints it five times.
> Nothing is wrong.

## Step 3 — keep the big tree out of the `files` job

If `/data/store` is in `paths`, then `/data/store/uploads` is in the nightly
tarball. Exclude it:

```
root@box:~# app-setup set files exclude='data/store/uploads, *.log, *.tmp'
```

> **No leading slash.** The copy runs from `/` with relative names, so a pattern
> starting with `/` matches nothing — silently. Same tree, same job, one line
> different:
>
> ```ini
> exclude=/data/store/uploads    →  archive is 20,412,339 bytes, all 200 images in it
> exclude=data/store/uploads     →  archive is 338 bytes, none
> exclude=uploads                →  also 338 bytes — matching by name works too
> ```

## Step 4 — mirror it

One current copy on the far end, always up to date. 40 GB stays 40 GB forever.

```sh
#!/bin/sh
# /usr/local/bin/mirror-uploads — one current copy, no history.
set -eu
SRC=/data/store/uploads/       # trailing slash: contents, not the dir
SSH=$(app-setup sshcmd store-rsync)
DEST=$(app-setup remote store-rsync uploads)
$SSH "${DEST%%:*}" "mkdir -p '${DEST#*:}'"
rsync -a --delete -e "$SSH" "$SRC" "$DEST/"
```

Those two `app-setup` lines are the whole trick. They print, for this store:

```
root@box:~# app-setup sshcmd store-rsync
ssh -i /etc/app-setup/secrets/backup_ed25519 -p 36000 -o IdentitiesOnly=yes \
    -o UserKnownHostsFile=/etc/app-setup/secrets/backup_known_hosts \
    -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10

root@box:~# app-setup remote store-rsync uploads
root@192.0.2.10:/backups/uploads
```

> **Do not write those flags out by hand.** Two of them are not guessable:
> `-p 36000`, which a hand-copied command silently drops to 22, and
> `UserKnownHostsFile`, because `app-setup test` pinned the far end's key into
> the *store's* known_hosts, not `~/.ssh/known_hosts`. Skip it and you get
> `No ED25519 host key is known … Host key verification failed`.
>
> The `mkdir -p` is not optional either: `rsync` creates only the **last**
> component of a destination path.

Then put it on a timer (`app-setup install cron`, or a line in
`/etc/crontabs/root`).

## Step 5 — or keep a snapshot a day

A mirror answers "the files as they are now". If you also want "the files as
they were last Tuesday", use `--link-dest`: each day is a **complete** tree, but
files that did not change are hard links to yesterday's, costing nothing.

```sh
#!/bin/sh
# /usr/local/bin/snapshot — dated snapshots that share unchanged files.
set -eu
SRC=/data/store/uploads/
SSH=$(app-setup sshcmd store-rsync)
DEST=$(app-setup remote store-rsync snapshots)
HOST=${DEST%%:*}; DIR=${DEST#*:}
today=$(date -u +%Y%m%d)
$SSH "$HOST" "mkdir -p '$DIR'"
rsync -a --delete -e "$SSH" \
  --link-dest="$DIR/latest" \
  --exclude='*.log' \
  "$SRC" "$HOST:$DIR/$today/"
$SSH "$HOST" "ln -sfn '$DIR/$today' '$DIR/latest'"
```

Two days of the 9.8 MB tree, on the far end:

```
root@far:~# du -shl /backups/snapshots     # counting shared files twice
20M
root@far:~# du -sh  /backups/snapshots     # what the disk actually gives up
11M
root@far:~# stat -c '%h %n' /backups/snapshots/*/img50.jpg   # never changed
2 /backups/snapshots/20260101/img50.jpg
2 /backups/snapshots/20260102/img50.jpg
```

Two links means one file on disk serving both days. At scale: a 40 GB tree
changing 200 MB a day keeps thirty snapshots in about 46 GB, not 1.2 TB.

> On the **first** run only it prints `--link-dest arg does not exist:
> …/latest`. Expected — there is no previous snapshot yet, so night one is a
> full copy. It exits 0 and does not come back.

## Step 6 — getting it back

This half has no **⟲ Restore** button, so keep these two commands somewhere.
Both are one `rsync` with the ends swapped, and neither uses `--delete` — a
restore should not remove files you have here and not there.

**From the mirror** — the files as of its last run:

```sh
SSH=$(app-setup sshcmd store-rsync)
DEST=$(app-setup remote store-rsync uploads)
mkdir -p /data/store/uploads
rsync -a -e "$SSH" "$DEST/" /data/store/uploads/
```

**From a snapshot** — ask which days exist, then pick one. `latest` in that
listing is the symlink, not a day:

```sh
SSH=$(app-setup sshcmd store-rsync)
DEST=$(app-setup remote store-rsync snapshots)
$SSH "${DEST%%:*}" "ls -1 ${DEST#*:}"
# 20260101
# 20260102
# latest
rsync -a -e "$SSH" "$DEST/20260101/" /data/store/uploads/
```

The same `img1.jpg`, restored from each day, really is a different file:

```
from 20260101 →  md5 2a0cd6684b9b5f03969a44eee3aef831
from 20260102 →  md5 53f285bb426b69c1247e8cfc1fc8805b
```

> **A mirror is only as current as its last run.** In that same test the mirror
> still held `2a0cd668…` — the older version — because nothing had run it since
> the file changed. Snapshots have the same property per day; the difference is
> that with snapshots yesterday is still there to go back to.

## More than one directory

Give each its own destination folder and reuse the same key and store:

```sh
for d in uploads avatars exports; do
  SSH=$(app-setup sshcmd store-rsync)
  DEST=$(app-setup remote store-rsync "$d")
  $SSH "${DEST%%:*}" "mkdir -p '${DEST#*:}'"
  rsync -a --delete -e "$SSH" "/data/store/$d/" "$DEST/"
done
```

On the far end that gives you:

```
/backups/uploads/    /backups/avatars/    /backups/exports/
```

---

# Reference

## The one idea: a store, and a job

<FigRows :arrow="1" :head="['You set up', 'which answers']" :rows="[
  [{ t: 'a store', tone: 'strong' }, { t: 'where do backups go?', tone: 'mute' }],
  [{ t: 'a job', tone: 'strong' }, { t: 'which paths, how often, keep how many?', tone: 'mute' }],
]" />

The store comes first — a job with nowhere to send its output will not install.
One store can hold many jobs; a job points at one store.

## Every kind of store

| Store | When you have |
|---|---|
| **store-r2** / **store-s3** | any S3 bucket — R2, AWS, MinIO, Aliyun OSS, Tencent COS, Backblaze |
| **store-rsync** | a machine with `rsync` — resumes, sends only the changed part of a file |
| **store-scp** | a machine with `sshd` and nothing else — see below |
| **store-webdav** / **store-ftp** | a Nextcloud share, or FTP space |

**The scp store, and hqnode hosts.** Modern OpenSSH `scp` (9+) speaks SFTP, so
the far end needs a working `sftp-server` — every ordinary `openssh-server` has
one. An hqnode host is not ordinary: its port 22 is the hqnode gateway
(`SSH-2.0-hqnode`), which relays a shell and `rsync` but offers no SFTP
subsystem, so `store-scp` there fails with `sftp-server: No such file or
directory` while `store-rsync` on the same port is fine. Point `store-scp` at
the machine's real sshd — often a high port such as 36000 — or just use
`store-rsync`.

## The four verbs

| Command | Does |
|---|---|
| `app-setup backup files` | pack the paths and upload |
| `app-setup archives files` | list what exists, here and there |
| `app-setup verify files` | open the newest and check it unpacks — writes nothing back |
| `app-setup restore files` | put the newest one back (overwrites in place) |

## The job file, in full

```ini
# /etc/app-setup/params/files.conf
paths=/data/code.yaml, /data/store, /etc/myapp/*.conf
exclude=data/store/uploads, *.log, *.tmp, node_modules, .git
service=                 # a service to stop while copying; blank = none
store=r2                 # the store you set up
folder=                  # blank = <hostname>/files on the far end
prune_remote=off         # also delete old archives there
schedule=daily           # off | hourly | daily | weekly | monthly
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=12
```

`service` is for a directory something writes to constantly — a plain directory
has no consistent snapshot, so name the service and it is stopped for the length
of the copy. Most config directories are not being written at 4am, so it is
usually blank.

## See also

- [Backing up PostgreSQL](/backup-postgresql) — the same stores, test and verbs,
  for a database. One store serves both.
- [Using your container](/using-your-container) — what `/data` is, and why the
  things worth backing up belong on it.
- `app-setup docs files` — the recipe explaining itself, on the box.
