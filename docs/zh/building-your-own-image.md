---
title: 自己做镜像
---

# 自己做镜像

重装对话框里有一个框，要的是一条完整的镜像引用 —— `ghcr.io/you/thing:tag` ——
框底下那个问题是「我该往里面填什么」。新建容器的表单上也有同一个框，所以它有两扇门：
机器的主人可以用一条引用直接建容器，拿着容器的人可以用一条引用来重装。

两扇门的答案是同一个。你需要**一个机器能拉下来、并且能作为系统容器启动的镜像**。
这就是一个 `Dockerfile`、一次推送、一次粘贴，最短的版本一屏就写得下。

- [1. 五分钟版本](#_1-五分钟版本)
- [2. 机器到底要求什么](#_2-机器到底要求什么)
- [3. 我们的镜像里已经装了什么](#_3-我们的镜像里已经装了什么)
- [4. 一个真实的例子：两个服务、cron，和放在 /data 上的配置](#_4-一个真实的例子-两个服务、cron-和放在-data-上的配置)
- [5. 从别的底包开始](#_5-从别的底包开始)
- [6. 用 GitHub Actions 打包](#_6-用-github-actions-打包)
- [7. 让机器拉得到它](#_7-让机器拉得到它)
- [8. 装上去，以及它的代价](#_8-装上去-以及它的代价)
- [9. 从 GitHub Actions 驱动它](#_9-从-github-actions-驱动它)
- [10. 贴进去之前先检查](#_10-贴进去之前先检查)
- [11. 起不来的时候](#_11-起不来的时候)
- [12. 让 AI 帮你写](#_12-让-ai-帮你写)

---

## 1. 五分钟版本

从你的容器现在正在跑的那个镜像开始。机器要求的东西它全都有，所以你的 `Dockerfile`
只需要往上加你自己的软件。

```dockerfile
FROM ghcr.io/yinyue123/hqnode:alpine-3.24

RUN apk add --no-cache nodejs npm
COPY app/ /opt/app/
RUN cd /opt/app && npm ci --omit=dev

# 写成一个服务，容器启动时它才会起来。写成 CMD 是不行的 —— 见第 2 节。
RUN printf '%s\n' \
      '#!/sbin/openrc-run' \
      'description="my app"' \
      'command=/usr/bin/node' \
      'command_args="/opt/app/server.js"' \
      'command_background=yes' \
      'pidfile=/run/app.pid' \
      'output_log=/var/log/app.log' \
      'error_log=/var/log/app.log' \
      'depend() { need net; }' \
      > /etc/init.d/app; \
    chmod +x /etc/init.d/app; \
    rc-update add app default
```

按机器的架构构建，推到机器够得着的地方：

```sh
echo "$GHCR_TOKEN" | docker login ghcr.io -u you --password-stdin
docker buildx build --platform linux/amd64 -t ghcr.io/you/myapp:v1 --push .
```

然后把 `ghcr.io/you/myapp:v1` 粘进**我自己的镜像**那一栏，确认。一两分钟之后，
容器就跑在你的镜像上了，`/data` 还在原地。

后面全是细节：机器要求什么（第 2 节）、从我们的镜像开始你白拿了什么（第 3 节）、
一个真的在跑、把网站和数据库装在一起的镜像（第 4 节）、怎么把构建从笔记本挪进
CI（第 6 节），以及怎么让一次 push 最后变成一个正在运行的容器（第 9 节）。

---

## 2. 机器到底要求什么

清单很短，而且每一条都是真的会拦你的，不是「建议」。

| 要什么 | 为什么 |
|---|---|
| **`/sbin/init`**，可执行，能当 PID 1 | 面板建出来的每一个容器都是**系统容器**，它的 PID 1 就是 `/sbin/init`。这条是最多人栽的 |
| **`/bin/sh`** | 每一次 SSH 会话都是在容器里 `sh -c`。登录 shell 是 `command -v bash \|\| command -v sh` |
| 镜像索引里有**机器的架构** | amd64 的机器上要有 `linux/amd64`。索引里没有匹配的平台会被拒绝，而不是悄悄换一个 |
| **init 认得的 `STOPSIGNAL`** | 否则每次停止都是干等 30 秒然后被杀掉。见下面 |
| `su` | 只有当容器的登录用户不是 root 时才需要：网关用它来让登录拿到那个用户自己的 shell、用户组和环境 |
| `PATH` 上有个叫 `sftp-server` 的东西 | 只有你要用 SFTP 和 `scp` 时才需要。网关兜底会去找 Debian 的 `/usr/lib/openssh/sftp-server`，放在别处就得做个软链 |

以及它**不需要**的东西 —— 下面每一条都真的有人往镜像里塞过：

- **不需要 sshd。** hqnode 的登录是主机上的网关钻进你容器的命名空间，不是连到容器里的
  某个守护进程。镜像里没有任何东西需要跟机器的 SSH 对齐。
- **不需要 `/etc/resolv.conf`**，也不需要 `/etc/hostname`。两个都是绑进去的，
  镜像里没有就替你建。
- **不需要 `/data` 这个挂载点。** 没有就建 —— 镜像里带上它只是整洁，不是要求。
- **不需要用户、公钥、密码。** shell 登录是机器那边的东西，它能熬过重装，恰恰是因为
  它从来就不在镜像里。

### 你的 `CMD` 不是被执行的那个

这是最大的坑。面板建的容器是系统容器，所以它的入口是 `/sbin/init` ——
**不管你镜像里的 `CMD` 或 `ENTRYPOINT` 写了什么**，而且每次重装都会重新算一遍。
两个后果：

- 按普通应用容器那样做的镜像 —— `CMD ["node", "server.js"]`、没有 init ——
  会被下载、解包，然后启动失败，因为没有 `/sbin/init` 可执行。你会得到一个存在但
  跑不起来的容器；
- 有 init、但只在 `CMD` 里启动你的程序的镜像，起来之后是一台你的程序没在跑的机器。

所以你的程序必须由 init 来拉起：Alpine 上是一个 OpenRC 服务（第 1 节），
其他系统上是一个 systemd unit。

```dockerfile
# 同一件事的 systemd 版本
RUN printf '%s\n' \
      '[Unit]' 'Description=my app' 'After=network.target' \
      '[Service]' 'ExecStart=/usr/bin/node /opt/app/server.js' 'Restart=always' \
      '[Install]' 'WantedBy=multi-user.target' \
      > /etc/systemd/system/app.service; \
    systemctl enable app
```

这两种怎么写才算写好 —— init 脚本、unit，以及围着它们的那些命令 ——
是[使用 Alpine](alpine.md) 和[使用 Debian](debian.md) 这两页的事。

你**也可以**把 `/sbin/init` 换成你自己的程序 —— 那只是一个路径而已 ——
但那样它就是 PID 1，该有的责任一样不少：没有服务、没有 cron、没有 `systemctl`，
僵尸进程你自己收，停止信号你自己处理，不处理就每次都被杀。面板照样把它显示成系统容器，
因为它当初就是这么建的。真要这么做，就写上 `STOPSIGNAL SIGTERM` 并且 trap 它。

### 平台

agent 是明确地从你的镜像索引里挑 `linux/<机器的架构>` 的。它绝不会「拿第一个 manifest」，
索引里没有匹配项就是一个错误，而不是一个惊喜。

大部分机器是 amd64。不确定的话，容器页面上写着架构；两个都构建也就多一行：
`--platform linux/amd64,linux/arm64`。在 GitHub Actions 上 arm64 是 QEMU 模拟的 ——
结果是对的，慢到你会注意到。

### 停止信号

哪个信号表示「关机」是 init 说了算的，而选错了这件事，在某个东西停了 30 秒之前
你根本看不出来。

| init | 信号 | 用错了会怎样 |
|---|---|---|
| systemd | `SIGRTMIN+3` | `SIGTERM` 会让它重启 |
| busybox init + OpenRC（Alpine） | `SIGUSR2` | `SIGTERM` 的意思是*重启*：容器关完又被拉起来，于是每次「停止」都变成了重启 |
| 你自己的 PID 1 | 你 trap 的那个 | 不处理就是等 30 秒然后 `SIGKILL` |

我们的镜像都声明了自己的那个，所以 `FROM` 我们的镜像会继承下来，你什么都不用做。
如果你从裸底包开始，就自己写上：

```dockerfile
STOPSIGNAL SIGRTMIN+3    # systemd
STOPSIGNAL SIGUSR2       # busybox init / OpenRC
```

**混用不同 init 家族之前，有一件事值得知道。** 停止信号是**创建**容器的时候
从当时那个镜像记下来的，重装不会改写它。所以一个当初用 Debian 建的容器，重装成你
基于 Alpine 的镜像之后，停止时发的还是 `SIGRTMIN+3` —— busybox init 会忽略它，
于是每次停止都变成干等 30 秒。跟容器创建时那个镜像待在同一个家族里就不会遇到；
否则就找你的房东用你的引用重新建一个容器，那条路是会读你镜像里的信号的。

---

## 3. 我们的镜像里已经装了什么

这些是**机器**，不是应用容器 —— 往里加东西的时候，先记住这一点。包管理器、
服务管理器、cron 守护进程都在里面，而且都跑着。所以把你自己的软件放进镜像，
和在一台真机器上做的是同样两步：装上，然后写一个拉起它的服务。

```sh
apk add nginx                  # Alpine。       其他系统是 apt-get install / dnf install
rc-update add nginx default    # 开机自启。      其他系统是 systemctl enable nginx
```

二十个系统、三份配方、一个公开的包 —— `ghcr.io/yinyue123/hqnode:<tag>`。
整套构建都在[这个站点自己的仓库](https://github.com/yinyue123/hqno.de/tree/main/images)里，
它就是这一页反复指着的那个「做好的例子」。

| 配方 | 系统 | 包管理器 | PID 1 | 大小 |
|---|---|---|---|---|
| [`openrc-alpine`](https://github.com/yinyue123/hqno.de/blob/main/images/openrc-alpine/Dockerfile) | Alpine 3.24、3.23 | apk | busybox init + OpenRC | 约 13 MB |
| [`systemd-deb`](https://github.com/yinyue123/hqno.de/blob/main/images/systemd-deb/Dockerfile) | Debian、Ubuntu | apt | systemd | 约 45–60 MB |
| [`systemd-rpm`](https://github.com/yinyue123/hqno.de/blob/main/images/systemd-rpm/Dockerfile) | AlmaLinux、Rocky、CentOS、Fedora | dnf，CentOS 7 上是 yum | systemd | 约 90–125 MB |

在发行版自己的底包之上，这些镜像里还有什么，以及每一样是干什么用的：

| 里面有什么 | 它是干什么的 |
|---|---|
| 一个 init —— `systemd systemd-sysv dbus`，或者 `openrc busybox-openrc busybox-suid` | 当 PID 1，并且把别的东西都拉起来。`systemctl start` / `enable`，或者 `rc-service` / `rc-update add … default`。这就是 `/sbin/init` |
| 发行版自己的包管理器 | `apk`、`apt-get`、`dnf`，能用而且是当前的。软件就是从这儿进盒子的 —— 在你的 `Dockerfile` 里是它，登进一个正在跑的容器里也是它 |
| cron —— `crond`、`cron`、`cronie`，**已经在默认运行级里** | 定时任务，从第一次开机就在跑。`crontab -e`；或者在 Alpine 上把脚本丢进 `/etc/periodic/15min\|hourly\|daily\|weekly\|monthly`，Debian 和 RPM 家族上是 `/etc/cron.d` |
| `bash` | 人们预期的那个登录 shell。硬要求是 `/bin/sh`（第 2 节），但只要 bash 在，登录拿到的就是它 |
| `openssh-sftp-server`，外加一个软链把 `sftp-server` 放到 `PATH` 上 | 提供 SFTP —— 从 OpenSSH 9 起 `scp` 说的也是这个协议。网关执行的是容器自己的那一份，所以文件和权限都是容器的 |
| OpenSSH **客户端** | 往外的那个方向：`git clone git@…`、`rsync -e ssh`、把文件拷到另一台机器 |
| `shadow` / `passwd`、`sudo`、`su` | 真正的账号体系：改 shell 密码、非 root 登录时用 `sudo`，以及 `su` —— 网关用它把非 root 登录落到那个用户自己的 shell、用户组和环境里 |
| `rsyslog` / `syslog`、`logrotate` | 服务的输出落到 `/var/log`，并且会轮转，而不是把盘撑满 |
| `procps` / `procps-ng`、`iproute2`、`iputils`、`curl`、`ca-certificates`、`less`、`nano`、`tzdata` | `top` 和 `free` 打出人们预期的东西而不是 busybox 那套简版、`ip`、`ping`、一个证书齐全的 `curl`、一个分页器、一个编辑器，以及一个可以设的时区 |
| `STOPSIGNAL` | 说明主机关这个盒子时发哪个信号（第 2 节） |
| 让 init 适应容器的那几个设置 —— `rc_sys="lxc"`、`rc_provide="loopback net"`、`/etc/inittab` 里删掉 getty；或者 systemd 把硬件相关的 unit mask 掉 | 拦住 init 去启动那些在容器里根本不可能工作的硬件服务。不改的话，一个完全健康的盒子在 `rc-status` 或 `systemctl status` 里满屏是红的 |
| sshd，装上了但**关着** | 留给想在自己端口上跑一个 sshd 的人：`systemctl enable --now ssh`，或者 `rc-update add sshd default && rc-service sshd start` |
| 开机刷一次包索引，一天最多一次 | 让刚登录进去的 `apk add nginx` 就能用，而不是回你一句「没有这个包」 |
| `app-setup`、它的配方，以及 `/etc/helppage` | 那个装 LNMP、WordPress、数据库、备份的菜单，以及 `helppage` 打出来的指南。往里加你自己的条目是[添加你自己的软件（英文）](/app-setup-sources) |
| `PATH` 上那几个 shim —— `passwd`、`poweroff`、`halt`、`dashboard`、`domain`、`reinstall`、`helppage` | 拿着容器的人得到的那几条命令：一次也会同步到 SSH 网关的改密码、一个关了就真的不再被拉起来的 `poweroff`、看自己配额、加域名，以及在 shell 里重装 |
| `/data`，里面放一个 README | 重装唯一保留的那块盘的挂载点 |

第 2 节是镜像必须有的那张短清单。上面这些则是你 `FROM` 我们的镜像白拿的东西 ——
去掉其中任何一样，改变的是这个盒子登进去的手感，不是它能不能启动。

---

## 4. 一个真实的例子：两个服务、cron，和放在 /data 上的配置

五分钟版本是一个服务、没有状态。真实的镜像通常两样都不止一个。下面是一个真在跑的
镜像的形状 —— 一个 Next.js 站点和它用的 PostgreSQL，装在同一个容器里，
那个容器一共 384 MB 内存。

```dockerfile
# ── 在有工具链的地方把应用构建出来 ─────────────────────────────────
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ── 盒子本身 ──────────────────────────────────────────────────────
FROM ghcr.io/yinyue123/hqnode:alpine-3.24

# 包管理器就在手边。两个服务的运行时；写 postgresql17 而不是不带版本号的包，
# 是因为更新的大版本打不开上个月那份 dump 所属的数据目录。
RUN apk add --no-cache nodejs postgresql17 postgresql17-client

# 站点不用 root 跑，这里也没有任何东西要绑特权端口：
# 域名可以路由到你指定的任意容器端口。
RUN addgroup -S app && adduser -S -D -H -G app -s /sbin/nologin app
COPY --from=build --chown=app:app /app/.next/standalone /app

# 一个服务一个 init 脚本，两个都加进默认运行级。
COPY init.d/app /etc/init.d/app
COPY init.d/db  /etc/init.d/db
RUN chmod 0755 /etc/init.d/app /etc/init.d/db; \
    rc-update add db  default; \
    rc-update add app default

# 这个底包上 crond 本来就在跑，所以一个每晚的任务就是一个文件。
RUN printf '#!/bin/sh\nexec /usr/local/sbin/app-backup\n' \
      > /etc/periodic/daily/app-backup; \
    chmod 0755 /etc/periodic/daily/app-backup
```

两个 init 脚本里的一个：

```sh
#!/sbin/openrc-run
name="app"
description="the site"

# 配置放在重装会保留的那块盘上，不在镜像里。
env_file="/data/app.env"
if [ -r "$env_file" ]; then set -a; . "$env_file"; set +a; fi

supervisor=supervise-daemon        # OpenRC 版的 Restart=always
command="/usr/bin/node"
command_args="/app/server.js"
command_user="app:app"
output_log="/var/log/app.log"
error_log="/var/log/app.log"
respawn_delay=10
respawn_max=5
respawn_period=60

depend() { need net; use db; }

start_pre() {
    [ -f "$env_file" ] || { eerror "没有 $env_file —— 这个容器还没配置过"; return 1; }
    checkpath --file --mode 0640 --owner app:app /var/log/app.log
}
```

里面有五件事，是「在你笔记本上能跑」和「在别人的机器上能跑」之间的差别：

- **配置放 `/data`，不要写进 `ENV`。** OpenRC 会把交给服务的环境清干净，
  所以镜像里的 `ENV` 只到 PID 1 为止 —— 实测：设了 `ENV PORT=80`，
  服务起来用的还是它自己的默认端口。改成在 init 脚本里读一个 env 文件。
  systemd 那边的 `EnvironmentFile=/data/app.env` 是同一招，而且还有第二个理由：
  unit 在镜像里，密码不该在。
- **用 `supervise-daemon`，不要 `start-stop-daemon`。** 后者在进程 fork 的那一刻
  就把它忘了，于是一次崩溃会让站点一直躺到有人去看。`respawn_period` 里的
  `respawn_max` 又拦住了「配置根本不可能work」的情况无限重试、把原因埋掉。
- **按容器自己的限额来配内存，不是按宿主机的。** V8 的堆和 PostgreSQL 的缓冲区
  默认都从 `/proc/meminfo` 算，而那在容器里是**宿主机**的内存，不是卖给你的 384 MB。
  改成读 `/sys/fs/cgroup/memory.max` 再据此设上限，否则内核迟早会杀掉盒子里最大的
  那个进程 —— 那可能正是写到一半的数据库。
- **不需要 root 的服务就别用 root。** OpenRC 里是 `command_user`，
  systemd unit 里是 `User=`。
- **状态放 `/data`，而且只放非放不可的。** 这里是数据目录（`PGDATA=/data/postgresql`）
  和那个 env 文件。其余一切重装镜像就能重建 —— 这恰恰是重装之所以便宜的原因。

systemd 系的同一个镜像是同样的形状：`apt-get install`、
`/etc/systemd/system` 下一个服务一个 unit、`systemctl enable`、
`EnvironmentFile=` 指到 `/data`，以及上面 `supervise-daemon` 那个位置写 `Restart=always`。
两个家族各自怎么管服务，在[使用 Alpine](alpine.md) 和[使用 Debian](debian.md) 里一条条写着。

---

## 5. 从别的底包开始

`FROM ghcr.io/yinyue123/hqnode:alpine-3.24` 是推荐做法，第 1 节就是理由 ——
第 2 节里的每一条要求都已经满足，第 3 节里的每一样方便也都白送。但这不是唯一的路，
而且确实有两个正当理由自己从发行版底包做起：你想要一个我们没发布的系统，
或者你想确切知道盒子里装的是什么。

如果是这样，去读你所在家族的那份配方 —— 一共三个文件，注释写得很满，
而里面每一条注释都是某次真的踩过的坑：

- [`openrc-alpine/Dockerfile`](https://github.com/yinyue123/hqno.de/blob/main/images/openrc-alpine/Dockerfile)
- [`systemd-deb/Dockerfile`](https://github.com/yinyue123/hqno.de/blob/main/images/systemd-deb/Dockerfile)
- [`systemd-rpm/Dockerfile`](https://github.com/yinyue123/hqno.de/blob/main/images/systemd-rpm/Dockerfile)

在 Debian 家族的底包上，最小的一份大概是这么多：

```dockerfile
FROM debian:13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-sftp-server \
 && rm -rf /var/lib/apt/lists/*

# 硬件相关的 unit 在容器里没有意义，而且开机时会失败得很大声。
RUN systemctl mask systemd-udevd.service systemd-udevd-kernel.socket \
      systemd-udevd-control.socket systemd-modules-load.service \
      sys-kernel-debug.mount sys-kernel-config.mount \
      systemd-journald-audit.socket

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
```

那行 `CMD` 是写给人看的，不是给机器的指令 —— 机器反正会执行 `/sbin/init`（第 2 节）——
但把它写对意味着这个镜像在 `docker run` 下也做同样的事，而你多半就是在那里测它的。

**把 `app-setup` 一起带走。** 它是一个静态二进制加一个装 shell 脚本的目录，
从我们任何一个镜像里都能干净地拷出来：

```dockerfile
FROM ghcr.io/yinyue123/hqnode:alpine-3.24 AS hq

FROM debian:13-slim
COPY --from=hq /bin/app-setup       /bin/app-setup
COPY --from=hq /usr/lib/app-setup/  /usr/lib/app-setup/
COPY --from=hq /etc/app-setup/      /etc/app-setup/
RUN mkdir -p /etc/app-setup/local /etc/app-setup/params /etc/app-setup/secrets \
 && chmod 0700 /etc/app-setup/secrets \
 && app-setup doctor >/dev/null
```

那个二进制是对着 musl 静态链接编出来的，这正是为什么一份拷贝在 CentOS 7 和 Alpine 上
都能跑。往它的菜单里加你自己的软件是另一件事，有自己的一页：
[添加你自己的软件（英文）](/app-setup-sources)。

---

## 6. 用 GitHub Actions 打包

这里没有一件事非要 runner 不可 —— 在笔记本上 `docker buildx build --push`
出来的是同一个镜像。用 CI 的理由和一贯的理由一样：装上去的那个镜像，是由一个
你事后能读的任务、从 `main` 上的东西构建出来的。

下面是给你自己仓库用的一份完整 workflow，放到 `.github/workflows/image.yml`：

```yaml
name: image

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write          # 唯一需要的凭据：GITHUB_TOKEN
    steps:
      - uses: actions/checkout@v4

      # 只有在 amd64 runner 上构建 linux/arm64 时才需要。
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          push: true
          # 证明（attestation）用的 manifest 会给每个平台多加一条，
          # 那一条自己的平台是 unknown/unknown。这里没有东西需要它们，
          # 而一个乏味的 manifest 就少一样可以被挑错的东西。
          provenance: false
          sbom: false
          tags: |
            ghcr.io/${{ github.repository_owner }}/myapp:latest
            ghcr.io/${{ github.repository_owner }}/myapp:${{ github.sha }}

      - run: echo "${{ steps.build.outputs.digest }}" >> $GITHUB_STEP_SUMMARY
```

不管你改什么，这四样值得留着：

- **`packages: write` 加 `GITHUB_TOKEN`。** 不用建 secret，不用轮换 token，
  推到 `ghcr.io/<你的账号>/…` 这就够了。
- **`platforms`。** 就一行，而它决定了机器是能启动这个镜像还是直接拒绝（第 2 节）。
  只构建 amd64 的话，`setup-qemu-action` 那步可以删掉。
- **两个 tag：一个会动的，一个不会动的。** `:latest` 方便，`:<sha>` 是你想
  确切知道装的是什么时该粘的那个 —— 从面板决定到主机去拉，中间 tag 是会动的。
- **把 digest 写进 summary。** `steps.build.outputs.digest` 就是那个镜像本身。
  第 9 节按 digest 安装，那是唯一能确定盒子里跑的正是这次构建产物的办法。

**然后手动把这个包设成公开，一次就好。** GHCR 上新建的包是私有的，
而私有的包在机器来拉的时候就是一个 `401`。到包的页面 → **Package settings** →
**Change visibility** → Public。workflow 里没有任何东西能替你做这件事。
如果它必须保持私有，看第 7 节。

### 这个站点上的镜像是怎么构建的

如果你要的是一条流水线而不是一个 Dockerfile，我们这条值得一读：三个 Dockerfile
加一份清单，做出二十个系统，都在
[`.github/workflows/images.yml`](https://github.com/yinyue123/hqno.de/blob/main/.github/workflows/images.yml)。

三个 job，这个形状是可以照抄的：

| job | 做什么 |
|---|---|
| `list` | 用 `yq` 读 [`images/systems.yml`](https://github.com/yinyue123/hqno.de/blob/main/images/systems.yml)，把它变成构建矩阵 —— 于是加一个系统就是在一个文件里加一条 |
| `build` | 每个系统一条矩阵腿，`fail-fast: false`，这样某个发行版的镜像站挂了不会连累另外十九个。每条腿推 `:<tag>` 和 `:<tag>-<运行编号>` |
| `catalog` | 从 registry **读回** digest，提交 `images/catalog.json` —— 每个面板都会拉这个文件来填自己的市场 |

里面有两个决定是承重的，换成你的流水线也一样承重。构建上下文是 `images/`
而不是配方自己的目录，因为三个 Dockerfile 都要拷同一棵 `app-setup` 树，
而上下文够不到自己的上一层。以及 digest 是从 registry 读回来的，
不是从构建里传出来的 —— 因为失败的构建会让 tag 继续指着上周那个好镜像，
而那恰恰是目录应该继续这么说的。

它还挂了一条每周的 cron，好让 tag 跟上发行版的安全更新。已经在跑的容器不受影响：
新的字节只有在重装时才会到达持有者手里。

---

## 7. 让机器拉得到它

**去拉的是机器，不是面板，也不是你的笔记本。** 面板是一整个机群的一个进程，
从不搬运镜像字节；你粘进去的引用会被转给主机，由主机直接去 registry 取。
所以要验的不是「我能不能拉到」，而是「那台机器能不能拉到」。

| 它放在哪 | 会发生什么 |
|---|---|
| GHCR、Docker Hub、Quay… 上的公开包 | 能用，而且这是推荐的情况 |
| 机器有凭据的私有 registry | 能用。凭据在机器上的 `/etc/hqnode/registry.json`，那是运维的文件 |
| 谁都没跟机器说过的私有 registry | 拉的时候 `401`/`403`，重装失败，但你的容器毫发无伤 |
| 只有你自己网络里能访问的 registry | 没什么好办法 —— 机器不在你的网络里 |

拿着容器的人没法自己提供 registry 凭据：面板里就没有地方填，这是故意的，
因为那等于把一个租户的密钥放在别人的机器上。如果你的镜像必须私有，
去找运行机器的人把它加进那个文件 —— 在他们那边就是一条记录加一次重启。

引用的写法，因为面板在别的事情发生之前就会先检查它：

```
ghcr.io/you/myapp:v1                          一个 tag
ghcr.io/you/myapp@sha256:<64 个十六进制字符>   钉死到唯一一个镜像
docker.io/library/alpine:3.20                 Docker Hub，写全
```

不带 scheme（`https://…` 会被拒绝，并且会告诉你这句话），不带空格和引号，
冒号后面不能是空的 tag，钉 digest 的话必须是 `sha256:` 加 64 个十六进制字符。
从终端里复制出来时前后带的空白会被去掉。

---

## 8. 装上去，以及它的代价

同一件事，三扇门。重装对话框，停在填引用的那一栏上：

<FigScreen :tabs="['我自己的镜像', '镜像市场', '这台主机上的归档']" :lines="[
  [{ t: '会清空 /。/data 是另一块盘，会保留。', tone: 'mute' }],
  ['镜像引用', { f: 'ghcr.io/you/myapp:v1', fw: 260 }],
  [{ t: '下载的量算在这个容器的流量里。', tone: 'mute', face: 'small' }],
  ['输入 web-1 以确认', { f: '' }],
  { align: 'right', cols: [{ b: '取消' }, { b: '重装，保留 /data' }] },
]" />

或者在容器里敲：

```
reinstall ref ghcr.io/you/myapp:v1
```

或者走 API，也就是第 9 节：

```sh
curl -sS --fail-with-body -b jar.txt -X POST "$PANEL/me/containers/$CID/reinstall" \
  -H 'content-type: application/json' \
  -d '{"ref":"ghcr.io/you/myapp:v1","confirm":"web-1"}'
```

**这一栏要出现，有两个前提。** 机器的策略得允许租户自带镜像（`allow_user_images`），
并且这个容器得有自己的盘 —— 一个只有这个容器看得见的镜像，需要一个只有这个容器
看得见的地方，而卖出去时没给磁盘大小的容器没有这个地方。对话框会告诉你缺的是哪一个，
两个都得你的房东来改。

然后是它的代价 —— 对话框只能用一行说完的那部分：

| | |
|---|---|
| **下载** | 由机器完整地下载，**每次重装都下**。两次重装之间不缓存任何东西 —— 这就是「私有」的价格 |
| **计费** | 每一个字节，算这个容器的入站流量。算的是真正过了网线的量，不是 manifest 上写的 |
| **存放** | 解到这个容器自己的盘里。机器上别人不会被推荐它，主机也不留副本 |
| **免费** | 如果机器上正好已经有一模一样的 digest，它就用自己那份：不下载、不计费，回复里会说明是哪一种 |
| **保留** | `/data`、shell 登录名和密码、你 SSH 的地址和端口、你的域名、公网端口、流量计数、到期日 |
| **丢掉** | `/` 下面其余的一切，包括 `app-setup` 装过的东西，以及它给你生成在 `/etc/app-setup/secrets` 里的密码 |

最后一行是最容易让人损失一个下午的。那些东西要在重装**之前**抄出来，不是之后。

**流量配额这个坑值得单独一段。** 下载是在重装成功之后计费的。如果它把容器顶过了
流量配额，容器会被暂停 —— 而被暂停的容器是不允许重装的，所以你没法靠再抹一次
把自己救回来。等配额窗口滚过去，或者等房东调高上限，它才会解开。一个 400 MB 的镜像
一天重装几次，在配额不大的机器上比人们预期的更快就撞上去 ——
这也是第 9 节第二种做法的又一个理由。

---

## 9. 从 GitHub Actions 驱动它

两种完全不同的活儿，而选错了是这一整页里最常见的浪费。

| | 用你的引用重装 | 通过 SSH 把程序送上去 |
|---|---|---|
| 搬动的东西 | 整个镜像，几十上百 MB | 你的构建产物，通常是几十 KB |
| 流量 | 计费，每一次 | 一样计费 —— 上传算入站流量，网关会统计 —— 但只有几十 KB |
| 活下来的东西 | 只有 `/data` | 全都在，什么都不抹 |
| 要多久 | 一两分钟，其中一段时间盒子是停的 | 几秒 |
| 适合 | 改**系统**：换发行版、加系统包、重做底包 | 改**程序**：你每天都在改的那个东西 |

一句话的经验：**镜像是给系统用的，`rsync` 是给程序用的。**
发版本时重装，提交代码时部署。

### 用你的引用重装

先构建镜像，然后按 digest 安装刚刚构建出来的那一个 ——
这样即使 tag 在任务和拉取之间动过，也不会装上别的东西。下面这几步要放在第 6 节
那个构建 job 里、构建之后：`steps.build.outputs.digest` 是那一步的输出。

```yaml
      - name: 登录面板
        run: |
          curl -sS --fail-with-body -c "$RUNNER_TEMP/jar" "$PANEL/auth/login" \
            -H 'content-type: application/json' \
            -d "$(jq -nc --arg u "${{ secrets.PANEL_USER }}" \
                         --arg p "${{ secrets.PANEL_PASSWORD }}" \
                         '{identifier:$u,password:$p}')" > /dev/null

      - name: 用刚构建出来的镜像重装
        run: |
          REF="ghcr.io/${{ github.repository_owner }}/myapp@${{ steps.build.outputs.digest }}"
          curl -sS --fail-with-body -b "$RUNNER_TEMP/jar" \
            -X POST "$PANEL/me/containers/$CID/reinstall" \
            -H 'content-type: application/json' \
            -d "$(jq -nc --arg r "$REF" --arg c "$NAME" '{ref:$r,confirm:$c}')"

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

`PANEL` 是 `https://hqno.de/api/v1`，`CID` 是容器 URL 里的那个 id，
`NAME` 是容器自己的名字 —— `confirm` 要等于它，不是 `"yes"`。
把面板密码存成 secret，每次运行重新登录；**永远不要存 cookie**，
那是一把七天有效、而你看不出它还剩多久的钥匙。`--fail-with-body` 很要紧：
光用 `curl`，遇到拒绝也会退出 0，于是一个不看状态码的任务会在一个根本没回来的容器上
打出绿色的勾。下载很久时用 `GET /me/containers/{cid}/progress` 看进度。
完整的参考在[面板 REST API（英文）](/api)。

### 通过 SSH 把程序送上去

在账号页面加一把公钥 —— **账号 → SSH 公钥** —— 它会落到这个账号持有的每一个容器上，
包括以后才拿到的。把对应的私钥放进仓库 secret，任务就很普通了：

```yaml
      - name: 送上去
        env:
          HOST: hk-1.example.com
          PORT: '22'
          USER: u7k2m9p
        run: |
          install -m 600 /dev/null key
          printf '%s\n' "${{ secrets.DEPLOY_KEY }}" > key
          rsync -az --delete -e "ssh -i key -p $PORT -o StrictHostKeyChecking=accept-new" \
            build/ "$USER@$HOST:/opt/app/"
          ssh -i key -p $PORT "$USER@$HOST" \
            'rc-service app restart || systemctl restart app'
          rm -f key
```

**`rsync` 也得在容器里有**，而我们的镜像都不带它。把它加在活得下来的地方 ——
在你已经有的那个 `Dockerfile` 里加一行（`RUN apk add --no-cache rsync`）——
或者用 `app-setup install rsync` 装一次，但记住重装会把它带走。
一样都不想加的话，`tar` 走 `ssh` 只用现成的东西：

```sh
tar czf - -C build . | ssh -i key -p "$PORT" "$USER@$HOST" 'tar xzf - -C /opt/app'
```

什么都没被抹掉，什么都没重新下载，容器停的时间不超过一次重启。
用 `-o StrictHostKeyChecking=accept-new`，别干脆把主机密钥检查关掉；
也尽量用公钥，而不是 `sshpass` 加一个存着的密码。

**不要从容器里面去调面板 API。** 容器里故意不放任何面板凭据。
在里面，你想要的那三样东西本来就是命令：`dashboard`、`app-setup domain add …`、`passwd`。

---

## 10. 贴进去之前先检查

五项检查，每一项都对应一次真的有人踩过的失败：

```sh
# 1. 索引里到底有没有这个平台？
docker buildx imagetools inspect ghcr.io/you/myapp:v1

# 2. 有没有一个能当 PID 1 的 init？
docker run --rm ghcr.io/you/myapp:v1 ls -l /sbin/init

# 3. 停止信号声明了吗，是对的那个吗？
docker image inspect ghcr.io/you/myapp:v1 \
  --format 'stop={{.Config.StopSignal}} cmd={{.Config.Cmd}}'

# 4. 两样很容易弄丢的方便东西
docker run --rm ghcr.io/you/myapp:v1 sh -c 'command -v sftp-server; command -v su'

# 5. 它有多大？这就是每次重装的流量账单 —— 压缩后的层字节数，
#    也就是真正过网线的量
docker buildx imagetools inspect ghcr.io/you/myapp:v1 --raw \
  | jq '[.layers[].size] | add'
```

多平台索引在最后一条上会打印 `null`，因为层在它的子 manifest 里：
从 `.manifests` 里取出 amd64 的 digest，再对 `ghcr.io/you/myapp@<那个 digest>`
问同一个问题。我们自己的 catalog 任务算市场里显示的大小时，用的就是这一招。

能不能先在本地启动一遍？部分能。`docker run --rm -it your-image sh`
能证明文件系统是正常的；但要像机器那样把 init 当 PID 1 跑起来，需要特权容器，
对大多数人来说不值当 —— 老实的测法是拿一个丢了也不心疼的容器重装一次。

---

## 11. 起不来的时候

容器会停在那儿，根文件系统已经是新的，`/data` 完好。面板会把主机自己的原话显示出来，
历史里那一行写着是哪个镜像。

再重装一次 —— 这次走**镜像市场**那一栏，让机器装一个它本来就有的东西，
几秒钟盒子就回来了。然后按第 10 节去查是哪里不对。一个坏镜像不会伤到容器本身：
登录、端口、域名、流量计数都在容器外面。

两个例外，别太安心：

- **镜像起不来，下载照样计费。** 字节确实过了网线。
- **因为超配额被暂停的容器根本不允许重装**（第 8 节）。如果坏镜像和用尽的配额
  一起来了，盒子就得等到配额窗口滚过去或者房东调高上限。

如果是重装本身失败了 —— registry 挂了、`401`、blob 传到一半断了 ——
那什么都没有被替换。容器还跑在旧镜像上，也不计费。

---

## 12. 让 AI 帮你写

这件事 AI 做得挺好，因为要求很短、而且不寻常 —— 只要**告诉**它，它就能写对。
不告诉它，它会写出一个普通的应用容器 Dockerfile，而那正好就是在这里起不来的那种。

把下面这段填好，粘给它：

```text
帮我写一个 Dockerfile 和一个 GitHub Actions workflow，做一个跑在 hqnode 上的
容器镜像。hqnode 跑的是「系统容器」，不是应用容器，所以：

- PID 1 永远是 /sbin/init。我的 CMD 和 ENTRYPOINT 会被宿主机忽略 ——
  不管镜像里写了什么，它都执行 /sbin/init。所以我的程序必须由 init 作为服务
  拉起来，绝不能靠 CMD。
- 基础镜像用 ghcr.io/yinyue123/hqnode:alpine-3.24（busybox init + OpenRC、
  apk、musl —— 没有 glibc，预编译的 glibc 二进制跑不了）。服务写成
  /etc/init.d 下的 OpenRC 脚本，并且 `rc-update add <名字> default`。
- 基础镜像已经声明了 STOPSIGNAL SIGUSR2 和 CMD ["/sbin/init"]，不要覆盖它们。
- 必须有 /bin/sh。不需要 sshd、不需要 resolv.conf、不需要 /data 挂载点 ——
  这些是宿主机提供的。
- 用 docker/build-push-action 构建 linux/amd64 并推到 ghcr.io，
  provenance: false、sbom: false，打两个 tag：:latest 和 :<git sha>。
- 镜像尽量小；每次重装都会把它整个下载一遍，并且算作容器的流量。

我要跑的东西：<例如：./app 里的一个 Node 20 HTTP 服务，监听 3000，
数据放在 /data/app>。
我的程序写的、需要熬过重装的东西，都放在 /data 下面。
```

如果你用的是 systemd 系的系统，就把底包和服务写法换掉：`…:debian-13`、
`/etc/systemd/system` 下的 unit、`systemctl enable`、`STOPSIGNAL SIGRTMIN+3`。

拿到结果之后，照着下面这张单子过一遍 —— 这五条是模型在这件事上真正会犯的错：

1. **`CMD ["node", "server.js"]`，没有服务。** 镜像起来了，你的程序没跑。这是最大的一条。
2. **用了 slim 或 distroless 底包** —— `node:20-alpine`、`gcr.io/distroless/…`。
   没有 init，有时连 shell 都没有：容器起不来，而你也登不进去查为什么。
3. **`EXPOSE`、`HEALTHCHECK`、`USER`、`VOLUME`。** 无害，而且四个都被忽略。
   端口是房东给的，不是镜像声明的。
4. **workflow 里没写 `platforms:`**，于是 runner 构建出什么算什么，
   而机器会拒绝一个没有匹配项的索引。
5. **`STOPSIGNAL` 和 init 对不上** —— 在 Alpine 上写 `SIGTERM`，
   会把每一次停止变成重启。

还有两样东西值得一并喂给模型：这一页的网址，以及你的镜像所基于的那份配方 ——
[`openrc-alpine/Dockerfile`](https://github.com/yinyue123/hqno.de/blob/main/images/openrc-alpine/Dockerfile)
只有 150 行，而里面每一条注释都是别人已经踩过的坑。

如果你真正想要的其实是**菜单里多一个软件**、而不是一个新镜像，那是件小得多的事，
它有自己的一页和自己的约定，AI 照着那一个文件也一样写得好：
[添加你自己的软件（英文）](/app-setup-sources)。

---

## 接下来

- [使用你的容器](using-your-container.md) —— 重装保留什么，以及住在里面的其他事
- [添加你自己的软件（英文）](/app-setup-sources) —— 一个 shell 文件，不用做镜像
- [面板 REST API（英文）](/api) —— 第 9 节用到的每一个调用，完整版
