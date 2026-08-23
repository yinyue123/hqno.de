---
title: 快速上手
---

# 快速上手

有人给了你一串分享码。走完这一页，你会有一个属于自己的网站，用自己的域名，地址栏里带小锁。

全程用同一个例子，你可以拿自己的屏幕逐行对：

<FigRows :rows="[
  [{ t: '账号', tone: 'mute' }, { m: 'ana' }],
  [{ t: '容器', tone: 'mute' }, { m: 'wp-1' }, { t: '在机器', tone: 'mute' }, { m: 'hk-1.example.com' }],
  [{ t: '域名', tone: 'mute' }, { m: 'example.com' }, { t: '和', tone: 'mute' }, { m: 'www.example.com' }],
  [{ t: '机器地址', tone: 'mute' }, { m: '203.0.113.7' }],
]" />

你的每个值都会不一样，除此之外都一样。

<FigRows :rows="[
  [{ t: '1', tone: 'accent' }, '领取分享码', { t: '6', tone: 'accent' }, '把域名指到机器上'],
  [{ t: '2', tone: 'accent' }, '两个密码', { t: '7', tone: 'accent' }, '把每个域名分流到对应的服务'],
  [{ t: '3', tone: 'accent' }, '登进去', { t: '8', tone: 'accent' }, '开启 HTTPS'],
  [{ t: '4', tone: 'accent' }, '装个网站', { t: '9', tone: 'accent' }, '出问题时去哪看日志'],
  [{ t: '5', tone: 'accent' }, '添加你的域名', null, null],
]" />

第 1 到 4 步只要那串码就够了。第 5 步开始需要一个域名 —— 随便哪家买都行，一年也就一杯咖啡钱。

---

## 1. 领取分享码

别人发给你的东西，长这样两种之一：

<FigRows :rows="[
  [{ m: 'https://hqno.de/redeem?code=HQ-7F3K-2M9P' }],
  [{ m: 'HQ-7F3K-2M9P' }],
]" />

打开那个链接，或者进面板的 **容器 → 兑换分享码**。没登录的话它会先让你登录或注册，然后自己
回到这串码上。注册只问用户名、邮箱和密码，别的不问 —— 这里只有一种账号，一个账号可以持有
任意多个人给你的容器。

<FigScreen title="兑换分享码" :lines="[
  ['分享码', { f: 'HQ-7F3K-2M9P' }],
  ['Shell 用户名', { f: 'ana', note: '可选' }],
  ['Shell 密码', { f: '', note: '留空则生成' }],
  { align: 'right', cols: [{ b: '领取' }] },
]" />

下面两栏留空就自动帮你生成。**你应该看到：**

<FigScreen title="归你了" :lines="[
  [{ m: 'ssh u7k2m9p@hk-1.example.com' }],
  { cols: ['密码', { t: '8Kd2-vQx7-mR', face: 'mono' }, { t: '只显示一次', face: 'small', tone: 'bad' }] },
  [{ t: '离开页面前先把密码复制走 —— 面板不保存它。', face: 'small', tone: 'mute' }],
]" />

离开页面之前先把密码存到安全的地方。它只显示这一次，别处都没有；丢了只能重设一个，找不回来
（第 2 步）。

还有两件事现在就该知道：领取会把登录名和密码重写，所以发码给你的人从此进不来了。另外，码在
生成后 **14 天**失效 —— 过期的码不等于容器丢了，跟对方再要一串新的就行。

**如果账号是别人替你开的**，你有用户名但还没有密码。用**忘记密码**填主机方给的那个邮箱，
邮件里的链接会把它变成一个你能登录的账号。

---

## 2. 两个密码

最容易搞混的一件事。你有两个密码，开的是不同的东西：

<FigRows :arrow="0" :rows="[
  [{ t: '面板密码', tone: 'strong' }, '你登录的那个网站'],
  [{ t: 'shell 密码', tone: 'strong' }, '你的那份容器'],
]" />

