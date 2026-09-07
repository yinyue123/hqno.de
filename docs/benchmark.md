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

## 1. Run it

Your container needs a **`/data` disk**. Everything the run keeps lives there,
including the one key that lets you edit the page afterwards, and `/data` is
the only thing a reinstall does not erase. Without it you get one page and can
never change it. The container page will tell you whether you have one.

From a shell in your container:

```
reinstall ref ghcr.io/yinyue123/nodequality
```

That is the whole instruction. Your SSH session drops while the container is
rebuilt — expected — and about a minute later it is back, and the benchmark
has already started on its own.

::: tip Why a reinstall and not "install a program"
The image *is* the program. It carries every tool the checks need, already
built, so a run downloads test payloads and nothing else — no package manager
in the middle of a disk benchmark skewing the disk benchmark.
:::

## 2. Wait, and watch if you like

**Twenty to fifty minutes**, and it moves **a few GB** of speedtest traffic,
which comes out of your container's allowance. On a small plan check the
allowance first.

```
tail -f /data/nodequality/first-boot.log
```

When it finishes, that log ends with your URL. You can also ask at any time:

```
nq-shop show
```

which prints every file it keeps and, once there is one, the published address:

```
published as https://shop.hqno.de/r/xxxxxxxxxx
```

The run happens **once**. It is keyed on whether a page has been published,
so a run that dies halfway is retried the next time the container boots, and a
run that worked is never repeated — restarting the container will not
re-benchmark it.

## 3. Edit the page

The measurements are the machine's. The prices, the name, the contact details
and the notes are yours, and they live in one file:

```
/data/nodequality/shop.json
```

Edit it with anything — `vi` in the container, or over SFTP — then:

```
nq-shop build      # fold your file back into the page
nq-shop publish    # replace the published page
```

Both are quick. **Neither re-runs the benchmark**, and the URL does not change
— the key in `/data` is what proves the page is yours to replace.

::: warning The key is the page
`/data/nodequality/credentials.json` is the only thing that can ever replace
your page. Lose it and the page stays up, readable, forever, and you cannot
touch it. It survives reinstalls because it is in `/data`; it does not survive
deleting the container. Back it up if the page matters.
:::

### What to put in it

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

Prices are **numbers**, not strings. Write `45`, not `"45"` — the yearly
saving is worked out from them, so `450` against 12×45 prints "save 17%" in
every language on its own.

## 4. Four languages, and which parts follow the reader

The page renders in **zh · en · fr · de**, and the reader picks. Three kinds
of text behave differently, and the difference is the whole trick:

| In your file | Renders as | Use it for |
|---|---|---|
| `"@k_ram"` | 内存 / Memory / Mémoire / Speicher | anything with a standard name |
| `{"zh": "…", "en": "…"}` | your own wording, per language | the things no table can know |
| `"1 GB"` | `1 GB`, everywhere | numbers, units, AS names |

So a row is written once:

```json
{ "k": "@k_ram", "v": "1 GB" }
```

and a French reader sees **Mémoire — 1 GB** without you writing a word of
French.

For the parts only you can name — what the machine is called, what a plan is
called — give the object form. You do not have to fill in all four; a missing
language falls back to English, then to Chinese, then to whatever is there:

```json
"title": { "zh": "洛杉矶 CN2 GIA", "en": "Los Angeles CN2 GIA" }
```

Two details that bite:

- **`@` starts a lookup.** A Telegram handle written `"@yourname"` is read as
  a key and comes out as `yourname`, sign and all gone. Write `"@@yourname"` —
  a doubled `@` is a literal one.
- **A key that does not exist** prints as itself without the `@`, which is how
  you spot a typo: if the page says `k_rma`, you meant `@k_ram`.

Send the language you want with a query, or leave it and let the browser
decide:

```
https://shop.hqno.de/r/xxxxxxxxxx?lang=en
```

## 5. Running only part of it

The steps are separate commands, and any one can be run on its own. The
useful ones after the first full run:

```
nq-shop bench                    # CPU benchmarks only, about two minutes
nq-shop collect --skip ip,hw,net # the nine backhaul routes only
nq-shop build                    # rebuild the page from what is on disk
nq-shop publish                  # push it, same URL
```

`--skip` takes a comma list of `ip`, `hw`, `net`, `bench`, `route`, so
`nq-shop collect --skip net` is the whole thing without the gigabytes.

::: warning `hqnode exec` gives up after 60 seconds
If you are driving this from the **host** rather than from a shell inside the
container, `hqnode exec` returns `context deadline exceeded` after a minute
and blames the agent. The command keeps running inside the container; you
just lose its output. Start long ones detached, or run them from a shell in
the container, where there is no such limit.
:::

## 6. What the page will not tell you

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
