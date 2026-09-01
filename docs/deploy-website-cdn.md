# Deploying a website and CDN

You sell to people in China and to people outside it. The problem is that no
single machine is good at both: the ones that are fast into China are small and
expensive, and the ones that are big and cheap crawl into China at exactly the
hours people shop.

**So rent two, and put the small fast one in front.** That is the whole idea,
and the rest of this page is why it works and how to build it.

<FigRows :arrow="0" :rows="[
  [{ t: '§1–§5', tone: 'accent' }, 'why one line costs ten times what another does'],
  [{ t: '§6–§8', tone: 'accent' }, 'the shape of the answer, and what it actually saves'],
  [{ t: '§9–§11', tone: 'accent' }, 'what to type, what goes wrong, when not to bother'],
]" />

If you only ever sell to one side of the world, skip to §11 — you probably do
not need any of this.

---

## 1. Two roads, the same distance

Two machines sit in the same building in Hong Kong. Same hardware, same cable
out of the rack. A visitor in Shanghai loads a page from each. One takes 300
milliseconds and drops a tenth of what it was sent; the other takes 40 and drops
nothing.

Nothing about the distance changed. What changed is **which road the traffic was
sold the right to use**.

<svg class="fig" viewBox="0 0 660 206" role="img" aria-label="An ordinary line goes through a public sorting centre that queues in the evening; an optimised line has a lane reserved for it and takes the same time all day">
  <defs><marker id="cd1" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="14" y="18">the same parcel, the same distance</text>
  <text class="s" x="14" y="56">ordinary</text>
  <rect class="box" x="86" y="36" width="104" height="40" rx="4"/>
  <text class="c" x="138" y="61">your machine</text>
  <path class="ln" d="M190,56 H240" marker-end="url(#cd1)"/>
  <rect class="box" x="248" y="36" width="176" height="40" rx="4"/>
  <text class="c" x="336" y="53">the public depot</text>
  <text class="s c" x="336" y="69">queued from 8pm to midnight</text>
  <path class="ln" d="M424,56 H474" marker-end="url(#cd1)"/>
  <rect class="box" x="482" y="36" width="104" height="40" rx="4"/>
  <text class="c" x="534" y="61">your visitor</text>
  <text class="s" x="86" y="96">slower when it matters, and some of it never arrives</text>
  <path class="rule" d="M14,116 H646"/>
  <text class="s" x="14" y="156">optimised</text>
  <rect class="box" x="86" y="136" width="104" height="40" rx="4"/>
  <text class="c" x="138" y="161">your machine</text>
  <path class="lnA" d="M190,156 H474" marker-end="url(#cd1)"/>
  <text class="s a c" x="332" y="149">a lane somebody paid to reserve</text>
  <rect class="box" x="482" y="136" width="104" height="40" rx="4"/>
  <text class="c" x="534" y="161">your visitor</text>
  <text class="s" x="86" y="196">the same at 9pm as at 9am</text>
</svg>

A **three-network optimised** line — 三网优化 — is the second one, for all three
of China's carriers at once. §2 says what the three are and why "all three"
needs saying.

---

## 2. The names you will see in a listing

China has three carriers, and your visitor is on one of them. Which one is not
your choice and not theirs — it is whoever wired their building.

<FigRows :arrow="0" :head="['carrier', 'roughly how many people']" :rows="[
  [{ t: 'China Telecom · 电信', tone: 'strong' }, 'the largest share of home broadband'],
  [{ t: 'China Unicom · 联通', tone: 'strong' }, 'strong in the north'],
  [{ t: 'China Mobile · 移动', tone: 'strong' }, 'most phones, and a lot of home broadband now'],
]" />

**Each carrier sells an ordinary road and a premium one, and they are separate
purchases.** A machine can be excellent for Telecom and terrible for Mobile.
That is the single most common way somebody pays for a "good line" and still has
half their customers complaining.

| What the listing says | Whose | In plain words |
|---|---|---|
| **163**, AS4134 | Telecom, ordinary | The public motorway. Fine at 3pm, a car park at 9pm. |
| **CN2 GT**, AS4809 | Telecom, middle | A better motorway. Still queues at the same hours. |
| **CN2 GIA**, AS4809 | Telecom, premium | The reserved lane. This is the one people mean. |
| **169**, AS4837 | Unicom, ordinary | The public motorway again. |
| **AS9929**, CUII | Unicom, premium | The reserved lane. |
| **CMI**, AS58453 | Mobile, ordinary | Public, and often the most roundabout of the three. |
| **CMIN2** | Mobile, premium | The reserved lane. |
| **三网优化**, three-network optimised | all three | One reserved lane bought from each. |

