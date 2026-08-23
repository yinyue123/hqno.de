# Backing up files

A database has a recipe. The program you wrote does not — and neither does the
one that keeps everything in files rather than a database. Something running
from `/opt/thing`, with its config in `/etc/thing` and its uploads in
`/var/lib/thing`, has three directories nothing else here would ever save. This
is the recipe that saves them: **`files`** — you name the directories, and it
backs them up the same way, to the same places, on the same timer as every
database recipe does.

This page is that recipe, start to finish, with a real example: an hqnode
container running [`code`](https://github.com/yinyue123/code) — which keeps its
sessions, settings and per-device passwords as **files under `/data`, with no
database at all** — backed up to another machine over SSH, and put back. The
two recipes it uses are `store-rsync` (where backups go) and `files` (what to
back up and how often).

> This is the same store, the same five-step test and the same four verb
> buttons as [Backing up PostgreSQL](/backup-postgresql) — only *what* is saved
> differs. If you have read that page, most of this is already familiar; skip to
> [the size question](#the-size-question-full-every-time-or-incremental), which
> is the one thing files have that a database dump does not.

---

## A worked example: a container's `/data` → another machine

### Step 0 — you have files worth keeping

The `code` container keeps everything under `/data`, and that is the whole of
it — two things and nothing else:

<FigRows :head="['under /data', 'what']" :rows="[
  [{ t: '/data/code.yaml', tone: 'strong' }, { t: 'the configuration', tone: 'mute' }],
  [{ t: '/data/store', tone: 'strong' }, { t: 'the file store — sessions, settings, the per-device passwords', tone: 'mute' }],
]" />

There is no `pg_dump` to run and no database to size, because there is no
database: a backup of this container is a **copy of those files**, and a restore
is putting them back. That is exactly what the `files` recipe is for.

### Step 1 — a place to put them

A backup has to live somewhere that is not this container. Cloudflare R2 works
(the [PostgreSQL page](/backup-postgresql#step-1-get-a-free-r2-bucket) walks
through it, and a job points at a bucket the same way), but files are just as
often sent to **a machine you already have** — a NAS, a VPS, another box with
`sshd` on it. That is what this example uses, and there are two cards for it:

<FigRows :head="['Card', 'when the far end has']" :rows="[
  [{ t: 'store-rsync', tone: 'strong' }, { t: 'rsync — resumes a transfer that died at 90%, sends only the changed part of a file', tone: 'mute' }],
  [{ t: 'store-scp', tone: 'strong' }, { t: 'only sshd — nothing to install on the far end but OpenSSH', tone: 'mute' }],
]" />

Both log in with a **key**, not a password. No password is stored anywhere; the
one time a password is used is putting the key onto the far end, once.

### Step 2 — set the destination, and let it make a key

```
root@box:~# app-setup install store-rsync
```

Open Settings and put the far end in **Target**, as `user@host:/path` — the path
is the base directory backups go under:

<FigScreen title="rsync over SSH · Settings" :lines="[
  [{ t: 'Target', tone: 'mute' }, { f: 'root@192.0.2.10:/tmp', fw: 230 }],
  [{ t: 'SSH port', tone: 'mute' }, { f: '22', fw: 80 }],
  { align: 'right', cols: [{ b: 'Show the public key' }, { b: '✓ Test connection' }] },
]" />

Installing makes an SSH key for backups the first time, at
`/etc/app-setup/secrets/backup_ed25519` — mode `600`, no passphrase, because this
runs from cron at four in the morning and there is nobody to type one. **Every
SSH store on this machine shares that one key**, so you only ever install it
once, no matter how many far ends you back up to.

### Step 3 — put the key on the far end

Press **Show the public key** (from a shell, it is the file
`/etc/app-setup/secrets/backup_ed25519.pub`), and add that one line to
`~/.ssh/authorized_keys` for the user in your Target. If you can already log in
to the far end with a password:

```
# from the far end, or from anywhere that can reach it with the password
ssh-copy-id -i /etc/app-setup/secrets/backup_ed25519.pub -p 22 root@192.0.2.10
```

or by hand on the far end:

```
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA…app-setup backup on <host>' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

> A directory at `chmod 600` is the trap here — no execute bit means sshd cannot
> read the `authorized_keys` inside it, and key auth fails with nothing in the
> client's output to say why. It is `700` on `~/.ssh` and `600` on the file.

Worth doing while you are there: restrict what the key may do, so a stolen
container cannot use it for a shell.

```
# rsync store — restrict to writing under one directory:
command="rrsync /tmp",restrict ssh-ed25519 AAAA…
# scp store — no rrsync, but still take away everything but file transfer:
restrict ssh-ed25519 AAAA…
```

### Step 4 — verify it (this is the step people skip and regret)

Press **✓ Test connection**, or:

```
root@box:~# app-setup test store-rsync
```

It does not just log in. It makes a folder, writes a file into it, lists it,
reads it back and compares the bytes, then deletes it — five steps, because an
account that can write a file but cannot make a folder under the directory it
was given is a normal configuration, and it looks fine until the first real
backup dies at its first `mkdir`:

<FigScreen title="rsync over SSH · Test" :lines="[
  [{ t: '✓', tone: 'ok' }, { t: 'making a folder', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'writing a file into it', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'listing it', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'reading it back and comparing', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: 'deleting it', tone: 'mute' }],
  [{ t: 'folder, write, read and delete all worked — root@192.0.2.10:/tmp', tone: 'ok' }],
]" />

The first test also **pins the far end's host key** and prints its fingerprint;
every connection after that requires it to match, and a changed host key fails
loudly rather than being trusted quietly. A store that has never passed all five
steps is one the next step refuses to use, on purpose.

### Step 5 — say what to save, and turn it on

```
root@box:~# app-setup install files
```

Three fields do the work — **What to save** (the directories, comma separated),
**Destination** (the store you just set up), and **When**:

<FigScreen title="Files and folders · Settings" :lines="[
  [{ t: '▸ What to save', tone: 'accent' }],
  [{ t: '   Paths', tone: 'mute' }, { f: '/data/code.yaml, /data/store', fw: 260 }],
  [{ t: '   Skip', tone: 'mute' }, { f: '*.log, *.tmp, node_modules, .git', fw: 260 }],
  [{ t: '   Stop first', tone: 'mute' }, { f: '', note: 'a service to stop while copying — optional' }],
  [{ t: '▸ Where it goes', tone: 'accent' }],
  [{ t: '   Destination', tone: 'mute' }, { r: 'rsync', on: true }],
  [{ t: '▸ When', tone: 'accent' }],
  [{ t: '   When', tone: 'mute' }, { r: 'off', on: true }, { r: 'daily' }],
  { align: 'right', cols: [{ b: 'Save & Apply' }, { b: 'Save' }, { b: 'Cancel' }] },
]" />

The same, from a shell:

```
root@box:~# app-setup set files paths=/data/code.yaml,/data/store store=rsync
root@box:~# app-setup install files
  ==> measuring
  ok  2 paths, 8.0K
  ok  ready — press ▶ Back up now to take one
```

Set **When** to `daily` and a copy goes to the far end every night on its own.
Left `off`, nothing runs on a timer but **▶ Back up now** still works — which is
what the next step is.

### Step 6 — prove it, right now

```
root@box:~# app-setup backup files
  ==> backing up files
  ==> copying /data/code.yaml
  ==> copying /data/store
  ==> packing files_20260822172333.tgz
  ok  /data/app-setup/backups/files/files_20260822172333.tgz  (2.0K)
  ==> uploading files_20260822172333.tgz to rsync:dmit/files
  ok  uploaded

root@box:~# app-setup archives files
  on this machine   /data/app-setup/backups/files/
    files_20260822172333.tgz   2.0K   just now   rsync
  on rsync          dmit/files/
    files_20260822172333.tgz          just now
```

There it is — a copy on the box, and a copy on the far end under
`<hostname>/files/`. The hostname in the path is what keeps two containers
sharing one destination from pruning each other's history.

### Step 7 — the day you need it back

```
root@box:~# app-setup restore files
  ==> fetching files_20260822172333.tgz from rsync:dmit/files
      restoring from files_20260822172333.tgz

  This puts back, overwriting what is there now:
      /data
      /data/store
      /data/store/projects

  ==> putting the saved files back
  ok  restored
