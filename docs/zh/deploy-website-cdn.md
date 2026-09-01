---
title: 部署网站和 CDN
---

# 部署网站和 CDN

同一个网页，从香港同一栋楼里的两台机器发出去，国内访客那边看到的是这样：

<LineRace
  title="同一个网页，两条线路，同时开始"
  gate="国际出口"
  machine="你的机器"
  fast="三网优化"
  slow="普通线路"
  clean="一个没丢"
  lost="丢了 {n} 个"
  sec="秒"
  verdict="上面这条能流畅看 4K；下面这条一到晚高峰，网页都打不开"
  note="丢掉的那一份得重新发一次 —— 所以下面那条不只是慢一点"
  replay="再放一遍"
  alt="两条线路在传同一个网页。三网优化那条，数据一个接一个直接穿过国际出口，两秒多就加载完，一个不丢。普通线路那条，数据在国际出口前面越堆越多，堆满了就往下掉、得重新发一次，时间是上面那条的两倍还多。"
/>

上面那条快的，是**三网优化**线路；下面那条，是普通线路。两台机器硬件一样、
同一条线出机柜、离访客一样远 —— 差的只有中间那道门。

这道门落到你国内客户身上，是这么个差别：

| 同一个网站 | 三网优化 | 普通线路 |
|---|---|---|
| **白天** | 秒开 | 能用，慢一点 |
| **晚上 8 点到 12 点** | 还是秒开。4K 视频拖到哪儿播到哪儿，中间不卡 | 图片刷一半停住，页面转圈转到超时 —— 网页根本打不开 |

而晚上 8 点到 12 点，正是大家逛店下单的时候。

做跨境生意的麻烦就在这儿：一台机器满足不了两边。进国内快的机器，配置小、还贵；
配置高又便宜的机器，就是下面那条。

**办法是租两台，把小的那台摆在前面挡着。** 为什么行得通、怎么搭，这一页讲清楚。

<FigRows :arrow="0" :rows="[
  [{ t: '§1–§5', tone: 'accent' }, '一条线路凭什么比另一条贵十倍'],
  [{ t: '§6–§8', tone: 'accent' }, '方案长什么样，到底省了什么'],
  [{ t: '§9–§11', tone: 'accent' }, '照着敲什么，会踩什么坑，什么时候别折腾'],
]" />

客户只在国内、或者只在国外的，直接翻到 §11 —— 这套东西你多半用不上。

---

## 1. 同一段路，两种走法

给刚才那张图配上数字。上海的一个访客同时打开这两台机器上的网页：一台 40 毫秒
就出来，一个不丢；另一台 300 毫秒才出来，中间还丢掉十分之一的数据。

距离没变，机器也没变。变的只有一样：**这批数据买没买到走好路的资格。**

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

上面那条是普通线路，下面那条就是**三网优化**。所谓三网，是电信、联通、移动这三家。
为什么非得强调「三家」，§2 说。

---

## 2. 商家列表里的那些名字

国内的宽带就三家在卖：电信、联通、移动。你的访客用哪一家，你决定不了，
他自己往往也决定不了 —— 当初谁给他家楼里拉的线，就是哪一家。

<FigRows :arrow="0" :head="['运营商', '大概是谁在用']" :rows="[
  [{ t: '中国电信', tone: 'strong' }, '家庭宽带里份额最大的一家'],
  [{ t: '中国联通', tone: 'strong' }, '北方偏多'],
  [{ t: '中国移动', tone: 'strong' }, '手机基本都是，家宽这几年也很多'],
]" />

**三家各卖两种路：一条普通的，一条精品的，而且要分开买。**
所以经常出现这种情况：同一台机器，电信访客飞快，移动访客卡成 PPT。
很多人花钱买了「好线路」，最后一半客户还在骂，多半就栽在这里。

| 列表上写的 | 是谁家的 | 说人话 |
|---|---|---|
| **163**、AS4134 | 电信普通 | 公共高速。下午三点畅通，晚上九点是停车场 |
| **CN2 GT**、AS4809 | 电信中档 | 好一点的高速，该堵的钟点照堵 |
| **CN2 GIA**、AS4809 | 电信精品 | 专用车道。商家说「好线路」，一般指它 |
| **169**、AS4837 | 联通普通 | 又一条公共高速 |
| **AS9929**、CUII | 联通精品 | 专用车道 |
| **CMI**、AS58453 | 移动普通 | 公共，而且三家里最爱绕远路的 |
| **CMIN2** | 移动精品 | 专用车道 |
| **三网优化**、三网直连 | 三家都算 | 三条专用车道，一家买一条 |

