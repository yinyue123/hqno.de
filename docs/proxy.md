# Running a proxy or VPN

Twenty containers on one machine, one address between them. This page is about
how a connection from outside finds **yours**: §2 and §3 are what to actually
type, §4 to §6 are why those are the only two ways.

Everything else — what you run, how you configure it, who you give it to — is
inside your box and is yours.

(One class of thing does not start here at all: the kind that creates a network
interface of its own. Not many people use it, but if you were going to, jump to
§9 first and save an afternoon.)

---

## 1. Which of the two is yours

<FigRows :arrow="0" :head="['what it looks like on the wire', 'how it gets in']" :rows="[
  [{ t: 'a TLS connection like any other', tone: 'strong' }, { t: 'a domain — shares 443 with every name on the machine' }],
  [{ t: 'a protocol of its own', tone: 'strong' }, { t: 'a public port — one number, opened by your host' }],
  [{ t: 'UDP, whatever it carries', tone: 'strong' }, { t: 'a public port — same' }],
]" />

One sentence under all three: **the machine can only hand a connection to the
right container if the connection says, in the clear, which one it is for.** A
TLS handshake says so; a protocol somebody designed themselves does not.

The first you add yourself. The other two you ask your host for. Here is each.

---

## 2. Adding a domain (the 443 way)

**Point DNS at the machine first.** An A record at your domain provider, aimed
at the machine's address. It is on the container page in the panel, and in the
container from `app-setup dashboard net`. Skip this and nothing below works.

Then any one of three doors — they all do the same thing.

### In the container, one command

```sh
# You terminate TLS yourself, inside the container. The machine only splices,
# and the key never leaves the box. This is the one this page is about;
# 8443 is the TLS port your service listens on.
app-setup domain add example.com 8443 self-hosted

# Leave "self-hosted" out and the default is a certificate the machine gets
# for you — which means the machine decrypts. 8080 is a plain-HTTP port.
app-setup domain add example.com 8080

# Self-hosted TLS, and port 80 also forwards to the container's 8080 in plain HTTP
app-setup domain add example.com 8443 self-hosted 8080

app-setup domain ls                 # which names you have
app-setup domain del example.com    # stop answering for one
```

**This command's default is the opposite one, which is worth remembering:**
without `self-hosted` you get a machine-issued certificate and a machine that
decrypts. For this page's purpose you have to type `self-hosted` yourself. (The
panel and the API default the other way, to passthrough — §6 is why that
difference matters.)

A wildcard is `*.example.com`, first label only.

### In the panel

Container page → the **Domains** card → **Add domain**, and type the name.
Then click the name's row to open its settings:

<FigScreen title="Domains" :lines="[
  { cols: [{ f: 'example.com' }, { b: 'Add domain' }] },
  [{ t: 'example.com', tone: 'strong' }],
  [{ k: 'Enable HTTPS' }],
  { cols: [{ t: 'Your certificate · SNI passthrough', tone: 'ok' }, { f: '8443', note: 'Backend HTTPS port' }] },
  { cols: [{ t: 'Our certificate · issued for you', tone: 'mute' }, { f: '8080', note: 'Forwards to HTTP port' }] },
  [{ k: 'Enable HTTP' }],
]" />

The two modes are one pair of radio buttons. Pick **Your certificate · SNI
passthrough** and the port you give it is your container's own TLS port. A name
added here starts on that one.

### From the API

```sh
# claim the name
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/domains" \
  -H 'content-type: application/json' -d '{"domain":"example.com"}'

# say how it is served. Leaving mode out gives you sni.
curl -sS -b jar.txt -X PUT "$PANEL/me/containers/$CID/routes/example.com" \
  -H 'content-type: application/json' \
  -d '{"http":{"enabled":false,"port":80},
       "https":{"enabled":true,"mode":"sni","port":8443}}'
```

Every field is in the [Panel REST API](api.md).

---

## 3. Getting a public port (the number way)

**You cannot open one**, and it is not a permission that was withheld: `POST`
and `DELETE` were never registered under `/me/containers/{cid}/ports`, so a
write there is a 404 from the router. §5 is why.

### Your side: ask, then check

Tell your host two things and that is the whole request:

- which port your service listens on **inside the container** (`7777`, `51820`,
  whatever it is)
- **TCP or UDP**

They pick the outside number. You do not need to name it — unless something out
in the world already insists on one (a client config you have handed out, a DNS
SRV record), in which case say so.

Once it is open, read it on the container page's **Ports** card, or in the
container:

```sh
app-setup dashboard ports
```

