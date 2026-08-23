---
title: 面板 REST API
---

# 面板 REST API

面板上的每一个界面都是这套 API 的客户端，按钮能做的事没有一件是 `curl` 够不着的。
从 GitHub Actions 任务里重装一个容器，部署完把它重启，在自己的机器上开一个，
把流量表读进监控，按计划轮换 shell 密码。

这一页是参考手册。[现成的做法](#recipes)里是可以直接拿去跑的完整脚本。

---

## 总则 {#general-information}

- 基地址是你的面板加上 `/api/v1`。在 `https://hqno.de` 登录，那就是
  **`https://hqno.de/api/v1`**。下面每一条路径都是相对它写的。
- 每个应答都是 `application/json`，带 `Cache-Control: no-store`。
- 请求体是 JSON，要带 `content-type: application/json`。没有一个接口收表单编码，
  查询参数只有 `?since=` 和 `?apply=`。
- **所有大小都是字节** —— 就是整数，不会出现 `"2G"`。所有时间戳都是 UTC 的
  RFC 3339（`2026-08-20T06:39:00Z`）。
- 它分成两半。`/me/…` 是你拿着的：别人给你的容器。`/machines/…` 是你在跑的：
  你自己的机器，以及机器上的每一个容器。一个账号，一个 cookie，两半都通 ——
  大多数人一辈子只用其中一半。
- id：容器 id（`cid`）是 **12 个十六进制字符**；机器 id（`mid`）是 `mch_`
  加 8 个十六进制字符。两个都是那样东西在面板里 URL 的最后一段。

**不要在你自己的容器里面调这套 API。** 容器里故意不放任何面板凭据 ——
它有 `dashboard`、`app-setup domain` 和 `passwd`，这三个通过它的宿主机够到面板，
盒子里不需要放任何秘密。见[在容器里面](#from-inside-the-container)。

---

## 认证 {#authentication}

没有 API key。这套 API 收的就是浏览器拿到的那个会话 cookie，从同一个登录表单来：
登录一次，把 cookie 留着，之后每个请求都带上它。

```sh
PANEL=https://hqno.de/api/v1

# 登录。凭据是那个 cookie，不是应答体里的任何东西。
curl -sS -c jar.txt "$PANEL/auth/login" \
  -H 'content-type: application/json' \
  -d '{"identifier":"you","password":"…"}'

# 之后每一个调用都带上这个 jar。
curl -sS -b jar.txt "$PANEL/me/containers"
```

| | |
|---|---|
| Cookie | `hq_session` |
| 有效期 | 7 天 |
| 属性 | `HttpOnly`、`SameSite=Lax`，面板是 HTTPS 时还有 `Secure` |
| 提前失效 | `POST /auth/logout`，或者在面板里登出 |

**为什么是 cookie 而不是 token。** token 是一种会泄漏的东西，而它不得不存放的每一个
地方，恰恰都是这个设计要把秘密赶出去的地方。会话是短命的、能在一个界面上吊销的，
而且就是浏览器已经拿着的那一份 —— 一个入口，一样可以收回的东西。在 CI 里，
**存面板密码，每次登录；永远不要存 cookie**。存下来的 cookie 是一把有效七天、
而你看不出它还剩多久的钥匙，重新登录一次不过多一个请求。

下面每个接口都标了**认证**是「会话」还是「无」。

---

## 应答格式 {#response-format}

成功时是这个接口自己的形状。失败时永远是这三个键：

```json
{"error":"Sign in first.","code":"unauthorized","message":"Sign in first."}
```

按 `code` 分支。`error` 和 `message` 是同一句英文，带两遍，
这样读其中任何一个的客户端都拿得到。有些拒绝会多带字段 ——
端口冲突会说出是哪个号码，证书拒绝会加上 `next_manual_at` —— 但那三个永远都在。

### HTTP 状态码 {#http-return-codes}

| 状态码 | 意思 |
|---|---|
| 200 | 做完了 |
| 201 | 创建了 —— 一个容器，或者一个分享码 |
| 202 | 收下了 —— 一个证书申请，机器接着去办 |
| 400 | 你的请求体不对。那句话会说哪里不对 |
| 401 | 没有 cookie，或者它过期了 |
| 402 | 你账号能拿的容器数用完了 |
| 403 | 当前密码不对，或者这个面板轮不到你管 |
| 404 | 没有这个东西 —— **或者它不是你的**，见下 |
| 409 | 它已经存在，或者它现在的状态不允许这么做 |
| 429 | 被限流了 |
| 502 | 面板够不着那台机器 |
| 500 | 面板自己坏了。这一个是 bug |

**404 同时也表示「不是你的」。** 授权是结构性的：不在你自己列表里的容器根本解析不出来，
所以没有一个 403 来区分「存在但不许你碰」和「不存在」。
这里没有任何东西会报告别人的容器，包括它存不存在。

**502 是正常的，而且是暂时的。** 你容器做的任何事都不经过面板；
面板通过一条会断的链路去够那台机器。链路断着的时候，读还是能从面板的记录里答出来，
写会回 `agent_unreachable`。重试就好 —— 这不是一次失败的部署。

### 错误码 {#error-codes}

| `code` | 状态码 | 什么时候 |
|---|---|---|
| `bad_request` | 400 | 请求体不对 |
| `unauthorized` | 401 | 没登录 |
| `bad_credentials` | 401 | 登录失败。用户名错和密码错给的是同一个答案 |
| `limit_reached` | 402 | 账号能拿的容器数用完了 |
| `bad_password` | 403 | `current` 对不上 |
| `forbidden` | 403 | 只有管理员能调的接口 |
| `not_found` | 404 | 没有，或者不是你的 |
| `no_route` | 404 | 没有这个接口 —— 你把路径打错了 |
| `exists` | 409 | 用户名或邮箱已经注册过了 |
| `name_taken` | 409 | 那台机器上已经有一个同名容器 |
| `gone` | 409 | 这个容器已经被删了 |
| `expired` | 409 | 已到期：只能关，不能开 |
| `suspended` | 409 | 被你的房东停用了 |
| `quota_exceeded` | 409 | 这个窗口的流量超了 |
| `unavailable` | 409 | 已到期或已停用，所以网络不给改 |
| `machine_offline` | 409 | 那台机器没有上报过 |
| `too_many_domains` | 409 | 到了这台机器的域名上限 |
| `domain_taken` | 409 | 那台机器上另一个容器在服务这个名字 |
| `not_managed` | 409 | 这个名字不是「由机器托管证书」那一档 |
| `port_taken`、`port_overlap`、`port_in_pool`、`span_too_large`、`no_free_port` | 409 | 主机拒绝了这个端口。字段里会说出号码和池子 |
| `port_in_use` | 409 | 还有域名路由到那个端口 |
| `rate_limited` | 429 | 你这个地址登录或重置得太频繁了 |
| `agent_unreachable`、`agent_error` | 502 | 那台机器不应答 |
| `agent_refused` | 4xx | 主机拒绝了，但没给出自己的错误码 |
| `internal` | 500 | 一个 bug |

### 频率限制 {#rate-limits}

| 接口 | 限制 |
|---|---|
| `/auth/login`、`/auth/signup` | 每个 IP 每分钟 10 次 |
| `/auth/forgot`、`/auth/reset` | 每个 IP 每 15 分钟 5 次 |
| 其余全部 | 无 |

超了就是 `429 rate_limited`，密码再对也一样。只登录一次的任务永远碰不到它；
一个十二路矩阵、每一步都登录一次的，会碰到。

---

## 通用接口 {#general-endpoints}

### 探活 {#test-connectivity}

```
GET /api/v1/ping
```

**认证**：无 · **参数**：无

```sh
curl -sS "$PANEL/ping"
```

```json
{"ok":true}
```

### 面板健康 {#panel-health}

```
GET /api/v1/healthz
```

**认证**：无 · **参数**：无

```sh
curl -sS "$PANEL/healthz"
```

```json
{"ok":true,"live_agents":true,"agents_linked":3}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `live_agents` | bool | 这个面板是真的在跟主机说话，还是在模拟它们 |
| `agents_linked` | int | 此刻链路活着的机器数 |

### 面板配置 {#panel-configuration}

```
GET /api/v1/config
```

**认证**：无 · **参数**：无

agent 应该跑的是哪个版本，好让机器页面提供升级。

```sh
curl -sS "$PANEL/config"
```

```json
{"agent_version":"0.1.0.g6a739b2b0867","agent_downloads":true}
```

### 镜像目录 {#image-catalog}

```
GET /api/v1/catalog
```

**认证**：会话 · **参数**：无

可选的系统。创建或重装时 `image_id` 要填的就是这里的 `id`。

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

## 账号接口 {#account-endpoints}

### 登录 {#log-in}

```
POST /api/v1/auth/login
```

**认证**：无

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `identifier` | string | 请求体 | 是 | 你的用户名**或者**邮箱 |
| `password` | string | 请求体 | 是 | |

```sh
curl -sS -c jar.txt "$PANEL/auth/login" \
  -H 'content-type: application/json' \
  -d '{"identifier":"you","password":"…"}'
```

```json
{"principal":{"hash":"9f2a…","username":"you","email":"you@example.com"},
 "home":"/containers"}
```

有用的那一半是 `Set-Cookie: hq_session=…` 这个头。用户名错和密码错给的是同一个
`401 bad_credentials`，而且一样快 —— 这个表单不是一个能拿来试探账号存不存在的东西。

### 当前会话 {#current-session}

```
GET /api/v1/auth/session
```

**认证**：无 · **参数**：无

```sh
curl -sS -b jar.txt "$PANEL/auth/session"
```

```json
{"principal":{"hash":"9f2a…","username":"you","email":"you@example.com"},
 "home":"/containers"}
```

**不管你登没登录，这个接口都答 `200`。** 没登录是 `{"principal":null}`，不是 401。
只看状态码的脚本会把一个过期的 cookie 读成一切正常 —— 要看那个字段。

### 登出 {#log-out}

```
POST /api/v1/auth/logout
```

**认证**：无（有 cookie 就用）· **参数**：无

```sh
curl -sS -b jar.txt -X POST "$PANEL/auth/logout"
```

```json
{"ok":true}
```

销毁这个 cookie 背后的那个会话。你其他的会话照常。

### 注册 {#sign-up}

```
POST /api/v1/auth/signup
```

**认证**：无

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `username` | string | 请求体 | 是 | 小写字母、数字、点、横线和下划线；2–31 个字符。永久不变 |
| `email` | string | 请求体 | 是 | |
| `password` | string | 请求体 | 是 | 至少 8 个字符 |

```sh
curl -sS -c jar.txt "$PANEL/auth/signup" \
  -H 'content-type: application/json' \
  -d '{"username":"you","email":"you@example.com","password":"…"}'
```

`201`，应答体和登录一样，而且你已经是登录状态了。用户名或邮箱被占了就是 `409 exists`。

### 改面板密码 {#change-your-panel-password}

```
POST /api/v1/auth/change-password
```

**认证**：会话

这是你的**面板账号**密码，不是容器 SSH 问你要的那个 shell 登录密码 ——
那个在[重置 shell 登录](#reset-the-shell-login)。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `current` | string | 请求体 | 是 | 错了就是 `403 bad_password` |
| `password` | string | 请求体 | 是 | 至少 8 个字符 |

```sh
curl -sS -b jar.txt -X POST "$PANEL/auth/change-password" \
  -H 'content-type: application/json' \
  -d '{"current":"…","password":"…"}'
```

```json
{"ok":true,"message":"Password changed."}
```

改了它不会让别的东西失效 —— 你其他的会话仍然是登录着的。

### 申请重置密码 {#request-a-password-reset}

```
POST /api/v1/auth/forgot
```

**认证**：无

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `email` | string | 请求体 | 是 | |

不管这个地址有没有账号，答的都是同一句话，所以这个表单没法拿来查谁注册过。

```json
{"ok":true,"message":"If that address has an account, a reset link is on its way."}
```

### 完成密码重置 {#complete-a-password-reset}

```
POST /api/v1/auth/reset
```

**认证**：无

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `token` | string | 请求体 | 是 | 从重置链接里来 |
| `password` | string | 请求体 | 是 | 至少 8 个字符 |

成功后顺带把你登录上。

---

## 容器对象 {#the-container-object}

大多数容器接口答的都是这个东西。它是套着的：外层是容器**以及它住在哪儿**，
里面那个 `container` 才是记录本身。

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

| 字段 | 类型 | 说明 |
|---|---|---|
| `container.cid` | string | 12 个十六进制字符。下面每条路径要的就是它 |
| `container.name` | string | 小写，2–31 个字符。重装和删除时 **`confirm` 要等于它** |
| `container.state` | string | `pending`、`active`、`suspended`、`expired`、`deleted` |
| `container.suspend_reason` | string | 流量表干的就是 `quota`。没有这个字段就是人干的 |
| `container.expires_at` | string | RFC 3339，永不到期的容器是 `""` |
| `container.image` | object | `ref`、`digest`，只有这个容器才有的镜像还会带 `private: true` |
| `container.allowed_images` | array | 持有者能重装成哪些目录 id。空表示整个目录都行 |
| `container.limits.cpu_cores` | float | 保证给你的份额。之上还空着的算力也是你的 |
| `container.limits.cpu_idle` | bool | 批处理档：只用剩下的算力，永远不耽误别人 |
| `container.limits.*_bytes` | int | 字节。`data_bytes` 大于零表示有一块能熬过重装的 `/data` 盘 |
| `container.net_usage` | object | 当前窗口的流量表 —— 见[读流量表](#read-the-traffic-meter) |
| `container.access.ssh_username` | string | 网关的登录名，不是容器里的一个 Unix 用户 |
| `container.access.domains` | array | 路由到这里的名字 |
| `container.live.run_state` | string | `running`、`stopped`、`reinstalling`、`unknown` |
| `container.live.*` | | 机器最后一次上报的东西。`loopback` 是这个容器的私有地址 |
| `container.history` | array | `{ts, event, by, detail, failed}`，最新的在前 |
| `machine.status` | string | `online` 或 `offline` —— 说的是机器，不是容器 |
| `ssh` | string | 整条 SSH 命令，可以直接粘 |

**`state` 和 `live.run_state` 回答的是两个不同的问题。** `state` 是面板对这个容器
下的判断；`run_state` 是它这一秒有没有在跑。一个 `active` 的容器完全可以是
`stopped` 的 —— 因为是你自己关的。

---

## 容器接口 {#container-endpoints}

这一节里的所有东西，范围都是**你拿着的**容器。如果机器是你在跑，
同样这些操作在[主机侧接口](#hosting-endpoints)里，路径是 `/machines/{mid}/…`。

### 列出你的容器 {#list-your-containers}

```
GET /api/v1/me/containers
```

**认证**：会话 · **参数**：无

```sh
curl -sS -b jar.txt "$PANEL/me/containers"
```

```json
{"containers":[ … 上面那个容器对象，一个容器一份 … ]}
```

### 取一个容器 {#get-one-container}

```
GET /api/v1/me/containers/{cid}
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID"
```

```json
{"container":{ … 那个容器对象 … },
 "images":[{"id":"debian-12","name":"Debian 12","size_bytes":124780544,"cached":true}],
 "allow_user_images":true,
 "can_own_image":true}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `images` | array | 这台主机能把它重装成什么，已经按 `allowed_images` 过滤过了 |
| `allow_user_images` | bool | 这台机器让不让你自己报一个仓库引用 |
| `can_own_image` | bool | 有没有一块私有盘来放它 |

### 开机、关机、重启 {#start-stop-or-restart}

```
POST /api/v1/me/containers/{cid}/power
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `action` | string | 请求体 | 是 | `start`、`stop` 或 `restart` |

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/power" \
  -H 'content-type: application/json' -d '{"action":"restart"}'
```

```json
{"ok":true,"message":"Done."}
```

关机是你自己的事，重新开机也是 —— 这是你的容器，
而一个「因为只有管理员才能关它、所以只好一直开着」的容器，
是在替它的主人白白付钱。停用是另一回事，那件事仍然归房东。

| 拒绝 | 意思 |
|---|---|
| `409 gone` | 这个容器已经被删了 |
| `409 expired` | 到期的容器只能关 |
| `409 suspended` | 房东把它停用了，只有他们能解 |
| `409 quota_exceeded` | 流量超了。窗口滚过去，或者额度调高，它就自己好了 |

**流量**这一种停用是你自己能解开的：数字允许了以后，`start` 会在同一个调用里
把这个停用一起解掉。

### 重启 {#restart}

```
POST /api/v1/me/containers/{cid}/restart
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |

和 `power` 带 `{"action":"restart"}` 是一回事，不用请求体，为最常见的那种情况准备的。

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/restart"
```

### 重装 {#rebuild}

```
POST /api/v1/me/containers/{cid}/reinstall
```

**认证**：会话

同一个容器上换一套干净的系统：id 不变，限额不变，shell 登录不变，域名不变。
`/` 会被换掉；容器有 `/data` 的话（`limits.data_bytes` 大于零）它会留下。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `confirm` | string | 请求体 | 是 | **容器自己的名字**，不是 `"yes"` |
| `image_id` | string | 请求体 | 四选一 | 一个目录 id —— `GET /catalog` |
| `digest` | string | 请求体 | 四选一 | 那台主机上已经有的一个镜像 |
| `ref` | string | 请求体 | 四选一 | 一个仓库引用，主机先去拉。这次下载算你的流量 |
| `archive` | string | 请求体 | 四选一 | 主机镜像目录里的一个文件 —— [列出本地镜像文件](#list-image-archives) |

`image_id`、`digest`、`ref`、`archive` 恰好填一个。主机设了 `allowed_images` 的话，
持有者受它约束；`ref` 还需要 `allow_user_images`。

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/reinstall" \
  -H 'content-type: application/json' \
  -d '{"image_id":"debian-12","confirm":"web"}'
```

```json
{"container":{ … 那条容器记录 … },
 "message":"Reinstalled from Debian 12. /data kept."}
```

`confirm` 写错是一个 `400`，而且它会告诉你该写什么。其他的拒绝：
`409 expired`、`409 suspended`、`409 gone`。

这个调用在机器干完之前就返回了。用下一个接口轮询。

### 看重装进度 {#watch-a-rebuild}

```
GET /api/v1/me/containers/{cid}/progress
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |

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

| 字段 | 类型 | 说明 |
|---|---|---|
| `kind` | string | 正在发生什么 —— `reinstall`、`pull`、`create` |
| `key` | string | 发生在哪个容器 id 上 |
| `step`、`index`、`steps` | | 走到序列的哪一步了，以及整个序列是什么 |
| `bytes`、`bytes_total` | int | 下载进度。什么都没在拉的时候 `bytes_total` 是 0 |
| `done` | bool | 完了。失败时 `err` 里是原因 |

只有这个容器的操作 —— 别人的那些，键是别的租户的容器名和镜像引用。
空的表示没有事情在进行中。机器失联时它答的是
`{"operations":[],"unreachable":true}`，而不是报错。

判断做完了，最简单的办法是看容器自己的 `live.run_state` 回到
`running`；[现成的做法](#recipes)里就是这么干的。

### 读流量表 {#read-the-traffic-meter}

两种不同的读法，大多数脚本两个都要。

**离额度还有多远**，在容器自己身上，不用多一个调用：

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID" \
  | jq '.container.container | {used: (.net_usage.rx_bytes + .net_usage.tx_bytes),
                                quota: .limits.net_quota_bytes,
                                since: .net_usage.window_start}'
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `net_usage.window_start` | string | 当前窗口是什么时候开的。哪一天由你的房东挑 |
| `net_usage.rx_bytes` | int | 这个窗口进来的 |
| `net_usage.tx_bytes` | int | 这个窗口出去的 |
| `limits.net_quota_bytes` | int | 两个方向都算进去。0 表示不限流量 |

到 100% 时容器会被**停用**，不是删掉，`suspend_reason` 是 `quota`。
窗口滚过去，或者额度调高，它就回来了。

**它随时间的形状**，是用量序列：

```
GET /api/v1/me/containers/{cid}/usage
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `since` | string | 查询参数 | 否 | 一个 Go duration（`24h`、`168h`）或者一个 RFC 3339 时间戳。不填就是留存的全部。**天不是一个单位** —— 写 `168h`，不要写 `7d` |

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID/usage?since=24h"
```

```json
{"points":[{"ts":"2026-08-20T06:10:00Z","cid":"a1b2c3d4e5f6","cpu_pct":2.4,
            "mem_bytes":712500000,"disk_bytes":4294967296,
            "rx_delta":18874368,"tx_delta":5242880}]}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `ts` | string | 这个点的时间 |
| `cpu_pct` | float | 占容器自己那份额度的百分比 |
| `mem_bytes`、`disk_bytes` | int | 那一刻的值 |
| `rx_delta`、`tx_delta` | int | **相对上一个点**新增的字节，不是累计值 |

要一段时间的量就把 delta 加起来，要这个月的就读 `net_usage`。

### 重置 shell 登录 {#reset-the-shell-login}

```
POST /api/v1/me/containers/{cid}/credentials
```

**认证**：会话

SSH 问你要的那个登录。它属于机器上的网关，不属于容器里的 `/etc/shadow` ——
这就是为什么它是一个面板调用，也是为什么重装不会把它弄丢。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `ssh_password` | string | 请求体 | 否 | **不填就生成一个强的** —— 脚本通常就该这么做。要自己设的话：至少 6 个字符，字母、数字、标点里占两类 |
| `ssh_username` | string | 请求体 | 否 | 顺便把登录名也改了。小写字母、数字、横线、下划线；2–31 个字符，以字母开头 |

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

**「只显示一次」是字面意思。** 面板从不保存 shell 密码：它去到机器上，
再进到这个应答里，别的地方哪儿都没有。在发起这个请求的那一步就把它接住 ——
没有任何接口能把它读回来。

### 列出本地镜像文件 {#list-image-archives}

```
GET /api/v1/me/containers/{cid}/archives
```

**认证**：会话

运维手工放到机器上的镜像文件 —— 一台网络扛不动 200 MB 拉取的主机，
拿这个来顶。这里的一个文件名，可以填到重装的 `archive` 里。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |

```json
{"sideload":{"dir":"/srv/hqnode/images",
             "files":[{"name":"debian-12.tar","size_bytes":124780544,
                       "modified_at":"2026-07-02T11:00:00Z"}]}}
```

失联的机器答的是 `200`、一个空列表加一个 `error` 字段，而不是一个失败 ——
别的重装方式还是能用的。

### 兑换分享码 {#redeem-a-share-code}

```
POST /api/v1/me/containers/bind
```

**认证**：会话

一步把一个容器接过来：你的账号成为它的持有者，shell 凭据被重写成只有你知道的。
之前的持有者或者管理员设过的东西全部作废 —— 绑定就是这个意思。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `code` | string | 请求体 | 是 | 分享码。不区分大小写 |
| `ssh_password` | string | 请求体 | 否 | 不填就生成一个 |
| `ssh_username` | string | 请求体 | 否 | 不填就沿用它现在的名字 |

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

码不认识、已经用过或者过期了，都是 `400`。

### 把容器转给别人 {#hand-a-container-to-somebody-else}

```
POST /api/v1/me/containers/{cid}/bind
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `username` | string | 请求体 | 是 | 一个**已经存在**的账号。造用户名是机器主人的权力 |

```json
{"ok":true,
 "message":"alice holds web now. Your shell login still works until they or the host reset it."}
```

没有这个账号就是 `404 no_such_user`。容器里面什么都不动：
变的是归属关系，shell 登录由他们自己去重置。

### 把容器交回去 {#give-a-container-back}

```
DELETE /api/v1/me/containers/{cid}/bind
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |

什么都不会被删。它回到机器上「没人持有」的状态，等房东再分配。

---

## 域名与路由接口 {#domain-and-routing-endpoints}

域名是你网络那部分里唯一一件你自己管的事。一个名字不花机器什么 ——
所有名字共用同一个 80 和 443，靠请求里的名字分派 ——
所以没有什么要配给的，也不用问谁。

把 DNS 指到机器上是你在域名服务商那边自己做的事；要指的那个地址是下面的 `host_ip`。

### 列出域名 {#list-domains}

```
GET /api/v1/me/containers/{cid}/domains
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |

```json
{"domains":[{"domain":"example.com"}],"max":10}
```

### 加一个域名 {#add-a-domain}

```
POST /api/v1/me/containers/{cid}/domains
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `domain` | string | 请求体 | 是 | 一个主机名。会被规范成小写，不带协议，不带结尾的点 |

```sh
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/domains" \
  -H 'content-type: application/json' -d '{"domain":"example.com"}'
```

答的是整个列表，所以不用再来一次调用。在这里加的名字，
一开始是把 HTTP 和 HTTPS 送到容器里的 80 端口；要改就用下面的**保存一条路由**。

| 拒绝 | 意思 |
|---|---|
| `409 too_many_domains` | 到了这台机器的上限。删一个 |
| `409 domain_taken` | 那台机器上另一个容器已经在服务它 |
| `409 unavailable` | 容器已到期或已停用 |

加一个你已经有的名字不算错 —— 它就答那个列表。

### 删一个域名 {#remove-a-domain}

```
DELETE /api/v1/me/containers/{cid}/domains/{domain}
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `domain` | string | 路径 | 是 | 那个名字，要 URL 编码 |

答的是剩下的列表。

### 列出路由 {#list-routes}

```
GET /api/v1/me/containers/{cid}/routes
```

**认证**：会话

你每个名字实际上在干什么。名字的列表是面板的；
这里其余的东西每次都从机器上读，因为决定包往哪走的那一份，在机器上。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |

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

| 字段 | 类型 | 说明 |
|---|---|---|
| `mode` | string | `both`、`http`、`tls`、`none` —— 由那两个开关推出来 |
| `tls_mode` | string | `managed`（机器持有证书）或 `sni`（字节原样穿过去；你的私钥不出容器） |
| `checks.*.state` | string | 每个徽标背后主机缓存的答案 |
| `host_ip` | string | 你的 DNS 记录要指到哪儿 |
| `host_online` | bool | `false` 不是错误：名字都是真的，只是这会儿改不了 |
| `managed_available` | bool | 机器的 TLS 监听离开了 443 就是 false —— 挑战是从 443 进来的 |

### 保存一条路由 {#save-a-route}

```
PUT /api/v1/me/containers/{cid}/routes/{domain}
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `domain` | string | 路径 | 是 | 这个容器已经有的一个名字 |
| `http.enabled` | bool | 请求体 | 是 | 提供明文 HTTP |
| `http.port` | int | 请求体 | 是 | 它进到容器的哪个端口。1–65535 |
| `https.enabled` | bool | 请求体 | 是 | 提供 HTTPS |
| `https.mode` | string | 请求体 | 否 | `managed` 或 `sni`。默认 `sni` |
| `https.port` | int | 请求体 | 是 | HTTPS 进到容器的哪个端口。**`managed` 下会被忽略** —— 机器自己终结 TLS，再把明文转给 `http.port` |
| `compress` | string | 请求体 | 否 | `on`、`off`，或者 `""` 表示随主机的默认 |
| `proxy_protocol` | bool | 请求体 | 否 | 前面加一个 PROXY 头，好让你的服务看到真实的客户端 IP |

```sh
curl -sS -b jar.txt -X PUT "$PANEL/me/containers/$CID/routes/example.com" \
  -H 'content-type: application/json' \
  -d '{"http":{"enabled":true,"port":8080},
       "https":{"enabled":true,"mode":"managed","port":443},
       "compress":"on","proxy_protocol":false}'
```

```json
{"route":{ … 上面那个路由视图 … }}
```

两个开关都关掉，这个名字还列在那里，但什么都不应答。
名字不是这个容器的就是 `404` —— 先把它加上。

### 检查一个域名 {#probe-a-name}

```
POST /api/v1/me/containers/{cid}/routes/{domain}/probe
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `domain` | string | 路径 | 是 | |
| `checks` | array | 请求体 | 否 | `dns`、`http`、`https` 里的任意几个。默认三个都查 |
| `force` | bool | 请求体 | 否 | 现在就去拨一次，而不是拿主机缓存里的答案 |

容器、以及拿来跟 DNS 比对的那些地址，是面板自己填的，不是你填的 ——
一个能指名另一个容器的请求体，就是一次带着会话 cookie 的端口扫描。

```json
{"dns":{"state":"ok","addresses":["203.0.113.10"],"expected":["203.0.113.10"]},
 "http":{"state":"ok","status":200,"took_ms":14},
 "https":{"state":"ok","days_left":74}}
```

### 申请证书 {#request-a-certificate}

```
POST /api/v1/me/containers/{cid}/routes/{domain}/certificate
```

**认证**：会话 · **参数**：路径里的 `cid`、`domain`

只对 `tls_mode` 是 `managed` 的名字有效，否则 `409 not_managed`。
机器平时会自己去签、自己去续 —— 这个是「我现在就要」的那个按钮。

```json
{"cert":{"state":"pending","issued_7d":1,"failed_1h":0}}
```

`202`。Let's Encrypt 对一个名字一周只发五张证书，所以一个会把最后一张用掉的申请，
在真的发出去**之前**就被拒了，请求体里带 `next_manual_at`，应答头上带 `Retry-After`。

---

## 端口接口 {#port-endpoints}

公网端口是机器自己地址上的一个号码，连过去就直接进到某一个容器里 ——
`203.0.113.10:31000` 落到你盒子里的 3000 端口上。
它适合游戏服务器、数据库、VPN；网站要的是域名。

**你读它们、测它们。开它们的是你的房东。** 一个域名不花机器什么，
但 `31000` 就是一个，只能给一个容器，两个租户都想要它，就是一件得有人来定的事。
所以 `/me/containers/{cid}/ports` 下面没有 `POST` 也没有 `DELETE` ——
这不是某个处理函数里的一次权限检查，而是这些路由压根没注册过，
所以往那里写，得到的是路由器给的一个 404。[公网端口](ports.md)是完整的说法；
开一个在主机那一侧，是[开一个公网端口](#open-a-public-port)。

### 列出公网端口 {#list-public-ports}

```
GET /api/v1/me/containers/{cid}/ports
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |

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

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | `proto-container-bind`，仅本机可达的映射是 `proto-container`。检查路径里的 `{id}` 就是它 |
| `public` | int | 互联网够到的那个号码。只有 `public_facing` 时才有 |
| `host` | int | 容器私有 loopback 上的号码。另外那一种情况 |
| `count` | int | 连续覆盖了几个端口。没有或者是 1 就是一个 |
| `live` | bool | 这会儿真占着。`false` 是对一条等着下次启动的映射的老实说法 |
| `check` | object | 最后一次检查：`ok`、`closed`、`unpublished`、`error`、`untested` |
| `used_by` | object | 一条仅本机可达的映射为什么关不掉：一个 `domain`，或者 SSH `gateway` |
| `can_edit` | bool | 在这条路径上永远是 `false`。对机器的主人才是 `true` |

关于机器内部的四个字段 —— `public_range`、`private_range`、`public_max_span`
和 `holder` —— 在主人那一份应答里有，这里是故意不给的。

### 测一个端口 {#probe-a-port}

```
POST /api/v1/me/containers/{cid}/ports/{id}/probe
```

**认证**：会话

到底有没有东西在听？它拨一次这个端口，什么都不改。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `cid` | string | 路径 | 是 | 容器 id |
| `id` | string | 路径 | 是 | 上面列表里的一个映射 id，比如 `tcp-3000-0.0.0.0` |

```json
{"state":"ok","took_ms":3,"port":3000,"checked_at":"2026-08-20T06:41:00Z"}
```

UDP 直接答 `untested`，不去拨 —— 一个 UDP 端口不出声，什么也说明不了。

---

## 主机侧接口 {#hosting-endpoints}

这套 API 的另一半：你自己的机器，以及上面的每一个容器。
同一个 cookie，同一个基地址。`{mid}` 是机器 id。

[容器接口](#container-endpoints)里的每一个，这里都有一个孪生的 —— 开关机、重装、
用量、凭据 —— 在 `/machines/{mid}/containers/{cid}/…` 下面，请求体一模一样。
下面写的是只有主人才能做的事。

[重装](#rebuild)的孪生版有两处不同，两处都是因为调用者拥有这台机器：
`allowed_images` 和 `allow_user_images` 不对它生效 ——
不管主机对持有者的策略怎么写，你自己的 `ref` 都能用 ——
以及，一个机器上已经没有了的容器，是被重新造出来而不是重装，
造是 create，所以它收 `image_id`、`digest` 或 `archive`，但绝不收 `ref`。

### 列出你的机器 {#list-your-machines}

```
GET /api/v1/machines
```

**认证**：会话 · **参数**：无

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
  "containers":[ … 完整的容器记录 … ],
  "link":{"connected":true,"token_sealed":true}}]}
```

`link.connected` 是 websocket **此刻**通不通；`cache.status` 是上一次轮询得出的结论。
要判断「我现在能不能对这台机器动手」，看前一个。

### 取一台机器 {#get-one-machine}

```
GET /api/v1/machines/{mid}
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `mid` | string | 路径 | 是 | 机器 id |

```json
{"machine":{ … 同上 … },
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

`psi_cpu_avg60` 是超售的那个表盘：长期在 25% 上下以上，
就说明租户在排队等 CPU，机器也会开始自己拒绝新容器。

`host_live` 是你问的时候现从机器上读的。失联的机器会把 `host_error` 填上，
并且仍然答 `200` —— 那是关于机器的一个事实，不是一次失败的请求。

### 创建容器 {#create-a-container}

```
POST /api/v1/machines/{mid}/containers
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `mid` | string | 路径 | 是 | 机器 id |
| `name` | string | 请求体 | 是 | 小写字母、数字和横线，2–31 个字符。在那台机器上唯一 |
| `image_id` | string | 请求体 | 二选一 | 一个目录 id |
| `archive` | string | 请求体 | 二选一 | 改用机器镜像目录里的一个文件 |
| `username` | string | 请求体 | 否 | 直接交给这个账号，需要的话把账号建出来。不填的话你拿到的是一个分享码 |
| `email` | string | 请求体 | 否 | 只有在要建那个账号时才用得上 |
| `ssh_username` | string | 请求体 | 否 | 网关登录名。不填就生成 |
| `ssh_password` | string | 请求体 | 否 | 不填就生成。至少 6 个字符，两类字符 |
| `limits` | object | 请求体 | 否 | 不写的字段取机器的默认值 |
| `limits.cpu_cores` | float | 请求体 | 否 | 比如 `0.5`、`2` |
| `limits.cpu_idle` | bool | 请求体 | 否 | 批处理档：只用剩下的算力 |
| `limits.mem_bytes` | int | 请求体 | 否 | 字节 |
| `limits.swap_bytes` | int | 请求体 | 否 | 字节。`0` 表示没有 —— 撞到内存墙就被杀 |
| `limits.reserve_bytes` | int | 请求体 | 否 | 内核不会回收到这个数以下。默认是内存的一半 |
| `limits.disk_bytes` | int | 请求体 | 否 | 字节。`0` 表示跟主机文件系统共用 |
| `limits.data_bytes` | int | 请求体 | 否 | 一块能熬过重装的 `/data` 盘，多少字节 |
| `limits.net_quota_bytes` | int | 请求体 | 否 | 每个窗口多少字节，两个方向都算 |
| `ports` | array | 请求体 | 否 | 创建时就发布出去的容器端口 |
| `domains` | array | 请求体 | 否 | 第一天就路由到这里的名字 |
| `expires_at` | string | 请求体 | 否 | 一个日期（`2026-12-31`）或者一个 RFC 3339 时间戳。不填取机器的默认；`""` 表示永不到期 |
| `allowed_images` | array | 请求体 | 否 | 持有者能重装成哪些目录 id。不填就是整个目录 |

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

`201`：

```json
{"container":{"cid":"a1b2c3d4e5f6","name":"web","state":"active", … },
 "machine_id":"mch_1a2b3c4d",
 "credentials":{"ssh_username":"u7k2m9p","ssh_password":"…",
                "ssh":"ssh u7k2m9p@hk-1.example.com -p 22"},
 "share_code":"K4M7PQR2",
 "share_url":"https://hqno.de/containers/redeem?code=K4M7PQR2",
 "share_expires_at":"2026-08-27T06:39:00Z"}
```

**密码和分享码都只显示一次。** 这个应答是它们唯一的一份；没有接口能把它们读回来。
分享码只有在 `username` 没填时才出现 —— 没人持有它，那把交出去的钥匙就跟着它一起来。

一台机器能扛多少容器，是**机器**的答案，不是面板里的一个数字：
主机按真实的内存和 CPU 压力来拒绝一次创建，并且说出原因。
面板管的上限是你的账号 —— `402 limit_reached`。

| 拒绝 | 意思 |
|---|---|
| `409 name_taken` | 那台机器上有一个同名的容器 |
| `402 limit_reached` | 你账号能拿的容器数用完了 |
| `409 machine_offline` | 一个还不存在的用户名，没法由一台没上报过的机器造出来 |
| `502 agent_unreachable` | 那台机器不应答 |

### 改限额、到期、名字或状态 {#change-limits-expiry-name-or-state}

```
PATCH /api/v1/machines/{mid}/containers/{cid}
```

**认证**：会话

只有你发过去的字段会变。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `mid`、`cid` | string | 路径 | 是 | |
| `limits` | object | 请求体 | 否 | 和创建时一样的形状。不写的字段保持原值 |
| `expires_at` | string | 请求体 | 否 | 三态：不写就不动，一个日期就挪过去，`""` 就取消到期 |
| `name` | string | 请求体 | 否 | 改名。规则和创建时一样 |
| `state` | string | 请求体 | 否 | `active` 或 `suspended` |
| `allowed_images` | array | 请求体 | 否 | |
| `domains` | array | 请求体 | 否 | 整个替换掉那个列表 |

```sh
curl -sS -b jar.txt -X PATCH "$PANEL/machines/$MID/containers/$CID" \
  -H 'content-type: application/json' \
  -d '{"limits":{"mem_bytes":4294967296},"expires_at":"2027-06-30"}'
```

给一个到期的容器续期，就是这个调用 —— 把 `expires_at` 往后挪，它就直接回来了，
盘还是那块盘，登录还是那个登录。

### 删除容器 {#delete-a-container}

```
DELETE /api/v1/machines/{mid}/containers/{cid}
```

**认证**：会话

唯一一个会毁掉数据的调用。到期从不删东西，别的也都不删。

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `mid`、`cid` | string | 路径 | 是 | |
| `confirm` | string | 请求体 | 是 | **容器自己的名字** |
| `force` | bool | 请求体 | 否 | 机器没应答时，把面板里的记录删掉。容器本身不动，可能还在跑 |

```sh
curl -sS -b jar.txt -X DELETE "$PANEL/machines/$MID/containers/$CID" \
  -H 'content-type: application/json' -d '{"confirm":"web"}'
```

```json
{"ok":true,"warning":""}
```

### 把容器绑给一个账号 {#bind-a-container-to-an-account}

```
POST /api/v1/machines/{mid}/containers/{cid}/bind
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `mid`、`cid` | string | 路径 | 是 | |
| `username` | string | 请求体 | 是 | **不存在就建出来** —— 这是唯一一个会造用户名的地方。需要一台上报过的机器 |
| `email` | string | 请求体 | 否 | 只有在建这个账号时才用得上 |

这样建出来的账号还没有密码；它的主人拿那个邮箱走**忘记密码**。
同一条路径上的 `DELETE` 是解绑 —— 容器还在，里面什么都不动。

### 生成分享码 {#mint-a-share-code}

```
POST /api/v1/machines/{mid}/containers/{cid}/bind-code
```

**认证**：会话 · **参数**：路径里的 `mid`、`cid`

给一个没人持有的容器用。谁兑换了它，谁就成为持有者，并设定 shell 登录。

```json
{"code":"K4M7PQR2","expires_at":"2026-08-27T06:39:00Z",
 "redeem_url":"https://hqno.de/containers/redeem?code=K4M7PQR2",
 "container":{"cid":"a1b2c3d4e5f6","name":"web","machine":"hk-1"}}
```

`201`，而且**只显示一次** —— 存下来的只有哈希。同一条路径上的 `GET`
会把这个容器已经有的那个码交回来，而不是再生成第二个。已经有持有者就是 `400`。

### 重置某个容器的 shell 登录 {#reset-a-containers-shell-login}

```
POST /api/v1/machines/{mid}/containers/{cid}/credentials
```

**认证**：会话

[重置 shell 登录](#reset-the-shell-login)在主人这一侧的版本，同样的请求体，
同样只显示一次的应答。管理员就是这样把一个密码丢了的容器救回来的。

### 开一个公网端口 {#open-a-public-port}

```
POST /api/v1/machines/{mid}/containers/{cid}/ports
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `mid`、`cid` | string | 路径 | 是 | |
| `container` | int | 请求体 | 是 | 容器里面的那个端口。1–65535 |
| `proto` | string | 请求体 | 否 | `tcp` 或 `udp`。默认 `tcp` |
| `public` | int | 请求体 | 否 | 外面那个号码：1024–65535。**不填或者填 `0`，主机就挑一个空的**，并告诉你是哪个 |
| `count` | int | 请求体 | 否 | 连续几个端口，最多 4096 个。`public+i → container+i` |
| `apply` | string | 请求体 | 否 | `now`（默认）或 `next_start`。`now` 会重启这个容器的网络，正在跑的连接会断 |

```sh
curl -sS -b jar.txt -X POST "$PANEL/machines/$MID/containers/$CID/ports" \
  -H 'content-type: application/json' -d '{"proto":"tcp","container":3000}'
```

答的是整个端口列表，跟 `GET` 一样，真的有东西重启了的话再多一个 `notice`。

公网端口从 1024 起，因为绑更低的号码需要一个这个设计不打算要的 capability。
什么号码空着、什么号码在它的私有池里、一段最长能有多长，都由主机说了算 ——
这些会以 `409 port_taken`、`port_in_pool`、`span_too_large`、`port_overlap`
或 `no_free_port` 回来，每一个都在字段里、也在那句话里说出具体的号码。

### 关一个公网端口 {#close-a-public-port}

```
DELETE /api/v1/machines/{mid}/containers/{cid}/ports/{id}
```

**认证**：会话

| 名字 | 类型 | 位置 | 必填 | 说明 |
|---|---|---|---|---|
| `mid`、`cid` | string | 路径 | 是 | |
| `id` | string | 路径 | 是 | 一个映射 id，比如 `tcp-3000-0.0.0.0` |
| `apply` | string | 查询参数 | 否 | `now`（默认）或 `next_start` |

`409 port_in_use` 会说出还在路由到它的那个域名。

### 其余机器接口 {#other-machine-endpoints}

这一页不写它们，因为它们讲的是怎么运营这台盒子，而不是容器：
`GET/POST /machines/{mid}/deps`、`/storage`、`/tuning`、`/ports`、
`/ports/sshd`、`/upgrade`、`/images`、`/progress`、
`PATCH /machines/{mid}/policy`、`DELETE /machines/{mid}`，以及接入。
它们遵守同样的约定。它们各自做什么，
[自己跑一台机器](running-a-machine.md)里有。

---

## 在容器里面 {#from-inside-the-container}

不要在你自己盒子里的 shell 上用上面任何一个。容器里没有面板凭据 ——
这是一个刻意的性质，不是疏忽 —— 而你会想要的那三件事，本来就已经在里面了：

| 命令 | 它做什么 |
|---|---|
| `dashboard` | 限额、用掉多少、流量还剩多少、到期、地址 |
| `app-setup domain add example.com` | 认领一个名字并把它路由到这里 |
| `passwd` | 改 shell 登录密码 |

它们走的是机器自己那条已经认证过的链路，通过一个 socket 到面板，
而你是哪个容器，是由「哪个监听端接下了这个连接」认出来的。
你敲什么都不可能指到另一个容器上，盒子里也没有任何秘密可偷。
见[使用你的容器](using-your-container.md)。

---

## 现成的做法 {#recipes}

### 一个 GitHub Actions 任务 {#a-github-actions-job}

重装一个容器，等它回来，没回来就让任务失败。

```yaml
name: rebuild
on: workflow_dispatch

jobs:
  rebuild:
    runs-on: ubuntu-latest
    env:
      PANEL: https://hqno.de/api/v1
      CID: a1b2c3d4e5f6
      NAME: web            # confirm 要等于它
    steps:
      - name: 登录
        run: |
          curl -sS --fail-with-body -c "$RUNNER_TEMP/jar" "$PANEL/auth/login" \
            -H 'content-type: application/json' \
            -d "$(jq -nc --arg u "${{ secrets.PANEL_USER }}" \
                         --arg p "${{ secrets.PANEL_PASSWORD }}" \
                         '{identifier:$u,password:$p}')" > /dev/null

      - name: 重装
        run: |
          curl -sS --fail-with-body -b "$RUNNER_TEMP/jar" \
            -X POST "$PANEL/me/containers/$CID/reinstall" \
            -H 'content-type: application/json' \
            -d "$(jq -nc --arg c "$NAME" '{image_id:"debian-12",confirm:$c}')"

      - name: 等它回来
        run: |
          for i in $(seq 1 60); do
            state=$(curl -sS -b "$RUNNER_TEMP/jar" "$PANEL/me/containers/$CID" \
                    | jq -r '.container.container.live.run_state')
            echo "run_state=$state"
            [ "$state" = "running" ] && exit 0
            sleep 10
          done
          echo "容器没有回来"; exit 1

      - name: 登出
        if: always()
        run: |
          curl -sS -b "$RUNNER_TEMP/jar" -X POST "$PANEL/auth/logout" > /dev/null
          rm -f "$RUNNER_TEMP/jar"
```

不管你的任务干什么，上面有四件事值得照抄：

- **`--fail-with-body`。** 光用 `curl`，遇到 409 也会退出 0，
  于是一个不看状态码的任务，会在一个根本没重启的容器上打出绿色的勾。
  这个参数会把面板那句话打出来，并让这一步失败。
- **用 `jq -nc` 拼 JSON**，这样一个带引号的密码不会变成一个坏掉的请求体，
  或者一次 shell 注入。
- **cookie jar 放在 `$RUNNER_TEMP` 里，最后删掉。**
  把密码存成 secret，永远不要存 cookie。
- **容忍 502。** `agent_unreachable` 是机器短暂失联，不是一次失败的部署。

### 部署完重启 {#restart-after-a-deploy}

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

### 流量到额度 80% 就报警 {#alert-at-80-of-the-traffic-quota}

```sh
curl -sS -b jar.txt "$PANEL/me/containers/$CID" | jq -e '
  .container.container
  | (.net_usage.rx_bytes + .net_usage.tx_bytes) as $used
  | .limits.net_quota_bytes as $quota
  | if $quota > 0 and $used / $quota > 0.8
    then "USED \($used) OF \($quota)" | halt_error(1)
    else empty end'
```

退出码 1 表示过线了。到 100% 容器会被停用 —— 是关掉，不是删掉 ——
窗口滚过去它就回来。

### 每月轮换 shell 密码 {#rotate-the-shell-password-monthly}

```sh
new=$(curl -sS --fail-with-body -b jar.txt \
  -X POST "$PANEL/me/containers/$CID/credentials" \
  -H 'content-type: application/json' -d '{}' \
  | jq -r '.credentials.ssh_password')

# 这是它唯一的一份。在这个脚本结束之前把它放到某个地方去。
printf '%s' "$new" | your-secret-store put hqnode/web/ssh
```

---

## 这一页不承诺什么 {#what-this-page-does-not-promise}

这是面板自己的 API，而面板和调用它的那个页面是一起发布的。`v1` 这个前缀没有变过形状，
上面这些调用也不会悄悄消失 —— 但这不是一份带着弃用政策的、厂商公开的契约。
按 `code` 分支，不要按 `message` 里的英文分支；脚本写短一点，
短到升级之后还能重读一遍；优先用[现成的做法](#recipes)里那些调用，
它们是面板自己的界面靠得最重的那几个。

没有 webhook，也没有事件流：自己轮询。也没有批量接口 —— 一次一个容器。