还有两个词，商家天天挂在嘴边，别搞混：

- **去程** —— 访客发到你机器上的东西。很少，就是点击和请求。
- **回程** —— 你机器发回给访客的东西。网页、图片、视频，全在这一程。
  网站快不快，看的就是回程。商家标 CN2 GIA，说的也是回程。

一份配置只写了某一家的精品网，那它交代清楚的就只有那一家。
另外两家什么样，它没说 —— 得你自己去问。

---

## 3. 差别有多大

下面是常见的数，不是承诺。掏钱之前自己测一遍。香港到中国大陆：

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

**丢包比慢更要命。** 慢一点顶多是烦；十个文件少送到一个，页面就是坏的。
更麻烦的是，丢包不是全天平均分布，它偏偏挤在晚上八点到十二点 ——
大家到家了、手机拿起来了。对一家店来说，一天的钱大半在这四个小时里。

### 怎么测才算数

两条规矩，说的都是「什么时候测」：

- **挑国内时间晚上九点到十一点测。** 白天测等于没测 —— 市面上所有线路，
  下午三点看起来都很好。
- **站在访客那一头测**，用真的国内宽带，三家运营商各测一次，能借到手机就借。
  从你的机器上拉一个大文件，看速度掉不掉，这就是全部。

容器里 `app-setup install nettools` 能装上 `mtr`、`traceroute`、`dig`。
不过先说清楚：容器里跑 traceroute，中间常常是一片星号 ——
沿途那些路由器的回应不一定送得回容器里。所以那个结果只能当参考，
真正算数的数字在国内那一头。

---

## 4. 快的那条快在哪里

不是海的问题。两条线路过海走的是同一批海缆，花的时间也差不多，
海里那一段从来不缺容量。

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

**堵的是最后那一道门。** 从境外进大陆，都要过国际出口。这道门的容量是固定的，
而且握在那三家手里。普通线路排队等空位；精品线路不管队多长，都有一份给它留着。

### 还有：路不一定是直的

一条便宜的香港线路，完全可能把你的数据先送到美国，再从美国绕回上海。
不是绕一点点，是路程翻了将近二十倍。

<svg class="fig" viewBox="0 0 660 272" role="img" aria-label="示意地图：香港到上海直连约 1200 公里、40 毫秒；普通线路可能横跨太平洋绕到洛杉矶再折回，两万多公里、300 毫秒">
  <defs><marker id="cd4" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker>
  <marker id="cd5" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="f-dot" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t" x="14" y="20">同样两个点，两种走法</text>
  <path class="box" d="M44,74 C52,50 92,38 138,42 C182,46 224,60 240,84 C252,102 250,128 236,148 C220,170 186,182 150,178 C108,173 66,152 50,124 C40,106 38,88 44,74 Z"/>
  <path class="box" d="M470,86 C486,62 530,52 574,58 C614,64 640,86 636,114 C632,144 606,172 570,180 C534,188 494,176 476,152 C462,132 460,102 470,86 Z"/>
  <text class="t c" x="140" y="70">中国大陆</text>
  <text class="t c" x="556" y="90">美国</text>
  <circle class="f-dot" cx="234" cy="94" r="4"/>
  <text class="s" x="228" y="98" text-anchor="end">上海 · 你的访客</text>
  <circle class="f-dot" cx="212" cy="166" r="4"/>
  <text class="s" x="204" y="170" text-anchor="end">香港 · 你的机器</text>
  <circle class="f-dot" cx="486" cy="130" r="4"/>
  <text class="s" x="498" y="134">洛杉矶</text>
  <path class="lnA" d="M216,160 C238,142 240,116 232,100" marker-end="url(#cd5)"/>
  <text class="s a" x="252" y="124">直连 · 1200 公里</text>
  <text class="s a" x="252" y="140">约 40 毫秒</text>
  <path class="ln" d="M220,172 C300,236 400,222 480,138" marker-end="url(#cd4)"/>
  <path class="ln" d="M484,122 C400,30 292,32 242,80" marker-end="url(#cd4)"/>
  <text class="s c" x="352" y="36">网页发回来，还得原路再绕一遍</text>
  <text class="s c" x="352" y="232">普通线路可能先绕美国 —— 两万多公里，约 300 毫秒</text>
  <text class="s" x="14" y="264">绕出去的那两万公里，不会有人给你开账单。你每点一下，就在替它等。</text>
