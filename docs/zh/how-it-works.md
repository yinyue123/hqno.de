---
title: 它是怎么工作的
---

# 它是怎么工作的

有人把一台 Linux 机器切成几份卖。每一份用起来都像一台自己的小电脑。这一页告诉你，
其中哪些东西是你的 —— 先拿一件多数人租过的东西打个比方，再用七张图画它本来的样子。

**也可以跳过 —— 看你是哪一种：**

<FigRows :arrow="0" :rows="[
  ['有人给了你一串码', '快速上手'],
  ['你手上有机器', '自己跑一台机器'],
]" />

- [**快速上手**](quick-start.md) —— 别人发了你一串分享码。领取、登进去、装个网站、
  把域名指过来、拿到小锁。十二步，每步都有图。
- [**自己跑一台机器**](running-a-machine.md) —— 你租了一台服务器，或者自己有硬件，
  想把它切成容器发出去。

---

## 租的是一间房，不是一整套

你到大城市上班。整租一套三室一厅太夸张了：白天你不在家，晚上回来睡一觉。
所以你在里面**租一间房**，厨房是大家的。

这整个产品就是这么回事，只不过把房子换成了电脑。六张图，然后同一件事再讲一遍，
不打比方。

**整套对一个人来说太多了。**

<svg class="fig" viewBox="0 0 660 190" role="img" aria-label="一整套房子里只住一个人，旁边是一整台机器上只跑一个小网站">
  <text class="t c" x="165" y="20">在合租房里</text>
  <text class="t c" x="495" y="20">在这里</text>
  <path class="rule" d="M330,30 V174"/>
  <rect class="box" x="20" y="36" width="290" height="110" rx="6"/>
  <text class="s" x="34" y="58">三室一厅 · 一个厨房 · 两个卫生间</text>
  <rect class="mine" x="34" y="90" width="80" height="38" rx="4"/>
  <text class="c" x="74" y="114">你</text>
  <text class="s" x="126" y="114">白天一直空着</text>
  <text class="s c" x="165" y="170">整套的租金，你一个人付</text>
  <rect class="box" x="350" y="36" width="290" height="110" rx="6"/>
  <text class="s" x="364" y="58">8 核 · 32 GB · 1 TB · 一个独立地址</text>
  <rect class="mine" x="364" y="90" width="80" height="38" rx="4"/>
  <text class="c" x="404" y="114">你的网站</text>
  <text class="s" x="456" y="114">大半天闲着</text>
  <text class="s c" x="495" y="170">整台机器的钱，你一个人付</text>
</svg>

一台机器出厂就是 8 核、32 GB 内存、1 TB 磁盘，外加一个自己的地址。
一个小网站用掉的是零点几个核、几百兆内存，而且一天里大半时间是睡着的。
整台租下来，等于租一整套房子，只为了放一张床。

**所以有人把它隔开。**

<svg class="fig" viewBox="0 0 660 210" role="img" aria-label="一套房子隔成三间房，共用厨房；一台机器切成三份，共用同一个 Linux">
  <text class="t c" x="165" y="20">在合租房里</text>
  <text class="t c" x="495" y="20">在这里</text>
  <path class="rule" d="M330,30 V196"/>
  <rect class="mine" x="20" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="67" y="72">你的</text>
  <text class="s c" x="67" y="92">一床一桌</text>
  <rect class="box" x="118" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="165" y="80">bob 的</text>
  <rect class="box" x="216" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="263" y="80">carol 的</text>
  <rect class="box" x="20" y="116" width="290" height="36" rx="4"/>
  <text class="c" x="165" y="139">厨房 · 卫生间 · 大门</text>
  <text class="s c" x="165" y="174">你的房门上锁</text>
  <text class="s c" x="165" y="190">厨房是大家的</text>
  <rect class="mine" x="350" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="397" y="68">你的</text>
  <text class="s c" x="397" y="88">1 核 · 2 GB</text>
  <text class="s c" x="397" y="103">20 GB 磁盘</text>
  <rect class="box" x="448" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="495" y="68">bob 的</text>
  <text class="s c" x="495" y="88">½ 核 · 1 GB</text>
  <rect class="box" x="546" y="40" width="94" height="72" rx="4"/>
  <text class="c" x="593" y="68">carol 的</text>
  <text class="s c" x="593" y="88">2 核 · 4 GB</text>
  <rect class="box" x="350" y="116" width="290" height="36" rx="4"/>
  <text class="c" x="495" y="139">一个 Linux · 一台机器 · 一个地址</text>
  <text class="s c" x="495" y="174">你那一份是你的</text>
  <text class="s c" x="495" y="190">机器是共用的</text>
