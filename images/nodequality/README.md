# nodequality — the image that turns a machine into a sales page

Runs the three [xykt](https://github.com/xykt) checks that
[NodeQuality](https://github.com/LloydAsp/NodeQuality) wraps, folds their JSON
together with a price list you edit, pays the endpoint's proof of work and
posts the result. What comes back is a URL.

```sh
podman volume create nq                       # the token lives here, not in the container

podman run --rm -v nq:/data ghcr.io/yinyue123/nodequality init
podman run --rm -it -v nq:/data --entrypoint vi \
  ghcr.io/yinyue123/nodequality /data/nodequality/shop.json

podman run --rm -it --cap-add=NET_RAW -v nq:/data ghcr.io/yinyue123/nodequality \
  run --endpoint https://shop.hqno.de
```

Four commands, and only the third is yours to think about: `shop.json` is the
price list, and nothing else in the page is typed by a human.

**`--cap-add=NET_RAW` is not optional**, and it is the one flag whose absence
is silent. Podman drops `CAP_NET_RAW` from its default set, `nexttrace` and
`mtr` both need a raw socket, and a traceroute that cannot open one does not
fail the run — it prints `Unknown -> NoData` nine times and the page comes back
without a route section. Neither does the check exit non-zero. If the route
tabs are missing from a page, this flag is the first thing to check.

The volume is not decoration. `credentials.json` is written into it on the
first publish and it is the only thing that can ever replace the page — a
`--rm` container without a volume publishes once and then owns nothing.

Two notes on editing in place. The image's `vi` is busybox's, which stores CJK
correctly but draws it as dots; if you are rewriting the Chinese titles rather
than the prices, bind a host directory instead (`-v /opt/nq:/data`) and edit
`/opt/nq/nodequality/shop.json` with a real editor. And `--entrypoint bash`
where `vi` is above gives a shell in the same volume, which is the easier way
to poke at `raw/` after a run.

Built by hand from the Actions tab — **nodequality image** — not on every
push. See [`../../shop/`](../../shop) for the endpoint it publishes to.

## Why Alpine, and no chroot

NodeQuality's whole shape is a sandbox: it fetches a Debian rootfs, chroots
into it, runs the checks inside and deletes it, so a benchmark leaves nothing
behind on the machine. That is the right design for a script pasted into a
production box.

A container already is that sandbox. There is no host to keep clean, the
container is deleted when it exits, and the chroot NodeQuality performs needs
`mount -t proc`, which wants `CAP_SYS_ADMIN` — a capability an app container
does not get. So the rootfs is dropped and the distribution is ours to choose.

It was Debian for a while, for one reason. The checks reach for four prebuilt
binaries, and a check that cannot find one does not fail — it fills the
section with `NoData` and carries on:

| tool | what happened to it |
|---|---|
| `nexttrace` | static Go, and always worked on musl. What did not was Net.sh's auto-installer, which serves a glibc build. Baked in from the release asset, so the installer never runs. |
| `speedtest` | Ookla ship an `x86_64-linux-musl` static build. Baked in. |
| `stun` | **cut.** One row, the NAT type, and it measured the wrong machine — see below. |
| `geekbench5` | **cut.** 129 MB, glibc-only, and the only real reason for Debian. |

So the base is Alpine again, the image is roughly half the size, and the two
that were cut are worth being explicit about.

### The NAT row, and why it went

`stun` filled one row. Alpine has no package for it and xykt's own fallback
binary is glibc, so keeping it meant writing a replacement — the interface is
small enough that this would have been easy: Net.sh runs `stun <host>` and
greps one `0x…` bitfield out of stdout.

It was not worth writing, because the row was misleading. The STUN request
leaves a container through pasta and comes back from the *machine's* public
address, so "Open Without NAT" was a fact about the host. What decides whether
a buyer can receive inbound traffic is which ports the host published, and on
a container with three published ports the answer is: those three. Measured on
DMIT — a listener on port 9999 inside the container answers from inside and is
unreachable from the internet.

### The CPU tiles, and what was lost with Geekbench

`nq-bench` runs four benchmarks that are all in Alpine's repositories and all
link against musl:

| | what it leans on |
|---|---|
| `sysbench` | integer and prime work, one thread and then all of them |
| `7z b` | LZMA, which is memory latency and branch prediction more than ALU |
| `openssl speed` | AES-256-GCM at 16 KB. On anything since Westmere this is AES-NI, so read it as "is TLS cheap here", not as a CPU score |
| `stress-ng` | `matrixprod` bogo-ops, floating point and cache |

Four numbers rather than one, so a machine that is fast at exactly one thing
cannot look fast at everything.

**What none of them replace is the URL.** Geekbench uploads every run to
`browser.geekbench.com` — that is how it returns a score at all — and the page
linked it as **原始结果 ↗**. It was the only figure on the whole page a buyer
could check against the machine rather than take on trust. Nothing here has an
equivalent, and the page no longer claims one. Scores from `nq-bench` are
comparable between two pages made by this image and to nothing else.

The thread count comes from `cpu.max`, not `nproc`: on a sold container the
cgroup limit is what the buyer is paying for, and a multi-thread score against
the host's core count would be a score for work that never ran.

### Privacy mode is now on for all four checks

`-p` does two unrelated things: it stops the script posting a copy of its
report to a paste site, *and* it skips Geekbench — the gate is
`mode_privacy -eq 0 && test_cpu_gb5` at the call site, not whether the binary
is installed.

The hardware check used to have `-p` dropped, which bought the Geekbench
scores in exchange for sending a hardware report to Report.Check.Place. There
is nothing left to buy with it, so `-p` is on everywhere and no report leaves
the machine for anywhere but your own endpoint.

`-F` (fast mode) is *not* used, and it is the obvious wrong turn here: it
skips sysbench, the memory test and fio as well, which leaves the performance
section of the page with nothing in it.

## What it runs, and what it costs

| check | flags | what the page gets | roughly |
|---|---|---|---|
| `IP.Check.Place` | `-p -y` | ownership, risk scores, unlock, blacklists | 3–5 min, little traffic |
| `Hardware.Check.Place` | `-p -y` | CPU, memory, disk, sysbench, fio | 3–6 min, no traffic |
| `Net.Check.Place` | `-p -y` | 31-province latency, speedtests, BGP, NAT | 10–20 min, **a few GB** |
| `Net.Check.Place` | `-p -R -n -S 123` | the nine backhaul routes | 3–8 min |

`--skip net` drops the expensive one; `--low-data` runs it in its own reduced
mode. A skipped check does not break the page — the renderer drops a section
with no rows, and its tab with it.

### The two sections this does not fill

**The route matrix and the hop-by-hop detail are not built automatically.**
The page can show both — [`shop/example.page.json`](../../../shop/example.page.json)
does — but nothing here fills them.

The reason is upstream. `Net.sh` writes exactly seven keys to its JSON —
`Head`, `BGP`, `Local`, `Connectivity`, `Delay`, `Speedtest`, `Transfer` — and
the nine backhaul routes are not among them. `-R` prints them to the report and
nowhere else, which is why the file NodeQuality saves as
`backroute_trace.json` is that same envelope with nothing route-shaped in it.
Getting them into the page would mean scraping a coloured, localized table, and
a route name guessed wrong is worse on a sales page than a route section that
is not there.

The report is kept verbatim as `raw/trace.log`. Read it, or paste the routes
into `page.json` by hand — the renderer draws them if they are there.

## Files it keeps

Everything lives under `/data/nodequality`, which on an hqnode container is
the directory a reinstall does not erase.

| | |
|---|---|
| `shop.json` | **yours** — prices, contacts, what the machine is called |
| `raw/*.json` | each check, exactly as it wrote it |
| `page.json` | the two folded together; this is what gets published |
| `credentials.json` | the id, the token and the URL that let you publish over the same page |

Back up `credentials.json`. Losing it does not lose the page — the page stays
up and readable forever. It loses the ability to ever change it.

## Commands

```
nq-shop run          collect, build and publish   (the default)
nq-shop init         write shop.json and stop
nq-shop collect      run the checks into raw/
nq-shop build        fold raw/ and shop.json into page.json
nq-shop publish      pay the proof of work and post page.json
nq-shop show         print the path of everything it keeps
```

`--endpoint URL` · `--skip ip,hw,net,trace` · `--low-data` · `--lang zh|en` ·
`--dry-run` · `--home DIR` · `--timeout SECONDS`

The normal loop is `init`, edit `shop.json`, `run`. After that, editing prices
is `build` and `publish` again — no need to re-benchmark, and the second
publish updates the same URL because the token is on disk.

## The solver

`nq-pow` is a 20 KB static binary that finds a nonce whose SHA-256 starts with
N zero bits. It exists because a shell cannot pay this bill: piping candidates
through `sha256sum` costs a process each and manages a few thousand tries a
second, so the endpoint's default 22 bits would take twenty minutes. This does
millions a second, which puts the same 22 bits inside a second or two and
leaves room for the endpoint to raise it.

```sh
nq-pow <challenge> <bits> [max-seconds]     # prints the nonce
```

## Collection language

Values that come back as a fixed vocabulary — a boolean, `Yes`, `Failed`, a
risk level — are mapped to translation keys, so they follow the reader's
language on the page. Values that are prose or a proper noun stay as the check
wrote them. That is why collection defaults to English: an AS name and a city
read the same everywhere, and English enums are what the mapping is written
against. `--lang zh` collects in Chinese if you would rather the free text be
Chinese.