</svg>

为什么会绕？因为卖家买的是最便宜的中转，中转商往哪儿走，他管不着。

所以精品线路卖的其实是三样东西：**出口的一份额度、一条不绕远的路，
还有回程那一段。** 最后这一样得单独说：数据从你机器发出去很容易，
没人为这个多收钱；让它沿着好路回到国内访客手上，那是运营商单独定价的产品 ——
也是贵的那一半。

---

## 5. 为什么这么贵

先看结果。下面是 2026 年的大概行情，价格随时在动，下单当天自己再比一次：

| 同样一个月 ¥100 | 你买到的是 |
|---|---|
| **普通线路** | 一个 1 Gbps 端口，不限流量，和几十个邻居一起用 |
| **三网优化** | 20–50 Mbps，或者几百 GB 的流量额度 |

**每兆的单价，差十倍到五十倍。**

差价从哪儿来？把同样这 ¥100 拆开看，钱花到哪儿去了：

<svg class="fig" viewBox="0 0 660 216" role="img" aria-label="同样一百块一个月拆成两条：普通高配机器里机器占大头、线路只占一点；三网优化机器正好反过来">
  <text class="t" x="14" y="20">同样 ¥100 一个月，钱花到哪儿去了</text>
  <text class="t" x="14" y="60">普通机器</text>
  <text class="s" x="14" y="76">高配</text>
  <rect class="box" x="150" y="44" width="388" height="36" rx="4"/>
  <text class="c" x="344" y="67">机器 · 8 核 16 GB</text>
  <rect class="mine" x="538" y="44" width="68" height="36" rx="4"/>
  <text class="s a c" x="572" y="67">线路</text>
  <text class="s" x="150" y="100">机器 ¥85 · 线路 ¥15 —— 带宽是超售的，几乎不要钱</text>
  <text class="t" x="14" y="146">三网优化</text>
  <text class="s" x="14" y="162">小机器</text>
  <rect class="box" x="150" y="130" width="68" height="36" rx="4"/>
  <text class="s c" x="184" y="153">机器</text>
  <rect class="mine" x="218" y="130" width="388" height="36" rx="4"/>
  <text class="a c" x="412" y="153">线路 · 30 Mbps，或 500 GB 流量</text>
  <text class="s" x="150" y="186">机器 ¥15 · 线路 ¥85 —— 同一台小机器，搬进普通机房只要 ¥15</text>
  <text class="s" x="14" y="210">机器不值钱，值钱的是那条路。所以路只买你真用得上的那一点。</text>
</svg>

**机器本身根本不值钱。** 一台 1 核 1 GB 的小机器，摆在普通机房，一个月十几块钱；
原样搬进三网优化的机房，一个月一百。多出来的那八十几块，没给你多一个核、
多一 G 内存、多一 G 磁盘 —— 全是路钱。

路凭什么这么贵？四条原因，而且是叠加的：

<FigRows :arrow="0" :head="['贵在哪里', '换成日常的说法']" :rows="[
  [{ t: '不超售', tone: 'strong' }, '自助餐的一个座位，和写着你名字的一整桌'],
  [{ t: '出口就那么多', tone: 'strong' }, '桥只有三家能修，而且没人在修新的'],
  [{ t: '回程是另一件商品', tone: 'strong' }, '出去那趟便宜，你真正付钱的是回来那趟'],
  [{ t: '三家运营商，要买三次', tone: 'strong' }, '一条专用车道不等于三条专用车道'],
]" />

第一条是大头。「1 Gbps 不限流量」这种端口，是按「这三十个人不会同时用」
卖给三十个人的。这句话下午三点成立，晚上九点不成立 ——
普通线路偏偏就在那个钟点垮掉，原因就在这儿。精品线路的一兆只卖一次，
卖完就没了；稀缺东西什么价，它就什么价。

