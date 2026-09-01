---
title: 部署网站和 CDN
---

# 部署网站和 CDN

你的客户一半在国内，一半在国外。麻烦的地方在于：没有哪一台机器两边都行 ——
进国内快的那种，配置小、还贵；配置高又便宜的那种，一到晚上就卡，
而那正好是大家逛店的时间。

**那就租两台，把小的那台放前面。** 这一页就讲这一件事：为什么行得通，怎么搭。

<FigRows :arrow="0" :rows="[
  [{ t: '§1–§5', tone: 'accent' }, '为什么一条线路能比另一条贵十倍'],
  [{ t: '§6–§8', tone: 'accent' }, '方案长什么样，到底省下了什么'],
  [{ t: '§9–§11', tone: 'accent' }, '照着敲什么，会踩什么坑，什么时候别折腾'],
]" />

如果你的客户只在世界的一边，直接跳到 §11 —— 这一整套你大概率用不上。

---

## 1. 同一段路，两种走法

两台机器放在香港同一栋楼里，同样的硬件，同一条线出机柜。上海的一个访客分别打开
它们上面的网页：一台要 300 毫秒，而且发出去的东西丢掉十分之一；另一台 40 毫秒，
一个不丢。

距离一点没变。变的是**这批流量买到了走哪条路的权利**。

<svg class="fig" viewBox="0 0 660 206" role="img" aria-label="普通线路要经过一个晚上会排队的公共分拣中心，优化线路有一条包下来的专用车道，全天一个样">
  <defs><marker id="cd1" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="14" y="18">同一批货，同一段路</text>
  <text class="s" x="14" y="56">普通线路</text>
  <rect class="box" x="86" y="36" width="104" height="40" rx="4"/>
  <text class="c" x="138" y="61">你的机器</text>
  <path class="ln" d="M190,56 H240" marker-end="url(#cd1)"/>
  <rect class="box" x="248" y="36" width="176" height="40" rx="4"/>
  <text class="c" x="336" y="53">公共分拣中心</text>
  <text class="s c" x="336" y="69">晚上八点排到十二点</text>
  <path class="ln" d="M424,56 H474" marker-end="url(#cd1)"/>
  <rect class="box" x="482" y="36" width="104" height="40" rx="4"/>
  <text class="c" x="534" y="61">你的访客</text>
  <text class="s" x="86" y="96">该快的时候慢，而且有一部分根本没送到</text>
  <path class="rule" d="M14,116 H646"/>
  <text class="s" x="14" y="156">三网优化</text>
  <rect class="box" x="86" y="136" width="104" height="40" rx="4"/>
  <text class="c" x="138" y="161">你的机器</text>
  <path class="lnA" d="M190,156 H474" marker-end="url(#cd1)"/>
  <text class="s a c" x="332" y="149">有人花钱包下来的专用车道</text>
  <rect class="box" x="482" y="136" width="104" height="40" rx="4"/>
  <text class="c" x="534" y="161">你的访客</text>
  <text class="s" x="86" y="196">晚上九点和早上九点一个样</text>
</svg>

**三网优化**就是下面那条，而且是电信、联通、移动三家各来一条。§2 讲这三家是谁，
以及为什么「三家」这三个字非说不可。

---

## 2. 商家列表里的那些名字

国内有三家运营商，你的访客一定在其中一家。用哪家不是你能选的，也不是他能选的 ——
是当初谁给他家楼里拉的线。

<FigRows :arrow="0" :head="['运营商', '大概是谁在用']" :rows="[
  [{ t: '中国电信', tone: 'strong' }, '家庭宽带里份额最大的一家'],
  [{ t: '中国联通', tone: 'strong' }, '北方偏多'],
  [{ t: '中国移动', tone: 'strong' }, '手机基本都是，家宽这几年也很多'],
]" />

**每家都同时卖一条普通路和一条精品路，而且是分开买的。** 所以一台机器完全可能
电信飞快、移动稀烂。很多人花钱买了「好线路」，结果一半客户还在抱怨，
十有八九栽在这里。