Two words worth knowing, because sellers use them and they are not the same
thing:

- **去程** — visitor to your machine. Small. Requests and clicks.
- **回程** — your machine back to the visitor. Everything else: pages, images,
  video. This is the leg that decides whether your site feels fast, and it is
  the leg a seller means when they advertise CN2 GIA.

A listing that names a premium network for only one carrier is telling you the
truth about that carrier and saying nothing about the other two. Ask.

---

## 3. How big the difference is

Typical, not a promise — measure your own before you commit. Hong Kong to
mainland China:

| | ordinary line | three-network optimised |
|---|---|---|
| **Daytime** | 60–90 ms, little loss | 30–50 ms, no loss |
| **8pm to midnight** | 150–300 ms, 5–30% loss | 30–60 ms, no loss |
| **How it feels** | images half-load, checkout hangs, some people simply cannot pay | the same all day |

<svg class="fig" viewBox="0 0 660 206" role="img" aria-label="A day of latency: the ordinary line is flat until early evening and then spikes between 8pm and midnight, while the optimised line stays flat all day">
  <text class="t" x="14" y="20">one day, one page, two machines in the same rack</text>
  <text class="s" x="14" y="52">higher is slower</text>
  <path class="rule" d="M541,40 V172"/>
  <text class="s c" x="563" y="36">8pm – midnight</text>
  <path class="rule" d="M96,172 H638"/>
  <path class="ln" d="M96,141 L185,143 L274,139 L363,137 L452,130 L519,86 L541,60 L563,44 L586,56 L608,98 L630,138"/>
  <path class="lnA" d="M96,155 L274,154 L452,156 L630,154"/>
  <text class="s" x="14" y="139">ordinary</text>
  <text class="s a" x="14" y="159">optimised</text>
  <text class="s c" x="96" y="190">midnight</text>
  <text class="s c" x="229" y="190">6am</text>
  <text class="s c" x="363" y="190">noon</text>
  <text class="s c" x="496" y="190">6pm</text>
  <text class="s c" x="630" y="190">midnight</text>
</svg>

**The dropped packets hurt more than the delay does.** A slow page is annoying;
a page missing one file in ten is broken. And the loss is not spread evenly —
it arrives in the four hours when people are at home with a phone in their hand,
which for a shop is most of the day's money.

### Testing it honestly

Two rules, and they are both about *when*:

- **Test between 9pm and 11pm, China time.** A daytime test tells you nothing.
  Every line on the market looks good at 3pm.
- **Test from the visitor's side**, on a real Chinese connection, on each of the
  three carriers if you can borrow the phones. Downloading a big file from your
  machine and watching the speed is the whole test.

From inside the container, `app-setup install nettools` gets you `mtr`,
`traceroute` and `dig`. Be aware that a traceroute run from a container often
shows gaps in the middle — the replies from intermediate hops do not always make
it back through the container's networking — so treat it as a hint, not the
answer. The number that matters is the one measured in China.

---

## 4. Why the fast one is fast

The ocean is not the problem. Both lines cross it on the same cables, in about
the same few milliseconds, and neither is ever short of capacity out there.

<svg class="fig" viewBox="0 0 660 196" role="img" aria-label="The path from your machine to a visitor: the undersea cable is shared and uncongested, the queue is at the gateway into China, and the last leg is the carrier's own network">
  <defs><marker id="cd2" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="14" y="18">where the queue actually is</text>
  <rect class="box" x="14" y="38" width="112" height="44" rx="4"/>
  <text class="c" x="70" y="65">your machine</text>
  <path class="ln" d="M126,60 H164" marker-end="url(#cd2)"/>
  <rect class="box" x="172" y="38" width="150" height="44" rx="4"/>
  <text class="c" x="247" y="56">undersea cable</text>
  <text class="s c" x="247" y="73">never the problem</text>
  <path class="ln" d="M322,60 H360" marker-end="url(#cd2)"/>
  <rect class="box" x="368" y="38" width="126" height="44" rx="4"/>
  <text class="c" x="431" y="56">the gateway</text>
  <text class="s c" x="431" y="73">into China</text>
  <path class="ln" d="M494,60 H532" marker-end="url(#cd2)"/>
  <rect class="box" x="540" y="38" width="106" height="44" rx="4"/>
  <text class="c" x="593" y="65">your visitor</text>
  <path class="lnA" d="M431,112 V90" marker-end="url(#cd2)"/>
  <text class="t a c" x="431" y="130">everything queues here</text>
  <text class="s c" x="431" y="150">an ordinary line waits its turn</text>
  <text class="s c" x="431" y="166">a premium line has a share held for it</text>
  <text class="s" x="14" y="190">two thousand kilometres of it is fine. It is the last two hundred metres that is sold by the megabit.</text>
