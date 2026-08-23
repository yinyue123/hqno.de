---
title: 使用 Debian
---

# 使用 Debian

Debian 是不用学的那个。它启动 systemd，用 `apt` 装东西，用 `journalctl` 看日志，
你在网上找到的每一份「Linux 服务器」教程，都是写给这样一台机器的。
Ubuntu 和这一页是同一回事 —— 同样的 `apt`、同样的 `systemctl`、
同样的目录布局 —— 所以你的容器如果写着 Ubuntu 24.04，照读。

这就是它的全部卖点。它是个很好的默认值，如果你不确定自己想要哪个系统，
想要的就是这个。

代价是体积：一个 Debian 容器什么都没装时文件系统约 **164 MB**，
[Alpine](alpine.md) 是 **36 MB**；空转时占十来兆内存，而不是一兆。
硬盘给得大方的容器上这点差别是噪音；卖 512 MB 硬盘的容器上，
这是你全部家当的四分之一，而 [使用 Alpine](alpine.md) 就是替另一边说话的那一页。

这一页默认你已经读过[使用你的容器](/using-your-container)（英文）——
容器怎么来的、重装做什么、五个限额是哪五个。这里讲的是日常。

---

## 1. 登录、密码和公钥

容器页面上写着用户名、主机和端口。拼起来就是你要运行的那一行：

```sh
ssh u7k2m9p@hk-1.example.com -p 22
```

你以 root 落进 bash，有自己的提示符和自己的 `/etc/profile`。

### 设密码

以 root 身份，在你自己的提示符下：

```sh
passwd
```

它一步改两处：容器自己的 `/etc/shadow`，**以及** SSH 网关校验的那个密码。
它不完全是原装的那个工具 —— `/usr/local/bin/passwd` 先跑真的那个，
成功之后再去告诉机器 —— 但每个参数的行为和以前一样，`passwd -S root`、
`passwd 某个用户`、以及非 root 用户改自己的密码，都原样落到真工具上。

面板也能改，在容器页面的 **操作 → Shell 登录 → 重置密码**。
两条路都只显示一次，之后只留哈希。丢了？重设一个，没有能找回来的东西。

### SSH 公钥

公钥属于你的**账号**，不属于某一台盒子。在面板的 **账号 → SSH 公钥** 里加一把，
它就会落到你名下的每一个容器上，以及之后别人交给你的每一个容器上 ——
这就是「配一次公钥」和「每次别人给你一台机器就再配一次」的区别。

```sh
ssh-keygen -t ed25519                 # 你自己电脑上，如果还没有钥匙
cat ~/.ssh/id_ed25519.pub             # 把这一行贴进面板
ssh-keygen -lf ~/.ssh/id_ed25519.pub  # 面板回显的那串 SHA256:…
```

**把公钥拷进容器里的 `~/.ssh/authorized_keys` 没有任何作用。**
这里面没有 sshd 去读它 —— 你的登录是由宿主机上的一个 SSH 服务应答的，
它验完身份再跨进这个容器的命名空间。「哪些钥匙可以代表你」这份名单
跟那个服务放在一起，而面板就是通向它的那扇门。

带选项的那种行（`command="…"`、`from="…"`、`restrict`）会被拒收而不是存下来：
网关没法执行这些限制，而存下一把丢了限制的钥匙，等于你以为自己设了限、
其实没有。

如果你想在房东给你开的端口上跑一个自己的 sshd，那是另一回事：
`apt install openssh-server`。

---

## 2. 装软件

### 短的版本

```sh
apt update              # 刷新「有些什么」的清单
apt install nginx       # 装
apt remove nginx        # 卸掉，配置留着
apt purge nginx         # 配置也一起
apt search nginx        # 找名字
apt show nginx          # 这是个什么东西
apt list --installed    # 你装了些什么
apt upgrade             # 全部更新，包括安全修复
```