</svg>

墙一砌，房间就可以一间一间往外租。你那间是你的 —— 你的钥匙、你的东西，别人进不来。
厨房、卫生间、大门是共用的，这样用起来也没什么问题。

在这里，你那一间叫**容器**：你的文件、你装的软件、你跑的服务，你是它的管理员。
共用的是底下那个 Linux、那台机器，还有对外的那一个地址。
你看不到别人那份里面，别人也看不到你的。

**你自己的钥匙。**

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="三把钥匙开三个房间，旁边是三条 ssh 命令进三个容器">
  <defs><marker id="k1" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t c" x="156" y="20">在合租房里</text>
  <text class="t c" x="485" y="20">在这里</text>
  <path class="rule" d="M310,30 V184"/>
  <circle class="lnA" cx="32" cy="56" r="7"/>
  <path class="lnA" d="M39,56 H64 M58,56 V62 M50,56 V62"/>
  <path class="ln" d="M74,56 H152" marker-end="url(#k1)"/>
  <rect class="mine" x="160" y="41" width="132" height="30" rx="4"/>
  <text class="c" x="226" y="61">你的房间</text>
  <circle class="ln" cx="32" cy="96" r="7"/>
  <path class="ln" d="M39,96 H64 M58,96 V102 M50,96 V102"/>
  <path class="ln" d="M74,96 H152" marker-end="url(#k1)"/>
  <rect class="box" x="160" y="81" width="132" height="30" rx="4"/>
  <text class="c" x="226" y="101">bob 的房间</text>
  <circle class="ln" cx="32" cy="136" r="7"/>
  <path class="ln" d="M39,136 H64 M58,136 V142 M50,136 V142"/>
  <path class="ln" d="M74,136 H152" marker-end="url(#k1)"/>
  <rect class="box" x="160" y="121" width="132" height="30" rx="4"/>
  <text class="c" x="226" y="141">carol 的房间</text>
  <text class="s c" x="156" y="176">同一个大门，三把不同的钥匙</text>
  <text class="m" x="326" y="61">ssh <tspan class="a">alice</tspan>@203.0.113.7</text>
  <path class="ln" d="M486,56 H528" marker-end="url(#k1)"/>
  <rect class="mine" x="536" y="41" width="109" height="30" rx="4"/>
  <text class="c" x="590" y="61">你的那份</text>
  <text class="m" x="326" y="101">ssh bob@203.0.113.7</text>
  <path class="ln" d="M486,96 H528" marker-end="url(#k1)"/>
  <rect class="box" x="536" y="81" width="109" height="30" rx="4"/>
  <text class="c" x="590" y="101">bob 的那份</text>
  <text class="m" x="326" y="141">ssh carol@203.0.113.7</text>
  <path class="ln" d="M486,136 H528" marker-end="url(#k1)"/>
  <rect class="box" x="536" y="121" width="109" height="30" rx="4"/>
  <text class="c" x="590" y="141">carol 的那份</text>
  <text class="s c" x="485" y="176">同一台机器：203.0.113.7</text>
</svg>

所有人都从同一个大门进，手上那把钥匙决定开的是哪一间。
在这里，大门就是那台机器的地址 —— `203.0.113.7`，机器上所有人都用这一个；
钥匙就是你的用户名，`@` 前面那一段，就是决定你进哪一间的全部依据。

