# Public ports

A **public port** is a number on the machine's own address that goes straight
into one container. Someone types `203.0.113.10:31000` and the connection lands
on port 3000 inside your box — no name, no certificate, no web server involved.
That is what makes it the answer for a game server, a database, a VPN, a proxy,
or anything else that is not a website.

It is also the one thing on the container page that the person holding the
container cannot do for themselves. That is not an oversight, and §2 says why.

If your service *is* a website, you want a domain instead: see
[quick start](quick-start.md), step 6. A name costs the machine nothing, and a
port costs it a number.

---

## 1. Two ways in, and what each costs

<FigRows :arrow="0" :head="['what you add', 'what it uses up']" :rows="[
  [{ t: 'a domain', tone: 'strong' }, { t: 'nothing — every name shares the same 80 and 443' }],
  [{ t: 'a public port', tone: 'strong' }, { t: 'one number on the machine, which one container gets' }],
]" />

A thousand names on one machine cost what one costs: they arrive on the same two
ports and the machine sorts them out by the name in the request. Numbers do not
work that way. `31000` is a single thing, one container can have it, and two
tenants who both want it are a disagreement somebody has to settle.

That difference decides everything below, including who presses the button.

---

## 2. Who opens one

| | |
|---|---|
| **The machine's owner** | opens, edits and closes public ports, on any container on a machine of theirs |
| **You, holding a container** | see every mapping, test whether anything answers, and ask for one |

You add your own **domains** and nobody has to approve them. You do not add your
own **ports**, because a port is a number on somebody else's machine and there
is only one of each. Ask your host; it is one button on their side.

Nothing about this is hidden from you. The card shows every mapping the
container has, live or waiting, and your container's history records each one
that was opened or closed, when, and by whom.

---

## 3. If you hold the container

The **Ports** card is on your container's page, under Domains. It has two
sections and they mean different things:

<FigScreen title="Ports" :lines="[
  [{ t: 'FROM THE INTERNET', face: 'small', tone: 'mute' }],
  { cols: [{ m: 'tcp' }, { m: '203.0.113.10:31000 → :3000' }, { t: 'live', tone: 'ok' }, { b: 'Test' }] },
  { cols: [{ m: 'udp' }, { m: '203.0.113.10:30051 → :51820' }, { t: 'live', tone: 'ok' }] },
  [{ t: 'FROM THIS HOST ONLY', face: 'small', tone: 'mute' }],
  { cols: [{ m: 'tcp' }, { m: ':80' }, { t: 'two.example.com', tone: 'mute' }] },
]" />

- **From the internet** — anyone can reach these. The address on the left is what
  you give people; the `:3000` on the right is what has to be listening inside.
- **From this host only** — how your domains arrive. These are reachable from the
  machine and nowhere else, which is exactly right: the machine's web server
  takes the request from the internet and passes it in here. Nothing to do with
  them unless a name is not working.

**Test** dials the number from the machine and tells you whether anything
answered. It is worth understanding what the two answers mean, because they
point at different people:

| What it says | What it means |
|---|---|
| **live**, and Test says it answers | Working. Somebody on the internet gets what you are serving. |
| **closed** | The machine is holding the number, and nothing inside your container answered on it. That is your side: the service is not running, or it is listening on `127.0.0.1` instead of all addresses. |
| **next start** | The mapping is recorded but not in effect yet. It starts working the next time the container's networking restarts. |
| no Test button | A UDP mapping. There is no handshake to complete, so there is nothing honest to report. |

That `closed` case is the common one, and the fix is usually one line of
configuration: a service bound to `127.0.0.1` inside the container is
unreachable from outside it. Bind to `0.0.0.0` and try again.

**To ask for one**, tell your host the port your service listens on inside the
container — `7777`, `51820`, whatever it is — and whether it is TCP or UDP. They
do not need to know anything else, and the number on the outside is theirs to
pick.

---

## 4. If you run the machine

On the container's page, **Ports → Open a port**:

<FigScreen title="Open a port" :lines="[
  { cols: [{ t: 'Container port', face: 'small', tone: 'mute' }, { t: 'Public port', face: 'small', tone: 'mute' }, { t: 'Protocol', face: 'small', tone: 'mute' }] },
  { cols: [{ f: '7777' }, { f: 'auto', note: 'blank = pick one' }, { f: 'tcp' }] },
  [{ t: '1 port · the host picks a free number in 30000-32767', face: 'small', tone: 'mute' }],
  [{ k: 'Wait for the next restart' }],
  { cols: [{ b: 'Open' }, { b: 'Cancel' }] },
]" />

- **Container port** is what the tenant's service listens on. They tell you this.
- **Public port** blank means the machine picks a free number from its pool
  (`30000–32767` unless you changed it). Type a number instead when something
  outside already expects one — a client configuration your tenant has shipped,
  a DNS SRV record, a monitoring probe.
- **Protocol** — TCP unless the service is UDP. WireGuard, DNS and most game
  servers are UDP.

The line under the boxes previews the whole mapping before anything is sent, and
two mistakes are refused there rather than on the machine: a number below 1024,
and a number inside the machine's private pool (`20000–29999`), which is where
container-side mappings are allocated from and would collide later.

**Opening a port here does not open your provider's firewall.** The machine
binds the number; the security group in front of it still has to allow it in.
Open the whole pool once — `30000–32767`, TCP and UDP — and it is done for every
container you ever sell. Without it, everything on the panel looks right, the
card says `live`, and nothing answers.

**A range** is one row rather than forty. Type `3000-3009` as the container port
and the machine maps ten numbers in one go, `31000→3000` through `31009→3009`.
Both sides are always the same length and the shift is fixed — that is what the
machine can express, so the card enforces it while you type. The default cap is
64 ports in one range.

**Opening or closing restarts that container's networking.** It takes well under
a second, and connections through its *other* ports drop while it happens — the
tenant's SSH session included. The card names them so you know whose. If it is
not urgent, tick **Wait for the next restart**: the mapping is recorded, nothing
is interrupted, and it comes into effect the next time the container restarts.

**Closing** is a button on the row, behind the gear. It gives the number back to
the pool, so the same mapping opened again may not get the same number. Nothing
inside the container changes. A mapping in the lower section — the ones domains
arrive on — cannot be closed while a name still needs it, and the refusal says
which name.

---

## 5. What a public port is not

- **Not for HTTP.** A domain reaches the same service on the standard port,
  costs the machine no number, and gets a certificate. If somebody has to be
  told a port number to visit your site, something has gone wrong.
- **Not a firewall.** Anyone on the internet can reach the number, and hqnode
  does not filter it. Whatever answers inside is what they get, so put the
  authentication in the service.
- **Not a fixed address.** Close a mapping and the number goes back to the pool.
  If something outside depends on a particular number, say so when you ask for
  it, and it will be opened by name rather than picked.

One thing you get here that a domain does not give you: the connection arrives
from the client's own address. Behind the web server a container sees one
address for the whole internet unless the service understands PROXY protocol; on
a public port it sees the real one, in any protocol, with nothing to configure.

---

## 6. When something is wrong

| What you see | What it usually is |
|---|---|
| The chip says **closed** | Nothing is listening inside on that container port, or it is bound to `127.0.0.1` instead of `0.0.0.0`. |
| Test says it answers, but you cannot reach it | The machine's provider firewall is not allowing that number in. The owner opens it in the security group, not in the panel. |
| The row says **next start** and stays that way | It is waiting for the container's networking to restart. Restart the container, or ask the owner to open it again without the deferral. |
| The number was refused as **taken** | Something else on the machine already has it. Let the machine pick instead, or ask for a different one. |
| The number was refused as **in the private range** | It is inside the pool the machine uses for its own internal mappings. Any number outside `20000–29999` and above 1024 is fine. |
| A UDP mapping and no way to check it | There is no check to run — UDP has no handshake. Test from outside with the client that will actually use it. |
| Everything looks right and nothing answers at all | Check the container is running, and that the machine is online: the panel says both on the same page. |

---

## Where next

- [Using your container](using-your-container.md) — the rest of what is yours to
  change.
- [Quick start](quick-start.md) — domains, DNS and HTTPS, in order.
- [Running a proxy or VPN](proxy.md) — which shapes need a port at all, and
  which get in on a name instead.
- [Running a machine of your own](running-a-machine.md) — the other side of this
  page.
