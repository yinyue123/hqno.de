---
title: 使用 Alpine
---

# 使用 Alpine

Alpine 是小的那个。用它做出来的容器，文件系统 **36 MB**，Debian 是
**164 MB**；开机起三个进程，加起来占 **168 KB** 内存，Debian 起七个，
加起来 **6.5 MB**。也就是说，同样一台盒子，硬盘和内存留给你真正要跑的
东西的部分更多。第 1 节是完整的账，每个数字都是实测出来的，不是说出来的。

代价是有的，而且是实打实的：**它不是网上大多数教程写给的那个 Linux。**
没有 systemd，没有 `apt`，没有 glibc。这三样每一样都有直接的替代品，
这一页就是完整的对照表。

**如果你不想学任何新东西，别往下读了，去看 [使用 Debian](debian.md)。**
重装过去就行 —— 一分钟，`/data` 保留，什么都不花。那边 `apt install`、
`systemctl`、`journalctl`，你搜到的每一篇博客都能照抄。这是个完全体面的选择，
第 12 节讲怎么做。

这一页默认你已经读过[使用你的容器](using-your-container.md) ——
容器怎么来的、重装做什么、五个限额是哪五个。这里讲的是 Alpine 那一半。

---

## 1. 系统本身要花掉你多少

下面每一个数字，都是在本面板发布的镜像上各开一个全新容器、什么都不装、
空转着量出来的。同一台宿主机，同样的限额，同一分钟。

| | Alpine 3.24 | Debian 13 |
|---|---|---|
| **什么都没装时的文件系统** | **36 MB** | **164 MB** |
| **空转时算进你内存限额的量** | **15 MB** | **105 MB** |
| —— 其中是页缓存，一有需要内核就还给你 | 14 MB | 94 MB |
| —— 其中是真正拿不回来的 | **0.9 MB** | **10 MB** |
| 跑着的进程数 | 3 | 7 |
| 包管理器 | `apk` | `apt` |
| init | busybox init + OpenRC | systemd |
| C 库 | musl | glibc |
| 日志 | 就是文件 | journald，外加文件 |

中间那两行得解释一句，因为「一个空转的容器占多少内存」有两个都算诚实的答案。

**105 MB 是面板和 `dashboard` 给你看的那个数。** 它是你这个 cgroup 的
`memory.current`，其中绝大部分是页缓存 —— 系统读过的那些二进制和文件，
先留着，万一还要读。一旦内存紧张，内核会悄无声息地把它扔掉。
**10 MB 才是你真正失去的**：那些守护进程申请的匿名内存，
加上内核为它们记账的开销。两个数都是真的；第一个是你会看到的，
第二个是你怎么也不可能拿去用在别处的。

### 内存花在哪了

空转时每个进程的私有（匿名）内存 —— 也就是回收不掉的那部分：

| 干什么的 | Alpine | Debian |
|---|---|---|
| PID 1 | busybox `init` —— **52 KB** | `systemd` —— **2,772 KB** |
| 系统日志 | busybox `syslogd` —— **64 KB** | `systemd-journald` 1,132 KB + `rsyslogd` 636 KB —— **1,768 KB** |
| 定时任务 | busybox `crond` —— **52 KB** | `cron` —— **200 KB** |
| 登录和会话 | *没有这个进程* | `systemd-logind` 1,116 KB + `dbus-daemon` 468 KB —— **1,584 KB** |
| 没人用的那个控制台 | *没有这个进程* | `agetty` —— **236 KB** |
| **合计** | **168 KB** | **6,560 KB** |

Alpine 这三个进程**是同一个二进制**。`init`、`syslogd`、`crond` 全都是
`/bin/busybox`，所以它们背后那 ~900 KB 的程序代码只映射一份、三个进程共用 ——
这就是为什么三个守护进程比 Debian 的任何一个都便宜。

Debian 那一列长，是因为 systemd 承诺的事更多。`logind` 管会话和座位，
`dbus` 在它们之间传消息，`journald` 维护一份能按 unit 和时间查询的
带索引二进制日志。在笔记本上这些都值得有。在一个你以 root 身份 SSH 进来的
容器里，`logind` 和那个控制台 getty 管的是根本不存在的东西。

