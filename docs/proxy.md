# Running a proxy or VPN

This page answers one question: when a connection arrives at a machine holding
twenty containers behind a single address, how does it find **yours**?

Everything else — what you run, how you configure it, who you give it to — is
inside your box and is yours. This is about the doorway, because the doorway is
the part the machine decides and the part that surprises people.

---

## 1. What can run here at all

Read this first. It rules out half the software in this category before you
spend an afternoon on it.

A container here gets no `CAP_NET_ADMIN`, and there is no `/dev/net/tun` inside
it. So:

- Anything that works by **creating a network interface of its own** and taking
  over routing — the kernel-side kind — does not run here. Not slowly, not
  partially: it cannot create the device, so it does not start.
- Anything that works as **an ordinary program holding an ordinary socket** —
  accept a connection, do something with the bytes, open an outbound connection
  — runs like any other program, because that is all it is.

The reason is billing, not suspicion. With `CAP_NET_ADMIN` a tenant renames the
`tap0` device the network is metered on, stands a fresh zero-counter device in
its place under the same name, and the traffic meter reads nothing for the rest
of the month. That decision is written down, and its cost was stated plainly
when it was made: no nftables, no tun, no kernel-side VPN in a container.

The rest of this page is about the userspace kind, which is the kind that runs.

---

## 2. Two shapes, and the one difference that decides everything

<FigRows :arrow="0" :head="['what it looks like on the wire', 'how it gets in']" :rows="[
  [{ t: 'a TLS connection like any other', tone: 'strong' }, { t: 'a domain — shares 443 with every other name on the machine' }],
  [{ t: 'a protocol of its own', tone: 'strong' }, { t: 'a public port — one number, which your host opens' }],
]" />

One sentence underneath both rows: **the machine can only hand a connection to
the right container if the connection says, in the clear, which one it is for.**
A TLS handshake says so. A protocol somebody designed themselves does not.

That is the whole of it. The two sections that follow are just that sentence
looked at from each side.

---

## 3. How a name gets sorted out

The first thing a TLS client sends is a ClientHello, and inside it, **in the
clear**, is the name of the server it is asking for.

It has to be in the clear. The server has not presented a certificate yet, and
it cannot choose which certificate to present without knowing which name is
wanted. Nothing is encrypted at that point in the conversation — encryption is
what the rest of the handshake is *for*.

The machine reads that one field and nothing else. It looks the name up in the
table of domains, finds the container that claimed it, and from that moment it
is a pipe: bytes from the client to the container, bytes from the container to
the client, until one end hangs up.

Three things follow, and together they are why this way costs nothing:

- **A thousand names share one 443.** The number is not doing the sorting — the
  name is. So a name costs the machine nothing, there is nothing to ration, and
  you add one yourself without asking anybody.
- **The machine holds no key.** It never decrypted anything, so there was never
  a moment when it could have read anything. The certificate for the name lives
  in your container. §6 is about keeping it that way.
- **The name has to resolve to the machine.** Sorting by name only helps if the
  packets arrive: an A record at your domain provider, pointing at the machine's
  address. The panel shows you which address.

Port 80 is the same idea one layer up: the name is in the HTTP `Host` header
instead of the handshake, and it is looked up in the same table.

---

## 4. Why a protocol of your own costs a number

A connection arrives. The machine has to decide which container it belongs to,
and it has to decide *before* it knows what any of the bytes mean.

On 443 there is something to read. In a protocol its author designed, the first
bytes are whatever that author decided they are — the machine does not know that
protocol, cannot know it, and guessing is not a design. So exactly one piece of
information is left, and the connection has already given it: **which number it
knocked on.**

That is what a public port is. One number on the machine's own address, wired in
advance to one container, and the number is the only thing being matched.

It is also why you cannot open one yourself. Names cost nothing, so nobody
rations names. A number is a single thing on a shared machine — two tenants who
both want `31000` is a disagreement somebody has to settle — so opening one is
your host's to do. [Public ports](ports.md) is that whole story, from both
sides, including what to tell your host when you ask.

---

## 5. UDP always costs a number

UDP has no handshake, no connection, and no first message the machine is
entitled to look inside. There is no field to read, so there is nothing to sort
by, and no equivalent of §3 exists. A UDP service needs a number of its own
whatever it carries.

One consequence worth knowing before you debug: the panel's **Test** button
cannot help you here. A UDP port with nothing behind it and a UDP port working
perfectly look identical from outside — silence is not an answer, so the panel
declines to pretend it is one. Test it with the client that is actually going to
use it.

---

## 6. On the domain path, stay on `sni`

A name's HTTPS setting has two modes, and only one of them is what you want
here.

| mode | what the machine does |
|---|---|
| **`sni`** (the default) | Reads the name out of the handshake, then splices bytes. Holds no certificate and no key for your name, and decrypts nothing. |
| **`managed`** | Holds a certificate for the name, terminates TLS itself, and forwards **plaintext** into your container. |

`managed` is the right answer for a website — the machine gets the certificate
and renews it and you never think about it again. For anything else, read the
second row once more: the machine decrypts. Leave the mode on `sni`, and getting
and renewing the certificate is yours to do inside the container, which is also
where the private key stays.

---

## 7. Two things that cost people an afternoon

- **Bind `0.0.0.0`, not `127.0.0.1`.** Both paths above reach your service from
  outside the container's own loopback. A service listening on `127.0.0.1`
  answers you when you test it over SSH and answers nobody else, and every
  symptom of that looks exactly like a closed port.
- **All of it is metered.** Traffic carried for somebody else is traffic. Both
  directions count against the quota like everything else, and this is the one
  kind of service where the number climbs while you are not watching. Read it
  with `dashboard` in the container, or on the container page. At 100% the
  container is **suspended** — stopped, not deleted — and it comes back when the
  window rolls over.

---

## 8. What the machine can see

This is not a promise about intentions. It is the shape of the path, which you
can check:

- On 443 in `sni` mode the machine holds no key for your name and never
  completes a handshake with your client. There is no point in the path where
  your traffic exists in the clear, so there is nothing to inspect.
- On a public port it is a number wired to a number. Nothing in that path parses
  what goes through it.
- The traffic meter counts bytes in each direction. It has no idea what they
  were, and no other component is looking either.

hqnode is a virtualization tool. What it does is cut one machine into pieces,
keep the pieces apart, and count. It does not inspect what you carry, and on
both paths above it could not.

Two honest limits on that, because a page that left them out would be selling
something:

- This describes the software. The person who owns the machine owns the machine,
  with root on it. Trust your host, or [run the machine
  yourself](running-a-machine.md).
- Nothing here hides *that* traffic exists, or how much, or which numbers and
  names are configured. Metering is the point of the product.

---

## 9. The law is yours to know

This page says how a machine moves bytes. What you run on top of it, who uses
it, and where it lands are yours — and so is knowing which rules apply to them.

Rules on this class of service vary a great deal between countries, they apply
to where you are as well as to where the machine is, and they change. If you
need one, look it up properly for your own situation. Nothing on this page is
legal advice, and nobody here has checked it on your behalf.

---

## Where next

- [Public ports](ports.md) — §4 and §5 in full, and what to tell your host.
- [Quick start](quick-start.md), step 6 — adding a domain and pointing DNS at
  the machine, the part §3 assumes you have done.
- [Panel REST API](api.md) — domains, routes and ports from a script.
- [Running a machine of your own](running-a-machine.md) — the other side of §8.