| 列表上写的 | 是谁家的 | 说人话 |
|---|---|---|
| **163**、AS4134 | 电信普通 | 公共高速。下午三点没问题，晚上九点是停车场。 |
| **CN2 GT**、AS4809 | 电信中档 | 好一点的高速。同样的钟点，同样会堵。 |
| **CN2 GIA**、AS4809 | 电信精品 | 专用车道。大家说「好线路」通常指这个。 |
| **169**、AS4837 | 联通普通 | 又一条公共高速。 |
| **AS9929**、CUII | 联通精品 | 专用车道。 |
| **CMI**、AS58453 | 移动普通 | 公共，而且三家里最爱绕路的。 |
| **CMIN2** | 移动精品 | 专用车道。 |
| **三网优化**、三网直连 | 上面三家都算 | 三家的专用车道各买一条。 |

还有两个词值得记住，因为商家天天用，而它们不是一回事：

- **去程** —— 访客到你的机器。很小，就是一些请求和点击。
- **回程** —— 你的机器回到访客。剩下全部：网页、图片、视频。
  网站快不快是这一程决定的，商家标 CN2 GIA 说的也是这一程。

一份只写了某一家精品网的列表，是在如实告诉你那一家的情况，并且对另外两家
只字未提。记得问。

---

## 3. 差别有多大

下面是常见值，不是承诺 —— 掏钱之前自己测一次。香港到中国大陆：

| | 普通线路 | 三网优化 |
|---|---|---|
| **白天** | 60–90 毫秒，基本不丢 | 30–50 毫秒，不丢 |
| **晚上八点到十二点** | 150–300 毫秒，丢 5%–30% | 30–60 毫秒，不丢 |
| **体感** | 图片加载一半、结账转圈、有些人干脆付不了款 | 一天到晚一个样 |

<svg class="fig" viewBox="0 0 660 206" role="img" aria-label="一天的延迟曲线：普通线路白天平稳，晚上八点到十二点尖峰；优化线路全天一条直线">
  <text class="t" x="14" y="20">同一个机柜里的两台机器，同一个页面，一整天</text>
  <text class="s" x="14" y="52">越往上越慢</text>
  <path class="rule" d="M541,40 V172"/>
  <text class="s c" x="563" y="36">晚高峰 20:00–24:00</text>
  <path class="rule" d="M96,172 H638"/>
  <path class="ln" d="M96,141 L185,143 L274,139 L363,137 L452,130 L519,86 L541,60 L563,44 L586,56 L608,98 L630,138"/>
  <path class="lnA" d="M96,155 L274,154 L452,156 L630,154"/>
  <text class="s" x="14" y="139">普通线路</text>
  <text class="s a" x="14" y="159">三网优化</text>
  <text class="s c" x="96" y="190">0 点</text>
  <text class="s c" x="229" y="190">6 点</text>
  <text class="s c" x="363" y="190">12 点</text>
  <text class="s c" x="496" y="190">18 点</text>
  <text class="s c" x="630" y="190">24 点</text>
</svg>

**丢包比延迟难受得多。** 慢一点只是烦；十个文件少一个，页面就是坏的。
而且丢包不是均匀分布的 —— 它偏偏出现在大家回到家、手里拿着手机的那四个小时，
对一家店来说，那是一天里大部分的钱。

### 怎么测才算数

两条规矩，说的都是**什么时候测**：

- **在国内时间晚上九点到十一点测。** 白天测等于没测，市面上每一条线路
  下午三点看起来都很好。
- **从访客那一头测**，用真正的国内网络，三家运营商各测一次（借得到手机就借）。
  从你的机器上下载一个大文件、看速度，这就是全部的测试。

在容器里 `app-setup install nettools` 能装上 `mtr`、`traceroute` 和 `dig`。
但要有心理准备：在容器里跑 traceroute 中间经常是一片空白 ——
中途那些跳的回应不一定送得回容器的网络里 —— 所以那只能当个参考，不是答案。
真正算数的那个数字，是在国内那一头量出来的。