The card has two halves. Yours is under **From the internet**: the address on
the left is what you give people, and the `:3000` on the right is the port
something has to be listening on inside your box.

### Their side: one button

Container page → **Ports** → **Open a port**:

<FigScreen title="Open a port" :lines="[
  { cols: [{ t: 'Container port', face: 'small', tone: 'mute' }, { t: 'Public port', face: 'small', tone: 'mute' }, { t: 'Protocol', face: 'small', tone: 'mute' }] },
  { cols: [{ f: '7777' }, { f: 'auto', note: 'blank = pick one' }, { f: 'tcp' }] },
  { cols: [{ b: 'Save' }, { b: 'Save and apply' }, { b: 'Cancel' }] },
]" />

Or one call:

```sh
curl -sS -b jar.txt -X POST "$PANEL/machines/$MID/containers/$CID/ports" \
  -H 'content-type: application/json' -d '{"proto":"tcp","container":7777}'
```

**The two save buttons differ, and the difference lands on somebody else.**
**Save and apply** restarts the container's networking now: about half a
second, and in that half second connections on the container's **other** ports
drop — including the SSH session its holder has open. **Save** records the
mapping, interrupts nothing, and it starts working at the container's next
restart. On the API these are `apply` set to `now` and `next_start`.

One more thing the panel cannot show you: **a number opened on the machine is
not a number opened in your cloud provider's firewall.** Open the whole pool
once — `30000–32767` unless it was changed, TCP and UDP — and it never comes up
again. Leave it shut and the panel looks entirely correct, the card says live,
and nothing outside can connect.

[Public ports](ports.md) is the full story.

---

## 4. How a name gets sorted out

The first thing a TLS client sends has a short **plaintext** stretch at the
front, and in it is the name of the server it is asking for.

<svg class="fig" viewBox="0 0 660 168" role="img" aria-label="One TLS connection: a short plaintext stretch at the front carries the server name, everything after it is encrypted, and the machine reads only the front">
  <defs><marker id="px1" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="20" y="22">one TLS connection, left to right</text>
  <rect class="mine" x="20" y="40" width="180" height="40" rx="4"/>
  <rect class="box" x="208" y="40" width="432" height="40" rx="4"/>
  <text class="m a c" x="110" y="65">example.com</text>
  <text class="c" x="424" y="65">every byte after this is encrypted</text>
  <text class="s c" x="110" y="100">in the clear — this much only</text>
  <text class="s c" x="424" y="100">the machine copies it; no key, no decryption</text>
  <path class="lnA" d="M110,140 V108" marker-end="url(#px1)"/>
  <text class="t c" x="110" y="160">the machine reads only this</text>
</svg>

**Why it has to be in the clear:** the server has not presented a certificate
yet, and it cannot choose which one to present without knowing the name being
asked for. So the name goes first and the encryption comes after.

The machine reads that one field. It looks the name up in the table of domains,
finds the container that claimed it, and from then on does one thing only: copy
bytes one way, copy bytes the other way, until an end hangs up.

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="Three domains arrive at the machine's single port 443, the machine looks each name up, and sends each to a different container">
  <defs><marker id="px2" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="20" y="20">a thousand names, one 443</text>
  <rect class="box" x="20" y="38" width="170" height="34" rx="4"/>
  <rect class="mine" x="20" y="86" width="170" height="34" rx="4"/>
  <rect class="box" x="20" y="134" width="170" height="34" rx="4"/>
  <text class="m c" x="105" y="60">a.example.com</text>
  <text class="m a c" x="105" y="108">b.example.com</text>
  <text class="m c" x="105" y="156">c.example.com</text>
  <path class="ln" d="M190,55 C222,55 222,103 246,103" marker-end="url(#px2)"/>
  <path class="lnA" d="M190,103 H246" marker-end="url(#px2)"/>
  <path class="ln" d="M190,151 C222,151 222,103 246,103" marker-end="url(#px2)"/>
  <rect class="box" x="254" y="60" width="152" height="86" rx="5"/>
  <text class="t c" x="330" y="88">the machine</text>
  <text class="s c" x="330" y="110">one address, one :443</text>
  <text class="s c" x="330" y="130">name → container</text>
  <path class="ln" d="M406,103 C434,103 434,55 462,55" marker-end="url(#px2)"/>
  <path class="lnA" d="M406,103 H462" marker-end="url(#px2)"/>
  <path class="ln" d="M406,103 C434,103 434,151 462,151" marker-end="url(#px2)"/>
  <rect class="box" x="470" y="38" width="170" height="34" rx="4"/>
  <rect class="mine" x="470" y="86" width="170" height="34" rx="4"/>
  <rect class="box" x="470" y="134" width="170" height="34" rx="4"/>
  <text class="c" x="555" y="60">another container</text>
  <text class="c" x="555" y="108">your container</text>
  <text class="c" x="555" y="156">another container</text>
  <text class="s" x="20" y="192">the name does the sorting, not the number — which is why you add a domain yourself</text>