### 硬盘花在哪了

| | Alpine | Debian |
|---|---|---|
| 包索引 —— 「有些什么」那份清单 | **2.9 MB**（`/var/cache/apk`） | **20.5 MB**（`/var/lib/apt/lists`） |
| 包数据库 —— 「你装了什么」 | **0.1 MB**（`/lib/apk/db`） | **5.9 MB**（`/var/lib/dpkg`） |
| 第一次开机两分钟后的日志 | **0 MB** | **8.1 MB**（journal 的第一个文件） |
| init 系统自己的文件 | 约 1 MB | 5.5 MB（`/usr/lib/systemd`） |
| 其余 —— 那些程序本身 | 约 32 MB | 约 124 MB |

`apt` 那 20.5 MB 索引值得单独知道一下：它不是你装的东西，
它是被刷新而不是被删掉的，在一个卖 1 GB 硬盘的容器上，
它永久占掉你全部家当的 2%。

**journal 是最容易吓你一跳的那个。** 它按文件系统的 10% 给自己定上限 ——
在这里量的这个容器上，那个上限是 **1.9 GB**，而且你什么都还没干，
它已经 8 MB 了。把它压住只要改一个文件，见 [Debian 第 5 节](debian.md)。

### 所以什么情况下选哪个

| 你的容器 | 选 |
|---|---|
| **硬盘不到 2 GB 左右** | **Alpine。** 128 MB 是 1 GB 硬盘的 13%，而你还什么都没装。这条理由不会随时间消失。 |
| **内存 256 MB 或更少** | **Alpine。** 那 9 MB 拿不回来的差别是 256 MB 的 4%，而 Debian 想吃掉的那 80 MB 缓存，是你自己的程序没吃到的内存。 |
| **内存 1 GB、硬盘 10 GB 以上** | 都行。差别是零头，冲着生态选 [Debian](debian.md)。 |
| **你要装厂商的 agent、MongoDB、aaPanel，或者任何以「下载一个二进制」方式发布的东西** | **Debian。** 见第 11 节 —— 这不是大小问题，是那东西到底跑不跑得起来的问题。 |
| **你在一台机器上跑很多个容器** | Alpine，而且这条会叠加：三十个空转的 Alpine 容器加起来不到半 GB 内存、1 GB 硬盘。 |

有一件表里体现不出来、但很重要的事：**Alpine 不会让你的软件变小。**
nginx 在两个系统上都占大约 9 MB 私有内存 —— 实测的，主进程加四个 worker，
同样的配置。Alpine 给你的是它下面那个更小的盒子。
如果你要跑的东西需要 400 MB，那它在两边都需要 400 MB。

### 代价是什么

上面这些都不是白来的，而且账不是用兆字节结的：

- **有些软件根本没有 Alpine 版本。** 你最可能想要的两个是 MongoDB 和 aaPanel，
  它们只发布 glibc 二进制。`app-setup` 在这里会直接拒绝并说明原因，
  而不是装到第四分钟才失败。
- **你自己下载的预编译程序通常跑不起来。** 为 glibc 编译的发布包会以
  `no such file or directory` 结束 —— 对一个明明就在那儿的文件来说，
  这个提示出了名地没用。见第 11 节。
- **没有 `systemctl`。** 你找到的每一条服务相关的说明都要翻译一遍。
  第 6 节就是那张对照表。

除此之外 —— nginx、MariaDB、PostgreSQL、Redis、PHP、Python、Node、Go、Rust、
WordPress —— 都有包，都能跑，`app-setup` 在这里装它们和在 Debian 上一模一样。

---

## 2. 登录、密码和公钥

登录那一行在你的容器页面上，和别处没什么两样：

```sh
ssh u7k2m9p@hk-1.example.com -p 22
```

你落进去的是 **bash**，不是 busybox 的 `ash` —— 容器里有 bash 时网关会起
`bash -l`，这个镜像里有。这一点后面有用：这里的 `/bin/sh` 仍然是 busybox，
所以一个写着 `#!/bin/sh` 又用了 bash 语法的脚本照样会挂，哪怕你的提示符是
bash。要用 bash 就写 `#!/bin/bash`。

### 设密码

以 root 身份，在你自己的提示符下：

```sh
passwd
```