**门上写着你的名字。**

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="一封信送到写着你名字的那扇门，旁边是访客输入的域名到达你那一份">
  <defs><marker id="k2" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path class="ink" d="M0,0 L10,5 L0,10 z"/></marker></defs>
  <text class="t c" x="165" y="20">在合租房里</text>
  <text class="t c" x="495" y="20">在这里</text>
  <path class="rule" d="M330,30 V184"/>
  <rect class="box" x="20" y="78" width="76" height="46" rx="3"/>
  <path class="ln" d="M20,78 L58,106 L96,78"/>
  <text class="s c" x="58" y="142">写着你的名字</text>
  <path class="ln" d="M104,101 H142" marker-end="url(#k2)"/>
  <rect class="box" x="150" y="42" width="160" height="34" rx="4"/>
  <text class="c" x="230" y="64">bob</text>
  <rect class="mine" x="150" y="84" width="160" height="34" rx="4"/>
  <text class="c" x="230" y="106">你</text>
  <rect class="box" x="150" y="126" width="160" height="34" rx="4"/>
  <text class="c" x="230" y="148">carol</text>
  <text class="s c" x="165" y="182">同一个门牌号，名字决定给谁</text>
  <text class="s" x="350" y="82">访客输入</text>
  <text class="m a" x="350" y="105">shop.example.com</text>
  <path class="ln" d="M472,101 H500" marker-end="url(#k2)"/>
  <rect class="box" x="508" y="42" width="132" height="34" rx="4"/>
  <text class="c" x="574" y="64">bob 的那份</text>
  <rect class="mine" x="508" y="84" width="132" height="34" rx="4"/>
  <text class="c" x="574" y="106">你的那份</text>
  <rect class="box" x="508" y="126" width="132" height="34" rx="4"/>
  <text class="c" x="574" y="148">carol 的那份</text>
  <text class="s c" x="495" y="182">同一个机器地址，域名决定给谁</text>
</svg>

信都送到同一个门牌号，门上的名字决定这封是谁的。
在这里，一台机器对外只有一个地址，**访客输入的那个域名**决定由哪一份来回答。
指到你这一份上的域名，在你持有期间就是你的，同一台机器上的别人抢不走。

**房间是带家具的。**

<svg class="fig" viewBox="0 0 660 200" role="img" aria-label="房间里有床、桌子和台灯，旁边是已经跑着 Linux、还带一个安装菜单的容器">
  <text class="t c" x="165" y="20">在合租房里</text>
  <text class="t c" x="495" y="20">在这里</text>
  <path class="rule" d="M330,30 V184"/>
  <rect class="box" x="20" y="36" width="290" height="112" rx="6"/>
  <rect class="ln" x="36" y="66" width="86" height="46" rx="4"/>
  <rect class="ln" x="42" y="72" width="24" height="34" rx="3"/>
  <text class="s c" x="79" y="132">一张床</text>
  <path class="ln" d="M140,80 H216 M146,80 V112 M210,80 V112"/>
  <text class="s c" x="178" y="132">一张桌子</text>
  <path class="ln" d="M242,74 L274,74 L266,54 L250,54 Z M258,74 V114 M244,114 H272"/>
  <text class="s c" x="258" y="132">一盏灯</text>
  <text class="s c" x="165" y="176">衣服你自己带</text>
  <rect class="box" x="350" y="36" width="290" height="112" rx="6"/>
  <text class="t" x="364" y="60">Alpine 3.24，已经在跑了</text>
  <rect class="box" x="364" y="74" width="64" height="26" rx="13"/>
  <text class="s c" x="396" y="91">nginx</text>
  <rect class="box" x="434" y="74" width="72" height="26" rx="13"/>
  <text class="s c" x="470" y="91">MariaDB</text>
  <rect class="box" x="512" y="74" width="52" height="26" rx="13"/>
  <text class="s c" x="538" y="91">PHP</text>
  <rect class="box" x="570" y="74" width="56" height="26" rx="13"/>
  <text class="s c" x="598" y="91">Node</text>
  <text class="s" x="364" y="126">按一下就装上，随你挑哪个</text>
  <text class="s c" x="495" y="176">代码你自己带</text>