`apt update` 已经替你跑过了 —— 开机时有个任务会刷新索引，每天最多一次 ——
所以你第一次登录进来直接 `apt install nginx` 就能装上。

**只有一个坑，而且只在容器生命的头一分钟里出现。** 那个开机任务运行时会占着
apt 的锁，而 `apt` 拿不到锁不会等，它直接失败。如果你的第一条命令回答
*Unable to locate package* 或者 *Could not get lock*，等三十秒再跑一遍。

### 更短的版本

敲 `app-setup`：

```
 ┌ 套件 ─ Web 服务器 ─ 数据库 ─ 开发 ─ 系统 ─┐
 │                                          │
 │ ▸ LNMP                      · 已安装      │
 │   nginx、MariaDB、PHP-FPM                 │
 │   硬盘 600M 内存 768M  端口 80, 3306      │
 │                                          │
 │   WordPress                 · 运行中      │
 │   WordPress、nginx、PHP-FPM、MariaDB      │
 │   硬盘 800M 内存 768M  端口 80            │
 │                                          │
 │ ↑↓←→ 移动   回车 打开   最上面的 ↑ 是返回  │
 └──────────────────────────────────────────┘
```

一个全屏的选择器，五个标签页 —— 套件、Web 服务器、数据库、开发工具、系统。
方向键移动，**回车**打开光标下那张卡，`L` 在中英文之间切换，`q` 退出，
鼠标也能用。每张卡上有安装、卸载、启动/停止、开机自启、**怎么用它** ——
会列出这个包写了哪些文件 —— 上一次运行的日志，以及有设置项的话还有「设置」。

每张卡还写着这东西要多少硬盘和内存，**而且当这个容器装不下它的时候那一行会变红**
—— 这个数字没人会在你装到第四分钟挂掉之前告诉你。

它也能写进脚本：

```sh
app-setup list                # 全部，带体积和当前状态
app-setup install lnmp        # nginx + MariaDB + PHP，接好线的
app-setup install wordpress   # ……再在上面装 WordPress，连数据库一起
app-setup status nginx        # 0 运行中，1 已停，2 没装
app-setup docs wordpress      # 这个配方自己怎么说
app-setup doctor              # 这个容器在 app-setup 眼里是什么样
```

它装的全都是 Debian 自己的包，装到 Debian 自己的路径。没有私有构建，
所以你接着去读的那份说明依然适用，安全更新也照常从 `apt` 来。
自动生成的密码写在 `/etc/app-setup/secrets/`，权限 600，
而不是在安装日志里滚过去。

卸载从不删你的数据：卸 WordPress 会删掉它的数据库和程序文件，
但会先把你上传的东西挪到 `/root/`，并且告诉你。

把你自己的软件加进这个菜单，就是往 `/etc/app-setup/` 丢一个 shell 脚本 ——
见[添加你自己的软件](/app-setup-sources)（英文）。

### 编辑器，以及其它你以为一定有的东西

镜像做得精简，所以你第一时间去摸的东西有几样不在里面：

| | 自带 | 怎么拿到 |
|---|---|---|
| `nano` | 有 | |
| `vim` `vi` | **没有** | `apt install vim`，或 `app-setup install vim` |
| `curl` `less` | 有 | |
| `wget` `unzip` `xz` `bzip2` | 没有 | `app-setup install essentials` |
| `ping` `ip` `ss` | 有 | |
| `dig` `traceroute` `mtr` `tcpdump` `netstat` | 没有 | `app-setup install nettools` |
| `htop` | 没有 | `apt install htop`，或 `app-setup install htop` |
| `git` | 没有 | `apt install git`，或 `app-setup install git` |
| `bash` `sudo` `cron` | 有 | |

任何你打算长住的容器，这两张卡都值得先装上：

```sh
app-setup install essentials   # curl wget unzip tar xz bzip2 less procps
app-setup install nettools     # ping dig traceroute mtr tcpdump netstat ss
```

---

## 3. 服务

这里 systemd 就是 PID 1，所以就是你已经会的那一套：