它一步改两处：容器自己的 `/etc/shadow`，**以及** SSH 网关校验的那个密码。
它不是原装的那个工具 —— `/usr/local/bin/passwd` 是个壳，先跑真的那个，
成功之后再去告诉机器 —— 但每个参数的行为和以前完全一样，
`passwd -S root`、`passwd 某个用户`、以及非 root 用户改自己的密码，
都原样落到真工具上。

面板也能改，在容器页面的 **操作 → Shell 登录 → 重置密码**。
两条路都只显示一次，之后只留哈希。丢了？重设一个，没有能找回来的东西。

### SSH 公钥

公钥属于你的**账号**，不属于某一台盒子。在面板的 **账号 → SSH 公钥** 里加一把，
它就会落到你名下的每一个容器上，以及之后别人交给你的每一个容器上。

```sh
ssh-keygen -t ed25519                 # 你自己电脑上，如果还没有钥匙
cat ~/.ssh/id_ed25519.pub             # 把这一行贴进面板
ssh-keygen -lf ~/.ssh/id_ed25519.pub  # 面板回显的那串 SHA256:…
```

**把公钥拷进容器里的 `~/.ssh/authorized_keys` 没有任何作用。**
这里面没有 sshd 去读它。你的登录是由宿主机上的一个 SSH 服务应答的，
它验完身份再跨进这个容器的命名空间 —— 所以「哪些钥匙可以代表你」这份名单
是跟那个服务放在一起的，而面板就是通向它的那扇门。

带选项的那种行（`command="…"`、`from="…"`、`restrict`）会被拒收而不是存下来：
网关没法执行这些限制，而存下一把丢了限制的钥匙，等于你以为自己设了限、
其实没有。

如果你**真的**想在房东给你开的端口上跑一个自己的 sshd，那是另一回事，
自己装：`apk add openssh`。

---

## 3. 包管理

`apk` 是 Alpine 的包管理器，比 `apt` 快，也短。索引已经替你取好了 ——
开机时有个任务会刷新它，每天最多一次 —— 所以你第一次登录进来直接
`apk add nginx` 就能装上。

| 你要做的 | Alpine | （Debian 对照） |
|---|---|---|
| 装 | `apk add nginx` | `apt install nginx` |
| 卸 | `apk del nginx` | `apt remove nginx` |
| 刷新索引 | `apk update` | `apt update` |
| 全部升级 | `apk upgrade` | `apt upgrade` |
| 搜 | `apk search nginx` | `apt search nginx` |
| 这个包是什么 | `apk info nginx` | `apt show nginx` |
| 它装了哪些文件 | `apk info -L nginx` | `dpkg -L nginx` |
| 这个文件属于哪个包 | `apk info -W /usr/sbin/nginx` | `dpkg -S /usr/sbin/nginx` |
| 装了些什么 | `apk list --installed` | `apt list --installed` |
| 哪些过期了 | `apk version -l '<'` | `apt list --upgradable` |
| 这个包会从哪来 | `apk policy nginx` | `apt policy nginx` |

两个仓库都开着，`main` 和 `community`，加起来就是 Alpine 发布的全部东西。
`main` 在这个版本的整个生命周期内都有支持；`community` 是尽力而为。
`apk policy <名字>` 会告诉你某个包来自哪一个。

有几个包名和 Debian 不一样，每个都会坑你一次：

| Debian | Alpine |
|---|---|
| `build-essential` | `build-base` |
| `python3-dev` | `python3-dev`，库则是 `py3-…` |
| `dnsutils` | `bind-tools` |
| `libfoo-dev` | `foo-dev` |
| `iputils-ping` | `iputils` |

**`--no-cache` 是给 Dockerfile 用的，不是给你用的。** 它跳过把索引写到硬盘，
构建镜像时是赚的，住在里面时是小亏。在提示符下你要的就是普通的 `apk add`。

### 装完之后：跑起来，以及开机自启

装上不等于跑起来，跑起来也不等于重启之后还在。这里是三条分开的命令：

```sh
apk add nginx                 # 装
rc-service nginx start        # 现在跑起来
rc-update add nginx default   # 每次开机都跑
```