</svg>

你要住一年，也可能就住几个月。没人为这个去买张床，
所以房间里本来就有床、有桌子、有台灯，你带自己的衣服过来就行。

你的容器交到手上时，里面的 Linux 已经在跑了 —— 用的是 Alpine，它本身够小，
你买的那点内存能省下来给自己的软件用。它还带一个菜单，剩下的东西由它来装：
网站服务器、数据库、WordPress、Node。你把自己的代码传上去就行。

**门上还有一把锁。**

<svg class="fig" viewBox="0 0 660 196" role="img" aria-label="自己配的锁和楼里统一的锁，旁边是两种情况下访客看到的同一个小锁">
  <text class="t c" x="165" y="20">在合租房里</text>
  <text class="t c" x="495" y="20">在这里</text>
  <path class="rule" d="M330,30 V180"/>
  <path class="ln" d="M28,62 a6,6 0 0 1 12,0"/>
  <rect class="ln" x="24" y="62" width="20" height="16" rx="3"/>
  <text class="t" x="58" y="74">自己配的锁</text>
  <text class="s" x="58" y="94">钥匙只有你有</text>
  <path class="ln" d="M28,128 a6,6 0 0 1 12,0"/>
  <rect class="ln" x="24" y="128" width="20" height="16" rx="3"/>
  <text class="t" x="58" y="140">楼里统一的锁</text>
  <text class="s" x="58" y="160">楼下前台也有一把</text>
  <rect class="box" x="350" y="52" width="196" height="30" rx="15"/>
  <path class="lnA" d="M370,66 a5,5 0 0 1 10,0"/>
  <rect class="lnA" x="366" y="66" width="18" height="14" rx="3"/>
  <text class="m" x="394" y="72">example.com</text>
  <text class="s" x="350" y="102">自己的证书 —— 路上没有人打得开</text>
  <rect class="box" x="350" y="126" width="196" height="30" rx="15"/>
  <path class="lnA" d="M370,140 a5,5 0 0 1 10,0"/>
  <rect class="lnA" x="366" y="140" width="18" height="14" rx="3"/>
  <text class="m" x="394" y="146">example.com</text>
  <text class="s" x="350" y="176">主机方托管 —— 机器打得开，也帮你续期</text>
</svg>

自己配的锁，钥匙只有你有，楼下谁也打不开；用楼里统一的锁，前台帮你配、坏了帮你换，
也打得开你的门。在这里，这把锁就是**证书** —— 让浏览器地址栏出现小锁的那个东西 ——
两条路你可以按域名分别选。而访客那边看到的小锁，两种都一样。

**整个比方，列成一张表：**

| 在合租房里 | 在这里 |
|---|---|
| 把房子隔开往外租的二房东 | 你的**主机方** |
| 你那一间房 | 你的**容器** |
| 一张床、一张桌子、一盏灯 | 已经跑起来的 Linux，和一个负责装其余东西的菜单 |
| 你的钥匙 | 你的 ssh 用户名和密码 |
| 门上你的名字 | 你的域名 |
| 厨房和大门 | 底下那个 Linux，和机器对外的那一个地址 |
| 你自己配的锁 | 你自己的证书 |
| 楼里统一的锁 | 主机方托管的证书 |
| 租期 | 你这一份的到期时间 |
| 水电费 | 你每个月的流量额度 |

这个比方到哪里为止：合租房里，墙就是墙。在这里，把各家隔开的是底下那个 Linux，
而那是主机方的 —— 就像二房东手上有一把万能钥匙，楼里哪扇门都开得了，这里也一样。

这一页剩下的部分，是把同一件事按它本来的样子再画一遍。

---