第四条是**三网优化**比只标「CN2 GIA」更贵的原因：那是三份分开谈的精品线路
装在同一台机器上，三份钱你都得付。

一句话收尾：**你花的钱大头不在机器上，在路上。** 那就别多租路 —— 这就是 §6。

---

## 6. 所以别只买一台

把网站真正吃的东西，和贵线路能给的东西，摆在一起看：

| | 三网优化 | 普通线路、高配 |
|---|---|---|
| **强在哪** | 晚上九点还能把数据送进国内 | 核、内存、磁盘，还有几乎不要钱的流量 |
| **弱在哪** | 什么都小，什么都按量收费 | 国内客户逛店的那四个小时 |
| **一个月 ¥100 买到** | 1 核、1 GB、500 GB 流量 | 8 核、16 GB、500 GB 磁盘，几个 TB 的流量 |

数据库、PHP、图片压缩、打包构建 —— 这些活儿跟网络好不好一点关系都没有，
它们要的是核和内存。而在三网优化的机器上，核和内存是跟着路钱一起卖的：
你用不用那条路，都得按那个价付（§5 那张图）。

所以分工很清楚：**网站放便宜那台，贵的那台只用来跑路。**

---

## 7. 方案长什么样

两个容器，尽量在同一个城市。一个主机方或者两个主机方，都行：

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

- **国内访客**先到加速节点。它手上有的东西自己就答了，走贵线路发出去，40 毫秒。
  手上没有的，它去源站拿 —— 源站只有 3 毫秒远，因为你是特意把两台租在同城的。
- **国外访客**直接找源站，压根不碰加速节点。柏林的客户没必要绕道香港，
  去访问一台本来就在他旁边的服务器。

第二条才是这套方案适合跨境生意的关键。它需要 DNS 服务商支持一件事：
**同一个域名，按提问的人在哪儿，给不同的答案。**
DNSPod、阿里云 DNS、华为云 DNS 和大部分国内服务商都有这个功能，叫「分线路解析」，
免费就带境内 / 境外这一组。

| 主机记录 | 线路 | 记录值 |
|---|---|---|
| `www.example.com` | 境内 | 加速节点那台机器 |
| `www.example.com` | 默认（境外） | 源站那台机器 |
| `origin.example.com` | 默认 | 源站那台机器 |

**没有分线路解析怎么办？** `www` 全指到加速节点。国外访客多走一跳、多几毫秒，
通常无所谓，偶尔会有点影响。先这么跑起来，分线路以后再加。

第三行的 `origin.example.com` 不是可选项：加速节点靠它找到源站；
加速节点出问题的时候，你也靠它直接摸到源站看看。

---

## 8. 缓存省下什么，不省什么

缓存就是门口一个架子。第一个人要某个文件，得有人跑到后屋去拿；
后面的人，直接从架子上取走。

<FigRows :arrow="0" :head="['谁来要', '发生什么']" :rows="[
  ['第一个访客要 logo.png', '加速节点没见过 —— 去源站取一份，留一份在架子上，再给他'],
  ['后面一万个人', { t: '直接从架子上拿。源站根本不知道有这回事。', tone: 'accent' }],
  ['有人往购物车里加东西', { t: '永远不缓存、永远不上架 —— 每次都去源站', tone: 'strong' }],
]" />

这笔账要算清楚，其中有一行会让人意外：

| | 缓存省得掉吗 |
|---|---|
| **加速节点发给访客的流量** | **省不掉。** 访客要什么都得从这台发出去，命中不命中一个样。这个数就是你要塞进额度里的数。 |
| **加速节点回源取的流量** | **能省掉绝大部分。** 而且流进来的也算额度，所以这是真省，不是账面上好看。 |
| **源站的 CPU、内存、磁盘** | **省很多。** 命中一次，就是少跑一次 PHP。 |
| **访客等的时间** | **省。** 命中的请求，少跑一个来回。 |

拿数字过一遍。假设你的站一个月要发给访客 300 GB：