**后两条不是一条。** systemd 把它们合成了 `systemctl enable --now`，
OpenRC 没有：启动一个服务不会把它加进 runlevel，把它加进 runlevel
也不会让它现在就跑。「装好了、也在跑」的东西重启一次就没了，
绝大多数是栽在这里。

两边分别怎么查：

```sh
rc-service nginx status    # 现在跑没跑
rc-update show default     # 开机会起来哪些
```

`app-setup` 装东西时两件事都替你做了，所以从菜单里装的包，
装完就在跑，也已经在 runlevel 里。完整的服务那一章是第 6 节 ——
停止、取消自启、以及自己写一个。

---

## 4. `app-setup`，替你把上面这些都做了

敲它：

```
app-setup
```

一个全屏的选择器，五个标签页 —— 套件、Web 服务器、数据库、开发工具、系统。
方向键移动，**回车**打开光标下那张卡，`L` 在中英文之间切换，`q` 退出，
鼠标也能用。每张卡上有安装、卸载、启动/停止、开机自启、**怎么用它** ——
会列出这个包写了哪些文件 —— 上一次运行的日志，以及有设置项的话还有「设置」。

每张卡还写着这东西要多少硬盘和内存，**而且当这个容器装不下它的时候那一行会变红**
—— 这个数字没人会在你装到第四分钟挂掉之前告诉你。在 Alpine 上你看到红色的
次数会少得多，这正是你在这里的理由。

要写进脚本，或者你已经知道自己要什么：

```sh
app-setup list                # 全部，带体积和当前状态
app-setup install lnmp        # nginx + MariaDB + PHP，接好线的
app-setup install wordpress   # ……再在上面装 WordPress，连数据库一起
app-setup status nginx        # 0 运行中，1 已停，2 没装
app-setup docs nginx          # 这个配方自己怎么说
app-setup doctor              # 这个容器在 app-setup 眼里是什么样
```

接手一台不是你自己搭的机器时，`app-setup doctor` 是最值得先跑的一条。
在这个镜像上它会回答：

```
system      Alpine Linux v3.24 (alpine)
init        openrc
packages    apk
```

它装的全都是 Alpine 自己的包，装到 Alpine 自己的路径 —— 没有私有构建 ——
所以你接着去读的那份说明依然适用，安全更新也照常从 `apk` 来。
它认识 OpenRC：`app-setup enable nginx` 就是 `rc-update add nginx default`，
它启动的服务就是 Alpine 自己的 `nginx-openrc` 包带来的那个。

**在这里它会拒绝装的两个**是 `mongodb` 和 `aapanel`，而且会说明为什么，
不会硬试：两个都要 glibc。第一个用 PostgreSQL 的 `jsonb` 字段代替，
第二个用 `lnmp` 那张卡代替。

把你自己的软件加进这个菜单，就是往 `/etc/app-setup/` 丢一个 shell 脚本 ——
见[添加你自己的软件](/app-setup-sources)（英文）。

---

## 5. 常用工具

镜像是刻意做小的。但你要用的东西大部分还是在的 —— busybox 用很少的硬盘
带了一大堆小程序。下面是一个全新容器里有什么，以及没有的怎么补：

| 用来 | 已经有 | 值得再装 |
|---|---|---|
| 改文件 | `vi`（busybox 的）、`nano` | `vim` —— `app-setup install vim` |
| 看和找 | `less` `grep` `find` `awk` `sed` `tail` `watch` `xxd` | |
| 压缩解压 | `tar` `gzip` `bzip2` `unzip` | `xz` —— `app-setup install essentials`；`zip` —— `apk add zip` |
| 下载 | `curl` `wget` | |
| 查网络 | `ping` `ip` `ss` `netstat` `nslookup` `traceroute` `nc` | `dig` `mtr` `tcpdump` —— `app-setup install nettools` |
| 看进程和占用 | `top` `ps` `free` `df` `du` `lsof` `killall` `tree` | `htop` `ncdu` `atop` —— `app-setup install htop` |
| 连到别的机器 | `ssh` `scp` `sftp` | `rsync` —— `app-setup install rsync` |
| 编译东西 | | `git` `make` `gcc` —— `app-setup install git`，再 `buildtools` |
| 断线不丢的会话 | | `tmux` 或 `screen` —— `app-setup install tmux` |
| shell | `bash`（就是你的登录 shell）、`sudo`、`crontab` | `zsh` + Oh My Zsh —— `app-setup install zsh` |