</svg>

Three things follow:

- **A thousand names share one 443.** A name costs the machine nothing, which is
  why §2 was yours to do without asking.
- **The machine holds no key.** It never decrypted anything, so there was never
  a moment it could have read anything. The certificate lives in your container
  — as long as the mode is right. §6.
- **The name has to resolve to the machine.** That is the A record §2 opened
  with.

Port 80 is the same idea one layer up: the name is in the HTTP `Host` header
instead, looked up in the same table.

---

## 5. Why a protocol of your own costs a number

A connection arrives. The machine has to decide which container it belongs to,
and it has to decide **before** it knows what any of the bytes mean.

On 443 there is something to read. In a protocol its author designed, the first
bytes are whatever that author decided — the machine does not know that
protocol, cannot know it, and guessing is not a design.

So one piece of information is left, and the connection already gave it:
**which number it knocked on.**

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="On the left, a domain: the machine can read the name and look it up. On the right, a protocol of its own: the machine cannot read the contents and knows only which number the connection knocked on">
  <defs><marker id="px3" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t c" x="165" y="20">on a domain</text>
  <text class="t c" x="495" y="20">own protocol, or UDP</text>
  <path class="rule" d="M330,30 V186"/>
  <rect class="mine" x="30" y="40" width="86" height="34" rx="4"/>
  <rect class="box" x="120" y="40" width="180" height="34" rx="4"/>
  <text class="s c" x="73" y="61">the name</text>
  <text class="s c" x="210" y="61">encrypted</text>
  <text class="c" x="165" y="98">readable → looked up</text>
  <path class="lnA" d="M165,108 V128" marker-end="url(#px3)"/>
  <rect class="mine" x="85" y="134" width="160" height="34" rx="4"/>
  <text class="c" x="165" y="156">your container</text>
  <text class="s c" x="165" y="188">no number used up</text>
  <rect class="box" x="360" y="40" width="270" height="34" rx="4"/>
  <text class="s c" x="495" y="61">the machine cannot read these bytes</text>
  <text class="c" x="495" y="98">all it knows is the number</text>
  <path class="lnA" d="M495,108 V128" marker-end="url(#px3)"/>
  <text class="m a" x="512" y="124">:31000</text>
  <rect class="mine" x="415" y="134" width="160" height="34" rx="4"/>
  <text class="c" x="495" y="156">your container</text>
  <text class="s c" x="495" y="188">one number, one container — ask your host</text>
</svg>

That is what a public port is: one number on the machine's address, wired in
advance to one container.

And that is why the button in §3 is your host's. Names cost nothing, so nobody
rations them; a number is a single thing on a shared machine, and two tenants
who both want `31000` is a disagreement somebody has to settle.

**UDP goes further**: no handshake, no connection, and no first message the
machine is entitled to look inside. No field to read means nothing to sort by,
so UDP always costs a number whatever it carries. The panel's **Test** button
cannot help you there either — a UDP port with nothing behind it and one working
perfectly look identical from outside. Test it with the client that will use it.

---

## 6. Get the mode wrong and the rest was pointless

This is the difference between the two modes in §2, and the one choice on this
page that still looks fine when it is wrong.

<svg class="fig" viewBox="0 0 660 212" role="img" aria-label="With SNI passthrough the traffic is encrypted from client to container and the machine only splices bytes; with a managed certificate the machine holds the key, decrypts, and forwards plaintext into the container">
  <defs><marker id="px4" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="20" y="20">Your certificate · SNI passthrough</text>
  <rect class="box" x="20" y="32" width="104" height="40" rx="4"/>
  <text class="c" x="72" y="57">client</text>
  <path class="ln" d="M124,52 H196" marker-end="url(#px4)"/>
  <text class="s c" x="160" y="44">encrypted</text>
  <rect class="box" x="204" y="32" width="176" height="40" rx="4"/>
  <text class="c" x="292" y="57">machine · splices</text>
  <path class="ln" d="M380,52 H452" marker-end="url(#px4)"/>
  <text class="s c" x="416" y="44">encrypted</text>
  <rect class="mine" x="460" y="32" width="180" height="40" rx="4"/>
  <text class="c" x="550" y="57">your container · your key</text>
  <text class="s" x="20" y="94">encrypted the whole way. No key on the machine, so no moment it could read.</text>
  <text class="t" x="20" y="134">Our certificate · issued for you</text>
  <rect class="box" x="20" y="146" width="104" height="40" rx="4"/>
  <text class="c" x="72" y="171">client</text>
  <path class="ln" d="M124,166 H196" marker-end="url(#px4)"/>
  <text class="s c" x="160" y="158">encrypted</text>
  <rect class="box" x="204" y="146" width="176" height="40" rx="4"/>
  <text class="c" x="292" y="171">machine · decrypts</text>
  <path class="lnA" d="M380,166 H452" marker-end="url(#px4)"/>
  <text class="s a c" x="416" y="158">plaintext</text>
  <rect class="box" x="460" y="146" width="180" height="40" rx="4"/>
  <text class="c" x="550" y="171">your container</text>
  <text class="s" x="20" y="208">the machine gets the certificate — at the cost of decrypting first. Right for a website, not for this.</text>