---

## 4. 快的那条快在哪里

海不是问题。两条线路过海走的是同一批海缆，花的时间差不多，
而且外面那一段从来不缺容量。

<svg class="fig" viewBox="0 0 660 196" role="img" aria-label="从你的机器到访客的整条路：海缆不堵，堵的是进入国内的那道门，最后一程是运营商自己的网">
  <defs><marker id="cd2" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="14" y="18">队到底排在哪里</text>
  <rect class="box" x="14" y="38" width="112" height="44" rx="4"/>
  <text class="c" x="70" y="65">你的机器</text>
  <path class="ln" d="M126,60 H164" marker-end="url(#cd2)"/>
  <rect class="box" x="172" y="38" width="150" height="44" rx="4"/>
  <text class="c" x="247" y="56">海底光缆</text>
  <text class="s c" x="247" y="73">从来不是瓶颈</text>
  <path class="ln" d="M322,60 H360" marker-end="url(#cd2)"/>
  <rect class="box" x="368" y="38" width="126" height="44" rx="4"/>
  <text class="c" x="431" y="56">国际出口</text>
  <text class="s c" x="431" y="73">进国内的那道门</text>
  <path class="ln" d="M494,60 H532" marker-end="url(#cd2)"/>
  <rect class="box" x="540" y="38" width="106" height="44" rx="4"/>
  <text class="c" x="593" y="65">你的访客</text>
  <path class="lnA" d="M431,112 V90" marker-end="url(#cd2)"/>
  <text class="t a c" x="431" y="130">所有人都堵在这里</text>
  <text class="s c" x="431" y="150">普通线路排队等空位</text>
  <text class="s c" x="431" y="166">精品线路有一份一直留着</text>
  <text class="s" x="14" y="190">两千公里都好好的。按兆卖钱的，是最后那两百米。</text>
</svg>

你买的其实是三样东西，只有第一样是明面上的：

- **出口的一份额度。** 进国内的容量是有限的，而且握在三家运营商手里。
  普通线路是去排剩下的空位；精品线路是不管队多长，都有一份留着。
- **一条不绕远的路。** 一条普通的香港线路，完全可能先去一趟美国，
  再回来找 2000 公里外的访客 —— 因为那是卖家能买到的最便宜的中转。
  这笔钱你每次请求都在用毫秒付。
- **专门是回程那一段。** 数据从你机器**发出去**很容易，没人为这个收多少钱；
  让它沿着一条好路**回到**国内访客手里，那是运营商单独卖的产品，
  也是贵的那一半。

---

## 5. 为什么这么贵

大致的样子，2026 年的行情，而且价格一直在动 —— 下单当天自己比一次：

| 同样一个月 ¥100 | 你买到的是 |
|---|---|
| **普通线路** | 一个 1 Gbps 端口，不限流量，和几十个邻居一起用 |
| **三网优化** | 20–50 Mbps，或者几百 GB 的流量额度 |

**每兆的单价差十倍到五十倍。** 这一页剩下的所有内容，都是这一个数字的后果。

四个原因，而且是叠加的：

<FigRows :arrow="0" :head="['贵在哪里', '换成日常的说法']" :rows="[
  [{ t: '不超售', tone: 'strong' }, '自助餐的一个座位，和写着你名字的一整桌'],
  [{ t: '出口就那么多', tone: 'strong' }, '桥只有三家能修，而且没人在修新的'],
  [{ t: '回程是另外一件商品', tone: 'strong' }, '出去那趟便宜，你真正在付的是回来那趟'],
  [{ t: '三家运营商，要买三次', tone: 'strong' }, '一条专用车道不等于三条专用车道'],
]" />

第一条占了大头。一个普通的「1 Gbps 不限流量」端口，是按「这三十个人不会同时用」
卖给三十个人的 —— 这话下午三点是对的，晚上九点是错的，
而普通线路偏偏就在那个钟点垮掉，原因就在这里。精品线路的一兆只卖一次，
卖完就没有了，稀缺的东西是什么价，它就是什么价。