这张表里有好几行 Alpine 反而比 Debian 强，这不是大家对「更小的镜像」的预期：
busybox 把 `vi`、`wget`、`unzip`、`bzip2`、`netstat`、`nslookup`、
`traceroute`、`nc`、`killall`、`lsof`、`tree` 都做成了 applet，一个才几 KB，
而 Debian 镜像这十一个一个都没有。

任何你打算长住的容器，这两张卡都值得先装上：

```sh
app-setup install essentials   # curl wget unzip tar xz bzip2 less procps-ng
app-setup install nettools     # ping dig traceroute mtr tcpdump netstat ss
```

有两行带着坑，值得先知道：

- **`vi` 是 busybox 的。** 它能开、能改、能存；没有语法高亮，没有分屏，
  命令集小得多。你敲 `vim` 得到 *not found*，原因就在这儿。
- **busybox 的 applet 认的参数比真程序少。** 常用的都在 ——
  `netstat -tlnp` 打出来的就是你预期的那样 —— 但你从某篇博客上抄来的
  冷门参数可能根本不存在。`ps`、`top`、`free`、`watch` 是例外：
  镜像为这几个装了真正的 `procps-ng`，所以 `ps aux` 和 `ps -ef --forest`
  和别处一模一样。哪个工具不认参数了，在这里 `<工具> --help` 很短，
  读一遍比猜快。

---

## 6. 服务：OpenRC 而不是 systemd

这是真正不一样的那部分，而且比它的名声要小。

### 对照表

| systemd | OpenRC |
|---|---|
| `systemctl start nginx` | `rc-service nginx start` |
| `systemctl stop nginx` | `rc-service nginx stop` |
| `systemctl restart nginx` | `rc-service nginx restart` |
| `systemctl reload nginx` | `rc-service nginx reload` |
| `systemctl status nginx` | `rc-service nginx status` |
| `systemctl enable nginx` | `rc-update add nginx default` |
| `systemctl disable nginx` | `rc-update del nginx default` |
| `systemctl is-enabled nginx` | `rc-update show default` |
| `systemctl list-units --state=running` | `rc-status` |
| `systemctl list-unit-files` | `rc-status -a`，或 `ls /etc/init.d` |
| `systemctl daemon-reload` | 不需要 —— 脚本每次都是现读的 |
| `journalctl -u nginx` | `tail -f /var/log/nginx/error.log`（第 7 节） |

`/etc/init.d/nginx restart` 也行，和 `rc-service` 是同一件事。
这里没有 `service` 命令，那是 Debian 的。

像第 3 节说的：**「启动」和「开机自启」在这里是两件事**，
systemd 把它们合成了 `enable --now`。凡是你打算留着的服务，
启动的同时顺手把它加进 runlevel。

### 看盘

```sh
rc-status               # default runlevel 里有什么，各是什么状态
rc-status -a            # 所有 runlevel
rc-status --servicelist # 存在的全部，不管跑没跑
```

一个什么都没加的容器，健康的盘面很短：

```
Runlevel: default
 hqnode-package-index   [  started  ]
 crond                  [  started  ]
```

`hqnode-package-index` 是让新容器上 `apk add` 能直接用的那个任务，别动它。

**这里的 runlevel 是 `sysinit`、`boot`、`default`、`shutdown`，你要的是
`default`。** `boot` 是给必须比其它一切都早跑的东西用的，`syslog` 在里面。
你加的东西几乎没有不属于 `default` 的。

### 自己写一个服务

OpenRC 的脚本是几个变量，不是一种文件格式。下面这个是完整的，
而且它会照看一个自己不会变成守护进程的程序 —— 你自己写的东西几乎都是这样：

```sh
cat > /etc/init.d/myapp <<'EOF'
#!/sbin/openrc-run
name="myapp"
description="我自己的程序"
command="/data/myapp/run"
command_args=""
command_user="root"
command_background=true
directory="/data/myapp"
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/${RC_SVCNAME}.log"
error_log="/var/log/${RC_SVCNAME}.log"

depend() {
	need net
}
EOF
chmod +x /etc/init.d/myapp
rc-update add myapp default
rc-service myapp start
```