第一个在 **账号** 页面改：

<FigScreen title="账号" :lines="[
  ['用户名', { t: 'ana', face: 'mono' }],
  { cols: ['邮箱', { t: 'ana@example.com', face: 'mono' }, { b: '修改' }] },
  { cols: ['密码', { t: '••••••••', face: 'mono' }, { b: '修改' }] },
]" />

第二个在容器页面的 **操作 → Shell 登录 → 重置密码**：

<FigScreen title="重设 shell 登录" :lines="[
  ['Shell 用户名', { f: 'u7k2m9p' }],
  ['新密码', { f: '', note: '留空则生成一个' }],
  { align: 'right', cols: [{ b: '设置' }] },
]" />

新密码只显示一次，旧的立刻失效 —— 所以别在正忙着别的事的时候做这一步。面板里的用户名永远
不变；上面那个 shell 用户名是另一个名字，想改多少次都行。

想用密钥而不是密码登录？在**账号 → SSH 公钥**里贴一把。它会落到这个账号持有的每一个
容器上，包括以后才拿到的那些。

---

## 3. 登进去

容器页面上写着你要的三样东西 —— **用户**、**主机**，以及主机后面那个端口。拼起来就是命令：

<FigRows :rows="[
  [{ m: 'ssh u7k2m9p@hk-1.example.com' }, { t: '端口是 22', tone: 'mute' }],
  [{ m: 'ssh u7k2m9p@hk-1.example.com -p 2222' }, { t: '其它端口', tone: 'mute' }],
]" />

然后打开一个终端：

<FigRows :rows="[
  [{ t: 'Windows 10 或更新', tone: 'strong' }, 'PowerShell，或者 Terminal'],
  [{ t: 'macOS', tone: 'strong' }, 'Terminal'],
  [{ t: 'Linux', tone: 'strong' }, '任意终端'],
]" />

```
  $ ssh u7k2m9p@hk-1.example.com
  The authenticity of host 'hk-1.example.com' can't be
  established. Continue connecting? yes
  Password:                    ← 粘贴密码；屏幕上不会有反应
  root@wp-1:~#
```

输入或粘贴密码时屏幕上什么都不显示，这是故意的，不是键盘坏了。那句 authenticity 的问题只在
第一次出现。

**你应该看到**一个以 `#` 结尾的提示符。现在你是自己这套系统的管理员：

```
  root@wp-1:~# free -h        有多少内存
  root@wp-1:~# df -h /        有多少磁盘
  root@wp-1:~# systemctl      有什么在跑
  root@wp-1:~# reboot         重启你这一份，很安全
```

如果进不去，跳到[第 10 步](#_10-出问题的时候)—— 常见原因就是密码不对，或者容器已经停了。

---

## 4. 装个网站

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

<FigRows :rows="[
  [{ t: '↑ ↓ ← →' }, '移动', { t: 'L', tone: 'accent' }, '中英文切换'],
  [{ t: '回车' }, '打开', { t: 'q', tone: 'accent' }, '退出'],
  [{ t: '↑ 走到顶' }, '返回', null, { t: '鼠标也能用', tone: 'mute' }],
]" />

第一次建站，从这两个里挑一个，回车进去，按 `[安装]`：

<FigRows :rows="[
  [{ t: 'LNMP', tone: 'strong' }, '网站服务器、数据库和 PHP，已经接好'],
  [{ t: 'WordPress', tone: 'strong' }, '同上，另外再装 WordPress 和它的数据库'],
]" />

按之前先看那一行占用 —— 你这一份装不下的时候它会**标红**，这是没人在装了四分钟之后才告诉你
的那个数字：

<FigRows :rows="[
  [{ t: '磁盘 600M   内存 768M' }, { t: '装得下', tone: 'ok' }],
  [{ t: '磁盘 600M   内存 768M', tone: 'bad' }, { t: '这份容器装不下 —— 会标红', tone: 'bad' }],
]" />