</svg>

**The queue is at the last door.** Everything entering mainland China from
outside crosses a gateway. Its capacity is fixed and the three carriers own it.
An ordinary line queues for whatever is spare; a premium line has a share held
for it however long the queue is.

### And the road may not be straight

A cheap Hong Kong line can send your data to the United States and bring it
back to Shanghai. Not a small detour — about twenty times the distance.

<svg class="fig" viewBox="0 0 660 272" role="img" aria-label="A sketch map: a direct route from Hong Kong to Shanghai is 1,200 km and about 40 ms, while an ordinary line may loop across the Pacific to Los Angeles and back, some 22,000 km and about 300 ms">
  <defs><marker id="cd4" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker>
  <marker id="cd5" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="f-dot" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="14" y="20">the same two points, two ways round</text>
  <path class="box" d="M44,74 C52,50 92,38 138,42 C182,46 224,60 240,84 C252,102 250,128 236,148 C220,170 186,182 150,178 C108,173 66,152 50,124 C40,106 38,88 44,74 Z"/>
  <path class="box" d="M470,86 C486,62 530,52 574,58 C614,64 640,86 636,114 C632,144 606,172 570,180 C534,188 494,176 476,152 C462,132 460,102 470,86 Z"/>
  <text class="t c" x="140" y="70">mainland China</text>
  <text class="t c" x="556" y="90">United States</text>
  <circle class="f-dot" cx="234" cy="94" r="4"/>
  <text class="s" x="228" y="98" text-anchor="end">Shanghai · your visitor</text>
  <circle class="f-dot" cx="212" cy="166" r="4"/>
  <text class="s" x="204" y="170" text-anchor="end">Hong Kong · your machine</text>
  <circle class="f-dot" cx="486" cy="130" r="4"/>
  <text class="s" x="498" y="134">Los Angeles</text>
  <path class="lnA" d="M216,160 C238,142 240,116 232,100" marker-end="url(#cd5)"/>
  <text class="s a" x="252" y="124">direct · 1,200 km</text>
  <text class="s a" x="252" y="140">about 40 ms</text>
  <path class="ln" d="M220,172 C300,236 400,222 480,138" marker-end="url(#cd4)"/>
  <path class="ln" d="M484,122 C400,30 292,32 242,80" marker-end="url(#cd4)"/>
  <text class="s c" x="352" y="36">and the answer comes back the same way</text>
  <text class="s c" x="352" y="232">an ordinary line may go via the US — some 22,000 km, about 300 ms</text>
  <text class="s" x="14" y="264">Nobody sends you a bill for the detour. You pay it in waiting, on every click.</text>
</svg>

It happens because the seller bought the cheapest transit available, and what
that transit does next is not theirs to decide.

So a premium line is three things at once: **a share of the gateway, a route
that does not wander, and the return leg.** That last one is worth naming
separately. Getting traffic *out* of your machine is easy and nobody charges
much for it. Getting it back *in* to a Chinese visitor along a good path is a
product a carrier prices on its own — and it is the expensive half.

---

## 5. Why it costs what it costs

Rough shape, in 2026, and prices move — check the day you buy:

| For the same ¥100 a month | you get |
|---|---|
| **an ordinary line** | a 1 Gbps port, unmetered, shared with a few dozen neighbours |
| **three-network optimised** | 20–50 Mbps, or a few hundred GB of quota |

**Ten to fifty times the price per megabit.** Everything else on this page is a
consequence of that one number.

Where does the difference go? Follow the same ¥100 into each:

<svg class="fig" viewBox="0 0 660 216" role="img" aria-label="Two bars splitting the same hundred yuan a month: on an ordinary high-spec box most of it is the machine and little is the line; on a three-network optimised box it is the other way round">
  <text class="t" x="14" y="20">the same ¥100 a month, and where it actually goes</text>
  <text class="t" x="14" y="60">ordinary,</text>
  <text class="t" x="14" y="76">high spec</text>
  <rect class="box" x="150" y="44" width="388" height="36" rx="4"/>
  <text class="c" x="344" y="67">the machine · 8 cores, 16 GB</text>
  <rect class="mine" x="538" y="44" width="68" height="36" rx="4"/>
  <text class="s a c" x="572" y="67">line</text>
  <text class="s" x="150" y="100">machine ¥85 · line ¥15 — the bandwidth is oversold, so it is nearly free</text>
  <text class="t" x="14" y="146">three-network</text>
  <text class="t" x="14" y="162">optimised</text>
  <rect class="box" x="150" y="130" width="68" height="36" rx="4"/>
  <text class="s c" x="184" y="153">machine</text>
  <rect class="mine" x="218" y="130" width="388" height="36" rx="4"/>
  <text class="a c" x="412" y="153">the line · 30 Mbps, or 500 GB of quota</text>
  <text class="s" x="150" y="186">machine ¥15 · line ¥85 — the same small box in an ordinary rack costs ¥15</text>
  <text class="s" x="14" y="210">The box is cheap. The road is not — so buy only as much road as you will use.</text>
</svg>

**The machine itself is nearly worthless.** A 1-core, 1 GB box in an ordinary
rack is about ¥15 a month. Move that identical box into a three-network
optimised rack and it is ¥100. The extra ¥85 buys no cores, no memory and no
disk. It is all road.

And the road is priced that way for four reasons, which compound:

<FigRows :arrow="0" :head="['what makes it expensive', 'the everyday version']" :rows="[
  [{ t: 'it is not oversold', tone: 'strong' }, 'a buffet seat versus a table booked in your name'],
  [{ t: 'the gateway is finite', tone: 'strong' }, 'three companies own the only bridges, and nobody is building more'],
  [{ t: 'the return leg is a separate product', tone: 'strong' }, 'the trip out is cheap; the trip back is what you actually pay for'],
  [{ t: 'three carriers, three purchases', tone: 'strong' }, 'one reserved lane is not three reserved lanes'],
]" />

The first one is most of it. An ordinary "1 Gbps unmetered" port is sold to
thirty people on the assumption they will not all want it at once — which is
true at 3pm and false at 9pm, and that is precisely why the ordinary line
collapses at the hour it does. A premium megabit is sold once. When it is gone
it is gone, and the price is what a scarce thing costs.

The fourth is why **三网优化** costs more than a line advertised as "CN2 GIA".
It is three separate premium arrangements on one machine, and you are paying for
all three.

Which means the honest summary is: **you are not buying a fast server, you are
renting road.** So rent as little of it as you can — which is §6.

---

## 6. So do not buy one machine

Look at what your website actually consumes, next to what the expensive line
gives you:

| | three-network optimised | ordinary, high spec |
|---|---|---|
| **What it is good at** | getting bytes into China at 9pm | cores, memory, disk, and traffic that costs almost nothing |
| **What it is bad at** | everything is small and everything is metered | the four hours a day your Chinese customers are shopping |
| **What ¥100 a month buys** | 1 core, 1 GB, 500 GB of traffic | 8 cores, 16 GB, 500 GB of disk, terabytes of traffic |