```sh
systemctl start nginx
systemctl stop nginx
systemctl restart nginx
systemctl reload nginx           # 重读配置，不断开连接
systemctl status nginx           # 状态、最近几行日志、进程号
systemctl enable --now nginx     # 现在启动，并且每次开机都启动
systemctl disable --now nginx
systemctl is-active nginx        # 给脚本用：跑着就退出 0
```

什么在跑，什么坏了：

```sh
systemctl list-units --type=service --state=running
systemctl --failed
```

`systemctl reboot` 可用，会原地重启这个容器。如果它卡到你根本连不进去，
面板上的 **重启** 从外面做同一件事。

### 自己写一个服务

一个文件，三段。下面这个跑你自己的程序，挂了就拉起来：

```sh
cat > /etc/systemd/system/myapp.service <<'EOF'
[Unit]
Description=我自己的程序
After=network.target

[Service]
Type=simple
ExecStart=/data/myapp/run
WorkingDirectory=/data/myapp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now myapp
systemctl status myapp
```

每次改完这个文件都要 `daemon-reload` —— systemd 会缓存 unit，
忘了这一步就是「改了好像没生效」的原因。`Type=simple` 表示你的程序留在前台；
如果它会 fork 然后自己退出，那你要的是 `Type=forking` 加一个 `PIDFile=`。

`ExecStart` 下面的东西，stdout 和 stderr 直接进 journal，
所以你什么都不用重定向就白得一份日志。

不想写 unit 文件的话，`app-setup install supervisor` 给你 Supervisor，
一个程序五行配置。

### 定时任务

`cron` 已经在跑了：

```sh
crontab -e        # 你自己的任务；默认开 nano，除非你设了 EDITOR
crontab -l
EDITOR=vim crontab -e
```

还有丢文件那种写法，它能扛过 `crontab -r`，在备份里也更好读：
往 `/etc/cron.daily/`、`/etc/cron.hourly/`、`/etc/cron.weekly/`
里放一个**可执行**文件。**可执行** —— 没加执行位的脚本会被悄悄跳过，
这是这件事上最经典的「白丢一小时」。Debian 的 `run-parts` 还会忽略
文件名里带点的文件，所以放在那儿的 `backup.sh` 永远不会跑；
就叫它 `backup`。

systemd 的 timer 也能用，你更喜欢的话。

---

### 日志里两行不是问题的东西

一个健康的容器上，`systemctl --failed` 会显示一条：

```
● dev-mqueue.mount   loaded failed failed   POSIX Message Queue File System
```

而你启动的 unit 会记一行：

```
Failed to get cgroup ID of cgroup /sys/fs/cgroup/system.slice/myapp.service,
ignoring: Operation not permitted
```

两条都是 systemd 去够一个只有宿主机能碰的东西，发现够不着，然后继续往下走 ——
这正是应该发生的事。它们不影响你跑的任何东西。忽略掉。

---

## 4. 日志

一切都进 journal，`journalctl` 是读它的方式：

```sh
journalctl -u nginx            # 某一个服务
journalctl -u nginx -f         # ……并且实时跟着
journalctl -u nginx -n 100     # 最后一百行
journalctl -u nginx --since -1h
journalctl -p err -b           # 只看错误，本次启动
journalctl -xe                 # 所有日志的结尾，带解释
```

`rsyslog` 也在跑，所以传统的那些文件也在，写 syslog 而不写 journal 的东西
落在里面：

| 文件 | 里面是什么 |
|---|---|
| `/var/log/syslog` | 系统日志 |
| `/var/log/nginx/` | 自己写日志的服务写的，比如 nginx |
| `/var/log/apt/history.log` | 你装过卸过的每一个包 |

```sh
tail -f /var/log/syslog
grep -i error /var/log/syslog
```

`logrotate` 装了，每天跑，所以这些不会撑爆你的硬盘限额 ——
但你自己的程序写的日志文件不会被轮转，除非你往 `/etc/logrotate.d/`
里丢一个配置。journal 自己有上限，不需要。

