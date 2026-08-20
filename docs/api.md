# Panel REST API

Every screen in the panel is a client of this API, and nothing a button does is
out of reach of `curl`. Rebuild a container from a GitHub Actions job, restart
it after a deploy, create one on a machine of yours, read the traffic meter into
a monitor, rotate the shell password on a schedule.

This page is the reference. [Recipes](#recipes) has complete working scripts.

---

## General information

- The base URL is your panel plus `/api/v1`. Signing in at `https://hqno.de`
  makes it **`https://hqno.de/api/v1`**. Every path below is relative to it.
- Every response is `application/json` with `Cache-Control: no-store`.
- Bodies are JSON and need `content-type: application/json`. Nothing takes a
  form encoding, and only `?since=` and `?apply=` are query parameters.
- **All sizes are bytes** — plain integers, never `"2G"`. All timestamps are
  RFC 3339 in UTC (`2026-08-20T06:39:00Z`).
- There are two halves. `/me/…` is what you hold: containers somebody gave you.
  `/machines/…` is what you run: machines of your own and every container on
  them. One account, one cookie, both halves — most people only ever use one.
- Ids: a container id (`cid`) is **12 hex characters**; a machine id (`mid`) is
  `mch_` and 8 hex characters. Both are the last part of that thing's URL in
  the panel.

**Do not call this from inside your own container.** A container holds no panel
credential, deliberately — it has `dashboard`, `app-setup domain` and `passwd`,
which reach the panel through its host and need no secret in the box. See
[From inside the container](#from-inside-the-container).

---

## Authentication

There is no API key. The API takes the same session cookie a browser gets, from
the same login form: sign in once, keep the cookie, send it with everything.

```sh
PANEL=https://hqno.de/api/v1

# Sign in. The credential is the cookie, not anything in the reply body.
curl -sS -c jar.txt "$PANEL/auth/login" \
  -H 'content-type: application/json' \
  -d '{"identifier":"you","password":"…"}'

# Every call after that carries the jar.
curl -sS -b jar.txt "$PANEL/me/containers"
```

| | |
|---|---|
| Cookie | `hq_session` |
| Lifetime | 7 days |
| Flags | `HttpOnly`, `SameSite=Lax`, `Secure` on an HTTPS panel |
| Ends early | `POST /auth/logout`, or signing out in the panel |

**Why a cookie and not a token.** A token is a thing that leaks, and every place
one would have to live is a place this design keeps secrets out of. A session is
short-lived, revocable from one screen, and the same credential the browser
already holds — one way in, one thing to take away. In CI, **store the password
and log in; never store the cookie**. A stored cookie is a seven-day key whose
age you cannot see, and logging in again costs one request.

Each endpoint below is marked **Auth: session** or **Auth: none**.

---

## Response format

Success is the endpoint's own shape. Failure is always these three keys:

```json
{"error":"Sign in first.","code":"unauthorized","message":"Sign in first."}
```

Branch on `code`. `error` and `message` are the same English sentence, carried
twice so a client reading either one gets it. Some refusals add fields — a port
conflict names the number, a certificate refusal adds `next_manual_at` — but
the three are always there.

### HTTP return codes

| Code | Meaning |
|---|---|
| 200 | Done |
| 201 | Created — a container, or a share code |
| 202 | Accepted — a certificate request the host now works on |
| 400 | Your body is wrong. The sentence says how |
| 401 | No cookie, or it expired |
| 402 | Your account's container allowance is used up |
| 403 | Wrong current password, or not your panel to administer |
| 404 | No such thing — **or it is not yours**, see below |
| 409 | It exists, or its state refuses this |
| 429 | Rate limited |
| 502 | The panel could not reach the machine |
| 500 | The panel broke. This one is a bug |

**404 is also "not yours".** Authorization is structural: a container outside
your own list does not resolve at all, so there is no 403 to tell "exists but
forbidden" from "does not exist". Nothing here reports on somebody else's
container, including whether it exists.

**502 is normal and temporary.** The panel is not in the path of anything your
container does; it reaches the machine over a link that can drop. While it is
down, reads still answer from the panel's record and writes come back
`agent_unreachable`. Retry — it is not a failed deploy.

### Error codes

| `code` | Status | When |
|---|---|---|
| `bad_request` | 400 | The body is wrong |
| `unauthorized` | 401 | Not signed in |
| `bad_credentials` | 401 | Login failed. The same answer for a wrong name and a wrong password |
| `limit_reached` | 402 | Account container allowance used up |
| `bad_password` | 403 | `current` did not match |
| `forbidden` | 403 | Admin-only endpoint |
| `not_found` | 404 | Not there, or not yours |
| `no_route` | 404 | No such endpoint — you mistyped a path |
| `exists` | 409 | Username or email already registered |
| `name_taken` | 409 | That machine already has a container by that name |
| `gone` | 409 | The container was deleted |
| `expired` | 409 | Expired: it can be stopped, not started |
| `suspended` | 409 | Suspended by your host |
| `quota_exceeded` | 409 | Over the traffic quota for this window |
| `unavailable` | 409 | Expired or suspended, so networking is not edited |
| `machine_offline` | 409 | The machine has not checked in |
| `too_many_domains` | 409 | At the machine's domain limit |
| `domain_taken` | 409 | Another container on that machine serves the name |
| `not_managed` | 409 | The name is not set to a managed certificate |
| `port_taken`, `port_overlap`, `port_in_pool`, `span_too_large`, `no_free_port` | 409 | The host refused a port. Fields name the number and pool |
| `port_in_use` | 409 | A domain still routes to that port |
| `rate_limited` | 429 | Too many logins or resets from your address |
| `agent_unreachable`, `agent_error` | 502 | The machine is not answering |
| `agent_refused` | 4xx | The host refused, without a code of its own |
| `internal` | 500 | A bug |

### Rate limits

| Endpoints | Limit |
|---|---|
| `/auth/login`, `/auth/signup` | 10 per minute per IP |
| `/auth/forgot`, `/auth/reset` | 5 per 15 minutes per IP |
| Everything else | none |

Over the limit is `429 rate_limited` however right the password is. A job that
logs in once never notices; a twelve-way matrix logging in per step will.

---

## General endpoints

### Test connectivity

```
GET /api/v1/ping
```

**Auth:** none · **Parameters:** none

```sh
curl -sS "$PANEL/ping"
```

```json
{"ok":true}
```

### Panel health

```
GET /api/v1/healthz
```

**Auth:** none · **Parameters:** none

```sh
curl -sS "$PANEL/healthz"
```

```json
{"ok":true,"live_agents":true,"agents_linked":3}
```

| Field | Type | Description |
|---|---|---|
| `live_agents` | bool | Whether this panel really talks to hosts, or simulates them |
| `agents_linked` | int | Machines with a live link right now |

### Panel configuration

```
GET /api/v1/config
```

**Auth:** none · **Parameters:** none

What an agent should be running, so a machine page can offer an upgrade.

```sh
curl -sS "$PANEL/config"
```

```json
{"agent_version":"0.1.0.g6a739b2b0867","agent_downloads":true}
```

### Image catalog

```
GET /api/v1/catalog
```

**Auth:** session · **Parameters:** none

The systems on offer. `id` is what `image_id` takes when creating or rebuilding.

```sh
curl -sS -b jar.txt "$PANEL/catalog"
```

```json
{"images":[{
  "id":"debian-12","name":"Debian 12","ref":"ghcr.io/hqnode/debian:12",
  "digest":"sha256:…","arch":["amd64","arm64"],"size_bytes":124780544,
  "built_at":"2026-07-01T00:00:00Z","blurb":"Plain Debian, systemd, nothing else.",
  "kind":"builtin","status":"ready","default":true}]}
```

---

## Account endpoints

### Log in

```
POST /api/v1/auth/login
```

**Auth:** none

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `identifier` | string | body | YES | Your username **or** your email |
| `password` | string | body | YES | |

```sh
curl -sS -c jar.txt "$PANEL/auth/login" \
  -H 'content-type: application/json' \
  -d '{"identifier":"you","password":"…"}'
```

```json
{"principal":{"hash":"9f2a…","username":"you","email":"you@example.com"},
 "home":"/containers"}
```

The useful half is the `Set-Cookie: hq_session=…` header. A wrong username and a
wrong password give the same `401 bad_credentials`, at the same speed — the form
is not an account-enumeration oracle.

### Current session

```
GET /api/v1/auth/session
```

**Auth:** none · **Parameters:** none

```sh
curl -sS -b jar.txt "$PANEL/auth/session"
```

```json
{"principal":{"hash":"9f2a…","username":"you","email":"you@example.com"},
 "home":"/containers"}
```

**This answers `200` whether or not you are signed in.** Signed out is
`{"principal":null}`, not a 401. A script that checks the status code will read
an expired cookie as fine — check the field.

### Log out

```
POST /api/v1/auth/logout
```

**Auth:** none (uses the cookie if there is one) · **Parameters:** none

```sh
curl -sS -b jar.txt -X POST "$PANEL/auth/logout"
```

```json
{"ok":true}
```

Destroys the session behind the cookie. Other sessions of yours keep working.

### Sign up

```
POST /api/v1/auth/signup
```

**Auth:** none

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `username` | string | body | YES | Lowercase letters, digits, dots, dashes and underscores; 2–31 characters. Permanent |
| `email` | string | body | YES | |
| `password` | string | body | YES | At least 8 characters |

```sh
curl -sS -c jar.txt "$PANEL/auth/signup" \
  -H 'content-type: application/json' \
  -d '{"username":"you","email":"you@example.com","password":"…"}'
```

`201` with the same body as login, and you are signed in. `409 exists` if the
username or the email is taken.

### Change your panel password

```
POST /api/v1/auth/change-password
```

**Auth:** session

This is your **panel account** password, not the shell login your container's
SSH asks for — that one is [Reset the shell login](#reset-the-shell-login).

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `current` | string | body | YES | `403 bad_password` if wrong |
| `password` | string | body | YES | At least 8 characters |

```sh
curl -sS -b jar.txt -X POST "$PANEL/auth/change-password" \
  -H 'content-type: application/json' \
  -d '{"current":"…","password":"…"}'
```

```json
{"ok":true,"message":"Password changed."}
```

Changing it invalidates nothing else — your other sessions stay signed in.

### Request a password reset

```
POST /api/v1/auth/forgot
```

**Auth:** none

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `email` | string | body | YES | |

Always answers the same thing whether or not the address has an account, so the
form cannot be used to find out who is registered.

```json
{"ok":true,"message":"If that address has an account, a reset link is on its way."}
```

### Complete a password reset

```
POST /api/v1/auth/reset
```

**Auth:** none

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `token` | string | body | YES | From the reset link |
| `password` | string | body | YES | At least 8 characters |

Signs you in on success.

---

## The container object

Most container endpoints answer with this. It is nested: the outer object is the
container **and where it lives**, and `container` inside it is the record.

```json
{"container":{
   "cid":"a1b2c3d4e5f6",
   "name":"web",
   "state":"active",
   "created_at":"2026-06-01T10:00:00Z",
   "expires_at":"2026-12-31T00:00:00Z",
   "image":{"ref":"ghcr.io/hqnode/debian:12","digest":"sha256:…"},
   "allowed_images":["debian-12","ubuntu-24.04"],
   "limits":{"cpu_cores":2,"cpu_idle":false,"mem_bytes":2147483648,
             "swap_bytes":2147483648,"disk_bytes":21474836480,
             "data_bytes":10737418240,"net_quota_bytes":1099511627776},
   "net_usage":{"window_start":"2026-08-01T00:00:00Z",
                "rx_bytes":214748364800,"tx_bytes":126100789760},
   "access":{"ssh_username":"u7k2m9p","ssh_port":22,
             "domains":["example.com"],"ports":[80,443]},
   "live":{"run_state":"running","cpu_pct":3.1,"mem_bytes":734003200,
           "swap_bytes":0,"disk_bytes":4294967296,
           "loopback":"127.100.0.7","started_at":"2026-08-19T09:12:00Z"},
   "history":[{"ts":"2026-08-19T09:12:00Z","event":"restart","by":"9f2a…"}]},
 "machine":{"id":"mch_1a2b3c4d","name":"hk-1","ssh_host":"hk-1.example.com",
            "ssh_port":22,"status":"online"},
 "ssh":"ssh u7k2m9p@hk-1.example.com -p 22"}
```

| Field | Type | Description |
|---|---|---|
| `container.cid` | string | 12 hex characters. The id every path below wants |
| `container.name` | string | Lowercase, 2–31 characters. **What `confirm` has to equal** on rebuild and delete |
| `container.state` | string | `pending`, `active`, `suspended`, `expired`, `deleted` |
| `container.suspend_reason` | string | `quota` when the meter did it. Absent means a person did |
| `container.expires_at` | string | RFC 3339, or `""` for a container that never expires |
| `container.image` | object | `ref`, `digest`, and `private: true` for an image only this container has |
| `container.allowed_images` | array | Catalog ids the holder may rebuild into. Empty means the whole catalog |
| `container.limits.cpu_cores` | float | Guaranteed share. Spare cycles above it are yours too |
| `container.limits.cpu_idle` | bool | Batch tier: only leftover cycles, never delays anyone |
| `container.limits.*_bytes` | int | Bytes. `data_bytes` above zero means a `/data` disk that survives a rebuild |
| `container.net_usage` | object | The traffic meter for the current window — see [Read the traffic meter](#read-the-traffic-meter) |
| `container.access.ssh_username` | string | The gateway login, not a Unix user in the container |
| `container.access.domains` | array | Names routed here |
| `container.live.run_state` | string | `running`, `stopped`, `reinstalling`, `unknown` |
| `container.live.*` | | What the machine last reported. `loopback` is this container's private address |
| `container.history` | array | `{ts, event, by, detail, failed}`, newest first |
| `machine.status` | string | `online` or `offline` — the machine, not the container |
| `ssh` | string | The whole SSH command, ready to paste |

**`state` and `live.run_state` answer different questions.** `state` is what the
panel has decided about the container; `run_state` is whether it is running this
second. An `active` container can be `stopped` because you stopped it.

---

## Container endpoints

Everything here is scoped to containers **you hold**. If you run the machines,
the same operations are in [Hosting endpoints](#hosting-endpoints) under `/machines/{mid}/…`.

### List your containers

```
GET /api/v1/me/containers
```

**Auth:** session · **Parameters:** none

```sh
curl -sS -b jar.txt "$PANEL/me/containers"
```

```json
{"containers":[ … the container object, one per container … ]}
```

### Get one container

```
GET /api/v1/me/containers/{cid}
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID"
```

```json
{"container":{ … the container object … },
 "images":[{"id":"debian-12","name":"Debian 12","size_bytes":124780544,"cached":true}],
 "allow_user_images":true,
 "can_own_image":true}
```

| Field | Type | Description |
|---|---|---|
| `images` | array | What this host can rebuild it from, already filtered by `allowed_images` |
| `allow_user_images` | bool | Whether the machine lets you name a registry reference of your own |
| `can_own_image` | bool | Whether there is a private disk to put one on |

### Start, stop or restart

```
POST /api/v1/me/containers/{cid}/power
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `action` | string | body | YES | `start`, `stop` or `restart` |

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/power" \
  -H 'content-type: application/json' -d '{"action":"restart"}'
```

```json
{"ok":true,"message":"Done."}
```

Stopping is yours to do and so is starting again — it is your container, and one
that has to stay up because only an admin may stop it is one that bills its owner
for nothing. Suspension is a different thing and stays your host's.

| Refusal | Meaning |
|---|---|
| `409 gone` | The container was deleted |
| `409 expired` | Expired containers can only be stopped |
| `409 suspended` | Your host suspended it; only they lift it |
| `409 quota_exceeded` | Over the traffic quota. It clears when the window rolls over or the limit rises |

A **quota** suspension is the one you can clear yourself: once the numbers allow
it, `start` lifts the stop as part of the same call.

### Restart

```
POST /api/v1/me/containers/{cid}/restart
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |

The same as `power` with `{"action":"restart"}`, with no body, for the common
case.

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/restart"
```

### Rebuild

```
POST /api/v1/me/containers/{cid}/reinstall
```

**Auth:** session

A fresh system on the same container: same id, same limits, same shell login,
same domains. `/` is replaced; `/data` survives if the container has one
(`limits.data_bytes` above zero).

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `confirm` | string | body | YES | **The container's own name.** Not `"yes"` |
| `image_id` | string | body | one of | A catalog id — `GET /catalog` |
| `digest` | string | body | one of | An image already on that host |
| `ref` | string | body | one of | A registry reference the host fetches first. The download counts as your traffic |
| `archive` | string | body | one of | A file in the host's image directory — [List image archives](#list-image-archives) |

Exactly one of `image_id`, `digest`, `ref`, `archive`. A holder is held to
`allowed_images` when the host set one; `ref` also needs `allow_user_images`.

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/reinstall" \
  -H 'content-type: application/json' \
  -d '{"image_id":"debian-12","confirm":"web"}'
```

```json
{"container":{ … the container record … },
 "message":"Reinstalled from Debian 12. /data kept."}
```

Getting `confirm` wrong is a `400` that tells you what to type. Other refusals:
`409 expired`, `409 suspended`, `409 gone`.

The call returns before the machine has finished. Poll the next endpoint.

### Watch a rebuild

```
GET /api/v1/me/containers/{cid}/progress
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID/progress"
```

```json
{"operations":[{"kind":"reinstall","key":"a1b2c3d4e5f6","step":"pulling image",
                "index":1,"steps":["pulling image","unpacking","starting"],
                "bytes":48234496,"bytes_total":124780544,
                "started_at":"2026-08-20T06:40:00Z","elapsed_ms":9400,
                "done":false}]}
```

| Field | Type | Description |
|---|---|---|
| `kind` | string | What is happening — `reinstall`, `pull`, `create` |
| `key` | string | The container id it is happening to |
| `step`, `index`, `steps` | | Where it is in the sequence, and what the sequence is |
| `bytes`, `bytes_total` | int | Download progress. `bytes_total` is 0 when nothing is being fetched |
| `done` | bool | Finished. `err` carries the reason when it failed |

Only this container's operations — the keys of the others are other tenants'
container names and image references. Empty means nothing is in flight. When the
machine is out of touch it answers `{"operations":[],"unreachable":true}` rather
than failing.

The simplest completion test is `live.run_state` back to `running` on the
container itself; [Recipes](#recipes) does exactly that.

### Read the traffic meter

Two different readings, and most scripts want both.

**Where you are against the quota** is on the container itself — no extra call:

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID" \
  | jq '.container.container | {used: (.net_usage.rx_bytes + .net_usage.tx_bytes),
                                quota: .limits.net_quota_bytes,
                                since: .net_usage.window_start}'
```

| Field | Type | Description |
|---|---|---|
| `net_usage.window_start` | string | When the current window opened. Your host picks the day |
| `net_usage.rx_bytes` | int | In, this window |
| `net_usage.tx_bytes` | int | Out, this window |
| `limits.net_quota_bytes` | int | Both directions count against it. 0 means no quota |

At 100% the container is **suspended**, not deleted, with `suspend_reason`
`quota`. It comes back when the window rolls over or the limit rises.

**The shape of it over time** is the usage series:

```
GET /api/v1/me/containers/{cid}/usage
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `since` | string | query | NO | A Go duration (`24h`, `168h`) or an RFC 3339 timestamp. Omit for everything kept. **Days are not a unit** — write `168h`, not `7d` |

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID/usage?since=24h"
```

```json
{"points":[{"ts":"2026-08-20T06:10:00Z","cid":"a1b2c3d4e5f6","cpu_pct":2.4,
            "mem_bytes":712500000,"disk_bytes":4294967296,
            "rx_delta":18874368,"tx_delta":5242880}]}
```

| Field | Type | Description |
|---|---|---|
| `ts` | string | Point time |
| `cpu_pct` | float | Percent of the container's own allowance |
| `mem_bytes`, `disk_bytes` | int | At that moment |
| `rx_delta`, `tx_delta` | int | Bytes **since the previous point**, not running totals |

Sum the deltas for a window, or read `net_usage` for the month.

### Reset the shell login

```
POST /api/v1/me/containers/{cid}/credentials
```

**Auth:** session

The login SSH asks for. It belongs to the gateway on the machine, not to
`/etc/shadow` inside the container, which is why this is a panel call and why a
rebuild does not cost you it.

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `ssh_password` | string | body | NO | **Omit and a strong one is generated** — what a script should usually do. If you set it: at least 6 characters, mixing two of letters, digits, punctuation |
| `ssh_username` | string | body | NO | Rename the login too. Lowercase letters, digits, dash, underscore; 2–31 characters, starting with a letter |

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/credentials" \
  -H 'content-type: application/json' -d '{}'
```

```json
{"credentials":{"ssh_username":"u7k2m9p","ssh_password":"…",
                "ssh_host":"hk-1.example.com","ssh_port":22,
                "ssh":"ssh u7k2m9p@hk-1.example.com -p 22"},
 "message":"Updated inside the container. Shown once."}
```

**Shown once is literal.** The panel never stores a shell password: it goes to
the machine and into this reply, and nowhere else. Capture it in the same step
that asked for it — there is no endpoint that reads it back.

### List image archives

```
GET /api/v1/me/containers/{cid}/archives
```

**Auth:** session

Image files an operator put on the machine by hand — what a host with a network
that cannot carry a 200 MB pull offers instead. A name from here goes in
`archive` on a rebuild.

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |

```json
{"sideload":{"dir":"/srv/hqnode/images",
             "files":[{"name":"debian-12.tar","size_bytes":124780544,
                       "modified_at":"2026-07-02T11:00:00Z"}]}}
```

An unreachable machine answers `200` with an empty list and an `error` field,
not a failure — the other ways to rebuild still work.

### Redeem a share code

```
POST /api/v1/me/containers/bind
```

**Auth:** session

Takes a container over in one step: your account becomes its holder and the
shell credentials are rewritten to ones only you know. Whatever the previous
holder or the admin set stops working — that is what binding is.

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `code` | string | body | YES | The share code. Case-insensitive |
| `ssh_password` | string | body | NO | Omit and one is generated |
| `ssh_username` | string | body | NO | Omit to keep the name it has |

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/bind" \
  -H 'content-type: application/json' -d '{"code":"K4M7PQR2"}'
```

```json
{"cid":"a1b2c3d4e5f6",
 "credentials":{"ssh_username":"u7k2m9p","ssh_password":"…",
                "ssh":"ssh u7k2m9p@hk-1.example.com -p 22"},
 "message":"web is yours. These credentials are shown once."}
```

`400` if the code is unknown, already used or expired.

### Hand a container to somebody else

```
POST /api/v1/me/containers/{cid}/bind
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `username` | string | body | YES | An account that **already exists**. Minting usernames is the machine owner's power |

```json
{"ok":true,
 "message":"alice holds web now. Your shell login still works until they or the host reset it."}
```

`404 no_such_user` if there is no such account. Nothing inside the container is
touched: the links move, and the shell login is theirs to reset.

### Give a container back

```
DELETE /api/v1/me/containers/{cid}/bind
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |

Nothing is deleted. It goes back to being an unbound container on its machine
for its host to reassign.

---

## Domain and routing endpoints

Domains are the one piece of your networking you manage yourself. A name costs
the machine nothing — every name shares the same 80 and 443, sorted out by the
name in the request — so there is nothing to ration and nobody to ask.

Pointing DNS at the machine is yours to do at your domain provider; the address
to point at is `host_ip` below.

### List domains

```
GET /api/v1/me/containers/{cid}/domains
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |

```json
{"domains":[{"domain":"example.com"}],"max":10}
```

### Add a domain

```
POST /api/v1/me/containers/{cid}/domains
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `domain` | string | body | YES | A hostname. Normalized to lowercase, no scheme, no trailing dot |

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/domains" \
  -H 'content-type: application/json' -d '{"domain":"example.com"}'
```

Answers the whole list, so nothing needs a second call. A name added here starts
serving HTTP and HTTPS on port 80 inside the container; change that with **Save
route** below.

| Refusal | Meaning |
|---|---|
| `409 too_many_domains` | At the machine's limit. Remove one |
| `409 domain_taken` | Another container on that machine already serves it |
| `409 unavailable` | The container is expired or suspended |

Adding a name you already have is not an error — it answers the list.

### Remove a domain

```
DELETE /api/v1/me/containers/{cid}/domains/{domain}
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `domain` | string | path | YES | The name, URL-encoded |

Answers the remaining list.

### List routes

```
GET /api/v1/me/containers/{cid}/routes
```

**Auth:** session

What each of your names actually does. The list of names is the panel's;
everything here is read from the machine every time, because the copy that
decides where packets go is the machine's.

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |

```json
{"routes":[{
   "domain":"example.com","cid":"a1b2c3d4e5f6","mode":"both",
   "http_port":80,"tls_port":443,"tls_mode":"managed",
   "compress":"on","proxy_protocol":false,
   "ports":{"http":{"port":80,"published":true},
            "https":{"port":80,"published":true}},
   "checks":{"dns":{"state":"ok","addresses":["203.0.113.10"],
                    "expected":["203.0.113.10"],"checked_at":"2026-08-20T06:00:00Z"},
             "http":{"state":"ok","status":200,"took_ms":14},
             "https":{"state":"ok","days_left":74,"issuer":"Let's Encrypt"}},
   "cert":{"state":"ready","expires_at":"2026-11-02T00:00:00Z","days_left":74,
           "issued_7d":1,"failed_1h":0}}],
 "max":10,"host_ip":"203.0.113.10","host_tls_port":443,
 "host_online":true,"managed_available":true}
```

| Field | Type | Description |
|---|---|---|
| `mode` | string | `both`, `http`, `tls`, `none` — derived from the two switches |
| `tls_mode` | string | `managed` (the machine holds a certificate) or `sni` (bytes spliced through; your key never leaves the container) |
| `checks.*.state` | string | The host's cached answer behind each badge |
| `host_ip` | string | Where to point your DNS record |
| `host_online` | bool | `false` is not an error: the names are real, only editing is unavailable |
| `managed_available` | bool | False when the machine's TLS listener has moved off 443, where the challenge arrives |

### Save a route

```
PUT /api/v1/me/containers/{cid}/routes/{domain}
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `domain` | string | path | YES | A name this container already has |
| `http.enabled` | bool | body | YES | Serve plain HTTP |
| `http.port` | int | body | YES | Container port it reaches. 1–65535 |
| `https.enabled` | bool | body | YES | Serve HTTPS |
| `https.mode` | string | body | NO | `managed` or `sni`. Default `sni` |
| `https.port` | int | body | YES | Container port HTTPS reaches. **Ignored in `managed`** — the machine terminates and forwards plaintext to `http.port` |
| `compress` | string | body | NO | `on`, `off`, or `""` for the host's default |
| `proxy_protocol` | bool | body | NO | Prepend a PROXY header so your service sees the real client IP |

```sh
curl -sS -b jar.txt -X PUT "$PANEL/me/containers/$CID/routes/example.com" \
  -H 'content-type: application/json' \
  -d '{"http":{"enabled":true,"port":8080},
       "https":{"enabled":true,"mode":"managed","port":443},
       "compress":"on","proxy_protocol":false}'
```

```json
{"route":{ … the route view from above … }}
```

Both switches off leaves the name listed and answering nothing. `404` if the
name is not one of this container's — add it first.

### Probe a name

```
POST /api/v1/me/containers/{cid}/routes/{domain}/probe
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `domain` | string | path | YES | |
| `checks` | array | body | NO | Any of `dns`, `http`, `https`. Default all three |
| `force` | bool | body | NO | Dial now instead of answering from the host's cache |

The container and the addresses to compare DNS against are filled in by the
panel, not by you — a body naming another container would be a port scan with a
session cookie on it.

```json
{"dns":{"state":"ok","addresses":["203.0.113.10"],"expected":["203.0.113.10"]},
 "http":{"state":"ok","status":200,"took_ms":14},
 "https":{"state":"ok","days_left":74}}
```

### Request a certificate

```
POST /api/v1/me/containers/{cid}/routes/{domain}/certificate
```

**Auth:** session · **Parameters:** `cid`, `domain` in path

Only for a name whose `tls_mode` is `managed`; `409 not_managed` otherwise. The
machine normally gets and renews the certificate on its own — this is the button
for when you want it now.

```json
{"cert":{"state":"pending","issued_7d":1,"failed_1h":0}}
```

`202`. Let's Encrypt allows five certificates a week for one name, so a request
that would spend the last of them is refused **before** it is made, with
`next_manual_at` in the body and `Retry-After` on the response.

---

## Port endpoints

A public port is a number on the machine's own address that goes straight into
one container — `203.0.113.10:31000` lands on port 3000 inside your box. Right
for a game server, a database, a VPN; a website wants a domain instead.

**You read them and test them. Your host opens them.** A domain costs the
machine nothing, but `31000` is a single thing that one container can have, and
two tenants who both want it is a disagreement somebody has to settle. So there
is no `POST` and no `DELETE` under `/me/containers/{cid}/ports` — not a
permission check inside a handler, but routes that were never registered, so a
write there is a 404 from the router. [Public ports](ports.md) is the whole
story; opening one is [Open a public port](#open-a-public-port) on the hosting side.

### List public ports

```
GET /api/v1/me/containers/{cid}/ports
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |

```json
{"mappings":[
   {"id":"tcp-3000-0.0.0.0","proto":"tcp","container":3000,"public":31000,
    "public_facing":true,"live":true,"added_at":"2026-08-01T09:00:00Z","by":"host",
    "check":{"state":"ok","took_ms":3,"checked_at":"2026-08-20T06:00:00Z"}},
   {"id":"tcp-80","proto":"tcp","container":80,"host":8080,
    "public_facing":false,"live":true,
    "used_by":{"kind":"domain","domain":"example.com"}}],
 "host_ip":"203.0.113.10","loopback":"127.100.0.7",
 "host_online":true,"can_edit":false}
```

| Field | Type | Description |
|---|---|---|
| `id` | string | `proto-container-bind`, or `proto-container` for a host-only mapping. This is `{id}` in the probe path |
| `public` | int | The number the internet reaches. Set only when `public_facing` |
| `host` | int | The number on the container's private loopback. The other case |
| `count` | int | Consecutive ports covered. Absent or 1 is one |
| `live` | bool | Held right now. `false` is honest for a mapping waiting on the next start |
| `check` | object | The last probe: `ok`, `closed`, `unpublished`, `error`, `untested` |
| `used_by` | object | Why a host-only mapping cannot be closed: a `domain` or the SSH `gateway` |
| `can_edit` | bool | `false` on this path, always. It is `true` for the machine's owner |

Four fields about the machine's internals — `public_range`, `private_range`,
`public_max_span` and `holder` — are on the owner's copy of this response and
deliberately absent here.

### Probe a port

```
POST /api/v1/me/containers/{cid}/ports/{id}/probe
```

**Auth:** session

Is anything actually listening? It dials one port and changes nothing.

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `cid` | string | path | YES | Container id |
| `id` | string | path | YES | A mapping id from the list above, e.g. `tcp-3000-0.0.0.0` |

```json
{"state":"ok","took_ms":3,"port":3000,"checked_at":"2026-08-20T06:41:00Z"}
```

UDP answers `untested` without dialling — there is nothing to conclude from
silence on a UDP port.

---

## Hosting endpoints

The other half of the API: machines of your own, and every container on them.
Same cookie, same base URL. `{mid}` is the machine id.

Everything in [Container endpoints](#container-endpoints) has a twin here — power, reinstall,
usage, credentials — under `/machines/{mid}/containers/{cid}/…` with the same
bodies. What follows is what only an owner can do.

### List your machines

```
GET /api/v1/machines
```

**Auth:** session · **Parameters:** none

```sh
curl -sS -b jar.txt "$PANEL/machines"
```

```json
{"machines":[{"id":"mch_1a2b3c4d","name":"hk-1",
  "host":{"hostname":"hk-1","arch":"amd64","cpu_cores":8,
          "mem_bytes":34359738368,"ssh_host":"hk-1.example.com","ssh_port":22},
  "policy":{"allow_user_images":true,"net_reset_day":1,"max_domains":10,
            "default_limits":{ … }},
  "cache":{"status":"online"},
  "containers":[ … full container records … ],
  "link":{"connected":true,"token_sealed":true}}]}
```

`link.connected` is whether the websocket is up **right now**; `cache.status` is
what the last poll concluded. For "can I act on this machine", read the first.

### Get one machine

```
GET /api/v1/machines/{mid}
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `mid` | string | path | YES | Machine id |

```json
{"machine":{ … as above … },
 "host_live":{"hostname":"hk-1","arch":"amd64","kernel":"6.12.0",
              "agent_version":"0.1.0.g6a739b2b0867","ip":"203.0.113.10",
              "cpu_cores":8,"cpu_pct":18.2,
              "mem_bytes":34359738368,"mem_used_bytes":12884901888,
              "zram_bytes":8589934592,"zram_used_bytes":1073741824,
              "disk_bytes":1099511627776,"disk_used_bytes":329853488332,
              "psi_mem_avg60":0.4,"psi_cpu_avg60":11.2,
              "net_rx_mbit":42.1,"net_tx_mbit":18.7,"containers_running":6},
 "host_error":""}
```

`psi_cpu_avg60` is the oversell dial: sustained above about 25% means tenants
are queueing for cores, and the machine starts refusing new containers of its
own accord.

`host_live` is read from the machine as you ask. An unreachable machine fills
`host_error` and still answers `200` — that is a fact about the machine, not a
failed request.

### Create a container

```
POST /api/v1/machines/{mid}/containers
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `mid` | string | path | YES | Machine id |
| `name` | string | body | YES | Lowercase letters, digits and dashes, 2–31 characters. Unique on that machine |
| `image_id` | string | body | one of | A catalog id |
| `archive` | string | body | one of | A file in the machine's image directory instead |
| `username` | string | body | NO | Hand it straight to this account, creating it if needed. Omit and you get a share code back instead |
| `email` | string | body | NO | Only used when that account has to be created |
| `ssh_username` | string | body | NO | The gateway login. Generated if omitted |
| `ssh_password` | string | body | NO | Generated if omitted. At least 6 characters, two character classes |
| `limits` | object | body | NO | Any field left out takes the machine's default |
| `limits.cpu_cores` | float | body | NO | e.g. `0.5`, `2` |
| `limits.cpu_idle` | bool | body | NO | Batch tier: leftover cycles only |
| `limits.mem_bytes` | int | body | NO | Bytes |
| `limits.swap_bytes` | int | body | NO | Bytes. `0` means none — killed at the memory wall |
| `limits.reserve_bytes` | int | body | NO | Bytes the kernel will not reclaim below. Default: half of memory |
| `limits.disk_bytes` | int | body | NO | Bytes. `0` means a share of the host filesystem |
| `limits.data_bytes` | int | body | NO | Bytes for a `/data` disk that survives rebuilds |
| `limits.net_quota_bytes` | int | body | NO | Bytes per window, both directions |
| `ports` | array | body | NO | Container ports to publish on creation |
| `domains` | array | body | NO | Names to route here on day one |
| `expires_at` | string | body | NO | A date (`2026-12-31`) or an RFC 3339 timestamp. Omit for the machine's default; `""` for never |
| `allowed_images` | array | body | NO | Catalog ids the holder may rebuild into. Omit for the whole catalog |

```sh
curl -sS -b jar.txt -X POST "$PANEL/machines/$MID/containers" \
  -H 'content-type: application/json' -d '{
    "name":"web",
    "image_id":"debian-12",
    "limits":{"cpu_cores":2,"mem_bytes":2147483648,
              "disk_bytes":21474836480,"net_quota_bytes":1099511627776},
    "expires_at":"2026-12-31",
    "ports":[80,443]
  }'
```

`201`:

```json
{"container":{"cid":"a1b2c3d4e5f6","name":"web","state":"active", … },
 "machine_id":"mch_1a2b3c4d",
 "credentials":{"ssh_username":"u7k2m9p","ssh_password":"…",
                "ssh":"ssh u7k2m9p@hk-1.example.com -p 22"},
 "share_code":"K4M7PQR2",
 "share_url":"https://hqno.de/containers/redeem?code=K4M7PQR2",
 "share_expires_at":"2026-08-27T06:39:00Z"}
```

**The password and the share code are shown once.** This reply is the only copy
of either; no endpoint reads them back. The code appears only when `username`
was omitted — with nobody holding it, the thing that hands it over comes with it.

How many containers a machine can carry is the **machine's** answer, not a number
in the panel: the host refuses a create on real memory and CPU pressure and says
why. What the panel caps is your account — `402 limit_reached`.

| Refusal | Meaning |
|---|---|
| `409 name_taken` | That machine has a container by that name |
| `402 limit_reached` | Your account's container allowance is used up |
| `409 machine_offline` | A username that does not exist yet cannot be minted by a machine that has not checked in |
| `502 agent_unreachable` | The machine is not answering |

### Change limits, expiry, name or state

```
PATCH /api/v1/machines/{mid}/containers/{cid}
```

**Auth:** session

Only the fields you send change.

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `mid`, `cid` | string | path | YES | |
| `limits` | object | body | NO | Same shape as create. Omitted fields keep their value |
| `expires_at` | string | body | NO | Three-way: absent leaves it, a date moves it, `""` removes the expiry |
| `name` | string | body | NO | Rename. Same rules as create |
| `state` | string | body | NO | `active` or `suspended` |
| `allowed_images` | array | body | NO | |
| `domains` | array | body | NO | Replaces the list |

```sh
curl -sS -b jar.txt -X PATCH "$PANEL/machines/$MID/containers/$CID" \
  -H 'content-type: application/json' \
  -d '{"limits":{"mem_bytes":4294967296},"expires_at":"2027-06-30"}'
```

Renewing an expired container is this call — move `expires_at` forward and it
comes straight back, same disk, same login.

### Delete a container

```
DELETE /api/v1/machines/{mid}/containers/{cid}
```

**Auth:** session

The only call that destroys data. Expiry never deletes; nothing else does either.

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `mid`, `cid` | string | path | YES | |
| `confirm` | string | body | YES | **The container's own name** |
| `force` | bool | body | NO | Delete the panel's record when the machine did not answer. The container itself is untouched and may still be running |

```sh
curl -sS -b jar.txt -X DELETE "$PANEL/machines/$MID/containers/$CID" \
  -H 'content-type: application/json' -d '{"confirm":"web"}'
```

```json
{"ok":true,"warning":""}
```

### Bind a container to an account

```
POST /api/v1/machines/{mid}/containers/{cid}/bind
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `mid`, `cid` | string | path | YES | |
| `username` | string | body | YES | **Created if it does not exist** — this is the one place a username is minted. Needs a machine that has checked in |
| `email` | string | body | NO | Only used when the account is created |

An account made this way has no password yet; its owner uses **Forgot password**
with that email. `DELETE` on the same path unbinds — the container stays, nothing
inside it is touched.

### Mint a share code

```
POST /api/v1/machines/{mid}/containers/{cid}/bind-code
```

**Auth:** session · **Parameters:** `mid`, `cid` in path

For a container nobody holds. Whoever redeems it becomes the holder and sets the
shell login.

```json
{"code":"K4M7PQR2","expires_at":"2026-08-27T06:39:00Z",
 "redeem_url":"https://hqno.de/containers/redeem?code=K4M7PQR2",
 "container":{"cid":"a1b2c3d4e5f6","name":"web","machine":"hk-1"}}
```

`201`, and **shown once** — only the hash is kept. `GET` on the same path hands
back the code a container already has instead of minting a second one. `400` if
it already has a holder.

### Reset a container's shell login

```
POST /api/v1/machines/{mid}/containers/{cid}/credentials
```

**Auth:** session

The owner's copy of [Reset the shell login](#reset-the-shell-login), same body, same shown-once
reply. How an admin recovers a container whose password went missing.

### Open a public port

```
POST /api/v1/machines/{mid}/containers/{cid}/ports
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `mid`, `cid` | string | path | YES | |
| `container` | int | body | YES | The port inside the container. 1–65535 |
| `proto` | string | body | NO | `tcp` or `udp`. Default `tcp` |
| `public` | int | body | NO | The number outside: 1024–65535. **Omit or `0` and the host picks a free one** and tells you which |
| `count` | int | body | NO | Consecutive ports, up to 4096. `public+i → container+i` |
| `apply` | string | body | NO | `now` (default) or `next_start`. `now` restarts the container's networking and drops live connections |

```sh
curl -sS -b jar.txt -X POST "$PANEL/machines/$MID/containers/$CID/ports" \
  -H 'content-type: application/json' -d '{"proto":"tcp","container":3000}'
```

Answers the whole ports list, as a `GET` would, plus a `notice` when something
actually restarted.

Public ports start at 1024 because binding lower would need a capability the
design does without. The host is the authority on what is free, what is inside
its private pool and how long a span may be — those come back as
`409 port_taken`, `port_in_pool`, `span_too_large`, `port_overlap` or
`no_free_port`, each naming the number in its fields as well as in the sentence.

### Close a public port

```
DELETE /api/v1/machines/{mid}/containers/{cid}/ports/{id}
```

**Auth:** session

| Name | Type | In | Mandatory | Description |
|---|---|---|---|---|
| `mid`, `cid` | string | path | YES | |
| `id` | string | path | YES | A mapping id, e.g. `tcp-3000-0.0.0.0` |
| `apply` | string | query | NO | `now` (default) or `next_start` |

`409 port_in_use` names the domain that still routes to it.

### Other machine endpoints

Not documented here, because they are about running the box rather than about
containers: `GET/POST /machines/{mid}/deps`, `/storage`, `/tuning`, `/ports`,
`/ports/sshd`, `/upgrade`, `/images`, `/progress`, `PATCH /machines/{mid}/policy`,
`DELETE /machines/{mid}`, and enrolment. They follow the same conventions.
[Running a machine of your own](running-a-machine.md) covers what they do.

---

## From inside the container

Do not use any of the above from a shell inside your own box. A container holds
no panel credential — that is a deliberate property, not an oversight — and the
three things you would want are already there:

| Command | What it does |
|---|---|
| `dashboard` | Limits, what is used, traffic left, expiry, addresses |
| `app-setup domain add example.com` | Claim a name and route it here |
| `passwd` | Change the shell login |

They reach the panel over the machine's own already-authenticated link, through
a socket that identifies your container by which listener accepted the
connection. Nothing you type can name another container, and there is no secret
in the box for anyone to steal. See
[using your container](using-your-container.md).

---

## Recipes

### A GitHub Actions job

Rebuild a container, wait for it, fail the job if it does not come back.

```yaml
name: rebuild
on: workflow_dispatch

jobs:
  rebuild:
    runs-on: ubuntu-latest
    env:
      PANEL: https://hqno.de/api/v1
      CID: a1b2c3d4e5f6
      NAME: web            # what `confirm` has to equal
    steps:
      - name: Sign in
        run: |
          curl -sS --fail-with-body -c "$RUNNER_TEMP/jar" "$PANEL/auth/login" \
            -H 'content-type: application/json' \
            -d "$(jq -nc --arg u "${{ secrets.PANEL_USER }}" \
                         --arg p "${{ secrets.PANEL_PASSWORD }}" \
                         '{identifier:$u,password:$p}')" > /dev/null

      - name: Rebuild
        run: |
          curl -sS --fail-with-body -b "$RUNNER_TEMP/jar" \
            -X POST "$PANEL/me/containers/$CID/reinstall" \
            -H 'content-type: application/json' \
            -d "$(jq -nc --arg c "$NAME" '{image_id:"debian-12",confirm:$c}')"

      - name: Wait for it
        run: |
          for i in $(seq 1 60); do
            state=$(curl -sS -b "$RUNNER_TEMP/jar" "$PANEL/me/containers/$CID" \
                    | jq -r '.container.container.live.run_state')
            echo "run_state=$state"
            [ "$state" = "running" ] && exit 0
            sleep 10
          done
          echo "container did not come back"; exit 1

      - name: Sign out
        if: always()
        run: |
          curl -sS -b "$RUNNER_TEMP/jar" -X POST "$PANEL/auth/logout" > /dev/null
          rm -f "$RUNNER_TEMP/jar"
```

Four things there are worth copying whatever your job does:

- **`--fail-with-body`.** Plain `curl` exits 0 on a 409, and a job that ignores
  the status shows a green tick over a container that never restarted. This
  prints the panel's sentence and fails the step.
- **`jq -nc` to build the JSON**, so a password containing a quote does not
  become a broken body or a shell injection.
- **The cookie jar in `$RUNNER_TEMP`, deleted at the end.** Store the password
  as a secret, never the cookie.
- **Tolerate a 502.** `agent_unreachable` is a machine briefly out of touch, not
  a failed deploy.

### Restart after a deploy

```sh
#!/bin/sh
set -e
PANEL=https://hqno.de/api/v1
CID=a1b2c3d4e5f6

curl -sS --fail-with-body -c /tmp/jar "$PANEL/auth/login" \
  -H 'content-type: application/json' \
  -d "$(jq -nc --arg p "$PANEL_PASSWORD" '{identifier:"you",password:$p}')" > /dev/null

curl -sS --fail-with-body -b /tmp/jar -X POST "$PANEL/me/containers/$CID/restart"
rm -f /tmp/jar
```

### Alert at 80% of the traffic quota

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID" | jq -e '
  .container.container
  | (.net_usage.rx_bytes + .net_usage.tx_bytes) as $used
  | .limits.net_quota_bytes as $quota
  | if $quota > 0 and $used / $quota > 0.8
    then "USED \($used) OF \($quota)" | halt_error(1)
    else empty end'
```

Exit 1 means over the line. At 100% the container is suspended — stopped, not
deleted — and comes back when the window rolls over.

### Rotate the shell password monthly

```sh
new=$(curl -sS --fail-with-body -b jar.txt \
  -X POST "$PANEL/me/containers/$CID/credentials" \
  -H 'content-type: application/json' -d '{}' \
  | jq -r '.credentials.ssh_password')

# The only copy there will ever be. Put it somewhere before this script ends.
printf '%s' "$new" | your-secret-store put hqnode/web/ssh
```

---

## What this page does not promise

This is the panel's own API, and the panel ships together with the page that
calls it. The `v1` prefix has not changed shape and none of the calls above are
going to disappear quietly — but this is not a vendor's published contract with
a deprecation policy behind it. Branch on `code` rather than on the English in
`message`, keep your scripts short enough to re-read after an upgrade, and
prefer the endpoints in [Recipes](#recipes), which are the ones the panel's own
screens lean on hardest.

There are no webhooks and no event stream: poll. There is no bulk endpoint — one
container per call.
