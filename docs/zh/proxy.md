---
title: 跑一个代理或 VPN
---

# 跑一个代理或 VPN

一台机器上有二十个容器，共用一个地址。这一页讲外面来的连接怎么找到**你**那一个：
第 2、3 节是具体怎么加，第 5 到 7 节是为什么只能这么加。

其余的事 —— 你跑什么、怎么配、给谁用 —— 都在你自己的盒子里，是你的事。

（有一类东西在这里根本起不来：要自己建网卡、接管路由表的那一种。
不多，但如果你打算用，先跳到第 10 节，省一个下午。）

---

## 1. 先分清你要哪一种

<FigRows :arrow="0" :head="['它在线路上长什么样', '它怎么进来']" :rows="[
  [{ t: '一条普通的 TLS 连接', tone: 'strong' }, { t: '一个域名 —— 和机器上所有名字共用 443' }],
  [{ t: '一套自己的协议', tone: 'strong' }, { t: '一个公网端口 —— 一个号码，房东来开' }],
  [{ t: 'UDP，不管什么协议', tone: 'strong' }, { t: '一个公网端口 —— 同上' }],
]" />

两行底下是同一句话：**机器要把连接交给对的容器，
前提是这条连接明文告诉它，它是给谁的。** TLS 握手会说，别人自己设计的协议不会。

第一种自己加，第二、三种要向房东要。下面分别是怎么加。

---

## 2. 加一个域名（走 443 这条路）

**先把 DNS 指过来。** 在你的域名服务商那里加一条 A 记录，指向机器的地址。
地址在面板的容器页面上，也可以在容器里 `app-setup dashboard net` 里看。
这一步不做，后面全都白搭。

然后三条路，任选一条，做的是同一件事。

### 在容器里，一条命令

```sh
# 你自己在容器里终结 TLS —— 机器只拼接，私钥不出容器。
# 这是这一页要的那一种。8443 是你容器里监听的 TLS 端口。
app-setup domain add example.com 8443 self-hosted

# 不写 self-hosted 的话，默认是「机器替你签证书」，机器会解密。
# 8080 是你容器里监听的明文 HTTP 端口。
app-setup domain add example.com 8080

# 自己终结 TLS，同时 80 端口也转到容器的 8080（明文）
app-setup domain add example.com 8443 self-hosted 8080

app-setup domain ls                 # 现在有哪些名字
app-setup domain del example.com    # 不要了
```

**这条命令的默认值是反的，值得记一下**：不写 `self-hosted`，
你拿到的是「机器替你签证书并且解密」。走这一页的用途，`self-hosted` 得自己敲上去。
（面板界面和 API 那两条路的默认值相反，是 SNI 直通。第 7 节讲这个区别为什么要紧。）

泛域名写 `*.example.com`，只支持第一段。

### 在面板界面里

容器页面 → **域名** 卡片 → **添加域名**，填名字。
加完点名字那一行展开，里面是这些：

<FigScreen title="域名" :lines="[
  { cols: [{ f: 'example.com' }, { b: '添加域名' }] },
  [{ t: 'example.com', tone: 'strong' }],
  [{ k: '启用 HTTPS' }],
  { cols: [{ t: '你的证书 · SNI 直通', tone: 'ok' }, { f: '8443', note: '后端 HTTPS 端口' }] },
  { cols: [{ t: '我们的证书 · 替你签发', tone: 'mute' }, { f: '8080', note: '转发到 HTTP 端口' }] },
  [{ k: '启用 HTTP' }],
]" />

两个模式是一对单选。选**你的证书 · SNI 直通**，
填的是你容器里那个 TLS 端口。在这里新加的名字，默认就是这一个。

### 用 API

```sh
# 认领名字
curl -sS -b jar.txt -X POST "$PANEL/me/containers/$CID/domains" \
  -H 'content-type: application/json' -d '{"domain":"example.com"}'

# 配这个名字怎么走。mode 不填就是 sni。
curl -sS -b jar.txt -X PUT "$PANEL/me/containers/$CID/routes/example.com" \
  -H 'content-type: application/json' \
  -d '{"http":{"enabled":false,"port":80},
       "https":{"enabled":true,"mode":"sni","port":8443}}'
```

完整参考在[面板 REST API](api.md)。

---

## 3. 要一个公网端口（走号码这条路）