## 整件事，一张图

<FigRows :arrow="1" :rows="[
  [{ t: '你', tone: 'strong' }, { t: '面板', tone: 'strong' }, { t: '「去做这个」→ 那台机器', tone: 'mute' }],
  [{ t: '你，用 ssh', tone: 'strong' }, { t: '你的那份', tone: 'accent' }, { t: '就在那台机器上', tone: 'mute' }],
  [{ t: '你的访客', tone: 'strong' }, { t: '你的那份', tone: 'accent' }, { t: 'bob 的、carol 的，也都在', tone: 'mute' }],
]" />

后面反复出现的三个词：**面板**是你登录的那个网站，**机器**是跑着你这一份的那台电脑，
**主机方**是这台机器的主人。你是**持有者** —— 机器上有一份是你的。

---

## 一台机器，切成几份

一台机器，底下是同一个 Linux：

| 你的 | bob 的 | carol 的 | … |
|---|---|---|---|
| 1 核 | ½ 核 | 2 核 | |
| 2 GB | 1 GB | 4 GB | |
| 20 GB | 10 GB | 80 GB | |

你那一份叫**容器**，用起来就像一台自己的小电脑：自己的文件、自己装的软件、自己的服务。
你是它的管理员。你看不到别人那份里面，别人也看不到你的。

那几个数字是主机方卖给你的额度 —— CPU、内存、磁盘，还有每月流量。碰到上限会发生什么，
写在[使用你的容器](using-your-container.md)里。

---

## 你的登录凭什么是你的：用户名

<FigRows :arrow="0" :rows="[
  [{ m: 'ssh alice@203.0.113.7', hi: 'alice' }, '你的那份'],
  [{ m: 'ssh bob@203.0.113.7', hi: 'bob' }, 'bob 的那份'],
  [{ t: '唯一的区别，就是这一段', face: 'small', tone: 'mute' }, null],
]" />

同一个地址、同一个门，进的是不同的房间。`@` 前面那个名字，就是决定你进哪间的全部依据。

<FigRows :arrow="0" :rows="[
  ['在面板里改密码', '会改变你怎么登进去'],
  ['在容器里面改', { t: '什么都不会变', tone: 'mute' }],
  ['把容器整个重装', '你的登录照样能用'],
]" />

密码是在机器的大门口验的，不在你的容器里面。所以改密码要在面板上改；也所以把容器擦掉
重装，不会让你丢掉进去的路。

---

## 你的网站凭什么是你的：域名

<FigRows :arrow="0" :head="['访客输入什么', '到哪里']" :rows="[
  [{ m: 'shop.example.com' }, '你的那份，端口 80'],
  [{ m: 'api.example.com' }, '你的那份，端口 3000'],
  [{ m: 'blog.bob.dev' }, 'bob 的那份，端口 80'],
]" />

一台机器可以服务任意多个网站，**访客输入的那个域名**决定由哪一份来回答。由此有两件事：

- 你的网址是正常的网址，后面不用挂端口号；
- 指到你这一份上的域名，在你持有期间就是你的 —— 同机器上的别人抢不走。

在你那一份里面，你想跑多少个服务都行，每个域名可以指到不同的服务上。

---

## 不会命令行也没关系

大多数人从来没敲过命令，也没人想去记自己这个 Linux 今年把软件包叫什么名字。所以有个菜单。
敲一个词：

```
  root@wp-1:~# app-setup
```

<FigScreen :tabs="['套件安装', 'Web 服务器', '数据库', '开发插件', '系统']" :lines="[
  [{ t: '▸', tone: 'accent' }, { t: 'LNMP', tone: 'accent' }, { t: '网站服务器 + 数据库 + PHP', tone: 'mute' }],
  ['', 'WordPress', { t: '十个网站里四个在用的建站软件', tone: 'mute' }],
  ['', 'MariaDB', { t: '只要数据库', tone: 'mute' }],
  ['', 'Node.js', { t: '…', tone: 'mute' }],
  [{ t: '磁盘 600M   内存 768M', face: 'small', tone: 'mute' }],
  [{ t: '↑↓←→ 移动     回车 打开     ↑ 走到顶是「返回」', face: 'small', tone: 'mute' }],
]" />

