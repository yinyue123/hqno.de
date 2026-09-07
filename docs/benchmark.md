# Benchmarking your node

One reinstall, half an hour, and you get a URL: a page that says what this
machine actually is — CPU, disk, memory, the IP's standing, speeds to a dozen
places, and the nine routes back into China — in Chinese, English, French and
German, switched by whoever is reading it.

It is meant to be pasted where you are selling the node, or sent to somebody
asking "what am I buying".

**Nothing on the page is checked by anybody.** It says what the machine
measured and what you typed. That is worth knowing in both directions: it is
why the page is honest about your machine, and why a page somebody else sends
you is worth exactly as much as your trust in them.

## 1. The address

Everything on this page starts from one image reference:

```
ghcr.io/yinyue123/hqnode:benchmark
```

Reinstall a container onto it and the benchmark runs on its own, once, on the
first boot after the install. There is nothing to install, nothing to start,
and no second command.

::: warning Your container needs a `/data` disk
Everything the run keeps lives there, including the one key that lets you edit
the page afterwards, and `/data` is the only thing a reinstall does not erase.
Without it you get one page and can never change it. The container page tells
you whether you have one — and the button you are about to press says
**keep /data** on it.
:::

## 2. Reinstall it, on the container page

**Reinstall…** on your container's page opens a dialog with three tabs. The
one that takes an address is *an image of my own*:

<FigScreen :tabs="['An image of my own', 'The market', 'An archive on this host']" :lines="[
  [{ t: 'Wipes /. /data is a separate disk and is kept.', tone: 'mute' }],
  ['Image reference', { f: 'ghcr.io/yinyue123/hqnode:benchmark', fw: 300 }],
  [{ t: 'What it downloads counts against this container’s traffic — 42 MB.', tone: 'mute', face: 'small' }],
  ['Type bench to confirm', { f: 'bench' }],
  { align: 'right', cols: [{ b: 'Cancel' }, { b: 'Reinstall, keep /data' }] },
]" />

Paste the address, type the container's own name into the box under it, press
**Reinstall, keep /data**. About a minute later the container is back, on the
benchmark image, and the run has already started.

Two things have to be true for that tab to exist at all: the machine's policy
has to allow images its tenants bring, and the container has to have a disk of
its own. The dialog says which one is missing, and both are your host's to
change.

### Or from a shell inside the container

`reinstall` is a command your *current* system carries, so this is the same
operation typed from whatever the container is right now:

```
reinstall ref ghcr.io/yinyue123/hqnode:benchmark
```

Your SSH session drops while the container is rebuilt. That is the reinstall
happening, not a fault.

::: tip Why a reinstall and not "install a program"
The image **is** the program. It carries every tool the checks need, already
built, so a run downloads test payloads and nothing else — no package manager
in the middle of a disk benchmark skewing the disk benchmark.
:::

::: warning Coming back is the button, not a command
This image does not carry `reinstall` — it is a benchmark, not a
general-purpose box. Once you are on it, going back to Debian or Alpine is the
**Reinstall** button on the container page, on the *market* tab. Nothing is
stuck; you just cannot do it from inside any more.
:::

## 3. Wait, and watch if you like

**Twenty to fifty minutes**, and it moves **a few GB** of speedtest traffic,
which comes out of your container's allowance. On a small plan check the
allowance first.

The log ends with your URL, and `nq-shop show` prints it at any time
afterwards:

```
tail -f /data/nodequality/first-boot.log
```
```
published as https://shop.hqno.de/r/xxxxxxxxxx
```

The run happens **once**. It is keyed on whether a page has been published, so
a run that dies halfway is retried at the next boot, and a run that worked is
never repeated — restarting the container does not re-benchmark it.

## 4. Everything else is one screen

SSH into the container and you do not get a shell. You get this:

```
  Node report

  page     https://shop.hqno.de/r/7Qn4kR2vXb
  langs    ?lang=zh · en · fr · de
  state    published

  What you can change
   1  Node name   Tokyo · direct routes
   2  Tags        AS64512 · Tokyo · direct
   3  Plans       Starter · 1C / 1 GB $6 · Standard · 2C / 2 GB $11
   4  Contacts    @yourname · sales@example.com
   5  Hours       Daily 10:00-22:00 UTC · 5 minutes after payment
   6  Notes       the wording the page ships with
   7  Language    en

  What to do
   p  save and publish  (in the background; closing SSH is fine)
   b  run the benchmark again  (20-50 minutes, a few GB)
   s  a shell
   q  quit
```

Type a number and it asks you one question at a time, showing what is there
now. **Type a new value to change it; press Enter to keep what is there.**
That rule is the whole thing, and it is the same at every prompt.

Three details it handles so you do not have to:

| | |
|---|---|
| **Prices are numbers** | Type `49`. The yearly saving is worked out from the two numbers and printed in all four languages on its own |
| **Four languages off one answer** | It asks for Chinese and English. French and German fall back to English, then to Chinese |
| **`@` is a lookup** | A Telegram handle typed `@yourname` is stored escaped, so it keeps its sign instead of being read as a key |

Every answer is written to disk the moment you give it. There is no save step
to forget, and closing the terminal loses nothing you have already typed.

The file behind it is still `/data/nodequality/shop.json`, still yours, and
still editable by hand over SFTP if you would rather — but nothing on this
page asks you to.

## 5. Publishing, which does not need you to wait

`p` rebuilds the page and publishes it **in the background**. The benchmark
does not re-run, and the URL does not change: the key in `/data` is what
proves the page is yours to replace, so the second publish lands on the first
one rather than making a second page.

Publishing costs a few seconds to a minute of one core — the endpoint charges
proof of work instead of asking you for an account. It runs detached from your
SSH session, so **you can close the terminal**. Log back in and the screen
says where it got to:

```
  状态   发布中 · 算工作量 75%（已试 3145728 次）· 12 秒前开始
```

and when it is done, the URL is at the top of the screen again.

::: tip Then turn the container off
Nothing needs to keep running once the page is published — the page lives on
the endpoint, not on your machine. Stop the container and it costs you no CPU
and no memory. Start it again whenever you want to change a price: `/data`
still holds your answers, your measurements and the key to the page.
:::

::: warning The key is the page
`/data/nodequality/credentials.json` is the only thing that can ever replace
your page. Lose it and the page stays up, readable, forever, and you cannot
touch it. It survives reinstalls because it is in `/data`; it does not survive
deleting the container. Back it up if the page matters.
:::

## 6. If you would rather type commands

The wizard is a front end to one program, and every step of it is a command
of its own. `s` from the menu gives you a shell, and so does
`hqnode exec <name> sh`:

| | |
|---|---|
| `nq-shop status` | what a publish started earlier is doing |
| `nq-shop bench` | the CPU numbers again, about two minutes |
| `nq-shop route` | the nine backhaul routes again |
| `nq-shop collect --skip net` | everything except the gigabytes |
| `nq-shop build` | rebuild the page from what is on disk |
| `nq-shop publish` | push it, same URL |

::: warning `hqnode exec` gives up after 60 seconds
If you are driving this from the **host** rather than from a shell inside the
container, `hqnode exec` returns `context deadline exceeded` after a minute
and blames the agent. The command keeps running inside the container; you just
lose its output. Start long ones detached, or use the wizard, which starts
everything long in the background on purpose.
:::

## 7. What the page will not tell you

- **No score on it can be verified by the reader.** The CPU tiles come from
  sysbench, 7-Zip, OpenSSL and stress-ng, none of which publishes a result
  anywhere. They compare honestly against another page made this way and
  against nothing else.
- **The multi-thread score is the optimistic one.** It uses the cgroup
  ceiling, which on hqnode is your *burst* limit rather than the cores you
  are sold.
- **Free text stays in the language it was collected in.** An AS name or a
  city name does not translate; fixed vocabularies — yes/no, blocked/open,
  risk levels — do.
- **The route sections need the routes to be traceable.** They are, from a
  container, but only over UDP; if your host filters that, those two sections
  come back empty rather than wrong.

## Where next

- [Using your container](using-your-container.md) — what reinstall does, and
  why `/data` is the part that survives it
- [Public ports](ports.md) — if you want the page on your own domain instead