然后它就开始跑，你看着它跑：

<FigScreen title="正在安装 LNMP" :lines="[
  [{ t: 'Reading package lists... done', face: 'mono', tone: 'mute' }],
  [{ t: 'Setting up nginx (1.24.0)', face: 'mono', tone: 'mute' }],
  [{ t: 'Setting up mariadb-server', face: 'mono', tone: 'mute' }],
  [{ t: 'Setting up php8.2-fpm', face: 'mono', tone: 'mute' }],
  [{ bar: 0.78, label: '78%' }],
]" />

**你应该看到**在自己这一份里面，网站服务器已经在回应了：

```
  root@wp-1:~# curl -I http://127.0.0.1
  HTTP/1.1 200 OK
  Server: nginx/1.24.0
```

这就是「网站已经存在」—— 还没牵扯到任何域名和证书。如果这一步不回应，后面域名怎么弄都没用，
所以就在这里解决掉。

它还替你做了两件事：它生成的密码写进 `/etc/app-setup/secrets/` 里，不会哗哗滚过屏幕 —— 跟软件脚本
和你在「设置」里改过的东西放在一起，要找什么记住 `/etc/app-setup` 一个路径就够；卸载软件从不
删你的数据 —— 会先把你会心疼的东西挪到 `/root/` 下面，并且告诉你挪到哪了。

不用菜单也能干同样的事，写脚本的时候用得上：

```
  root@wp-1:~# app-setup list
  root@wp-1:~# app-setup install lnmp
  root@wp-1:~# app-setup status nginx
  root@wp-1:~# app-setup docs wordpress
```

想装的东西不在列表里？你可以自己加一条：[添加你自己的软件](/app-setup-sources)（英文）。

---

## 5. 改配置

回车打开你的软件。按钮都在它那一页上，「东西在哪改」的答案也在：

<FigScreen title="Nginx" :lines="[
  { pack: true, cols: [{ b: '卸载' }, { b: '停止' }, { b: '开机自启' }, { b: '参数设置' }] },
  { pack: true, cols: [{ b: '使用说明' }, { b: '日志' }] },
  [{ t: '参数设置', tone: 'strong' }],
  [{ t: '这个软件没有可以改的参数。', tone: 'mute' }],
]" />

现在随镜像发布的软件，几乎都是在自己的配置文件里改，而不是在表单里改 —— 而**使用说明**会把
文件路径一个个列出来，你不用自己找：

```
  root@wp-1:~# app-setup docs nginx
  Nginx

    Where things are
      /var/www/html                     你的网站文件
      /etc/nginx/conf.d/app-setup.conf  默认站点
      /var/log/nginx/error.log          出问题先看这个
```

所以改一次配置就是三条命令，中间那条最重要 —— 配置写坏了它会拒绝重载，而不是把你的网站
弄挂：

```
  root@wp-1:~# nano /etc/nginx/conf.d/app-setup.conf
  root@wp-1:~# nginx -t
  nginx: ... test is successful
  root@wp-1:~# systemctl reload nginx
```

**如果某个软件确实有参数**，表单里会是它自己的字段，加三个按钮：

<FigRows :rows="[
  [{ b: '保存并应用' }, '写进去，并且立刻生效'],
  [{ b: '保存' }, { t: '只写进去 ——「还没生效」', tone: 'mute' }],
  [{ b: '取消' }, { t: '这次改动丢掉', tone: 'mute' }],
]" />

```
  root@wp-1:~# app-setup set myapp port=8080   脚本里这么写
```

你自己往菜单里加的东西可以声明这些字段，见
[添加你自己的软件](/app-setup-sources)（英文）。

---

## 6. 添加你的域名

在容器页面上找到 **域名** 这张卡片：