回车打开光标那一项，真正干活的是它自己那一页：

<FigScreen title="WordPress" :lines="[
  { pack: true, cols: [{ b: '安装' }, { b: '启动' }, { b: '开机自启' }, { b: '参数设置' }] },
  { pack: true, cols: [{ b: '使用说明' }, { b: '日志' }] },
  [{ t: '十个网站里有四个在用的建站软件。会自己把数据库也装好。', tone: 'mute' }],
  [{ t: '磁盘 800M   内存 768M   端口 80', face: 'small', tone: 'mute' }],
]" />

界面本身是双语的 —— 按 `L` 在中英文之间切换。

<FigRows :arrow="0" :rows="[
  ['装的是普通软件、放在普通位置', '以后看的教程照样对得上'],
  ['每一项都写着自己占多大', '装不下会标红'],
  ['「使用说明」列出它写过的文件', '不用自己去找'],
]" />

它装软件的方式，跟一个照着博客文章一步步做的人是一样的。所以你以后看到的教程还是对的，
更新照旧从 `apt` 或 `dnf` 来。想手动做的部分，你随时可以手动做。

[快速上手](quick-start.md)会带你一步步用它。

---

## 拿到小锁的两条路

<FigRows :arrow="0" :rows="[
  [{ t: '自己的证书', tone: 'strong' }, null, null],
  [{ t: '访客', face: 'small' }, { t: '一路加密到你的那份', tone: 'accent' }, { t: '机器原样转发、不解开', face: 'small', tone: 'mute' }],
  [null, null, { t: '证书由你自己申请、自己续期', face: 'small', tone: 'mute' }],
  [{ t: '主机方托管的证书', tone: 'strong' }, null, null],
  [{ t: '访客', face: 'small' }, { t: '加密到机器，明文进你的那份' }, { t: '机器解开、再转给你', face: 'small', tone: 'mute' }],
  [null, null, { t: '证书由机器保管，到期前自己续', face: 'small', tone: 'mute' }],
]" />

**证书**就是让地址栏出现小锁的那个东西。你有两条路，而且可以按域名分别选：

| | 自己的证书 | 主机方托管 |
|---|---|---|
| 你要做什么 | 自己申请、自己续期 | 按一次按钮 |
| 主机方能看到你的流量吗 | 不能 | 能 |
| 什么时候选它 | 你已经有证书了，或者上一行的答案必须是「不能」 | 你只想要小锁，不想操心 |

两条路的前提是同一件事：域名得先指到那台机器。所以「快速上手」先把域名弄好，再去要证书。

---

## 面板不在中间挡着

<FigRows :arrow="0" :rows="[
  [{ t: '你', tone: 'strong' }, { t: '面板' }, { t: '「帮我重启一下」→ 那台机器', tone: 'mute' }],
  [{ t: '访客', tone: 'strong' }, { t: '你的网站', tone: 'accent' }, { t: '中间不经过面板', tone: 'mute' }],
]" />

面板不在第二行上。面板挂了的时候，你的网站照样回应，你的登录照样能用，你装的东西照样在跑 ——
只是它上面的按钮得等一等。

---

## 接下来

- [快速上手](quick-start.md) —— 从一串分享码到一个跑起来的网站。
- [自己跑一台机器](running-a-machine.md) —— 这件事的另一面。

侧栏的**进阶**是以后再看、甚至不用看的东西：碰到限额是什么感觉、重装会拿掉什么，看
[使用你的容器](using-your-container.md)；想用的系统不在已发布列表里，看
[自己做镜像](building-your-own-image.md)；想在安装菜单里加自己的条目，看
[添加你自己的软件](/app-setup-sources)（英文）。走完「快速上手」，这些一个都不需要。