四行承担了全部重量。`command_background=true` 是让 OpenRC 能照看一个前台程序的
前提 —— 不写它，`rc-service start` 会一直卡住。`pidfile` 是它之后靠什么找回这个
进程去停它，只要设了 `command_background` 就必须有。`output_log`/`error_log`
是程序自己的 stdout 和 stderr 落到哪儿去 —— 这里没有 journal 接着它们。
`depend() { need net }` 让它排在网络之后。

要是你不想写，`app-setup install supervisor` 给你 Supervisor，
往里加一个程序就是五行配置，效果一样。

### 两处不是错误的噪音

你加完脚本、OpenRC 第一次重建依赖缓存时，会打印：

```
Service 'machine-id' needs non existent service 'dev'
Service 'watchdog' needs non existent service 'dev'
```

两条说的都是容器本来就正确地不去跑的硬件服务。镜像里已经告诉了 OpenRC
自己在容器里（`/etc/rc.conf` 里的 `rc_sys="lxc"`），这也正是其余那些没出现在
`rc-status` 里的原因。这两条忽略掉。

第二处：刚启动之后的一两秒内，`rc-service nginx status` 回答的是
**`starting`** 而不是 `started`。启动完立刻去检查的脚本得等一下，
那不是失败。

### 定时任务

busybox 的 `crond` 已经在跑了，`crontab -e` 和你预期的一样。
它默认开 `vi`，除非你另说：

```sh
EDITOR=nano crontab -e
crontab -l
```

还有丢文件那种写法，它能扛过 `crontab -r`，在备份里也更好读：

```
/etc/periodic/15min/   /etc/periodic/hourly/   /etc/periodic/daily/
/etc/periodic/weekly/  /etc/periodic/monthly/
```

这些目录里任何一个**可执行**文件都会按那个频率跑。**可执行** ——
没加执行位的脚本会被悄悄跳过，这是这件事上最经典的「白丢一小时」。

要在每次开机时跑一条命令而不是按点跑，用 `/etc/local.d`：

```sh
printf '#!/bin/sh\n/data/myapp/warmup\n' > /etc/local.d/warmup.start
chmod +x /etc/local.d/warmup.start
rc-update add local default      # 只需一次 —— `local` 默认不在任何 runlevel 里
```

---

## 7. 日志

这里**没有 journald，也没有 `journalctl`**。全都是文件 —— 看你从哪儿来，
这要么是解脱，要么是麻烦。

| 文件 | 里面是什么 |
|---|---|
| `/var/log/messages` | 系统日志 —— busybox `syslogd`，大多数守护进程写这里 |
| `/var/log/rc.log` | OpenRC 开机做了什么，以及之后每一次启停 |
| `/var/log/apk.log` | 你装过卸过的每一个包，带时间 |
| `/var/log/<服务>/` | 服务自己写的，比如 `nginx/access.log`、`nginx/error.log` |
| `/var/log/<名字>.log` | 你自己写的服务的 `output_log`（第 6 节） |

```sh
tail -f /var/log/messages           # 跟着系统日志
grep -i error /var/log/messages     # 第一件该试的事
tail -100 /var/log/rc.log           # 某个服务开机没起来的原因
logger "我自己的一行"                # 从脚本里往里写
```

`logrotate` 装了，也从 cron 里跑，所以这些不会撑爆你的硬盘限额。
但你自己加的服务不会被轮转，除非你往 `/etc/logrotate.d/` 里丢一个文件。
在小容器上，这件事值得在你加服务那天做，而不是硬盘满那天：

```sh
cat > /etc/logrotate.d/myapp <<'EOF'
/var/log/myapp.log {
	weekly
	rotate 4
	compress
	missingok
	notifempty
	copytruncate
}
EOF
```

用 `copytruncate` 而不是 `create`，因为被 OpenRC 照看的程序会一直开着自己的
日志文件，收到信号也不会重开它。

---

## 8. 进程、内存、硬盘

镜像装的是 `procps-ng` 而不是把这些交给 busybox，所以 `top`、`ps`、`free`、
`uptime` 打出来的就是你在一台 Linux 上预期的样子：