<FigScreen title="域名" right="0 / 10" :lines="[
  [{ t: '还没有域名。加一个，这份容器就会在 :80', tone: 'mute' }],
  [{ t: '和 :443 上回应它。', tone: 'mute' }],
  { align: 'right', cols: [{ b: '添加域名' }] },
]" />

先加 `example.com`，再加 `www.example.com` —— 每个域名单独一行：

<FigScreen title="域名" right="2 / 10" :lines="[
  [{ m: 'example.com' }, { t: 'DNS ·', tone: 'mute' }, { t: 'HTTP ·', tone: 'mute' }, { t: 'HTTPS ·', tone: 'mute' }, { t: '⚙', tone: 'mute' }],
  [{ m: 'www.example.com' }, { t: 'DNS ·', tone: 'mute' }, { t: 'HTTP ·', tone: 'mute' }, { t: 'HTTPS ·', tone: 'mute' }, { t: '⚙', tone: 'mute' }],
]" />

这一步只是告诉机器：这些域名是你的。它**不会**去动你域名商那边的解析，也**不会**给你证书 ——
那是接下来两步的事。

新加的名字默认走 HTTP 80 端口、HTTPS 走 SNI 直通；徽标几秒内会自己填上。一般允许 10 个域名，
卡片上会数着，具体数字主机方可以改。卡片上的 **?** 会告诉你该指向哪个地址；打开某个名字后的
**文档**按钮就回到这一页。

---

## 7. 把域名指到机器上

上面那张卡片写着要指向的地址 —— 例子里是 `203.0.113.7`。去卖你域名的那家，找到 DNS 或
「解析记录」，加两条：

<FigRows :head="['类型', '主机记录', '值', '对应的网址']" :rows="[
  [{ m: 'A' }, { m: '@' }, { m: '203.0.113.7' }, { m: 'example.com' }],
  [{ m: 'A' }, { m: 'www' }, { m: '203.0.113.7' }, { m: 'www.example.com' }],
]" />

`@` 就是不带前缀的主域名。如果面板给你的是一串域名而不是四段数字，那就改用 `CNAME`，值填那串
域名。

过几分钟，从你自己的电脑上验一下：

```
  $ nslookup example.com
  Name:     example.com
  Address:  203.0.113.7      ← 就是那台机器，对了
```

同时，卡片上的徽章会自己变绿。不用刷新，也不用按任何东西：

<FigRows :rows="[
  [{ t: 'DNS ·', tone: 'mute' }, { t: 'HTTP ·', tone: 'mute' }, { t: 'HTTPS ·', tone: 'mute' }, { t: '还没检查', tone: 'mute' }],
  [{ t: 'DNS ✓', tone: 'ok' }, { t: 'HTTP ✕', tone: 'bad' }, { t: 'HTTPS ·', tone: 'mute' }, { t: '名字到了，但没人应答' }],
  [{ t: 'DNS ✓', tone: 'ok' }, { t: 'HTTP ✓', tone: 'ok' }, { t: 'HTTPS ·', tone: 'mute' }, { t: '有应答了 —— 可以去要证书' }],
  [{ t: 'DNS ✓', tone: 'ok' }, { t: 'HTTP ✓', tone: 'ok' }, { t: 'HTTPS ✓', tone: 'ok' }, { t: '齐了' }],
]" />

新加的域名，机器会每隔几分钟查一次，解析出来之后就查得稀一些。域名设置里的 **测试** 可以立刻
查一次。

**有个坑。** 那台机器首先得被允许接收网页流量。租来的服务器多半在云厂商的防火墙后面，
新开的机器往往只放行登录端口 —— 于是你的域名解析得好好的，就是永远没有应答。
只有主机方能把它打开，去找他。

---

## 8. 把每个域名分流到对应的服务

这一步能把一份容器变成好几个网站：

