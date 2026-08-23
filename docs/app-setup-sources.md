# Adding your own software to app-setup

`app-setup` does not know what nginx is. It reads a directory of shell scripts,
draws one entry per script, and runs the script when you press a key. So adding
your own software — a private build, a game server, your company's agent — is
writing one file and dropping it in a directory. Nothing is recompiled, nothing
is registered, and your file is treated exactly like the ones that shipped with
the image.

**Do not write that file by hand.** Nobody does any more, and there is nothing
to be won by it. The whole contract is one page — this one — and a model handed
that page plus any one of the forty-nine recipes already in the repository
writes a working recipe on the first or second try. Sections 1 to 4 are that
route, in order, and they are short.

- [1. Get the recipes](#_1-get-the-recipes)
- [2. The prompt](#_2-the-prompt)
- [3. Check what comes back](#_3-check-what-comes-back)
- [4. Ship it](#_4-ship-it)

Everything after those four is the contract itself, unchanged. You do not have
to read it: it is what you hand the model, and what you look things up in when
what it gave you does something you did not expect.

- [The shortest possible source](#the-shortest-possible-source)
- [Where files go](#where-files-go)
- [The header](#the-header)
- [The functions](#the-functions)
- [The status verb](#the-status-verb)
- [Helpers you get for free](#helpers-you-get-for-free)
- [Writing for more than one distro](#writing-for-more-than-one-distro)
- [Testing it](#testing-it)
- [A worked example](#a-worked-example)
- [Publishing a set of sources](#publishing-a-set-of-sources)
- [Rules of the road](#rules-of-the-road)

---

## 1. Get the recipes

```sh
git clone https://github.com/yinyue123/hqno.de.git
cd hqno.de/images/app-setup
```

Three things are in there, and the first two are what the model needs:

| | |
|---|---|
| `recipes/` | the forty-nine that ship in every image, one file each |
| `lib/common.sh` | the helper library all of them source |
| `install.sh` | puts the whole thing on a Linux box you have root on, so you can test off the container |

Pick the recipe closest to what you are adding and give the model that one file
as well as this page. It is worth more than any amount of description:

| Yours is… | Read |
|---|---|
| one package, no service | `htop.sh`, `ncdu.sh` — a dozen lines |
| a package with a service and a config file | `nginx.sh`, 140 lines, the best reference there is |
| a single binary off GitHub, no package anywhere | `gitea` in [a worked example](#a-worked-example) below |
| several pieces behind one menu entry | `lnmp.sh` — nginx, MySQL and PHP as one |
| something with a Settings form | `backup.sh`, and [Settings somebody can change](#settings-somebody-can-change) |

---

## 2. The prompt

Paste this, with the last two lines filled in. Give the model the URL as well —
this page is one file and models read it whole:
`https://doc.hqno.de/app-setup-sources`.

```text
Write one app-setup source file for hqnode. app-setup is a TUI software
picker inside a container: it reads /etc/app-setup/*.sh, draws one menu
entry per file from the comment header, and runs a function in the file
when somebody chooses an action. The full contract is at
https://doc.hqno.de/app-setup-sources — read it before writing anything.

Hard requirements:

- POSIX sh only. It runs under busybox ash on Alpine. No [[ ]], no arrays,
  no ${x^^}, no $'...', no bashisms of any kind.
- The file starts with `#!/bin/sh` and a comment header. `# app-setup: 1`
  is what makes it a source at all; `id`, `name`, `summary`, `category`
  and `disk` are the minimum after it. Add `.zh` variants of name, summary
  and includes — the panel is bilingual.
- Source /usr/lib/app-setup/common.sh and USE IT. pkg_install, make_service,
  svc_enable, fetch, rand_pass, param, data_path, guess_host, step, ok, die
  already exist. Do not write per-distro if/else and do not write systemd
  units and OpenRC scripts by hand — make_service emits whichever this
  machine uses.
- End the file with `app_main "$@"` and put nothing else at top level. The
  file is executed for every action, so a bare `exit` in the body runs at
  parse time for all of them.
- do_uninstall removes the program and NEVER the data. Leave the databases,
  the uploads, the repositories, and print where they are and the exact
  command to delete them.
- Installing twice in a row must work. The second run must not fail on a
  user, a directory or a config the first one left behind.
- Declare every temporary variable `local`. Functions share one namespace.
- do_status runs every 8 seconds for every entry on screen: read a file or
  check a process, nothing more. Exit 0 running, 1 stopped, 2 absent,
  3 broken.
- Be honest in `disk` and `memory`. Somebody on a 512MB box decides with
  those numbers.

Here is a shipped recipe to match the style of: <paste one file from
images/app-setup/recipes/>

What I am adding: <what it is, how it installs, what it listens on, where
its data lives, and anything a person has to do by hand afterwards>
```

The two placeholders at the bottom are doing most of the work. "Add Uptime
Kuma" gets you something plausible; "add Uptime Kuma, it is a Node app, npm
install into /opt/uptime-kuma, listens on 3001, data in its own directory, no
package exists for it" gets you something that installs.

If it is your own private software, say so and say how it is fetched — a
tarball behind a token, a `.deb` on an internal host, a git checkout. That is
the part no model can guess and the only part that is really yours.

---

## 3. Check what comes back

Six mistakes, and they are the six that actually happen. Two minutes with this
list beats an hour of debugging a menu entry that half works.

1. **Bashisms.** `[[ ]]` and arrays are the common two, and they run fine on
   the model's mental Ubuntu and die on Alpine. One command settles it:
   `busybox ash -n yourfile.sh`.
2. **A hand-written systemd unit,** or an `if [ "$OS_ID" = alpine ]` ladder
   around two copies of the same thing. `make_service` is one line and covers
   both inits. If the answer has a heredoc writing into
   `/etc/systemd/system`, send it back.
3. **`rm -rf` in `do_uninstall`.** Sometimes on the data directory, sometimes
   on `/data`. This is the one that costs somebody their database, so read
   that function even if you read nothing else.
4. **Not idempotent** — `useradd` with no `id … ||` in front of it,
   `mkdir` without `-p`. Install it, uninstall it, install it again; the
   second install is where sources break.
5. **A `do_status` that starts a process** — `curl` at the port, a `docker
   ps`, a full `systemctl show`. Every eight seconds, for every entry on the
   screen.
6. **A missing `summary`,** or a header that stops early because a blank line
   crept into it. `app-setup doctor` exits non-zero on it, which is why that
   is the first thing to run in §4.

---

## 4. Ship it

Two ways, and they answer different questions.

<FigRows :head="['', 'One container', 'Your own image']" :rows="[
  [{ t: 'what you do', tone: 'mute' }, { t: 'copy the file into /etc/app-setup/local/', tone: 'strong' }, { t: 'add it to images/app-setup/recipes/ in your fork', tone: 'strong' }],
  [{ t: 'how long', tone: 'mute' }, { t: 'seconds', tone: 'ok' }, { t: 'a push and a few minutes of CI', tone: 'mute' }],
  [{ t: 'survives a reinstall', tone: 'mute' }, { t: 'no — /etc comes from the image', tone: 'bad' }, { t: 'yes, it is in the image', tone: 'ok' }],
  [{ t: 'who gets it', tone: 'mute' }, { t: 'this one container', tone: 'mute' }, { t: 'everything installed from your image', tone: 'mute' }],
]" />

### Into one container

```sh
scp myapp.sh you@container:/etc/app-setup/local/     # from your laptop
chmod +x /etc/app-setup/local/myapp.sh
app-setup doctor && app-setup info myapp && app-setup install myapp
```

`local/` is already on the default search path and comes after the shipped
directory, so a file there with the same `id` as one of ours replaces it
without editing anything. [Testing it](#testing-it) is the longer version of
that last line.

This is the right way to find out whether the recipe works, and the wrong way
to keep it: `/etc/app-setup` comes from the image and a reinstall replaces it.
Keep the original under `/data` and copy it into place at boot, or do the other
thing.

### Into an image of your own

The recipes directory *is* the image's `/etc/app-setup` — all three Dockerfiles
carry one line, `COPY app-setup/recipes/ /etc/app-setup/`. So a file in that
directory of your fork is in the image, and nothing else has to be told about
it. No index, no registration, no build script to edit.

1. **Fork** [`yinyue123/hqno.de`](https://github.com/yinyue123/hqno.de) on
   GitHub, and clone your fork rather than ours.
2. **Drop the file in** `images/app-setup/recipes/myapp.sh`, `chmod +x`, commit,
   push to `main`.
3. **Turn Actions on.** A fork arrives with its workflows disabled — the
   Actions tab says so and has the button. One click, once.
4. **The workflow then runs itself.**
   [`.github/workflows/images.yml`](https://github.com/yinyue123/hqno.de/blob/main/.github/workflows/images.yml)
   triggers on any push touching `images/**`, builds every system in
   [`systems.yml`](https://github.com/yinyue123/hqno.de/blob/main/images/systems.yml),
   and pushes them to `ghcr.io/<you>/hqnode:<tag>` — `alpine-3.24`,
   `debian-13`, and eighteen more. It needs no secret: `GITHUB_TOKEN` and
   `packages: write` are enough. Trim `systems.yml` to the one or two systems
   you actually install from and the build drops from twenty legs to two.
5. **Make the package public, once, by hand.** A new GHCR package is private,
   and a private package is a `401` when the machine tries to pull it.
   Settings → Packages → hqnode → Change visibility. Nothing in the workflow
   can do this for you.
6. **Install a container from it.** In the panel, paste the reference where an
   image reference goes: `ghcr.io/<you>/hqnode:alpine-3.24`. The machine pulls
   it, not the panel and not your laptop —
   [Getting the machine to pull it](/building-your-own-image#_7-getting-the-machine-to-pull-it)
   is the full set of cases, including private registries.

Your fork also gets its own `images/catalog.json`, written back by the same
workflow with the digests it just pushed. That is the file a panel fetches to
fill its market, so a host pointed at your fork's raw URL offers your systems
instead of ours.

**A whole tab of your own** is one header line in any one source, if you have
enough of them to want one:

```sh
# category: mycompany
# category.name: Our software
# category.name.zh: 我们的软件
```

---

## The shortest possible source

Save this as `/etc/app-setup/hello.sh`, `chmod +x` it, and run `app-setup`. It
is on the System tab.

```sh
#!/bin/sh
# app-setup: 1
# id: hello
# name: Hello
# summary: The smallest possible app-setup source.
# category: system
# disk: 1M
. /usr/lib/app-setup/common.sh

PKGS="cowsay"
CHECK_BIN="cowsay"

do_help() { echo "Run: cowsay hello"; }

app_main "$@"
```

That is a complete, working entry, with Install, Uninstall and How-to-use-it in
the menu it opens. Install and remove are inherited — `PKGS` is enough for anything that is one package
and no service.

The `# app-setup: 1` line is what makes the file a source. A file without it is
ignored, which is how the helper library can live in the same directory
tree without appearing as software.

---

## Where files go

| Path | What it is |
|---|---|
| `/etc/app-setup/*.sh` | the shipped sources |
| `/etc/app-setup/local/*.sh` | your own. Same id as a shipped one and yours wins |
| `/etc/app-setup/params/<id>.conf` | what the Settings form saved for a source |
| `/etc/app-setup/secrets/<id>.txt` | generated passwords, mode 600 in a 0700 directory |
| `/usr/lib/app-setup/common.sh` | the helper library every source sources |
| `/var/log/app-setup/<id>.log` | every action's output, appended |
| `/var/lib/app-setup/` | bookkeeping — the package-index refresh stamp lives here |

Everything you might want to open is under `/etc/app-setup`, which is the point
of it: one directory, and it is the one you would have looked in anyway.
`$APP_SETUP_CONF` moves `params/` and `secrets/` if you need them elsewhere.

Search order is `$APP_SETUP_PATH`, which defaults to
`/etc/app-setup:/etc/app-setup/local`. Later directories win, so a file in
`/etc/app-setup/local/nginx.sh` replaces the shipped `nginx` entry without
editing anything. That is the intended way to override one of ours: leave the
original alone so an image update can still replace it. `local/` is also the
half that survives app-setup reinstalling its own recipes, which only ever
replaces `*.sh` in the parent directory.

To try a source without installing it anywhere:

```sh
APP_SETUP_PATH=/etc/app-setup:$HOME/my-sources app-setup
```

**Sources survive a container restart but not a reinstall.** A reinstall
replaces the image, and `/etc/app-setup` comes from the image. Keep the
originals under `/data`, which does survive, and copy them into place — a line
in `/etc/rc.local` or a systemd unit is enough.

---

## The header

Comment lines at the top of the file, `key: value`, ending at the first line
that is not a comment. app-setup parses these; it never sources the file to
draw an entry. That is deliberate — drawing the catalogue must not execute forty
shell scripts, and a file somebody dropped in should not get to run merely by
existing. It runs when a key is pressed.

| Key | Required | Meaning |
|---|---|---|
| `app-setup: 1` | **yes** | marks the file as a source. Without it the file is invisible |
| `id` | no | the name used on the command line. Defaults to the filename without `.sh` |
| `name` | no | the title in the listing. Defaults to the id |
| `name.zh` | no | the title in Chinese |
| `category` | no | which tab. `stack`, `web`, `db`, `dev`, `system`, or your own. Defaults to `system` |
| `category.name` | no | the label for a category you invented |
| `category.name.zh` | no | the same in Chinese |
| `order` | no | position within the tab, lowest first. Defaults to 100 |
| `summary` | no | one line of prose in the listing. Say what it is *for* |
| `summary.zh` | no | the same in Chinese |
| `includes` | no | what lands on the machine, in a phrase |
| `includes.zh` | no | the same in Chinese |
| `disk` | no | installed size — `800M`, `2G`. Shown, and compared against free space |
| `memory` | no | what it needs to run. Compared against this machine's RAM |
| `ports` | no | what it listens on, for the listing |
| `requires` | no | what it needs, for the listing. Prose, not a dependency solver |
| `service` | no | the init service name, if there is one |
| `param` | no | a setting the holder may change. Repeatable, up to 12 — see below |

Every `.zh` is optional. Leave it out and the English is shown to everybody,
which is better than a bad translation.

`disk` and `memory` earn their place: the size line turns red when this machine
cannot hold what you are about to install, and app-setup asks for confirmation
rather than letting somebody discover it 400MB into a download. Guess honestly
— an install that fails at 95% is worse than one that warns first.

Two categories are worth knowing about:

- Listing more than one is allowed: `category: dev, web` puts it in both
  lists.
- Naming a category nobody has heard of creates it. `category: games` plus
  `category.name: Game servers` adds a tab, and no code changes.

---

## Settings somebody can change

A `param:` line puts a field in the Settings form, which is the entry in the
menu you get by pressing Enter on your software.

```sh
# param: port  | 8080          | Listen port      | 监听端口   | number
# param: root  | /var/www/demo | Document root    | 网站目录
# param: ssl   | off           | Enable HTTPS     | 启用 HTTPS | bool
# param: level | info          | Log level        | 日志级别   | debug,info,warn
```

Five fields, separated by `|`, and everything after the name is optional:

| | |
|---|---|
| name | becomes `APP_PARAM_PORT` in your environment. Letters, digits, `_` |
| default | what applies until somebody changes it |
| label | shown in the form |
| 中文标签 | the same in Chinese. Left out, the English is shown to everybody |
| type | `bool` a checkbox, `number` digits only, a comma list a chooser, `@name` a list this machine fills in, absent a text box |

**`@name` is the one type you do not write the values for.** A comma list is
fixed at the moment you write the recipe; `@backup` is answered with the
packages *on this machine* that can be backed up, which is not something you
can know from where you are sitting:

```sh
# param: targets | | What to back up | 备份哪些 | @backup
```

The field opens a tick-list rather than a text box — space ticks, Enter
commits — and the value it saves is the same comma-separated string you would
have typed, so `param targets` reads it back unchanged. What is installed is
listed first and every entry says whether it is there. `@backup` is the only
source today; a name this binary does not know degrades to a text box rather
than to an empty list, so a recipe written for a newer app-setup is still
usable on an older one.

Being in that list is not a header field you set. It is whether your recipe
defines `do_backup` — the same function `app-setup backup <id>` calls. Write
one and you are in it, with nothing else to declare and nothing to keep in
sync.

Read one back with `param`, always giving the default again:

```sh
do_install() {
    pkg_install $(pmv PKGS)
    sed -i "s/^listen .*/listen $(param port 8080);/" /etc/myapp.conf
    param_on ssl && enable_tls
}
```

Giving the default twice is not redundancy — it is what makes
`sh /etc/app-setup/myapp.sh install` behave identically when run by hand, with
no form and no saved file anywhere. **A recipe must never require that the
form has been opened.**

Saved values live in `/etc/app-setup/params/<id>.conf`, next to the source they
configure, one `name=value` a line, and `app-setup set myapp port=9090` edits
them from a script.

The form has three buttons, and they are LuCI's: **Save & Apply** writes the
settings and then runs your `install`, **Save** writes them and stops, and
**Cancel** throws the edit away. So `do_install` is also the reconfigure path,
and it is worth making it a fast one — if the binary is already the right
version, rewrite the config, restart the service and return. A holder who
changes a port should not wait for a download, and one who changes it back
should not wait twice.

Four kinds of field is the whole of it, deliberately. If your software needs
more configuration than that, it has a config file, and the useful thing to do
is say where it is in `do_help` rather than grow a wizard here. What follows —
grouping fields and giving one a button — is not a fifth field kind; it is
answering "which of my six fields does somebody actually have to look at,"
which a field type was never going to fix.

### Folding a run of fields together

```sh
# param: port     | 8080 | Listen port      | 监听端口
# group: adv | Advanced | 高级 | collapsed
# param: workers  | 4    | Worker processes | 工作进程数 | number
# param: timeout  | 30   | Request timeout  | 超时时间   | number
```

Every `param:` line after a `group:` line joins it, until the next one —
nothing goes on the param line itself. Fields declared before the first
`group:` stay ungrouped, at the top, which is why a recipe that never groups
anything needs no change at all. The fourth field is `collapsed` or
`expanded` (default); a holder folds or unfolds it in the form with Enter or
a click, same as everything else. Old binaries — anything before 2.9 — see a
comment line with a colon they do not recognise and skip it, so a recipe
using this shows every field flat on one, same as it always did.

### A button belonging to one field

```sh
# param: target  |      | Camouflage site   | 伪装网站
# action: target | scan | ↻ Refresh         | ↻ 重新扫描
```

`action: <field it belongs to> | <verb> | label | 中文标签` draws a button on
its own row directly under that field. The field must already be declared —
name the field before the action that refreshes it, same order `group:`
already asks for. `<verb>` is whatever `case "$1" in …` your own script
answers before it hands off to `app_main "$@"`:

```sh
[ "$1" = scan ] && { do_scan; exit $?; }   # before app_main "$@"
app_main "$@"
```

Pressing the button runs that verb through the exact progress screen Install
already uses — same bar, same step sentence, same log — and comes back to
Settings with the form reloaded, so a verb that rewrites your own header (the
way `rewrite_choices`-style code fills a chooser with what it just found) has
somewhere for the new choices to show up without a holder leaving the screen.
`private-pkg/realityscan.sh`'s own `↻ Refresh` next to Camouflage target is
the worked example this was built against: one press re-scans a subnet and
refreshes the dropdown, without also touching whatever configuration is
already live.

Still no sub-form, and that boundary has not moved: a field with a button can
run one script and reload; it cannot open a second form of its own. That is
still a config file's job.

---

## The functions

Define the ones you need, after sourcing `common.sh`. Anything you leave out
gets a default that works from `PKGS` and `SERVICE`.

| Function | When it runs | Default |
|---|---|---|
| `do_install` | the Install row | install `PKGS`, enable and start `SERVICE` |
| `do_uninstall` | the Uninstall row | stop and disable `SERVICE`, remove `PKGS` |
| `do_start` | the Start row | `svc_start` |
| `do_stop` | the Stop row | `svc_stop` |
| `do_restart` | the Restart row | stop then start |
| `do_enable` | the Start-at-boot row | `svc_enable` |
| `do_disable` | the same row again | `svc_disable` |
| `do_status` | constantly — see below | derived from `is_installed` and `SERVICE` |
| `do_help` | the How-to-use-it row | "this source ships no documentation" |
| `do_backup` | `app-setup backup <id>`, and the schedule | "this software has no backup in its recipe" |
| `do_restore` | `app-setup restore <id>` | the same |
| `do_dump` | `app-setup dump <id>` | "this software has no dump in its recipe" |
| `do_load` | `app-setup load <id>` | the same |
| `do_list` | `app-setup archives <id>` — the name differs because `list` is already the catalogue | "this software has no backup in its recipe" |
| `do_verify` | `app-setup verify <id>` | the same |
| `do_test` | `app-setup test <id>`, and a `# button: test` | "this is not a backup destination" |
| `is_installed` | inside `do_status` | `CHECK_PKG`, else `CHECK_BIN`, else `CHECK_FILE`, else all of `PKGS` |
| `version_line` | inside `do_status` | nothing |

The last line of the file must be `app_main "$@"`. That is what turns the verb
in `$1` into one of the calls above.

A few variables drive the defaults:

```sh
PKGS="nginx nginx-common"   # what to install
SERVICE="nginx"             # what to start
CHECK_BIN="nginx"           # how to tell it is installed — a command on PATH
CHECK_FILE="/etc/nginx"     # ...or a path, if there is no command
CHECK_PKG="nginx"           # ...or a package, when the command is not proof
```

**Reach for `CHECK_PKG` when the command might already exist.** On Alpine,
busybox provides applets called `unzip`, `ping`, `wget`, `less` and about three
hundred others *in the base image*, so `CHECK_BIN="unzip"` is true on a machine
where nothing has been installed — the listing reads "installed" and Install
never gets offered. `CHECK_PKG` asks the package manager, which busybox
cannot answer for.

Write `do_help` even when you write nothing else. It is the difference between
software somebody installed and software somebody can use. Say where the config
is, what the log is called, what the three most common errors look like, and
what uninstall will and will not delete.

---

## What the install screen shows

While a verb runs, app-setup draws a title, a progress bar, the step it is on,
and the detailed log underneath. All three come out of your script, and the
one you already use does most of it:

```sh
do_install() {
    step_total 4                       # optional — makes the bar a fraction
    step "installing packages"         # the sentence under the bar
    pkg_install $(pmv PKGS)
    step "writing the configuration"
    ...
}
```

`step` is the ordinary output helper. Every line it prints becomes the current
phase on the screen, so the sentence a holder reads is yours — *fetching
WordPress*, *creating the database* — rather than something app-setup invented.
Everything else your script prints lands in the log pane and in
`/var/log/app-setup/<id>.log`.

`step_total N` is the one extra line. With it the bar is completed steps over
`N`; without it the bar follows a curve that approaches the end without ever
arriving, which is the honest drawing for a script that has not said how long
it is. Count the `step` calls on the path actually taken — and if your install
branches so that the count differs per distro, say nothing and take the curve.
A bar that finishes at step three of six is worse than no bar.

Nothing is measuring bytes or asking the package manager how far along it is,
because neither of them knows.

---

## The status verb

The one function app-setup reads a *value* out of rather than an exit code, and
the only one that runs without anybody pressing anything. It is called for
every entry on the screen, repeatedly.

**Exit code is the state:**

| Exit | Card shows |
|---|---|
| `0` | running — or, when there is no service, simply installed |
| `1` | installed but stopped |
| `2` | not installed |
| `3` | installed and broken |

**stdout is `key=value` lines:**

| Key | Effect |
|---|---|
| `detail=` | replaces the summary line in the listing. Put the version here |
| `enabled=1` / `enabled=0` | fills the boot tick |

```sh
version_line() { printf 'nginx %s' "$(nginx -v 2>&1 | sed 's|.*nginx/||')"; }
```

...is usually all you need, because the default `do_status` calls it.

**It must be fast.** app-setup kills it after eight seconds and shows the entry
as broken. Do not query the network in `do_status`, do not `apt-get update` in
it, and do not run anything that can block on a lock another install is
holding.

---

## Helpers you get for free

`. /usr/lib/app-setup/common.sh` at the top brings in all of this. It is POSIX
sh — Alpine's `/bin/sh` is busybox ash, so there are no arrays, no `[[ ]]` and
no bashisms anywhere in it or in anything you write.

**Telling the user what is happening.** Everything goes to the log as well as
the screen, and colour is dropped when it is not a terminal.

```sh
step "installing the thing"     # ==> installing the thing
info "a detail"                 #     a detail
ok   "it worked"                #   ok it worked
warn "this is odd"              #   !  this is odd
err  "this is wrong"            #   x  this is wrong
die  "stop here"                # err, then exit 1
```

**Packages**, without caring which package manager:

```sh
pkg_install nginx curl          # apt / dnf / yum / apk / zypper / pacman
pkg_remove  nginx
pkg_present nginx               # is it installed?
pkg_exists  nginx               # do the configured repos offer it?
pkg_install_first php8.3-fpm php8.2-fpm php-fpm   # the first that exists here
pkg_install_optional php-intl   # install if offered, shrug if not
pm_refresh                      # at most once an hour, machine-wide
pm_wait_unlocked                # wait out another apt/dnf/apk, up to 3 minutes
enable_epel                     # the RHEL rebuilds keep half of userland here
```

`pkg_install` and `pkg_remove` already wait for a competing package operation,
so you rarely call `pm_wait_unlocked` yourself. It matters because your recipe
may well run on a container that booted seconds ago, where the image's own
boot-time index fetch still holds apt's lock — and apt's answer to that is to
fail in a way that reads like the package does not exist.

**Services**, without caring which init:

```sh
svc_start x; svc_stop x; svc_restart x; svc_reload x
svc_enable x; svc_disable x          # at boot
svc_running x; svc_enabled x         # exit code
svc_supported                        # false when there is no init at all
make_service NAME "Description" "/usr/local/bin/thing --serve" user /var/lib/thing
remove_service NAME
```

`make_service` writes a systemd unit or an OpenRC script from one description,
which is what a single binary with no packaging needs. Set `SVC_ENVIRON` first
if the unit needs `Environment=` lines.

**What machine is this:**

```sh
$OS_ID $OS_VERSION $OS_MAJOR $OS_NAME $OS_CODENAME   # debian, 13, 13, ...
$PM      # apt dnf yum apk zypper pacman none
$PMF     # deb rpm apk arch none  — the family, which is what you usually want
$INIT    # systemd openrc sysv none
$ARCH    # amd64 arm64 armv7
in_container    # true inside one, which is always, here
have curl       # is this command on PATH
lang_zh         # is the user reading Chinese
```

**Downloads**, curl or wget, whichever exists:

```sh
fetch https://example.com/x.tar.gz /tmp/x.tar.gz
fetch_stdout https://example.com/version.txt
ensure_downloader        # install one if neither is here
run_bounded 180 sh /tmp/vendor-install.sh    # give up after 180s, exit 124
```

`fetch` bounds its own curl. `run_bounded` is for the case it cannot reach:
somebody *else's* installer, which you hand control to and which may have no
timeout of its own. Oh My Zsh's `install.sh` ends in a `git fetch`, and where
github.com is dropped rather than refused — a firewall, a country, a flaky
route — that call waits forever and the holder watches an install that never
finishes. **Every vendor script goes through `run_bounded`.**

**Web things**, because every distro puts them somewhere different:

```sh
$WEBROOT                 # /var/www/html, on every image
nginx_conf_dir           # /etc/nginx/conf.d, or http.d on Alpine
nginx_drop_default       # remove the shipped default server, wherever it hides
nginx_test_reload        # nginx -t, then reload — refuses to reload a broken config
php_service              # php8.2-fpm, php-fpm, php83-fpm...
php_fastcgi_pass         # 127.0.0.1:9000 or unix:/run/php/....sock
php_nginx_site [root]    # a complete default server with PHP wired in
web_user; web_group      # www-data, nginx, apache — whoever php-fpm runs as
php_bin                  # php, or the versioned binary
```

**Databases:**

```sh
mysql_root -e "SELECT 1"            # root, over the socket or with .my.cnf
mysql_wait                          # the service is up before the socket is
db_mysql_create mydb myuser "$pw"   # utf8mb4, and syntax that works back to 5.5
db_mysql_drop   mydb myuser
```

**Passwords and notes.** Never print a generated password only to the install
log — nobody scrolls back through 900 lines of `apt` output.

```sh
pw="$(rand_pass 24)"
save_note myapp <<EOF          # /etc/app-setup/secrets/myapp.txt, mode 600
password   $pw
EOF
show_note myapp                # print it again at the end of the install
drop_note myapp                # in do_uninstall
```

**Composing other sources.** This is how LNMP is four lines rather than a
duplicate of nginx, PHP and MariaDB:

```sh
recipe nginx install         # run another source's verb
recipe_ensure nginx          # ...but only if it is not already installed
recipe_status nginx          # 0 running, 1 stopped, 2 absent
```

`recipe_ensure` is almost always the one you want. `recipe nginx install`
rewrites the default site, which takes down whatever was being served there.

**Files:**

```sh
backup_once /etc/nginx/nginx.conf     # keeps .app-setup-orig, once, ever
restore_backup /etc/nginx/nginx.conf
tmp_dir                               # mktemp -d, with a fallback
guess_host                            # the address to print in a URL
port_busy 80; require_ports 80 443
```

---

## Backing your software up

If your source keeps data, give it `do_backup` and `do_restore`. You describe
what the data *is*; the library names the archive, packs it, uploads it,
prunes it and puts the service back afterwards.

```sh
do_backup() {
        bk_begin myapp                 # names myapp_20260819033240.tgz
        bk_quiesce                     # stops SERVICE if the method is `files`
        myapp dump > "$(bk_path data.sql)"
        bk_add /etc/myapp              # config travels with the data
        bk_finish                      # tar, upload, prune, restart
}

do_restore() {
        bk_open myapp "${1-}"          # newest, or the archive named
        myapp load < "$BK_UNPACKED/data.sql"
        bk_restore_files "$BK_UNPACKED"
        bk_close
}
```

| Helper | What it does |
|---|---|
| `bk_begin <prefix>` | starts an archive, and installs the trap that restarts the service if anything below fails |
| `bk_path <name>` | a path inside the archive for a dump to write to |
| `bk_add <path>` | copies a file or directory in, keeping its absolute path. Honours `$BK_EXCLUDE`, never packs the backup directories, refuses `/` and friends |
| `bk_quiesce` / `bk_resume` | stop and start `SERVICE`, but only when the method is `files` |
| `bk_finish` | pack, restart, upload, prune |
| `bk_open <prefix> [archive]` | unpack into `$BK_UNPACKED` — downloads from the bucket if there is no local copy |
| `bk_restore_files <dir>` | put back everything `bk_add` saved |
| `bk_close` | clean up |
| `bk_mysql_db <db>` / `bk_mysql_load <dir>` | one MySQL database, for sources that keep one |
| `dump_target <prefix> <ext> [given]` | where a dump should be written — what was asked for, or a dated name under `/data/dumps` |
| `dump_source <prefix> <ext> [given]` | which dump to read — what was named, or the newest |
| `mysql_dump_db <db> <file>` / `mysql_load_file <file>` | the same database, as a plain file |
| `dump_tool_check <cmd> <sentence>` | say at install time whether the dump tool is actually here |

### `dump` and `load`

Worth having as well as `backup`, and not the same thing. A backup is the whole
pipeline — packed, dated, uploaded, pruned, on a timer. A dump is one plain
file somebody can open, `scp`, or feed to another server:

```sh
do_dump() {
        local _f
        _f="$(dump_target myapp sql "${1-}")"
        myapp export > "$_f" || die "the export failed"
        [ -s "$_f" ] || die "the dump came out empty; that is not a backup"
        chmod 600 "$_f"
        ok "$_f"
}

do_load() {
        local _f
        _f="$(dump_source myapp sql "${1-}")"
        myapp import < "$_f" || die "the import failed"
}
```

Make `do_backup` and `do_dump` call the *same* function with different
destinations. Two separate implementations of "how do you dump this database"
drift, and the one that drifts is always the one on the timer that nobody
watches.

Whatever produces the dump has to actually be installed — name it in `PKGS`
rather than trusting a metapackage, and end `do_install` with
`dump_tool_check`, so a distro that splits its client package differently is
found on installation day and not on the night somebody needs a restore.

Two rules worth following, both learned the expensive way:

**Fail loudly, never quietly.** Check the dump is non-empty before letting
`bk_finish` pack it. A zero-byte file inside a well-named archive looks like a
backup for a year and is discovered not to be one at the worst possible moment.

**Never leave the service down.** `bk_begin` traps `EXIT`, `INT` and `TERM` so
a failed dump or a Ctrl-C still restarts what `bk_quiesce` stopped. If you stop
something yourself, set `BK_SVC_WAS` to its name so that trap covers it too.

`bk_open` sets a variable instead of echoing a path on purpose: writing
`d="$(bk_open myapp)"` would run it in a subshell, and the trap would delete the
unpacked archive the instant the substitution closed.

Config files, not just data: `bk_add` whatever your software needs to come back
as it was. A database restored under a default config is a different server.

If your software has no recipe here at all — something you wrote yourself —
you do not need one. The shipped `files` source takes a list of paths and
globs in its settings and backs them up on the same schedule; put `files` in
the backup card's list next to `mysql`.

## Writing for more than one distro

Package names drift more than anything else. `pmv` picks the most specific
value that exists — this distro, then its package manager, then its family,
then the plain one:

```sh
PKGS="iputils-ping net-tools dnsutils"
PKGS_rpm="iputils net-tools bind-utils"
PKGS_apk="iputils net-tools bind-tools"
PKGS_centos="iputils net-tools bind-utils"   # this distro specifically

pkg_install $(pmv PKGS)
```

The suffixes, most specific first: `_<os_id>`, `_<pm>`, `_<pmf>`, then bare.
So `PKGS_ubuntu`, `PKGS_apt`, `PKGS_deb`, `PKGS`. It works for any variable
name, not just `PKGS` — `SERVICE_rpm="httpd"` is the usual second one.

When the name varies by *release* rather than by distro, ask instead of
guessing:

```sh
pkg_install_first php8.4-fpm php8.3-fpm php8.2-fpm php-fpm
```

Four systems, four things that will catch you:

- **Alpine** has no systemd, no glibc and no bash. `$INIT` is `openrc`, and a
  prebuilt binary from a vendor's website usually will not run at all.
- **AlmaLinux, Rocky and CentOS** keep half of ordinary userland — `htop`,
  `atop`, `fail2ban` — in EPEL. Call `enable_epel` before looking for them.
- **CentOS 7** is past end of life. Its MariaDB is 5.5 and predates most
  modern SQL syntax; its Python is 2.
- **Debian and Ubuntu** name PHP packages after the release, and the release
  changes every two years.

---

## Testing it

```sh
app-setup doctor                # does it parse? what does this machine look like?
app-setup list                  # is your entry there, in the right category?
app-setup info myapp            # every header field, as parsed
app-setup status myapp          # 0 running, 1 stopped, 2 absent, 3 broken
app-setup install myapp         # the real thing, with output on the terminal
app-setup docs myapp            # your do_help
app-setup screenshot --width 80 # one frame of the TUI, as text, no terminal needed
```

`doctor` counts a source with no `summary` as a problem, and exits non-zero, so
it is the one to put in a script.

The screenshot subcommand is how the listing is checked at every width without
a terminal, and `--screen menu|params|progress` does the same for the dialogs:

```sh
for w in 130 88 46; do app-setup screenshot --width $w --category system | tail -1; done
```

Check the syntax against the shell Alpine actually has, not just yours:

```sh
sh -n myapp.sh && dash -n myapp.sh && busybox ash -n myapp.sh
```

And then genuinely install it, remove it, and install it again. The second
install is where sources break: something was left behind, and the recipe
assumed a clean machine.

---

## A worked example

A single-binary server, which is the case the helpers are really for — no
package, no unit file, and a different tarball per architecture.

```sh
#!/bin/sh
# app-setup: 1
# id: gitea
# name: Gitea
# name.zh: Gitea 代码仓库
# category: dev
# order: 40
# summary: A git server with a web interface, in one binary. Your own GitHub, at about 200MB.
# summary.zh: 一个二进制文件的 Git 服务器，带网页界面。自己的 GitHub，占用约 200MB。
# includes: the gitea binary, a service, a git user, SQLite storage
# includes.zh: gitea 主程序、服务、git 用户、SQLite 存储
# disk: 250M
# memory: 200M
# ports: 3000
# service: gitea
. /usr/lib/app-setup/common.sh

SERVICE="gitea"
CHECK_FILE="/usr/local/bin/gitea"
GITEA_VER="1.22.3"

version_line() { printf 'Gitea %s on port 3000' "$GITEA_VER"; }

do_install() {
	# git itself is a package; gitea is not. One entry, both handled.
	pkg_install git

	id git >/dev/null 2>&1 || {
		step "creating the git user"
		# adduser's flags differ between shadow and busybox, so try both.
		useradd --system --shell /bin/sh --home /var/lib/gitea --create-home git 2>/dev/null ||
		adduser -S -s /bin/sh -h /var/lib/gitea git 2>/dev/null ||
		die "could not create the git user"
	}

	step "downloading gitea $GITEA_VER for $ARCH"
	fetch "https://dl.gitea.com/gitea/$GITEA_VER/gitea-$GITEA_VER-linux-$ARCH" \
	      /usr/local/bin/gitea ||
		die "could not download gitea. Check this container has a route out."
	chmod 755 /usr/local/bin/gitea

	mkdir -p /var/lib/gitea/custom /var/lib/gitea/data /etc/gitea
	chown -R git:git /var/lib/gitea
	chown -R git:git /etc/gitea          # it writes its config on first run

	# One description, and a systemd unit or an OpenRC script comes out.
	make_service gitea "Gitea" "/usr/local/bin/gitea web --config /etc/gitea/app.ini" \
	             git /var/lib/gitea
	svc_enable gitea
	svc_start  gitea

	ok "Gitea is running"
	info "finish the setup at http://$(guess_host):3000/"
}

do_uninstall() {
	remove_service gitea
	rm -f /usr/local/bin/gitea
	warn "/var/lib/gitea was NOT deleted — your repositories are still there."
	warn "Remove it yourself if you mean it:  rm -rf /var/lib/gitea /etc/gitea"
}

do_status() {
	[ -x /usr/local/bin/gitea ] || exit 2
	echo "detail=$(version_line)"
	if svc_enabled gitea; then echo "enabled=1"; else echo "enabled=0"; fi
	svc_running gitea && exit 0
	exit 1
}

do_help() { cat <<'EOF'
Gitea

  Finishing the install
    http://<your address>:3000/ — the first page is the setup form. The
    defaults are right for this machine; SQLite needs no database server.
    The first account you create is the administrator.

  Where things are
    /usr/local/bin/gitea    the program
    /etc/gitea/app.ini      the configuration, written on first run
    /var/lib/gitea          repositories, and the SQLite database

  Reaching it
    Port 3000 has to be published by the panel before your laptop can see
    it. A container's 3000 is not the host's 3000.

  Backing it up
    tar -czf /data/gitea.tar.gz /var/lib/gitea /etc/gitea
    /data is the only path that survives a reinstall.

  Uninstalling
    Removes the binary and the service. /var/lib/gitea is left behind,
    because it holds every repository you pushed.
EOF
}

app_main "$@"
```

Note what is *not* there: no `if [ "$OS_ID" = ... ]`, no systemd unit written
twice, no init detection. That is the point of the library.

---

## Publishing a set of sources

If you maintain several machines, keep the sources in a git repository and
check it out to a directory of its own:

```sh
git clone https://example.com/my-app-setup.git /etc/app-setup/local
```

`/etc/app-setup/local` is already on the default `APP_SETUP_PATH`, and it comes
*after* `/etc/app-setup`, so a file there with the same name as one of ours
replaces it. Nothing else is needed — no registration, no index file.

To make them survive a reinstall of the container, clone into `/data` instead
and link it:

```sh
git clone https://example.com/my-app-setup.git /data/app-setup
ln -s /data/app-setup /etc/app-setup/local
```

Your own tab, if you have enough of them, is one header line in any one source:

```sh
# category: mycompany
# category.name: Our software
# category.name.zh: 我们的软件
```

---

## Rules of the road

Things that are easy to get wrong, and unpleasant when they are.

**Be honest in `disk` and `memory`.** They are what somebody on a 512MB
container uses to decide. An optimistic number turns into an install that dies
two minutes in.

**Never delete data on uninstall.** Remove the program; leave the databases,
the uploads and the repositories, and say plainly in the output where they are
and how to delete them if that is really what they want. Every shipped source
does this, and it is the one convention worth enforcing.

**Assume it will be run twice.** The second install must not fail because the
first one left a user, a directory or a config behind.

**Do not `exit` outside a verb.** The file is executed for every action, and a
bare `exit` in the body runs at parse time for all of them.

**Ask before piping the internet into a shell.** If your install needs a
vendor's script, say so in `summary` and again in `do_help`. Somebody choosing
an entry in a menu has not agreed to run arbitrary code from a third party; tell
them that is what this one does.

**`do_status` is on a timer.** Eight seconds, and it runs for every entry on
screen. Keep it to reading a file or checking a process.

**Declare your temporary variables `local`.** Shell functions share one global
namespace, so a helper that loops over `_p` and a recipe that is holding
something in `_p` are the same variable. This is not hypothetical — it is how
`/usr/bin/php` on Alpine came to be a symlink to a file that does not exist:

```sh
do_install() {
	_p="$(alpine_php)"                     # php84
	pkg_install_optional "$_p-intl" "$_p-ctype"
	ln -sf "/usr/bin/$_p" /usr/bin/php     # ...links to php84-ctype
}
```

Everything in `common.sh` now declares its temporaries, so the library will not
do this to you. Do the same in anything of yours that calls anything else:

```sh
do_install() {
	local _p _svc
	…
}
```

And when the thing you are creating is a symlink, check it afterwards. `have
php` answers *yes* for a dangling one, so the breakage surfaces somewhere else
entirely — in that case as four unrelated entries claiming PHP was missing.

**POSIX sh only.** No `[[ ]]`, no arrays, no `local -a`, no `${x^^}`, no
`$'...'`. `busybox ash -n yourfile.sh` is the check that catches it.

---

Everything here is also true of the sources that shipped in the image — they
use no private interface. `/etc/app-setup/nginx.sh` is 140 lines and is the
best reference there is; `lnmp.sh` is the one to read for composing several
into one entry.