| | 加速节点被计的流量 |
|---|---|
| 完全不缓存 | 出去 300 GB ＋ 回源取回 300 GB ＝ **600 GB** |
| 八成能缓存、也缓存了 | 出去 300 GB ＋ 回源取回 60 GB ＝ **360 GB** |

hqnode 的容器**进出两个方向都计流量**（见[使用你的容器](using-your-container.md) §3），
所以缓存等于把贵机器上的开销砍掉一半。快是白送的。

**加速节点按流量挑，别按核数挑。** 一核一 GB 发静态文件绰绰有余，
先见底的一定是流量。

---

## 9. 动手搭

例子：店铺是 `www.example.com`，加速节点那台机器 `203.0.113.10`，
源站那台 `203.0.113.20`。

### 第 1 步 —— 要两个容器

跟主机方开口，要两个：一个在三网优化的机器上，一个在便宜的高配机器上，
**而且要同一个城市**。「同一个地区」不算数 —— 香港到东京 50 毫秒，
这 50 毫秒会加在每一个没命中的请求上。

直接告诉主机方你要干什么。挑两台物理上挨着的机器，对他们是举手之劳；
对你来说，从外面根本没法验证。

### 第 2 步 —— 网站装在源站上

这一半没有任何特别的地方，就是一台普通机器上的一次普通部署：
[部署 LNMP 网站](deploy-lnmp.md)、[部署 Node.js 程序](deploy-nodejs.md)，
或者你本来就有的那一套。

### 第 3 步 —— 给源站一个名字

在源站的容器里：

```sh
app-setup domain add origin.example.com 80
```

这样拿到的是机器替你打理的证书，这里正合适 —— 这个名字上没什么秘密，
还少一样要惦记着续期的东西。先把 `origin.example.com` 的 DNS 加好，
否则证书签不下来：一条 A 记录，指向 `203.0.113.20`。

往下走之前先验一下：

```sh
curl -I https://origin.example.com/
```

不是 `200` 就停在这儿。后面每一步都建立在这一步上。

### 第 4 步 —— 加速节点上装 nginx

在加速节点的容器里：

```sh
app-setup install nginx
```

配置写进一个文件。Alpine 是 `/etc/nginx/http.d/cdn.conf`，
Debian 和 Ubuntu 是 `/etc/nginx/conf.d/cdn.conf`：