<FigRows :arrow="0" :rows="[
  [{ m: 'example.com' }, { t: '80', face: 'mono' }, { t: '你刚装的网站服务器', tone: 'mute' }],
  [{ m: 'www.example.com' }, { t: '80', face: 'mono' }, { t: '同一个', tone: 'mute' }],
  [{ m: 'api.example.com' }, { t: '3000', face: 'mono' }, { t: '你自己写的那个应用', tone: 'mute' }],
]" />

点某个域名后面的齿轮：

<FigScreen title="api.example.com 的设置" :lines="[
  { cols: [{ t: 'DNS', tone: 'strong' }, { t: '这个名字解析到这台主机了吗？' }] },
  { cols: ['', { b: '测试' }, { t: 'DNS ✓', tone: 'ok' }] },
  { cols: [{ r: '开启 HTTP', on: true }, { t: '容器端口' }, { f: '3000' }] },
  { cols: ['', { b: '测试' }, { t: 'HTTP ✓', tone: 'ok' }] },
  { cols: [{ r: '开启 HTTPS', on: true }, { t: 'HTTPS ·', tone: 'mute' }] },
  { cols: ['', { r: '你自己的证书 · SNI 原样转发' }] },
  { cols: ['', { t: '容器里的 HTTPS 端口' }, { f: '443' }] },
  { cols: ['', { r: '我们的证书 · 帮你签发', on: true }] },
  { cols: ['', { t: '转发到 HTTP 端口' }, { f: '3000' }] },
  { pack: true, cols: [{ b: '测试后端' }, { b: '申请证书' }] },
  { pack: true, cols: [{ b: '保存' }, { b: '删除' }, { b: '文档' }, { b: '关闭' }] },
]" />

**容器端口**填的是你这一份容器里面的端口，也就是访问这个域名的人最终到达的地方。普通网站留着
80；自己写的程序就填 3000。上面那两个开关是按名字分的：一个名字可以只开 HTTP、只开 HTTPS，
或者两个都开。

**测试**会从机器上连一下，答案就写在徽标旁边：

<FigRows :rows="[
  [{ t: 'HTTP ✓', tone: 'ok' }, { t: '端口通，HTTP 有应答' }],
  [{ t: 'HTTP ✕', tone: 'bad' }, { t: '端口不通' }, { t: '是你的应用，不是面板', face: 'small', tone: 'mute' }],
  [{ t: 'HTTP ✕', tone: 'bad' }, { t: '端口通，但没有 HTTP 应答' }],
  [{ t: 'DNS ✓', tone: 'ok' }, { t: '解析到了这台主机' }],
  [{ t: 'DNS ✕', tone: 'bad' }, { t: '解析到了 198.51.100.9 —— 不是这台' }],
]" />

保存的时候，如果那个端口还没打开，它会顺手打开，并且明确告诉你：

<FigRows :rows="[
  [{ t: '⚠', tone: 'bad' }, { t: '发布容器端口 3000 时，这份容器的网络' }],
  [null, { t: '短暂重启了一下。' }],
]" />

字面意思：这一份容器的网络断了一瞬间，正在连着的连接会重连一次，同一个端口不会再有第二次。

---

## 9. 开启 HTTPS

两条路，可以按域名分别选。都在你刚打开的那个设置里。

### 我们的证书、替你签发 —— 一个按钮

选 **我们的证书 · 替你签发**，按下按钮：

<FigRows :rows="[
  [{ b: '申请证书' }, null],
  [{ t: 'HTTPS ⟳', tone: 'accent' }, { t: '正在申请证书…' }, { t: '一分钟以内', face: 'small', tone: 'mute' }],
  [{ t: 'HTTPS ✓', tone: 'ok' }, { t: '已签发，会自动续期' }, { t: '托管', face: 'small', tone: 'mute' }],
]" />

不用装东西，之后也不用记着 —— 续期它自己做，而且离到期还早就做了（到期前 30 天）。注意那个端口
框**锁在你的 HTTP 端口上**：这条路上加密在机器这里就结束了，明文交给你容器里的一个端口，所以
只需要填一个端口 —— 要改就改上面那个 HTTP 端口框。