Your database, your PHP, your image resizing, your build — none of that cares
what the network is like. It wants cores and memory, and on a premium-line
machine cores and memory carry the road's price whether you use the road or
not (§5's bars).

So put the site on the cheap machine and buy **only the road** on the expensive
one.

---

## 7. The plan

Two containers, in the same city, from the same host or from two:

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="Visitors in China reach a small optimised-line node that caches and forwards to a big ordinary-line origin nearby; visitors elsewhere go straight to the origin">
  <defs><marker id="cd3" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <rect class="box" x="14" y="32" width="112" height="44" rx="4"/>
  <text class="c" x="70" y="59">visitors in China</text>
  <path class="lnA" d="M126,54 H172" marker-end="url(#cd3)"/>
  <rect class="mine" x="180" y="20" width="176" height="68" rx="5"/>
  <text class="t c" x="268" y="42">the front node</text>
  <text class="s c" x="268" y="60">optimised line · 1 core, 1 GB</text>
  <text class="s c" x="268" y="78">nginx, and nothing else</text>
  <path class="ln" d="M356,54 H424" marker-end="url(#cd3)"/>
  <text class="s c" x="392" y="46">3 ms</text>
  <rect class="box" x="432" y="20" width="214" height="68" rx="5"/>
  <text class="t c" x="539" y="42">the origin</text>
  <text class="s c" x="539" y="60">ordinary line · 8 cores, 16 GB</text>
  <text class="s c" x="539" y="78">your actual website</text>
  <rect class="box" x="14" y="140" width="112" height="44" rx="4"/>
  <text class="c" x="70" y="167">everyone else</text>
  <path class="ln" d="M126,162 H539 V92" marker-end="url(#cd3)"/>
  <text class="s c" x="320" y="154">straight there — no detour through China's front door</text>
</svg>

- **Visitors in China** land on the front node. Anything it has already seen it
  answers itself, over the expensive line, in 40 milliseconds. Anything it has
  not, it fetches from the origin — which is 3 milliseconds away, because you
  deliberately rented both in the same city.
- **Everyone else** goes straight to the origin and never touches the front node
  at all. A customer in Berlin should not be routed through Hong Kong's
  optimised line to reach a server that is right there.

That last split is what makes this work for a cross-border shop rather than just
for a Chinese one. It needs one thing from your DNS provider: **the ability to
answer differently depending on where the question came from.** DNSPod, Alibaba
Cloud DNS, Huawei Cloud DNS and most Chinese providers call this 分线路解析 and
give you a 境内 / 境外 split for free.

| Name | Line | Points at |
|---|---|---|
| `www.example.com` | China (境内) | the front node's machine |
| `www.example.com` | Default (境外/默认) | the origin machine |
| `origin.example.com` | Default | the origin machine |

**No split-line DNS?** Point `www` at the front node for everybody. Foreign
visitors pay one extra hop of a few milliseconds — usually nothing, occasionally
enough to matter. Get it working this way first and add the split later.

`origin.example.com` is the third row and it is not optional: it is how the
front node reaches the origin, and how you check the origin when the front node
is what broke.

---

## 8. What the cache saves, and what it does not

A cache is a shelf by the door. The first person to ask for a file makes
somebody walk to the back to fetch it; everyone after that gets it off the
shelf.

<FigRows :arrow="0" :head="['who asks', 'what happens']" :rows="[
  ['the first visitor wants logo.png', 'the front node has never seen it — fetches it from the origin, keeps a copy, hands it over'],
  ['the next ten thousand', { t: 'straight off the shelf. The origin is never told.', tone: 'accent' }],
  ['somebody adds to their cart', { t: 'never cached, never shelved — always the origin', tone: 'strong' }],
]" />

Now the honest accounting, because one row of this surprises people:

| | does caching save it? |
|---|---|
| **What the front node sends to visitors** | **No.** Every byte a visitor asks for leaves that node, cached or not. This is the number that has to fit in its quota. |
| **What the front node pulls from the origin** | **Yes, nearly all of it.** And since inbound traffic counts against your quota too, this is a real saving, not a bookkeeping one. |
| **The origin's CPU, memory and disk** | **Yes, a lot.** A cached page is a PHP request that never ran. |
| **How long the visitor waits** | **Yes.** A hit skips the round trip to the origin entirely. |

Put numbers on it. Say your site sends 300 GB a month to visitors:

| | front node's metered traffic |
|---|---|
| No cache at all | 300 GB out + 300 GB pulled from the origin = **600 GB** |
| 80% of it cacheable and cached | 300 GB out + 60 GB pulled = **360 GB** |

Both directions count on an hqnode container ([using your
container](using-your-container.md) §3), so the cache roughly **halves** what
you spend on the expensive machine. That is on top of the speed.

**Size the front node by traffic, not by cores.** One core and a gigabyte of
memory serves an enormous amount of static content. The quota is what runs out.

---

## 9. Building it

The example: `www.example.com` is the shop, the front node's machine is
`203.0.113.10`, the origin's is `203.0.113.20`.