**这个你自己开不了**，而且不是权限没给到位：`/me/containers/{cid}/ports`
下面根本没有注册 `POST` 和 `DELETE`，写过去拿到的是路由器给的 404。
为什么是这样，第 6 节讲。

### 你这一侧：去要，然后确认

跟房东说两件事就够了：

- 你的服务在**容器里**监听哪个端口（`7777`、`51820`，随便多少）
- **TCP 还是 UDP**

外面那个号码由他们挑，你不用指定 —— 除非外面已经有东西认死了某个号码
（已经发出去的客户端配置、一条 DNS SRV 记录），那就说清楚要哪个。

开好之后，在容器页面的**端口**卡片上看，或者在容器里：

```sh
app-setup dashboard ports
```

卡片分两段。你要的那条在**来自互联网**下面，
左边是你发给别人的地址，右边的 `:3000` 是容器里必须有东西在听的端口。

### 房东那一侧：一个按钮

容器页面 → **端口** → **开一个端口**：

<FigScreen title="开一个端口" :lines="[
  { cols: [{ t: '容器端口', face: 'small', tone: 'mute' }, { t: '公网端口', face: 'small', tone: 'mute' }, { t: '协议', face: 'small', tone: 'mute' }] },
  { cols: [{ f: '7777' }, { f: '自动', note: '留空 = 自动挑一个' }, { f: 'tcp' }] },
  { cols: [{ b: '保存' }, { b: '保存并应用' }, { b: '取消' }] },
]" />

或者一个调用：

```sh
curl -sS -b jar.txt -X POST "$PANEL/machines/$MID/containers/$CID/ports" \
  -H 'content-type: application/json' -d '{"proto":"tcp","container":7777}'
```

**那两个保存按钮是有区别的**，而且区别落在别人身上。**保存并应用**会立刻重启这个
容器的网络：大约半秒，但那半秒里走这个容器**其他**端口的连接会断 ——
包括租户正开着的 SSH。**保存**只把映射记下来，什么都不打断，容器下次重启时生效。
API 上这就是 `apply` 的 `now` 和 `next_start`。

还有一件在面板里看不出来的事：**机器上开了号码，不等于云厂商的安全组放行了。**
把整个池子一次放开（没改过的话是 `30000–32767`，TCP 和 UDP），
以后就不用再想。不放的话，面板上一切正常，卡片写着生效中，而外面连不上。

[公网端口](ports.md)是这件事的完整版。

---

## 4. 整条路，以及这一页管到哪儿

<svg class="fig" viewBox="0 0 660 186" role="img" aria-label="一条连接的整条路：访客到机器，机器按名字或按号码送进你的容器，容器里你跑的程序再连出去到互联网上的目标">
  <defs><marker id="px5" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="14" y="20">一条连接的整条路</text>
  <rect class="box" x="14" y="42" width="96" height="62" rx="4"/>
  <text class="c" x="62" y="79">访客</text>
  <path class="ln" d="M110,73 H136" marker-end="url(#px5)"/>
  <rect class="box" x="144" y="42" width="164" height="62" rx="4"/>
  <text class="t c" x="226" y="64">机器</text>
  <text class="s c" x="226" y="84">:443 → 按名字</text>
  <text class="s c" x="226" y="100">:31000 → 按号码</text>
  <path class="ln" d="M308,73 H334" marker-end="url(#px5)"/>
  <rect class="mine" x="342" y="42" width="156" height="62" rx="4"/>
  <text class="t c" x="420" y="66">你的容器</text>
  <text class="s c" x="420" y="87">你跑的那个程序</text>
  <path class="lnA" d="M498,73 H524" marker-end="url(#px5)"/>
  <rect class="box" x="532" y="42" width="114" height="62" rx="4"/>
  <text class="c" x="589" y="68">互联网上的</text>
  <text class="c" x="589" y="88">目标</text>
  <path class="rule" d="M336,118 V160"/>
  <text class="s c" x="175" y="142">第 1–3 节：机器把连接送到你门口</text>
  <text class="s c" x="495" y="142">从这里往右：容器里面，你自己的事</text>
</svg>

左边那两段是第 1 到 3 节讲的：机器按名字、或者按号码，
把连接送到你容器的门口。到这里为止是面板和机器的事，
而且只有这一段有「只能这么做」的规矩。

**从容器门口往里，是你自己的事。** 里面跑什么程序、怎么配它、
怎么让它开机自己起来 —— 这一页不写，也不推荐任何软件。