两个前提，缺哪个徽标都会说：

<FigRows :rows="[
  [{ t: '✕', tone: 'bad' }, { t: '签发失败。检查这个名字是不是解析到了这台主机。' }, { t: '→ 第 6 步', face: 'small', tone: 'mute' }],
  [{ t: '✕', tone: 'bad' }, { t: '端口不通' }, { t: '→ 第 7 步', face: 'small', tone: 'mute' }],
]" />

一个名字签下证书之后，按钮会变成**重新签发证书**，而且每签一次之后会安静一阵：

<FigRows :rows="[
  [{ b: '47 分钟后可重签' }, { t: '签发方限制同一个名字多久能签一次', tone: 'mute' }],
]" />

同一个域名**一小时一次、一周五次** —— 这是签发方的规矩，按第六次会把你自己这个域名锁上好几天。
自动续期从不受这个限制，所以它只会在你折腾配置的时候咬你。

### 你的证书 —— 私钥在你手上

选 **你的证书 · SNI 直通**，把**后端 HTTPS 端口**填成你这一份里面处理加密流量的那个端口：

<FigRows :arrow="0" :rows="[
  [{ t: '访客', tone: 'strong' }, { t: '加密，机器不解开', tone: 'accent' }],
  [null, { t: '原样转发到你容器的 443 端口', face: 'small', tone: 'mute' }],
]" />

机器不解开就转发过去，所以你的证书不会出现在容器之外 —— 反过来，容器之外也没有任何东西会替你
续期。在容器里面按常规办法申请一张，自己续着；徽章会告诉你你的容器实际在提供什么：

<FigRows :rows="[
  [{ t: 'HTTPS ✓', tone: 'ok' }, { t: '端口通，证书有效' }],
  [{ t: 'HTTPS ✓', tone: 'ok' }, { t: '证书有效，还剩 63 天' }],
  [{ t: 'HTTPS ✕', tone: 'bad' }, { t: '证书过期了' }],
  [{ t: 'HTTPS ✕', tone: 'bad' }, { t: '端口通，但没有 TLS' }],
]" />

面板上没有上传证书的地方。这条路上，证书属于解开流量的那一头，也就是你的容器里面。

两条路都一样，**你应该看到：**

<FigRows :arrow="0" :rows="[
  [{ t: '浏览器里输入', tone: 'strong' }, { m: 'example.com' }, { t: '🔒 你的网站', tone: 'ok' }],
  [{ t: '不算数', tone: 'mute' }, { m: 'curl http://example.com' }, { t: '明文，什么都证明不了', tone: 'mute' }],
]" />

在浏览器地址栏里输入不带前缀的域名。浏览器会先试加密的那一边，而那正是你要验的东西；一条不
加密的 curl 什么都证明不了。

---

## 10. 出问题的时候

四个地方，按这个顺序看：

<FigRows :rows="[
  [{ t: '1', tone: 'accent' }, '徽章', { t: 'HTTP ✕ 端口不通', tone: 'mute' }],
  [{ t: '2', tone: 'accent' }, '容器里面', { m: 'systemctl status myapp' }],
  [{ t: '3', tone: 'accent' }, '安装日志', { m: '/var/log/app-setup/wordpress.log' }],
  [{ t: '4', tone: 'accent' }, '面板', { t: '这份容器自己的历史，最新的在上面', tone: 'mute' }],
]" />

徽章会指出坏的是哪一半 —— 域名、端口，还是证书 —— 而且看一眼不花钱。然后进容器里面：

```
  root@wp-1:~# systemctl status myapp
  ● myapp.service — failed (exit code 1)
  root@wp-1:~# journalctl -u myapp -n 20
  root@wp-1:~# journalctl -xe          最近的全部
```

从菜单装的东西都有自己的日志，出错的时候屏幕上会直接把路径打出来：