你自己写的服务其实根本不需要日志文件：往 stdout 写，让 systemd 接住，
用 `journalctl -u` 看。

---

## 5. 进程、内存、硬盘

```sh
top                     # 交互式；`q` 退出
ps aux                  # 所有进程
ps -ef --forest         # 进程树，能看出 systemd 起了什么
free -m                 # 内存，MB
df -h /                 # 硬盘
du -sh /* 2>/dev/null   # 硬盘去哪了
uptime                  # 负载
systemd-cgtop           # 同样的东西，按服务分组
```

**这些数字是你的，不是机器的。** 宿主机把按容器切分的 `/proc` 映射了进来，
所以 `free` 报的是卖给你的内存，`nproc` 报的是你的核数 ——
不是你寄居其上的那台 64 核。调数据库参数要照着这些数字，不是宿主机的。

两个例外：`top` 和 `uptime` 里的**负载**是宿主机的，
因为内核没有按容器算的负载；而 `top` 里的 `%CPU` 是相对你自己的核数。

容器自己看不到的那些 —— 流量、到期、域名、公网端口 ——
敲 `dashboard`（第 7 节）。

---

## 6. 把网站放到公网上

### 没有防火墙，你也不需要

`iptables` 装得上，但不工作：容器没有 `CAP_NET_ADMIN`，
所以哪怕你是 root，内核也会用 *Permission denied* 拒绝每一条规则。
`nft` 和建立在它之上的每一个封装也一样。

这不是从你手里拿走了什么，因为这里根本没有需要防火墙去关的东西。
**这个容器里的任何东西，除非下面两件事之一成立，否则公网够不着：**

1. 有一个**域名**指向它 —— 这个你自己加，而且它只会到达机器上的 80 和 443；
2. 有一个**公网端口**映射到它 —— 这个只有你的房东能开，一次一个号码，
   并且会列在你的容器页面上。

一个监听 3000 端口、没有域名也没有映射的服务，只有这个容器自己看得见。
那就是防火墙。

反过来说：**公网端口开在机器的公网地址上，所以它后面的东西就是在公网上。**
给它加个密码。见[公网端口](ports.md)。

### 要监听 `0.0.0.0`，不要 `127.0.0.1`

这是这里「服务明明好的却像坏了」的头号原因。

进来的流量 —— 域名的也好，公网端口的也好 —— 是送到容器自己的网卡上的，
**不是**送到它的 loopback 上。所以绑在 `127.0.0.1` 的服务接不到任何外面的
连接：TCP 连上了，然后什么都不回，看起来像程序坏了，而不像地址写错了。

```
listen 127.0.0.1:3000   →  连得上，空响应，哪儿都不报错
listen 0.0.0.0:3000     →  正常
```

绑 `0.0.0.0` 不会多暴露任何东西，因为进来的路只有上面那两条。
从「程序蹲在本机 nginx 后面」的机器上抄来的配置几乎一定带着 `127.0.0.1`，
那就是要改的那一行。

`127.0.0.1` 留给唯一的调用方就在同一个容器里的东西 —— PHP-FPM 的套接字、
外面没人访问的数据库。

### 加域名

在面板的容器页面上加，或者在你自己的提示符下：

```sh
domain add example.com 80          # HTTP 和 HTTPS，证书替你办
domain add *.example.com 3000      # 泛域名，指向一个 Node 程序
domain ls                          # 这个容器现在应答哪些名字
domain del example.com
domain help                        # 完整语法
```

`domain add example.com 80` 两个都给你：`example.com:443`，
证书由机器申请并在过期前续期；以及 `example.com:80`。两个都转发到这里的
80 端口。你不用跑 certbot，也不用把私钥拷到任何地方。