```sh
top                     # 交互式；`q` 退出
ps aux                  # 所有进程
ps -ef --forest         # 进程树，能看出 init 起了什么
free -m                 # 内存，MB
df -h /                 # 硬盘
du -sh /* 2>/dev/null   # 硬盘去哪了
uptime                  # 负载
```

**这些数字是你的，不是机器的。** 宿主机把按容器切分的 `/proc` 映射了进来，
所以 `free` 报的是卖给你的内存，`nproc` 报的是你的核数 ——
不是你寄居其上的那台 64 核。在照着这些数字调数据库之前，这一点值得知道。

两个例外记一下：`top` 和 `uptime` 里的**负载**是宿主机的，
因为内核没有按容器算的负载；而 `top` 里的 `%CPU` 是相对你自己的核数。

容器自己看不到的那些 —— 流量用了多少、什么时候到期、有哪些域名、
有哪些公网端口 —— 敲 `dashboard`（第 10 节）。

---

## 9. 把网站放到公网上

### 没有防火墙，你也不需要

你可以装 `iptables`。它不会工作：

```
iptables v1.8.13 (nf_tables): Could not fetch rule set generation id:
Permission denied (you must be root)
```

你**确实**是 root —— 但容器没有 `CAP_NET_ADMIN`，所以内核拒绝。
`nft` 也一样，建立在它们之上的每一个封装也一样。

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

进来的流量 —— 域名的也好，公网端口的也好 —— 是送到容器自己的网卡 `tap0` 上的，
**不是**送到容器的 loopback 上。所以绑在 `127.0.0.1` 的服务接不到任何外面的
连接：TCP 连上了，然后什么都不回，看起来像程序坏了，而不像地址写错了。

```
listen 127.0.0.1:3000   →  连得上，空响应，哪儿都不报错
listen 0.0.0.0:3000     →  正常
```

绑 `0.0.0.0` 不会多暴露任何东西，因为进来的路只有上面那两条。
从「程序蹲在本机 nginx 后面」的机器上抄来的配置几乎一定带着 `127.0.0.1`，
那就是要改的那一行。

`127.0.0.1` 只留给唯一的调用方就在同一个容器里的东西。

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

如果你想自己终结 TLS —— 你有自己的证书，或者你跑的东西坚持要自己拿私钥 ——
加上 `self-hosted` 这个关键字，机器就把加密的字节原样接过去，
全程碰不到你的私钥：

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

静态站或者你自己的程序，就 `apk add nginx`，然后改 `/etc/nginx/http.d/`。
注意这个目录：Alpine 把 server 段放在 `/etc/nginx/http.d/`，
不是 Debian 那套 `sites-available` / `sites-enabled`。

---

## 10. 在容器里看流量、限额和到期

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

同样这些数字每次 SSH 登录时都会打在提示符上方，所以你很少需要专门去问。

你也可以直接读内核给这个容器网卡记的计数：

```sh
ip -s link show tap0
```

那是真实的字节数，但它**不是**计费表：容器重启它就归零，
它把以太网帧头和 DNS 也算进去，而且它完全不知道你在哪个计费窗口里。
用它回答「现在是不是有东西在传」；用 `dashboard net` 回答「我还剩多少」。

`helppage` 是容器里的说明书，不用开浏览器：端口和域名、装软件、备份、
每个限额是什么意思、重装保留什么。`helppage --list` 列出所有页，
`helppage --text limits` 把某一页当纯文本打出来。

---

## 11. musl 到底让你付出什么

Alpine 用 musl，而几乎所有别的发行版用 glibc。你自己编译的源码没问题，
别人编译好的二进制才是问题。

**你会看到的报错**，而且它很坑：

```
./some-tool: not found
```

文件明明就在那儿，`ls` 都能看见。缺的是
`/lib64/ld-linux-x86-64.so.2` —— 这个二进制点名要的 glibc 加载器 ——
而内核把「加载器不在」报告成了「程序本身不在」的样子。

```sh
file ./some-tool        # "dynamically linked, interpreter /lib64/ld-linux-…"  → glibc
ldd ./some-tool         # "Not a valid dynamic program"                        → glibc
```

按值得尝试的顺序，你可以：