<FigRows :rows="[
  [{ t: '✕', tone: 'bad' }, { t: 'WordPress 安装失败 —— 退出码 1。' }],
  [null, { m: '日志在 /var/log/app-setup/wordpress.log' }],
]" />

面板还记着你这一份被做过什么，最新的在最上面：

<FigRows :rows="[
  [{ t: '8 月 11 日 14:02', face: 'small', tone: 'mute' }, '为 example.com 签发了证书'],
  [{ t: '8 月 11 日 13:58', face: 'small', tone: 'mute' }, 'api.example.com：http 端口 80 → 3000'],
  [{ t: '8 月 11 日 13:40', face: 'small', tone: 'mute' }, '添加了 example.com'],
]" />

有两种故障哪里都不留话，靠样子认：

<FigRows :arrow="0" :rows="[
  ['服务反复挂掉，日志里什么都没有', { t: '内存', tone: 'bad' }],
  [{ m: 'no space left on device' }, { t: '磁盘', tone: 'bad' }],
]" />

| 你看到的 | 通常是什么 |
|---|---|
| 登不进去 | 容器停了、到期了，或者因为流量被暂停了。面板会说是哪一种。 |
| 一直重复问密码 | 密码不对。重设一个（第 2 步）—— 旧的谁也变不出来。 |
| 浏览器找不到这个域名 | 解析问题。按第 7 步在自己电脑上查一下那两条记录。 |
| 域名找到了，但没人回应 | 要么你这一份里那个端口上没程序在听（第 8 步），要么那台机器根本没被允许接收网页流量 —— 主机方的防火墙（第 7 步）。 |
| 浏览器显示的是别人的网站 | 域名没指到这台机器，或者你在面板里加了域名但没去改解析。 |
| 证书警告 | 域名和证书对不上，或者证书过期了。托管模式下重新要一次；自己的证书就在容器里面续。 |
| 要证书被拒，还给了个日期 | 这个域名本周的五次用完了，等到那个日期。 |
| 服务挂了但日志里什么都没有 | 内存。让它跑着，同时看容器页面上的内存数字。 |
| no space left on device | 磁盘。你这一份里所有东西共用一个额度。 |
| 面板说机器离线 | 主机方那台机器没在向面板报到。你的容器很可能还好好跑着，只是按钮得等。找主机方。 |
| 什么都很慢 | 你的 CPU 份额，或者那台机器本身很忙。容器页面上的曲线是最近一周的。 |

---

## 11. 丢不起的东西放哪

重装之后只有一个目录还在。别的都是「系统 + 你对它的改动」，重装换掉的正是这一部分：

<FigRows :arrow="0" :rows="[
  [{ m: '/etc/nginx/nginx.conf' }, { t: '没了', tone: 'bad' }],
  [{ m: '/var/www/site' }, { t: '没了', tone: 'bad' }],
  [{ m: '/root/notes.txt' }, { t: '没了', tone: 'bad' }],
  [{ m: '/data/mysql' }, { t: '留着', tone: 'ok' }],
  [{ m: '/data/uploads' }, { t: '留着', tone: 'ok' }],
]" />

所以数据库、上传的文件、任何你会心疼的东西，放到 `/data` 下面，然后让服务指向那里。

还有三件会让网站停下、但什么都不会删的事，各一行：

<FigRows :arrow="0" :rows="[
  ['流量用完', '暂停；下个月窗口一到就回来'],
  ['到期日过了', '停掉；主机方可以续'],
  ['你按了重装', '一个全新的系统，/data 留着'],
]" />

这三件各自的细节 —— 还有碰到限额是什么感觉 —— 写在
[使用你的容器](/using-your-container)（英文）里。

---

## 接下来

- [使用你的容器](/using-your-container)（英文）—— 限额、到期、重启和重装。
- [添加你自己的软件](/app-setup-sources)（英文）—— 把自己的东西加进菜单。
- [它是怎么工作的](how-it-works.md) —— 上面这一切背后的那张图。