两个原因都挺实在：这类东西版本换得快，配置写下来过几个月就过期了；
而且选哪一个、怎么用，取决于你的用途，以及你要守的规矩（第 11 节）。

真要做，三条路随便走：翻那个软件自己的文档，问 AI，
或者就在容器里自己试 —— 这是一整台 Linux，你是 root，
装什么都行（除了第 10 节那一类）。

跟容器里的**系统**有关的那部分，这个站上是有的：
[使用 Alpine](alpine.md) 和 [使用 Debian](debian.md) 讲装包、
让程序开机自启、看日志、查内存 —— 不管你最后跑的是什么，这几件事都得用上。

---

## 5. 名字是怎么被分开的

一条 TLS 连接的**开头有一小段是明文的**，里面写着客户端要找的服务器名字。

<svg class="fig" viewBox="0 0 660 168" role="img" aria-label="一条 TLS 连接：开头一小段是明文的服务器名字，之后全部加密，机器只读开头那一段">
  <defs><marker id="px1" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="20" y="22">一条 TLS 连接，从左往右</text>
  <rect class="mine" x="20" y="40" width="180" height="40" rx="4"/>
  <rect class="box" x="208" y="40" width="432" height="40" rx="4"/>
  <text class="m a c" x="110" y="65">example.com</text>
  <text class="c" x="424" y="65">之后的每一个字节都是加密的</text>
  <text class="s c" x="110" y="100">明文 —— 只有这一小段</text>
  <text class="s c" x="424" y="100">机器照搬，不解密，也没有钥匙</text>
  <path class="lnA" d="M110,140 V108" marker-end="url(#px1)"/>
  <text class="t c" x="110" y="160">机器只看这里</text>
</svg>

**为什么它必须是明文**：服务器这时候还没把证书拿出来，
而不知道对方要哪个名字，它就不知道该拿哪一张。所以名字得先说，加密在后面。

机器读的就是这一个字段。读完去查域名表，查到是哪个容器，
接下来它就只做一件事：把字节从这头搬到那头，两个方向，直到有一头挂断。

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="三个域名进到机器同一个 443 端口，机器按名字查表，分别送到三个容器">
  <defs><marker id="px2" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="20" y="20">一千个名字，共用同一个 443</text>
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
  <text class="t c" x="330" y="88">机器</text>
  <text class="s c" x="330" y="110">一个地址，一个 :443</text>
  <text class="s c" x="330" y="130">读名字 → 查表</text>
  <path class="ln" d="M406,103 C434,103 434,55 462,55" marker-end="url(#px2)"/>
  <path class="lnA" d="M406,103 H462" marker-end="url(#px2)"/>
  <path class="ln" d="M406,103 C434,103 434,151 462,151" marker-end="url(#px2)"/>
  <rect class="box" x="470" y="38" width="170" height="34" rx="4"/>
  <rect class="mine" x="470" y="86" width="170" height="34" rx="4"/>
  <rect class="box" x="470" y="134" width="170" height="34" rx="4"/>
  <text class="c" x="555" y="60">别人的容器</text>
  <text class="c" x="555" y="108">你的容器</text>
  <text class="c" x="555" y="156">别人的容器</text>
  <text class="s" x="20" y="192">做分流的是名字，不是号码 —— 所以域名你自己加，不用问谁</text>
</svg>

由此三件事：

- **一千个名字共用一个 443。** 名字不花机器什么，所以第 2 节里你自己就能加。
- **机器手上没有钥匙。** 它没解密过，也就不存在「它本可以看到」的那一刻。
  证书在你的容器里 —— 前提是模式选对了，见第 7 节。
- **名字得能解析到这台机器。** 这就是第 2 节第一句话说的那条 A 记录。

80 端口是同一件事，只是名字在 HTTP 的 `Host` 头里，查的是同一张表。

---

## 6. 为什么自己的协议要占一个号码

一条连接进来，机器得决定它是给哪个容器的 ——
而且得在还不知道这些字节是什么意思**之前**就决定。

443 上有名字可读。换成一套别人自己设计的协议，开头是什么全看作者当初怎么定：
机器不认识，也不可能认识，靠猜不能算设计。