</svg>

| where you added it | what you get without saying otherwise |
|---|---|
| `app-setup domain add <name> <port>` | **issued for you** — the machine decrypts. Add `self-hosted` for passthrough |
| the panel's **Domains** card | **Your certificate · SNI passthrough** |
| API `PUT /routes/{domain}` with no `https.mode` | **`sni`** |

The three doors do not agree, and the CLI is the odd one out. Whichever you
used, open the domain's row in the panel afterwards and look at which of the two
radio buttons is lit — that is what is actually in effect.

On passthrough, getting and renewing the certificate is yours to do inside the
container, and the private key stays there.

---

## 7. Two things that cost people an afternoon

- **Bind `0.0.0.0`, not `127.0.0.1`.** Both paths above reach your service from
  outside the container's own loopback. A service on `127.0.0.1` answers you
  when you test it over SSH and answers nobody else, and every symptom looks
  exactly like a closed port.
- **All of it is metered.** Traffic carried for somebody else is traffic. Both
  directions count against the quota, and this is the one kind of service where
  the number climbs while you are not watching. `app-setup dashboard net` in the
  container, or the container page. At 100% the container is **suspended** —
  stopped, not deleted — and it returns when the window rolls over.

---

## 8. What the machine can see

Not a promise about intentions. The shape of the path, which you can check:

- On 443 with passthrough the machine holds no key for your name and never
  completes a handshake with your client. There is no point in the path where
  your traffic exists in the clear, so there is nothing to inspect.
- A public port is a number wired to a number. Nothing in that path parses what
  goes through it.
- The traffic meter counts bytes in each direction. It has no idea what they
  were, and nothing else is looking either.

hqnode is a virtualization tool. It cuts one machine into pieces, keeps the
pieces apart, and counts. It does not inspect what you carry, and on both paths
above it could not.

Two honest limits, because a page that left them out would be selling something:

- This describes the software. The person who owns the machine owns the machine,
  with root on it. Trust your host, or [run the machine
  yourself](running-a-machine.md).
- Nothing here hides *that* traffic exists, or how much, or which numbers and
  names are configured. Metering is the point of the product.

---

## 9. One class of thing does not run here

Everything above is the userspace kind: an ordinary program holding an ordinary
socket — accept a connection, do something with the bytes, open an outbound
connection. That is what nearly everyone uses, and it runs like any other
program.

What does not run is the other kind: the one that **creates a network interface
of its own** and takes over routing. A container gets no `CAP_NET_ADMIN` and
there is no `/dev/net/tun` inside it, so this is not slow or partial — the
device cannot be created, so it does not start.

The reason is billing, not suspicion. With `CAP_NET_ADMIN` a tenant renames the
`tap0` device the meter follows, stands a fresh zero-counter device in its place
under the same name, and the traffic meter reads nothing for the rest of the
month. The decision is written down, and its cost was stated when it was made:
no nftables, no tun, no kernel-side VPN in a container.

---

## 10. The law is yours to know

This page says how a machine moves bytes. What you run on top of it, who uses
it, and where it lands are yours — and so is knowing which rules apply.

Rules on this class of service vary a great deal between countries, they apply
to where you are as well as to where the machine is, and they change. If you
need one, look it up properly for your own situation. Nothing here is legal
advice, and nobody has checked it on your behalf.

---

## Where next

- [Public ports](ports.md) — §3 in full, from both sides.
- [Quick start](quick-start.md), step 6 — adding a domain and pointing DNS, with
  a picture per step.
- [Panel REST API](api.md) — every call behind domains, routes and ports.
- [Running a machine of your own](running-a-machine.md) — the other side of §8.