1. **先找包。** `apk search <名字>` —— Alpine 打包的东西比大家以为的多得多，
   而发行版的包按定义就是对着 musl 编的。
2. **找 musl 版或静态版**，在项目的 releases 页上。Go 和 Rust 的项目几乎一定
   有一个；静态链接的二进制根本不需要加载器，哪里都能跑。
3. **自己从源码编。** `apk add build-base` 给你一套编译器。
4. **放弃，这一样东西用 Debian。** 这是个正当答案，重装也就一分钟。

有两种情况值得单独点名，因为它们天天出现：

- **Python。** 一个没有纯 Python 版本的包，`pip install` 在 Debian 上会下载
  现成的 wheel，在这里则要从源码编 —— 除非项目发布了 `musllinux` 的 wheel
  （现在很多都发了）。从源码编需要编译器和头文件，
  这正是 `app-setup install python` 会把 `python3-dev` 和 `build-base`
  一起带上的原因。这样装，`pip` 就正常了。
- **Node。** Alpine 自己的 `nodejs` 包是跟得上游的，所以
  `app-setup install nodejs` 给你的是 musl 构建，`npm install` 能跑。
  会出问题的是那种自带预编译 `.node` 的 npm 包，它们会退回到现场编译，
  又一次需要 `build-base`。

Go、Rust、PHP、Java、nginx、PostgreSQL、MariaDB、Redis：完全没麻烦。
Rust 在这里甚至默认产出全静态的二进制，算是个小赠品。

### 而它不让你付出的：内存

两个 C 库管内存的方式不一样，值得分清楚哪些差别真的会记到你账上，
哪些只是看着吓人。

**同一个程序在两边占的内存是一样的。** nginx，主进程加四个 worker，
同样的配置：Alpine 上大约 9 MB 私有内存，Debian 上也是大约 9 MB。
申请 250 MB 再释放掉，两边都会把它全部还给内核。
Alpine 缩小的是你程序底下那个系统，不是你的程序。

**它们真正的差别在地址空间，而地址空间不是内存。** glibc 给每个线程
8 MB 栈，还允许它拥有自己的 malloc arena；musl 抠门得多。
同一段 Python 脚本挂着二十个空闲线程，两边实测：

| | Alpine（musl） | Debian（glibc） |
|---|---|---|
| 0 个线程时的虚拟大小 | 10 MB | 15 MB |
| 20 个线程时的虚拟大小 | **52 MB** | **1,490 MB** |
| 常驻内存，0 → 20 个线程 | 7.2 → 7.6 MB | 9.2 → 9.7 MB |

一点五个 GB 的地址空间，背后是不到半 MB 的真实内存。
**你的限额算的是常驻内存，不是地址空间**，所以那 1.5 GB 一分钱都不会算给你，
也不可能因为它把你 OOM 掉。它真正的含义是：Debian 上一个多线程程序在 `top` 里
的 **VIRT** 那一列是个该无视的数字，**RES** 才是你的额度在乎的那个。

**musl 的抠门唯一可能咬你的地方**是那个更小的栈。
用同一个解释器在两边量：这里一个线程拿到 2 MB 栈，Debian 上是 8 MB。
递归很深、或者把一个大数组放在栈上而不是堆上的代码，
在这里只有四分之一的余地，于是在 Debian 上不会溢出的地方在这里溢出了 ——
而栈溢出的表现是一个光秃秃的 segfault，任何日志里都不会有东西。
如果你的某个多线程程序只在这里这么死、别处不死，先怀疑这个；
在创建线程的地方显式指定栈大小就是解法。

---

## 12. 受够了的时候

重装成 Debian 会保留 `/data`、你的登录名、密码和地址。
它会毁掉别的一切 —— 每一个包、每一个服务、`/data` 以外的每一个文件。

```sh
reinstall                  # 这个容器能用什么重建
reinstall debian-13        # 名字的一部分就够了
```

它会让你把容器的名字打一遍，然后你的 SSH 会话会在重建到一半时断开 ——
那是应该发生的事。一分钟后再登回来，地址不变，密码不变，
然后去读[使用 Debian](debian.md)。

反过来走是同一条命令换个名字。两个方向上，你的限额、域名和公网端口都不变。