于是只剩唯一一样它已经知道的东西：**这条连接敲的是哪个号码。**

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="左边走域名：机器读得到名字所以能查表；右边走自己的协议：机器读不到内容，只知道连接敲的是哪个号码">
  <defs><marker id="px3" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t c" x="165" y="20">走域名</text>
  <text class="t c" x="495" y="20">走自己的协议，或者 UDP</text>
  <path class="rule" d="M330,30 V186"/>
  <rect class="mine" x="30" y="40" width="86" height="34" rx="4"/>
  <rect class="box" x="120" y="40" width="180" height="34" rx="4"/>
  <text class="s c" x="73" y="61">名字</text>
  <text class="s c" x="210" y="61">加密的内容</text>
  <text class="c" x="165" y="98">机器读得到 → 查表</text>
  <path class="lnA" d="M165,108 V128" marker-end="url(#px3)"/>
  <rect class="mine" x="85" y="134" width="160" height="34" rx="4"/>
  <text class="c" x="165" y="156">你的容器</text>
  <text class="s c" x="165" y="188">不占机器的号码</text>
  <rect class="box" x="360" y="40" width="270" height="34" rx="4"/>
  <text class="s c" x="495" y="61">机器不认识这些字节</text>
  <text class="c" x="495" y="98">它唯一知道的是号码</text>
  <path class="lnA" d="M495,108 V128" marker-end="url(#px3)"/>
  <text class="m a" x="512" y="124">:31000</text>
  <rect class="mine" x="415" y="134" width="160" height="34" rx="4"/>
  <text class="c" x="495" y="156">你的容器</text>
  <text class="s c" x="495" y="188">一个号码，一个容器 —— 要向房东要</text>
</svg>

这就是公网端口：机器地址上的一个号码，事先接到一个容器上。

也正因为如此，第 3 节里这个按钮在房东手上。名字不花钱，所以没人限量；
号码在一台共用的机器上就那么一个，两个租户都要 `31000`，得有人来定。

**UDP 更彻底**：连握手都没有，也没有一个「机器有资格拆开看」的首包，
没有字段可读就没有东西可以分流。所以 UDP 一律要一个号码，不管它承载什么。
另外，面板上的**测试**按钮对 UDP 帮不了你 —— 一个后面什么都没有的 UDP 端口，
和一个好好工作着的，从外面看一模一样。用真正要用它的那个客户端去试。

---

## 7. 模式选错，前面全白做

第 2 节那两个模式的区别在这里。这是这一页唯一一个选错了「看上去还是好的」的地方。

<svg class="fig" viewBox="0 0 660 212" role="img" aria-label="SNI 直通模式下客户端到容器全程加密，机器只拼接字节；托管证书模式下机器持有钥匙、先解密，再把明文送进容器">
  <defs><marker id="px4" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="20" y="20">你的证书 · SNI 直通</text>
  <rect class="box" x="20" y="32" width="104" height="40" rx="4"/>
  <text class="c" x="72" y="57">客户端</text>
  <path class="ln" d="M124,52 H196" marker-end="url(#px4)"/>
  <text class="s c" x="160" y="44">加密</text>
  <rect class="box" x="204" y="32" width="176" height="40" rx="4"/>
  <text class="c" x="292" y="57">机器 · 只拼接</text>
  <path class="ln" d="M380,52 H452" marker-end="url(#px4)"/>
  <text class="s c" x="416" y="44">加密</text>
  <rect class="mine" x="460" y="32" width="180" height="40" rx="4"/>
  <text class="c" x="550" y="57">你的容器 · 钥匙在这</text>
  <text class="s" x="20" y="94">全程加密。机器没有钥匙，也就没有能读到的时刻。</text>
  <text class="t" x="20" y="134">我们的证书 · 替你签发</text>
  <rect class="box" x="20" y="146" width="104" height="40" rx="4"/>
  <text class="c" x="72" y="171">客户端</text>
  <path class="ln" d="M124,166 H196" marker-end="url(#px4)"/>
  <text class="s c" x="160" y="158">加密</text>
  <rect class="box" x="204" y="146" width="176" height="40" rx="4"/>
  <text class="c" x="292" y="171">机器 · 有钥匙，解密</text>
  <path class="lnA" d="M380,166 H452" marker-end="url(#px4)"/>
  <text class="s a c" x="416" y="158">明文</text>
  <rect class="box" x="460" y="146" width="180" height="40" rx="4"/>
  <text class="c" x="550" y="171">你的容器</text>
  <text class="s" x="20" y="208">机器替你签证书 —— 代价是它先解密。给网站够用，这个用途不是。</text>