把这个名字的 DNS 指向机器，是你在域名商那边做的那一半；
要指向的地址就在面板的同一张卡上。检查按计划跑，结果作为徽章显示在每个名字上，
所以一个不通的名字会告诉你是哪一段不对。

如果你想拿着自己的证书，加上 `self-hosted` 这个关键字，
机器就把加密的字节原样接过去，全程碰不到你的私钥：

```sh
domain add example.com 8443 self-hosted        # 你的 TLS 在 8443，:80 上什么都没有
domain add example.com 8443 self-hosted 8080   # ……再加上 8080 上的明文 HTTP
```

[快速上手](quick-start.md)把整件事 —— 加名字、改 DNS、拿到小锁 ——
分四步走完。

### 最短的一条路

```sh
app-setup install lnmp      # nginx + MariaDB + PHP-FPM，按这台盒子调好参数
domain add example.com 80
```

静态站或者你自己的程序，就 `apt install nginx`，把 server 段写进
`/etc/nginx/sites-available/`，再软链到 `/etc/nginx/sites-enabled/`，
然后 `systemctl reload nginx`。先跑 `nginx -t` —— 它会检查配置并告诉你行号，
而且配置有错时 reload 会保住正在跑的那份，不会把你的站点弄下线。

---

## 7. 在容器里看流量、限额和到期

```sh
dashboard              # 全部：盒子、CPU、内存、硬盘、流量、
                       # 公网端口、域名，以及怎么再登进来
dashboard net          # 只看流量表
dashboard cpu mem      # 只看这两个
```

流量这一段是容器自己怎么也答不上来的，因为额度属于面板持有的一个计费窗口：

```
Network
  Allowance   1.0T monthly
  Used        318.0G (29%) — 210.0G in, 108.0G out
  Left        706.0G
  Window      counting since 2026-08-01
```

进出都算。到 80% 面板记一条警告；到 100% 容器会被**暂停** ——
是停掉，不是删掉 —— 等窗口翻篇，或者房东把额度调高，它就回来。

同样这些数字每次 SSH 登录时都会打在提示符上方：

```
  System   Debian GNU/Linux 13 (trixie)
  Uptime   6d 4h
  CPU      4% of 2 cores
  Memory   734.0M of 2.0G (36%)
  Disk     11.0G of 40.0G (28%)
  Traffic  318.0G of 1.0T (29%) · 706.0G left
  Expires  2026-09-30 (in 41 days)
```

你也可以用 `ip -s link show tap0` 直接读内核给这个容器网卡记的计数。
那是真实的字节数，但它**不是**计费表：容器重启它就归零，
而且它完全不知道你在哪个计费窗口里。用它回答「现在是不是有东西在传」；
用 `dashboard net` 回答「我还剩多少」。

`helppage` 是容器里的说明书，不用开浏览器：端口和域名、装软件、备份、
每个限额是什么意思、重装保留什么。`helppage --list` 列出所有页，
`helppage --text limits` 把某一页当纯文本打出来。

---

## 8. `/data`，以及重装

**`/data` 是能活下来的那部分。** 其余的一切都是「镜像 + 你对它的改动」，
而重装换掉的正好就是那部分。数据库、上传的文件、任何丢了你会难受的东西：
放到 `/data` 下面，然后让你的服务指过去。容器有独立数据盘时，
`app-setup` 装的软件已经这么做了。

```sh
reinstall                  # 这个容器能用什么重建
reinstall debian-13        # 名字的一部分就够了
reinstall alpine-3.24      # ……或者试试小的那个
```

它会告诉你会装什么、你要失去什么，然后让你把容器的名字打一遍。
你的 SSH 会话会在重建到一半时断开 —— 那是应该发生的事。
一分钟后再登回来，地址不变，密码不变。

你的限额、域名和公网端口都不变。

如果 164 MB 的文件系统比你愿意花的多，或者这个容器小到让它变成一件事，
[使用 Alpine](alpine.md) 是同一批答案的另一个版本，系统只有四分之一大 ——
并且老实交代了代价。
