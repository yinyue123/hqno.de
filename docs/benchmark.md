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
ghcr.io/yinyue123/nodequality
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
  ['Image reference', { f: 'ghcr.io/yinyue123/nodequality', fw: 300 }],
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
reinstall ref ghcr.io/yinyue123/nodequality
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

## 4. The half of the page that is yours

<FigRows :head="['on the page', 'comes from']" :rows="[
  [{ t: 'CPU, memory, disk, IP standing, speeds, routes', tone: 'mute' }, { t: 'the machine — measured, not editable', tone: 'strong' }],
  [{ t: 'what the node is called', tone: 'mute' }, { t: 'you', tone: 'accent' }],
  [{ t: 'the plans, and what each one costs', tone: 'mute' }, { t: 'you', tone: 'accent' }],
  [{ t: 'how somebody reaches you to buy it', tone: 'mute' }, { t: 'you', tone: 'accent' }],
]" />

Your half is one file, and it is already there after the first run:

```
/data/nodequality/shop.json
```

Edit it with anything — `vi` in the container, or over SFTP from your own
machine. It arrives filled in with a worked example, so the shape below is
already in front of you; the parts worth knowing are these.

**A plan, and its prices.** Prices are **numbers**, not strings. Write `45`,
not `"45"` — the yearly saving is worked out from them, so `450` against
12×45 prints "save 17%" in every language on its own.

```json
{
  "shop": {
    "title": { "zh": "洛杉矶 CN2 GIA", "en": "Los Angeles CN2 GIA" },
    "plans": [
      {
        "name": { "zh": "标准 · 1C / 1 GB", "en": "Standard · 1C / 1 GB" },
        "currency": "¥", "monthly": 45, "yearly": 450,
        "rows": [
          { "k": "CPU", "v": "1 vCPU" },
          { "k": "@k_ram", "v": "1 GB" },
          { "k": "@k_traffic", "v": "100 GB" }
        ]
      }
    ],
    "contacts": [ { "k": "@k_tg", "v": "@@yourname" } ]
  }
}
```

**Four languages, and you write one.** The page renders in zh · en · fr · de
and the reader picks. Three kinds of text behave differently, and the
difference is the whole trick:

| In your file | Renders as | Use it for |
|---|---|---|
| `"@k_ram"` | 内存 / Memory / Mémoire / Speicher | anything with a standard name |
| `{"zh": "…", "en": "…"}` | your own wording, per language | the things no table can know |
| `"1 GB"` | `1 GB`, everywhere | numbers, units, AS names |

So a row is written once, and a French reader sees **Mémoire — 1 GB** without
you writing a word of French. For the parts only you can name — what the
machine is called, what a plan is called — give the object form; a missing
language falls back to English, then to Chinese, then to whatever is there.

Two details that bite:

- **`@` starts a lookup.** A Telegram handle written `"@yourname"` is read as
  a key and comes out as `yourname`, sign and all gone. Write `"@@yourname"` —
  a doubled `@` is a literal one.
- **A key that does not exist** prints as itself without the `@`, which is how
  you spot a typo: if the page says `k_rma`, you meant `@k_ram`.

## 5. Publishing your edits, on the same URL

Two commands, both quick, **neither of which re-runs the benchmark**:

```
nq-shop build      # fold your file back into the page
nq-shop publish    # replace the published page
```

The URL does not change. The key in `/data` is what proves the page is yours
to replace, so the second publish lands on the first one rather than making a
second page.

<FigRows :head="['what you did', 'what it costs', 'the URL']" :rows="[
  [{ t: 'changed a price or a name', tone: 'mute' }, { t: 'seconds — build, publish', tone: 'ok' }, { t: 'the same', tone: 'ok' }],
  [{ t: 'want the machine measured again', tone: 'mute' }, { t: 'nq-shop run, 20–50 min and a few GB', tone: 'mute' }, { t: 'the same', tone: 'ok' }],
  [{ t: 'lost /data/nodequality/credentials.json', tone: 'mute' }, { t: 'nothing can replace that page', tone: 'bad' }, { t: 'a new one, next time', tone: 'bad' }],
]" />

::: warning The key is the page
`/data/nodequality/credentials.json` is the only thing that can ever replace
your page. Lose it and the page stays up, readable, forever, and you cannot
touch it. It survives reinstalls because it is in `/data`; it does not survive
deleting the container. Back it up if the page matters.
:::

Send the language you want with a query, or leave it and let the browser
decide:

```
https://shop.hqno.de/r/xxxxxxxxxx?lang=en
```

## 6. Running one part again

Every step is a command of its own, and `--skip` takes a comma list of `ip`,
`hw`, `net`, `bench`, `route`:

| | |
|---|---|
| `nq-shop bench` | the CPU numbers, about two minutes |
| `nq-shop route` | the nine backhaul routes |
| `nq-shop collect --skip net` | everything except the gigabytes |
| `nq-shop build` | rebuild the page from what is on disk |
| `nq-shop publish` | push it, same URL |

::: warning `hqnode exec` gives up after 60 seconds
If you are driving this from the **host** rather than from a shell inside the
container, `hqnode exec` returns `context deadline exceeded` after a minute
and blames the agent. The command keeps running inside the container; you just
lose its output. Start long ones detached, or run them from a shell in the
container, where there is no such limit.
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