</svg>

| 你在哪里加 | 不额外指定的话，你拿到的是 |
|---|---|
| `app-setup domain add <名字> <端口>` | **替你签发**（机器解密）。要直通就加 `self-hosted` |
| 面板界面 **域名** 卡片 | **你的证书 · SNI 直通** |
| API `PUT /routes/{domain}`，`https.mode` 不填 | **`sni`** |

三条路的默认值不一致，CLI 是反的那一个。选完回头在面板的域名卡片上看一眼，
那两个单选哪个亮着，就是实际生效的。

选了直通，证书就归你自己在容器里申请和续期，私钥一直待在容器里。

---

## 8. 两件会让人白花一个下午的事

- **绑 `0.0.0.0`，不要绑 `127.0.0.1`。** 上面两条路都是从容器自己的 loopback
  之外来找你的服务的。只监听 `127.0.0.1` 的服务，你 SSH 进去测它，它答；
  换成别人，谁都不答 —— 而这件事的症状看上去跟端口没开一模一样。
- **这些流量全都计费。** 替别人搬的流量也是流量，两个方向都算进配额，
  而且这一类服务恰恰是那种「你没在看的时候数字自己往上爬」的。
  在容器里 `app-setup dashboard net`，或者看容器页面。到 100% 容器会被**停用** ——
  是关掉，不是删掉 —— 窗口滚过去它就回来。

---

## 9. 这台机器能看到什么

这不是一句「我们不会那么做」的承诺，是数据通路的形状，你可以自己核对：

- 443 上选了 SNI 直通，机器不持有你这个名字的钥匙，
  也从来没有和你的客户端完成过一次握手。整条路径上不存在
  「你的流量以明文出现」的那一个点，所以没有东西可供审查。
- 公网端口就是一个号码接到一个号码，路径上没有任何东西去解析穿过它的内容。
- 流量表数的是两个方向各多少字节。它不知道那些字节是什么，别的组件也没在看。

hqnode 是一个虚拟化程序。它做的事是把一台机器切开、把每一份隔开、然后计数。
它不审查你搬运的内容，而在上面这两条路径上，它也没有能力审查。

关于这一点有两条老实话，不说这一页就是在推销东西：

- 上面说的是这个**程序**。机器的主人拥有这台机器，在上面有 root。
  要么信任你的房东，要么[自己跑一台机器](running-a-machine.md)。
- 这里没有任何东西隐藏「有流量」这件事本身，也不隐藏有多少、
  以及配了哪些号码和名字。计量本来就是这个产品的用途。

---

## 10. 有一类在这里跑不起来

前面九节讲的都是用户态的东西：一个普通程序，拿着一个普通 socket ——
收一个连接，对字节做点什么，再往外开一个连接。绝大多数人用的就是这一类，
它和别的程序一样地跑。

跑不起来的是另一类：**要自己建一块网卡、接管路由表**的那一种。
容器拿不到 `CAP_NET_ADMIN`，里面也没有 `/dev/net/tun`，
所以不是慢，也不是功能残缺 —— 设备建不出来，它起不来。

原因是计费，不是怀疑。有了 `CAP_NET_ADMIN`，租户可以把计流量的那块 `tap0` 改名，
再用同一个名字立一块计数从零开始的新设备，这个月的流量表读到的就是零。
这个决定是写下来的，代价当时也说明白了：没有 nftables，没有 tun，
容器里没有内核态 VPN。

---

## 11. 法律是你自己要弄清楚的事

这一页讲的是一台机器怎么搬字节。你在它上面跑什么、给谁用、落在哪里，
都是你的事 —— 弄清楚哪些规定适用于这些事，同样是你的事。

这一类服务的规定，各个国家和地区差别很大，
既管你所在的地方也管机器所在的地方，而且会变。
真要用，就针对你自己的情况认真查清楚。
这一页上的任何内容都不是法律意见，也没有谁替你核对过。

---

## 接下来

- [公网端口](ports.md) —— 第 3 节的完整版，两边都讲。
- [快速上手](quick-start.md)第 6 步 —— 加域名和指 DNS，一步一张图。
- [面板 REST API](api.md) —— 域名、路由、端口的每一个调用。
- [自己跑一台机器](running-a-machine.md) —— 第 9 节的另一面。