### Step 1 — get the two containers

Ask your host for one on a machine with an optimised line and one on a big
ordinary machine, **in the same city**. "Same region" is not close enough — Hong
Kong to Tokyo is 50 ms, and you would be adding it to every uncached request.

Tell your host what you are doing; picking two machines that are physically near
each other is easy for them and impossible for you to check from outside.

### Step 2 — put the website on the origin

Nothing special about this half. It is an ordinary deployment on an ordinary
machine: [Deploying an LNMP site](deploy-lnmp.md), [Deploying a Node.js
app](deploy-nodejs.md), or whatever you already have.

### Step 3 — give the origin a name

In the origin container:

```sh
app-setup domain add origin.example.com 80
```

That gives it a certificate the machine manages for you, which is what you want
here — there is nothing secret about it and one less thing to renew. Add the DNS
record for `origin.example.com` first, or the certificate cannot be issued: an A
record at `203.0.113.20`.

Check it before going any further:

```sh
curl -I https://origin.example.com/
```

If that is not a `200`, stop here. Nothing downstream can be right.

### Step 4 — nginx on the front node

In the front node's container:

```sh
app-setup install nginx
```

Then write one file — `/etc/nginx/http.d/cdn.conf` on Alpine,
`/etc/nginx/conf.d/cdn.conf` on Debian or Ubuntu:

```nginx
# Where cached files live, and how much to keep. /data survives a
# reinstall; the cache need not, but the disk quota is shared anyway.
proxy_cache_path /data/cache levels=1:2 keys_zone=site:20m
                 max_size=4g inactive=7d use_temp_path=off;

# A request carrying any of these cookies belongs to one person and must
# never be served to another. Add your own cart and session cookies here.
map $http_cookie $private {
    default                        0;
    "~*wordpress_logged_in"        1;
    "~*woocommerce_items_in_cart"  1;
    "~*wp_woocommerce_session"     1;
    "~*comment_author"             1;
}

upstream origin {
    server 203.0.113.20:443;   # the origin machine, by address
    keepalive 32;              # reuse connections, no re-handshake
}

server {
    # The machine already terminated HTTPS on 443.
    listen 80;
    server_name www.example.com example.com;

    # Everything below this line is inherited by all three locations.
    proxy_http_version 1.1;
    proxy_set_header Connection "";

    # Ask the origin machine for this name so its front door knows whose
    # site this is — even though the request carries the visitor's name.
    proxy_ssl_server_name on;
    proxy_ssl_name origin.example.com;

    proxy_set_header Host              $host;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;

    proxy_cache site;
    # Ten people, one file, one fetch.
    proxy_cache_lock on;
    # Origin having a bad day: serve the shelf copy, not an error.
    proxy_cache_use_stale error timeout updating
                          http_500 http_502 http_503 http_504;
    add_header X-Cache $upstream_cache_status always;

    # Images, styles and scripts: keep them a month. Video is left out
    # on purpose — it is the priciest thing to send from the costly box.
    location ~* \.(jpe?g|png|gif|webp|avif|svg|ico|css|js|woff2?)$ {
        proxy_pass https://origin;
        proxy_cache_valid 200 30d;
        proxy_ignore_headers Set-Cookie Cache-Control Expires;
    }

    # Admin, login, cart, checkout: not one byte on the shelf.
    location ~* ^/(wp-admin|wp-login|cart|checkout|my-account) {
        proxy_pass https://origin;
        proxy_cache off;
    }

    # Everything else: ten minutes; signed-in visitors skip the shelf.
    location / {
        proxy_pass https://origin;
        proxy_cache_valid 200 301 302 10m;
        proxy_cache_valid 404 1m;
        proxy_cache_bypass $private;
        proxy_no_cache     $private;
    }
}
```

```sh
mkdir -p /data/cache
nginx -t          # says what is wrong before anything goes live
rc-service nginx restart      # Alpine
systemctl restart nginx       # Debian, Ubuntu, the rest
```

The package's own default site can stay where it is. It has no `server_name`,
so it only answers requests that match nothing else.

### Step 5 — give the front node the real name

In the front node's container:

```sh
app-setup domain add www.example.com 80
app-setup domain add example.com 80
```