```

It pulls the newest archive from the far end, opens it, and copies the files
back to exactly where they came from. One command, and the container's data is
back where it was.

> **Restoring overwrites in place.** A website has one document root that can be
> moved aside and put back; this is a handful of paths scattered around the
> filesystem, and there is no single directory to move. What is at those paths
> now is overwritten, not moved aside — so if it matters, take your own copy
> first. This is the one way `files` differs from a database restore, and it is
> the reason it is the one verb that asks you to confirm.

That is the whole thing. Everything below is reference — read it when you want
to change something.

---

## The one idea behind it: a store, and a job

You set up two cards, not one, and it is the same idea as every backup on the
machine. A **store** is *where backups go* — the SSH box you just set up, or an
R2 bucket. A **job** is *what to back up and how often* — these directories,
nightly, keep a fortnight. One store can hold many jobs; a job points at one
store.

<FigRows :arrow="1" :head="['You set up', 'which answers']" :rows="[
  [{ t: 'a store', tone: 'strong' }, { t: 'where do backups go?', tone: 'mute' }],
  [{ t: 'a job', tone: 'strong' }, { t: 'which paths, how often, keep how many?', tone: 'mute' }],
]" />

The store comes first, because a job with nowhere to send its output will not
install. After that you never think about the store again.

## A store other than rsync

Any of these hold a `files` backup, and a job points at one the same way — pick
whatever you already have somewhere to put files:

| Store | when you have |
|---|---|
| **store-rsync** | a machine with `rsync` — resumes, and sends only the changed part of a file |
| **store-scp** | a machine with `sshd` and nothing else — see the note below |
| **store-s3** / **store-r2** | any S3 bucket — AWS, MinIO, Aliyun OSS, Tencent COS, Backblaze, Cloudflare R2 |
| **store-webdav** / **store-ftp** | a Nextcloud share, or an FTP space |

**A note on the scp store, learned the hard way.** Modern OpenSSH `scp` (9+)
speaks the SFTP protocol, so the scp store needs the far end to run a working
`sftp-server` — which every ordinary `openssh-server` ships and enables, so on a
normal box it just works. Where it does *not* is a far end whose SSH is **not**
ordinary OpenSSH. An hqnode host is exactly that: its public port 22 is answered
by the hqnode gateway (`SSH-2.0-hqnode`), which relays a shell and `rsync` but
does not offer the SFTP subsystem — so the scp store fails there with a puzzling
`sftp-server: No such file or directory`, while the rsync store to the same port
is fine. The fix is to point the scp store at the far end's **real OpenSSH
port** (an hqnode machine's own `sshd` is typically on a high port such as
36000), not at the gateway on 22. If in doubt, use the rsync store: it needs no
SFTP subsystem, and it resumes.

## The `files` job, in detail

The job form saves one small file — this is all of it, and the values are the
ones from the example above:

```ini
# /etc/app-setup/params/files.conf
paths=/data/code.yaml,/data/store    # comma separated; globs allowed
exclude=*.log, *.tmp, node_modules, .git
service=                             # blank = nothing is stopped while copying
store=rsync                          # the store you set up
folder=                              # blank = <hostname>/files on the far end
prune_remote=off                     # also delete old archives on the far end
schedule=off                         # off | hourly | daily | weekly | monthly
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

A few of these earn a word:

<FigRows :rows="[
  [{ t: 'Paths', tone: 'strong' }, { t: 'comma separated, and globs expand — /var/www/*/uploads is fine. A path listed but not on this machine is warned about, not skipped silently: a typo in a path is indistinguishable from a working backup until the day it is not.', tone: 'mute' }],
  [{ t: 'Skip', tone: 'strong' }, { t: 'excluded WHILE copying, not after — a node_modules that got copied and then pruned has already cost the disk and the minutes.', tone: 'mute' }],
  [{ t: 'Stop first', tone: 'strong' }, { t: 'a service to stop for the length of the copy. A plain directory has no consistent snapshot, so if something is writing to it steadily, name it here. Most config directories are not being written at 4am, so this is usually blank.', tone: 'mute' }],
]" />

The **retention** numbers are a ladder, not a count: keep the newest in each
hour, day, week and month, as long as that period is still inside its budget.
`0 / 7 / 4 / 6` is a week of dailies, a month of weeklies, half a year of
monthlies.

### Two mistakes already prevented

<FigRows :rows="[
  [{ t: 'Backing up /data would not swallow itself', tone: 'strong' }, { t: 'app-setup writes its own archives under /data/app-setup, and that directory is always excluded — otherwise backing up /data would pack every previous archive into the new one, and each backup would be bigger than the last until the disk filled.', tone: 'mute' }],
  [{ t: '/, /proc, /sys, /dev, /run are refused', tone: 'strong' }, { t: 'outright — they are not things to put in a backup.', tone: 'mute' }],
]" />

## The four verbs, from the menu or a script

<FigRows :head="['Command', 'does']" :rows="[
  [{ m: 'app-setup backup files' }, { t: 'pack the paths and upload the archive', tone: 'mute' }],
  [{ m: 'app-setup archives files' }, { t: 'list what exists, here and on the far end', tone: 'mute' }],
  [{ m: 'app-setup verify files' }, { t: 'open the newest and check it unpacks — nothing is written back', tone: 'mute' }],
  [{ m: 'app-setup restore files' }, { t: 'put the newest one back (overwrites in place)', tone: 'mute' }],
]" />

`verify` is worth running once after the first backup: it fetches the newest
archive, unpacks it to a scratch directory, counts the files and throws the
scratch copy away — "this archive opens and holds 5 saved files, nothing has
been written back." A backup you have never opened is a hope, not a backup.

## The size question: full every time, or incremental?

**Every `files` backup is a full one.** It packs the paths into a fresh, dated
`.tgz` and uploads the whole thing — there is no delta against last night's. The
rsync store's "sends only what changed" is about resuming *one file's* transfer;
because each night is a **new** tarball with a new name, rsync sees a brand-new
file and sends all of it. So the honest picture is:

<FigRows :arrow="1" :head="['If the total is', 'a nightly full backup is']" :rows="[
  [{ t: 'small — configs, a few MB', tone: 'strong' }, { t: 'exactly right. Do this. The retention ladder keeps a handful of tiny files and you never think about it.', tone: 'ok' }],
  [{ t: 'large — tens of GB of uploads', tone: 'strong' }, { t: 'wasteful: you store and send the whole tree every time, times however many copies the ladder keeps.', tone: 'mute' }],
]" />

For the small case — which is most containers, and certainly the `code` example
above at 8KB — stop here; full is the simple, correct answer.

For a genuinely large tree, three ways out, cheapest first:

**1. Save less.** Most big directories are big because of things that do not
need backing up — caches, logs, `node_modules`, thumbnails, or uploads that
already live in an S3 bucket. `Skip` them. The backup you do not take is the
cheapest one there is.

**2. Keep fewer.** Drop the retention ladder to `keep_daily=2, keep_weekly=0,
keep_monthly=0` and you hold two full copies instead of seventeen. Often that is
the whole fix.

**3. A true incremental mirror, with rsync `--link-dest`.** When you really do
need many restore points over a large tree, the packaged full-tarball job is the
wrong tool — reach past it to rsync directly. `--link-dest` makes each night a
**complete** snapshot on the far end, but any file unchanged since last night is
a hard link to last night's copy, so it costs no extra bytes. A 40 GB tree that
changes by 200 MB a day keeps thirty daily snapshots in ~46 GB, not 1.2 TB:

```sh
#!/bin/sh
# /usr/local/bin/snapshot — an incremental mirror, using the key app-setup made.
set -eu
SRC=/data/                                  # trailing slash: contents, not the dir
DEST=root@192.0.2.10                         # a real OpenSSH far end
BASE=/backups/thisbox                        # snapshots live under here
KEY=/etc/app-setup/secrets/backup_ed25519
today=$(date -u +%Y%m%d)
rsync -a --delete \
  -e "ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes" \
  --link-dest="$BASE/latest" \
  --exclude='app-setup/'  --exclude='*.log' \
  "$SRC" "$DEST:$BASE/$today/"
ssh -i "$KEY" "$DEST" "ln -sfn $BASE/$today $BASE/latest"
```

Point cron at it (`app-setup install cron`, or a line in `/etc/crontabs/root`),
and every `$BASE/<date>/` is a full directory tree you can browse and copy back
from with a plain `rsync` or `scp` in the other direction. This is deliberately
*outside* the store-and-job model — it does not pack, date, prune or verify the
way `app-setup backup` does, and putting it back is your own `rsync` rather than
one button. That is the trade: `--link-dest` buys space on a large tree at the
cost of the packaging the `files` job gives you for free on a small one.

> The rule of thumb: **use the `files` recipe until a full nightly tarball
> actually hurts** — the disk it fills or the bandwidth it costs is a number you
> can see, and `app-setup archives files` shows you the size. Only then is the
> `--link-dest` mirror worth its extra moving parts.

## Every config file, in full

Two small files, both plain text under `/etc/app-setup`, both readable and
editable. Edit one and the change takes effect on the next run.

```ini
# /etc/app-setup/params/store-rsync.conf   — where backups go
target=root@192.0.2.10:/tmp
port=22
```

```ini
# /etc/app-setup/params/store-scp.conf     — a real OpenSSH far end (not :22 on
target=root@192.0.2.10:/tmp                 # an hqnode host — see the scp note)
port=36000
```

```ini
# /etc/app-setup/params/files.conf         — the job
paths=/data/code.yaml,/data/store
exclude=*.log, *.tmp, node_modules, .git
service=
store=rsync
folder=
prune_remote=off
schedule=daily
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

The key lives at `/etc/app-setup/secrets/backup_ed25519` (mode `600`), shared by
every SSH store. Nothing here is a password — the key is the whole of the
credential, and taking the container away takes nothing a far end would honour
once you remove that one line from its `authorized_keys`.

## Is this actually simple?

For the common case — a container that keeps its data in files, copied to a
machine you own every night — yes: it is the seven steps above, most of which
are one command, and after them it runs itself. The one idea to hold is the
**store and the job**, and it is one idea.

The shortest possible path, all of it:

```
root@box:~# app-setup install store-rsync        # set the target, press Test
root@box:~# app-setup install files              # name the paths, pick the store
root@box:~# app-setup backup files               # once now, to be sure
root@box:~# app-setup restore files              # the day you need it
```

## See also

- [Backing up PostgreSQL](/backup-postgresql) — the same store, test and verbs,
  for a database. The store you set up here serves both.
- [Using your container](/using-your-container) — what `/data` is, and why the
  things worth backing up belong on it.
- `app-setup docs files` — the recipe explaining itself, on the box.