```nginx
# 缓存放在哪、最多放多少。/data 重装容器不会丢；缓存本来也不用留着，
# 不过磁盘额度反正是一起算的。
proxy_cache_path /data/cache levels=1:2 keys_zone=site:20m
                 max_size=4g inactive=7d use_temp_path=off;

# 带这些 cookie 的请求是属于某一个人的，绝不能发给另一个人。
# 你自己的购物车和会话 cookie，也加进来。
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
    # 443 上的 HTTPS，机器已经替你解完了
    listen 80;
    server_name www.example.com example.com;

    # 这条线以下的设置，下面三个 location 都会继承。
    proxy_http_version 1.1;
    proxy_set_header Connection "";

    # 回源握手时报这个名字，源站那台机器的大门靠它认出是谁的站；
    # 请求里带的仍然是访客输入的那个名字。
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

    # 图片、样式、脚本：存一个月。视频故意没写进来 ——
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

nginx 自带的那个默认站点，放着别管。它没写 `server_name`，
只接谁都匹配不上的请求。

### 第 5 步 —— 把真正的域名加到加速节点上

在加速节点的容器里：

```sh
app-setup domain add www.example.com 80
app-setup domain add example.com 80
```

机器在 443 上把 HTTPS 解开、证书自己续，然后用明文 HTTP 送进容器的 80 端口。
所以上面那份配置监听的是 80，而且从头到尾没有一张证书。
它还会在 nginx 看到请求之前把 `X-Forwarded-For` 填好，
源站日志里记的就是访客的地址，不是香港的。

想自己拿着证书？`app-setup domain add www.example.com 8443 self-hosted`，
TLS 改在 nginx 里终结。两种做法的取舍写在[跑一个代理或 VPN](proxy.md) §7。

### 第 6 步 —— 解析域名

就是 §7 那三条记录。加完等几分钟。

### 第 7 步 —— 确认架子在用

```sh
curl -sI https://www.example.com/logo.png | grep -i x-cache
curl -sI https://www.example.com/logo.png | grep -i x-cache
# 第一次是  X-Cache: MISS
# 第二次是  X-Cache: HIT
```

先 `MISS` 后 `HIT`，就是通了。第二次还是 `MISS`，§10 里有四种常见原因。

**改完东西想把缓存全清掉：**

```sh
rm -rf /data/cache/*
nginx -s reload
```

---

## 10. 会出的问题

| 你看到的 | 通常是什么 |
|---|---|
| **一直 `MISS`，从来不 `HIT`** | 源站每个响应都在发 `Set-Cookie` 或者 `Cache-Control: no-cache`。WordPress 装了某些插件、每个页面都开会话，就会这样。要么在源站改掉，要么在 `location /` 里加 `proxy_ignore_headers Set-Cookie;` —— 加之前先看下一行。 |
| **一个客户看到了别人的购物车** | 你把不该缓存的东西缓存了。这个故障赔掉的是一个客户，不是一秒钟。§9 里第二个 `location` 列的那几条路径、还有那个 cookie 的 `map`，全是为了挡这件事。自己试一遍：登录，往购物车加一件，再开无痕窗口打开同一个页面。 |
| **换了图片，访客看到的还是旧的** | 它按你写的在架子上放三十天，没错。清一次缓存；更省事的办法是换文件名 —— `logo.v2.png` —— 以后再也不用管这事。 |
| **加速节点的流量额度一周就没了** | 按核数挑机器就会这样。访客要的每一个字节都从它这里过。账在 §8。 |
| **一直跳转，跳不完** | 源站在往它自己的名字上跳。`proxy_set_header Host $host;` 要原样保留 —— 源站必须看到访客输入的那个名字，不是 `origin.example.com`。 |
| **源站日志里整个互联网只有一个 IP** | 源站没读 `X-Forwarded-For`。那是源站上那个程序的设置，跟这边无关。 |
| **加速节点报 `502`** | 它连不上源站。在加速节点的容器里跑一次 `curl -I https://origin.example.com/`。 |
| **`origin.example.com` 被搜索引擎收录了** | 它本来就是你店铺一份能访问的完整副本，不收录才怪。让源站在被请求的名字是 `origin.example.com` 时返回 `X-Robots-Tag: noindex`。 |

**有一个坑得单独拎出来：两个容器别放在同一台机器上。**
放一起不只是把整件事的意义抵消掉 —— 照上面写的它根本跑不起来。
容器去连自己那台机器的公网地址，连到的是它自己，不是隔壁那个容器。
于是加速节点转给自己，转成死循环。两台机器，两个地址。

---

## 11. 什么时候别搭这套

这是一件实打实要花功夫的事，而且多了一样会坏的东西。下面几种情况，直接跳过：

<FigRows :arrow="0" :head="['如果你是这种', '那就这样']" :rows="[
  ['客户全在国外', '一台普通机器就够。那份溢价你本来就不用付。'],
  ['客户全在国内', '直接买国内机器，域名去备案。比这页任何方案都又便宜又快。'],
  ['站很小，一个月几个 GB', '一个三网优化的容器，网站直接跑上面。为这点量搭两台不值。'],
  ['要在十个国家都快', '买商业 CDN。这套只有一个前置节点，人家有两百个。'],
]" />

这套方案两台机器都在境外，所以整页没提备案。源站一旦挪进大陆境内，
域名必须先备案，才能在 80 和 443 上对外服务 —— 那是换方案，不是改配置。

最后：拿不准这条贵线路值不值，就先买一个月小的那台，把一个页面复制上去，
晚上九点比一次。这是整页里最便宜的一次实验。

---

## 接下来

- [快速上手](quick-start.md) —— 域名、DNS 和 HTTPS，一步一张图。没做过就先做这个。
- [部署 LNMP 网站](deploy-lnmp.md) · [部署 Node.js 程序](deploy-nodejs.md) ——
  源站上放什么。
- [使用你的容器](using-your-container.md) §3 —— 流量额度怎么算的，跑满了会怎样。
- [公网端口](ports.md) —— 前置节点后面那个东西不是网站的时候，看这里。
- [跑一个代理或 VPN](proxy.md) §7 —— 两种证书模式，完整版。