The machine terminates HTTPS on 443, renews the certificate itself, and hands
nginx plain HTTP on 80 — which is why the config above listens on 80 and there
is no certificate anywhere in it. It also fills in `X-Forwarded-For` before
nginx sees the request, so the address your origin logs is the visitor's, not
Hong Kong's.

Prefer to hold your own certificate? `app-setup domain add www.example.com 8443
self-hosted` and terminate in nginx instead. [Running a proxy or
VPN](proxy.md) §7 has the trade-off in full.

### Step 6 — point DNS

The three records from §7. Give it a few minutes.

### Step 7 — check that the shelf is being used

```sh
curl -sI https://www.example.com/logo.png | grep -i x-cache
curl -sI https://www.example.com/logo.png | grep -i x-cache
# first says  X-Cache: MISS
# second says X-Cache: HIT
```

`MISS` then `HIT` is the whole thing working. If the second one is still `MISS`,
§10 has the four usual reasons.

**To throw the cache away** after you change something:

```sh
rm -rf /data/cache/*
nginx -s reload
```

---

## 10. What goes wrong

| What you see | What it usually is |
|---|---|
| **Always `MISS`, never `HIT`** | The origin is sending `Set-Cookie` or `Cache-Control: no-cache` on everything. WordPress does this when a plugin starts a session on every page. Either fix it at the origin or add `proxy_ignore_headers Set-Cookie;` to the `location /` block — and read the next row before you do. |
| **One customer sees another's cart** | You cached something private. This is the failure that costs you a customer rather than a second. Every path in §9's second `location` block, plus the cookie `map`, exists to stop it. Test it: log in, add something to the cart, then open the same page in a private window. |
| **Changed an image, visitors see the old one** | It is on the shelf for thirty days, as instructed. Clear the cache, or better, change the filename — `logo.v2.png` — and never think about it again. |
| **Front node's traffic quota gone in a week** | Expected, if you sized it by cores. Every visitor byte goes through it. §8 has the arithmetic. |
| **Everything redirects in a loop** | The origin is redirecting to its own name. Keep `proxy_set_header Host $host;` exactly as written — the origin must see the visitor's name, not `origin.example.com`. |
| **Origin logs show one IP for the entire internet** | The origin is not reading `X-Forwarded-For`. That is a setting in whatever runs there, not here. |
| **`502` from the front node** | It cannot reach the origin. Check `curl -I https://origin.example.com/` from inside the front node's container. |
| **Google indexed `origin.example.com`** | It is a real, reachable copy of your shop, so of course it did. Have the origin return `X-Robots-Tag: noindex` when the requested name is `origin.example.com`. |

**One trap worth stating on its own: do not put both containers on the same
machine.** Beyond it defeating the entire purpose, it does not even work as
written — a container that connects to its own machine's public address reaches
*itself*, not its neighbour, so the front node would proxy to itself and loop.
Two machines, two addresses.

---

## 11. When you should not do this

This is real work and it adds a thing that can break. Skip it when:

<FigRows :arrow="0" :head="['if this is you', 'do this instead']" :rows="[
  ['all your customers are outside China', 'one ordinary machine. You were never paying the premium.'],
  ['all your customers are inside China', 'a machine inside China, with the domain filed (备案). Cheaper and faster than anything here.'],
  ['a small site, a few GB a month', 'one optimised-line container, running the site directly. Two machines is not worth the wiring.'],
  ['you need it fast in ten countries', 'a commercial CDN. This design has one front node; they have two hundred.'],
]" />

Both machines in this design sit outside mainland China, which is why nothing
here mentions filing. Move the origin inside and the domain needs an ICP filing
before it may answer on 80 or 443 at all — that is a change of plan, not a
change of configuration.

And if you are unsure whether the premium line is worth it: buy the small one
for a month, put a copy of one page on it, and compare at 9pm. It is the
cheapest experiment on this page.

---

## Where next

- [Quick start](quick-start.md) — a domain, DNS and HTTPS, step by step with a
  picture per step. Do this first if you have not.
- [Deploying an LNMP site](deploy-lnmp.md) · [Deploying a Node.js
  app](deploy-nodejs.md) — what goes on the origin.
- [Using your container](using-your-container.md) §3 — how the traffic quota is
  counted, and what happens at 100%.
- [Public ports](ports.md) — for the case where the thing behind the front node
  is not a website.
- [Running a proxy or VPN](proxy.md) §7 — the two certificate modes, in full.