第四条是**三网优化**比单标「CN2 GIA」更贵的原因：那是一台机器上三份分开的精品
安排，三份你都在付钱。

所以老实的总结是：**你买的不是一台快服务器，你是在租路。**
那就尽量少租 —— 这就是 §6。

---

## 6. 所以别只买一台

把你的网站真正消耗的东西，和那条贵线路能给你的东西放在一起看：

| | 三网优化 | 普通线路、高配 |
|---|---|---|
| **强在哪** | 晚上九点还能把数据送进国内 | 核、内存、磁盘，还有几乎不要钱的流量 |
| **弱在哪** | 什么都小，什么都按量收费 | 国内客户逛店的那四个小时 |
| **一个月 ¥200 买到** | 1 核、1 GB、500 GB 流量 | 8 核、16 GB、500 GB 磁盘，几个 TB 的流量 |

你的数据库、PHP、图片压缩、打包构建 —— 这些东西根本不关心网络好不好。
它们要的是核和内存，而在一台精品线路的机器上，核和内存的价格是隔壁的好几倍。

所以：网站放便宜那台，在贵的那台上**只买路**。

---

## 7. 方案长什么样

两个容器，在同一个城市，同一个主机方或者两个主机方都行：

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="国内访客到一台三网优化的小节点，它缓存并转发到附近一台普通线路的高配源站；国外访客直接到源站">
  <defs><marker id="cd3" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <rect class="box" x="14" y="32" width="112" height="44" rx="4"/>
  <text class="c" x="70" y="59">国内访客</text>
  <path class="lnA" d="M126,54 H172" marker-end="url(#cd3)"/>
  <rect class="mine" x="180" y="20" width="176" height="68" rx="5"/>
  <text class="t c" x="268" y="42">加速节点</text>
  <text class="s c" x="268" y="60">三网优化 · 1 核 1 GB</text>
  <text class="s c" x="268" y="78">只跑一个 nginx</text>
  <path class="ln" d="M356,54 H424" marker-end="url(#cd3)"/>
  <text class="s c" x="392" y="46">3 毫秒</text>
  <rect class="box" x="432" y="20" width="214" height="68" rx="5"/>
  <text class="t c" x="539" y="42">源站</text>
  <text class="s c" x="539" y="60">普通线路 · 8 核 16 GB</text>
  <text class="s c" x="539" y="78">你的网站真正跑在这里</text>
  <rect class="box" x="14" y="140" width="112" height="44" rx="4"/>
  <text class="c" x="70" y="167">国外访客</text>
  <path class="ln" d="M126,162 H539 V92" marker-end="url(#cd3)"/>
  <text class="s c" x="320" y="154">直接过去，不用绕一趟国内的大门</text>
</svg>

- **国内访客**落在加速节点上。它见过的东西自己就答了，走那条贵线路，40 毫秒。
  没见过的，它去源站取 —— 而源站只有 3 毫秒远，因为你是特意把两台租在同一个城市的。
- **国外访客**直接到源站，完全不碰加速节点。柏林的客户没有理由绕道香港的优化线路，
  去访问一台本来就在那边的服务器。

最后这个分流，才是让这套东西适合跨境生意、而不只是适合国内站的地方。
它只需要你的 DNS 服务商支持一件事：**同一个域名，按提问的人在哪里给出不同的答案。**
DNSPod、阿里云 DNS、华为云 DNS 和大部分国内服务商都叫它「分线路解析」，
免费就有境内 / 境外这一组。

| 主机记录 | 线路 | 记录值 |
|---|---|---|
| `www.example.com` | 境内 | 加速节点那台机器 |
| `www.example.com` | 默认（境外） | 源站那台机器 |
| `origin.example.com` | 默认 | 源站那台机器 |

**没有分线路解析怎么办？** 把 `www` 全都指到加速节点。国外访客多走一跳、
多几毫秒 —— 通常无所谓，偶尔会有点影响。先这样跑起来，分线路以后再加。

`origin.example.com` 是第三行，而且不是可选的：加速节点靠它找到源站；
加速节点出问题的时候，你也靠它直接摸到源站看看。

---

## 8. 缓存省下什么，不省什么

缓存就是门口的一个架子。第一个人要某个文件，得有人跑到后面去拿；
后面所有人，都是从架子上直接拿走。

<FigRows :arrow="0" :head="['谁来要', '发生什么']" :rows="[
  ['第一个访客要 logo.png', '加速节点没见过 —— 去源站取一份，留一份在架子上，再给他'],
  ['后面一万个人', { t: '直接从架子上拿。源站根本不知道有这回事。', tone: 'accent' }],
  ['有人往购物车里加东西', { t: '永远不缓存、永远不上架 —— 每次都去源站', tone: 'strong' }],
]" />

下面是老实的账，其中有一行会让人意外：

| | 缓存省得掉吗 |
|---|---|
| **加速节点发给访客的流量** | **省不掉。** 访客要的每一个字节都从这台出去，命中不命中都一样。要塞进额度里的，就是这个数。 |
| **加速节点回源取东西的流量** | **省掉几乎全部。** 而且进来的流量也算你的额度，所以这是真金白银的省，不是账面上的。 |
| **源站的 CPU、内存、磁盘** | **省很多。** 一个命中的页面，等于一次没有跑过的 PHP。 |
| **访客等的时间** | **省。** 命中的请求整整少跑一个来回。 |

拿数字算一遍。假设你的站每个月要发给访客 300 GB：

| | 加速节点被计的流量 |
|---|---|
| 完全不缓存 | 出去 300 GB ＋ 回源取回 300 GB ＝ **600 GB** |
| 八成能缓存、也缓存了 | 出去 300 GB ＋ 回源取回 60 GB ＝ **360 GB** |

hqnode 的容器**两个方向都计流量**（见[使用你的容器](using-your-container.md) §3），
所以缓存基本上把你在贵机器上的开销**砍掉一半**。这还是在快之外多出来的。

**加速节点按流量选，不是按核数选。** 一核一 GB 内存能扛住极大量的静态内容，
先用完的一定是流量额度。

---

## 9. 动手搭

例子：`www.example.com` 是店铺，加速节点那台机器是 `203.0.113.10`，
源站那台是 `203.0.113.20`。

### 第 1 步 —— 拿到两个容器

跟主机方要：一个在三网优化的机器上，一个在便宜的高配机器上，
**而且要在同一个城市**。「同一个地区」不够近 —— 香港到东京是 50 毫秒，
你会把它加到每一个没命中的请求上。

直接告诉主机方你要干什么。挑两台物理上挨得近的机器对他们很容易，
对你来说从外面根本没法验证。

### 第 2 步 —— 把网站装在源站上

这一半没什么特别的，就是一台普通机器上的一次普通部署：
[部署 LNMP 网站](deploy-lnmp.md)、[部署 Node.js 程序](deploy-nodejs.md)，
或者你本来就有的那一套。

### 第 3 步 —— 给源站一个名字

在源站的容器里：

```sh
app-setup domain add origin.example.com 80
```

这样拿到的是一张由机器替你打理的证书 —— 这里正合适，这个名字上没有什么秘密，
也少一样要续期的东西。先把 `origin.example.com` 的 DNS 记录加好，
否则证书签不下来：一条 A 记录，指向 `203.0.113.20`。

往下走之前先确认这一步：

```sh
curl -I https://origin.example.com/
```

不是 `200` 就停在这里。后面的每一步都不可能对。

### 第 4 步 —— 在加速节点上装 nginx

在加速节点的容器里：

```sh
app-setup install nginx
```

然后写一个文件 —— Alpine 上是 `/etc/nginx/http.d/cdn.conf`，
Debian 或 Ubuntu 上是 `/etc/nginx/conf.d/cdn.conf`：

```nginx
# 缓存放在哪、最多放多少。/data 重装容器不会丢；缓存本来也不需要留着，
# 不过磁盘额度反正是一起算的。
proxy_cache_path /data/cache levels=1:2 keys_zone=site:20m
                 max_size=4g inactive=7d use_temp_path=off;

# 带着下面这些 cookie 的请求是属于某一个人的，绝不能发给另一个人。
# 把你自己的购物车和会话 cookie 加进来。
map $http_cookie $private {
    default                        0;
    "~*wordpress_logged_in"        1;
    "~*woocommerce_items_in_cart"  1;
    "~*wp_woocommerce_session"     1;
    "~*comment_author"             1;
}

upstream origin {
    server 203.0.113.20:443;   # 源站那台机器，直接写地址
    keepalive 32;              # 连接复用，不用每次重新握手
}

server {
    # 443 上的 HTTPS，机器已经替你做完了
    listen 80;
    server_name www.example.com example.com;

    # 这条线以下的设置，下面三个 location 都会继承。
    proxy_http_version 1.1;
    proxy_set_header Connection "";

    # 回源握手时报这个名字，源站那台机器的大门靠它认出这是谁的站 ——
    # 尽管请求本身带的是访客输入的那个名字。
    proxy_ssl_server_name on;
    proxy_ssl_name origin.example.com;

    proxy_set_header Host              $host;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;

    proxy_cache site;
    # 十个人同时要一个文件，只回源一次
    proxy_cache_lock on;
    # 源站出毛病的时候，先把架子上的旧东西发出去
    proxy_cache_use_stale error timeout updating
                          http_500 http_502 http_503 http_504;
    add_header X-Cache $upstream_cache_status always;

    # 图片、样式、脚本：存一个月。视频故意没放进来 ——
    # 那是最烧流量的东西，不该从贵的那台发。
    location ~* \.(jpe?g|png|gif|webp|avif|svg|ico|css|js|woff2?)$ {
        proxy_pass https://origin;
        proxy_cache_valid 200 30d;
        proxy_ignore_headers Set-Cookie Cache-Control Expires;
    }

    # 后台、登录、购物车、结账：一个字节都不上架。
    location ~* ^/(wp-admin|wp-login|cart|checkout|my-account) {
        proxy_pass https://origin;
        proxy_cache off;
    }

    # 其余页面：存十分钟，登录过的访客绕开架子。
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
nginx -t          # 有毛病会在上线之前告诉你
rc-service nginx restart      # Alpine
systemctl restart nginx       # Debian、Ubuntu 和其余
```

装 nginx 时自带的那个默认站点，放着别动就行。它没有写 `server_name`，
只会接那些谁也匹配不上的请求。

### 第 5 步 —— 把真正的域名加到加速节点上

在加速节点的容器里：

```sh
app-setup domain add www.example.com 80
app-setup domain add example.com 80
```

机器在 443 上把 HTTPS 解掉、自己续证书，然后用明文 HTTP 送到容器的 80 端口 ——
所以上面那份配置监听的是 80，而且里面一张证书都没有。
它还会在 nginx 看到请求之前填好 `X-Forwarded-For`，
所以源站日志里记的是访客的地址，不是香港的。

想自己拿着证书？`app-setup domain add www.example.com 8443 self-hosted`，
TLS 改在 nginx 里终结。取舍写在[跑一个代理或 VPN](proxy.md) §7。

### 第 6 步 —— 解析域名

就是 §7 那三条记录。加完等几分钟。

### 第 7 步 —— 确认架子真的在用

```sh
curl -sI https://www.example.com/logo.png | grep -i x-cache
curl -sI https://www.example.com/logo.png | grep -i x-cache
# 第一次是  X-Cache: MISS
# 第二次是  X-Cache: HIT
```

先 `MISS` 后 `HIT`，整套就是通的。第二次还是 `MISS` 的话，
§10 里有四种常见原因。

**改完东西想把缓存全扔掉：**

```sh
rm -rf /data/cache/*
nginx -s reload
```

---

## 10. 会出的问题

| 你看到的 | 通常是什么 |
|---|---|
| **一直 `MISS`，从来不 `HIT`** | 源站在每个响应上都发 `Set-Cookie` 或者 `Cache-Control: no-cache`。WordPress 装了某些插件、每个页面都开会话时就是这样。要么在源站修掉，要么在 `location /` 里加 `proxy_ignore_headers Set-Cookie;` —— 加之前先读下一行。 |
| **一个客户看到了另一个人的购物车** | 你缓存了不该缓存的东西。这个故障赔进去的是一个客户，不是一秒钟。§9 里第二个 `location` 的每一条路径、还有那个 cookie 的 `map`，都是为了挡这件事。测法：登录，往购物车里加一件，再在无痕窗口里打开同一个页面。 |
| **换了图片，访客看到的还是旧的** | 它按你写的在架子上放三十天。清缓存，或者更好的办法：换个文件名 —— `logo.v2.png` —— 从此不用再想这件事。 |
| **加速节点的流量额度一周就没了** | 如果你是按核数选的机器，这就是意料之中。访客的每一个字节都从它这里过。账在 §8。 |
| **一直在跳转，跳不完** | 源站在往它自己的名字上跳。`proxy_set_header Host $host;` 要原样保留 —— 源站必须看到访客输入的那个名字，不是 `origin.example.com`。 |
| **源站日志里整个互联网只有一个 IP** | 源站没有去读 `X-Forwarded-For`。那是源站上那个程序的设置，不在这边。 |
| **加速节点报 `502`** | 它连不到源站。在加速节点的容器里跑一次 `curl -I https://origin.example.com/`。 |
| **`origin.example.com` 被搜索引擎收录了** | 它本来就是你店铺的一份真实、可访问的副本，不收录才怪。让源站在被请求的名字是 `origin.example.com` 时返回 `X-Robots-Tag: noindex`。 |

**有一个坑值得单独说：两个容器不要放在同一台机器上。** 这么做不只是把整件事的
意义抵消掉 —— 它照着上面写的根本跑不起来：一个容器去连自己那台机器的公网地址，
连到的是**它自己**，不是隔壁那个容器，所以加速节点会转给自己，然后转成死循环。
两台机器，两个地址。

---

## 11. 什么时候别搭这套

这是一件实打实的工程，而且多了一个会坏的东西。以下情况直接跳过：

<FigRows :arrow="0" :head="['如果你是这种', '那就这样']" :rows="[
  ['客户全在国外', '一台普通机器就够。那份溢价你本来就不用付。'],
  ['客户全在国内', '直接买国内的机器，域名去备案。比这一页里任何方案都又便宜又快。'],
  ['站很小，一个月几个 GB', '一个三网优化的容器，网站直接跑在上面。为这点量搭两台不值。'],
  ['要在十个国家都快', '买商业 CDN。这套设计只有一个前置节点，人家有两百个。'],
]" />

这个方案里两台机器都在境外，所以整页没提备案。一旦源站挪进大陆境内，
域名必须先备案才能在 80 和 443 上对外服务 —— 那是换方案，不是改配置。

还有：如果你拿不准这条贵线路值不值，就买一个月小的那台，
把一个页面复制上去，晚上九点比一次。这是这一页里最便宜的一次实验。

---

## 接下来

- [快速上手](quick-start.md) —— 域名、DNS 和 HTTPS，一步一张图。没做过就先做这个。
- [部署 LNMP 网站](deploy-lnmp.md) · [部署 Node.js 程序](deploy-nodejs.md) ——
  源站上放什么。
- [使用你的容器](using-your-container.md) §3 —— 流量额度怎么算的，跑满了会怎样。
- [公网端口](ports.md) —— 前置节点后面那个东西不是网站的时候，看这里。
- [跑一个代理或 VPN](proxy.md) §7 —— 两种证书模式，完整版。
