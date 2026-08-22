# 备份和恢复数据库

备份就是设置一次的两件事 —— **存到哪**，和**备什么** —— 之后它就定时自己跑，你不用再管。
恢复是一条命令。这一页说的就这些，下面全是只看一次的细节。

如果你按[快速上手](/zh/quick-start)装过数据库，它已经在跑了，也已经按你这份容器的大小调好了。
这一页讲的是接下来做什么，好让硬盘挂掉那天只是难受一个小时，而不是难受一整周。

## 一句话版本

装两个，它就每晚定时跑了：

```
root@box:~# app-setup install store-r2          # 存到哪 —— 一个桶
root@box:~# app-setup install backup-postgresql # 备什么 —— 数据库
```

两个第一次都会弹表单。第一个填桶名和密钥，按 **✓ 测试连接**；第二个选数据库，按保存。
就这样 —— 每晚一份 dump 进桶里。

想手动来，随时：

<FigRows :arrow="1" :rows="[
  [{ m: 'app-setup backup backup-postgresql' }, { t: '现在备一份', tone: 'mute' }],
  [{ m: 'app-setup restore backup-postgresql' }, { t: '把最新的一份放回去', tone: 'mute' }],
  [{ m: 'app-setup archives backup-postgresql' }, { t: '列出都有哪些', tone: 'mute' }],
]" />

MySQL / MariaDB 就是把 `backup-postgresql` 换成 `backup-mysql`，其余一模一样。这一页两边都适用。

## 只有一个概念：存储源，和备份任务

是两张卡，不是一张，而搞懂这个「为什么」就等于搞懂了整个功能。**存储源（store）**是
*备份往哪送* —— 一个桶、一台开了 SSH 的机器。**备份任务（job）**是*备什么、多久备一次* ——
这个数据库、每晚、留两周。一个存储源能装很多任务；一个任务指向一个存储源。

<FigRows :arrow="1" :head="['你配的', '回答的问题']" :rows="[
  [{ t: '存储源', tone: 'strong' }, { t: '备份往哪送？', tone: 'mute' }],
  [{ t: '备份任务', tone: 'strong' }, { t: '备什么、多久一次、留几份？', tone: 'mute' }],
]" />

先配存储源，因为一个没地方送的任务装不上。配完之后，存储源你就再也不用想了。

## 第一步 —— 备份存到哪

敲 `app-setup`，走到 **Backup（备份）** 那一栏。存储源是最上面一排：

<FigScreen :tabs="['数据库', '备份', '开发插件', '系统']" :lines="[
  { pack: true, cols: [{ tag: 'STORE-S3' }, { tag: 'STORE-R2' }, { tag: 'STORE-WEBDAV' }] },
  { pack: true, cols: [{ tag: 'STORE-FTP' }, { tag: 'STORE-SCP' }, { tag: 'STORE-RSYNC' }] },
  [{ t: '备份存到哪。挑你已经有地方放的那一个。', tone: 'mute', face: 'small' }],
]" />

| 挑哪个 | 当你已经有 |
|---|---|
| **store-r2** | 一个 Cloudflare R2 桶 —— 表单比 S3 少两个框 |
| **store-s3** | AWS、MinIO、阿里云 OSS、腾讯云 COS、Backblaze —— 任何说 S3 的 |
| **store-scp** | 任何一台只有 `sshd`、别的都没有的机器 |
| **store-rsync** | 同上，但对面还有 `rsync`（断了能续，只传变化的部分） |
| **store-webdav** / **store-ftp** | 一个 Nextcloud 共享，或者一块 FTP 空间 |

打开 **store-r2**，它问的正好是 Cloudflare 后台给你的那几样 —— 端点和区域它替你算好：

<FigScreen title="Cloudflare R2 · 设置" :lines="[
  [{ t: 'Cloudflare 账号 id', tone: 'mute' }, { f: '', fw: 200 }],
  [{ t: '存储桶', tone: 'mute' }, { f: '', fw: 200 }],
  [{ t: '根目录', tone: 'mute' }, { f: 'backups', fw: 200 }],
  [{ t: 'Access key', tone: 'mute' }, { f: '', fw: 200 }],
  [{ t: 'Secret key', tone: 'mute' }, { f: '', fw: 200 }],
  { align: 'right', cols: [{ b: '保存并应用' }, { b: '保存' }, { b: '取消' }] },
]" />

这张表单存下来就是一个小文件 —— 这就是存储源的全部配置，也是你的密钥唯一存放的地方，权限 `600`：

```ini
# /etc/app-setup/params/store-r2.conf
account=<你的 32 位十六进制 Cloudflare 账号 id>
bucket=web3
prefix=backups
access_key=<R2 access key>
secret_key=<R2 secret key>
```

然后按 **✓ 测试连接**。它不是光登录一下 —— 它建一个目录、写一个文件、列目录、读回来比对字节、
再删掉。五步，因为每一步都会单独失败：一个只有只读权限的密钥能连上、能列目录，然后在第一次
真备份时才挂 —— 这正是它要抓的坑：

<FigScreen title="Cloudflare R2 · 测试" :lines="[
  [{ t: '✓', tone: 'ok' }, { t: '建目录', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '往里写文件', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '列目录', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '读回来比对', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '删掉', tone: 'mute' }],
  [{ t: '建、写、读、删全通过', tone: 'ok' }],
]" />

一个没通过全部五步的存储源，任务是不肯指向它的。写脚本的话，不用菜单也一样：

```
root@box:~# app-setup set store-r2 account=… bucket=web3 access_key=… secret_key=…
root@box:~# app-setup test store-r2
```

> **store-scp 一个密码都不存。** 它用一把自己生成的密钥登录。按 **显示公钥**，把打印出来的
> 那一行加到对面机器那个用户的 `~/.ssh/authorized_keys` 里，再按测试。偷到容器的人拿这个
> 也换不到一个 shell —— 详见 `app-setup docs store-scp`。

## 第二步 —— 备什么

打开 **backup-postgresql**（或 **backup-mysql**）。它的表单分了组：数据库、方式、存到哪、和定时。

<FigScreen title="PostgreSQL · 设置" :lines="[
  [{ t: '▸ 数据库', tone: 'accent' }],
  [{ t: '   主机', tone: 'mute' }, { f: '', note: '留空 = 本机 socket' }],
  [{ t: '   数据库', tone: 'mute' }, { f: '', note: '留空 = 全部' }],
  [{ t: '▸ 方式', tone: 'accent' }],
  [{ t: '   方式', tone: 'mute' }, { r: 'dump', on: true }, { r: 'binary' }, { r: 'files' }],
  [{ t: '▸ 存到哪', tone: 'accent' }],
  [{ t: '   目的地', tone: 'mute' }, { r: 'r2', on: true }],
  [{ t: '▸ 定时与保留', tone: 'accent' }],
  [{ t: '   何时', tone: 'mute' }, { r: '每天', on: true }],
  { align: 'right', cols: [{ b: '保存并应用' }, { b: '保存' }, { b: '取消' }] },
]" />

**主机**留空 —— 那就是本机 socket，数据库信任本机登录，一个密码都不用存。**数据库**留空就是
整个集群。选 **dump**，**目的地**设成你刚测通的那个存储源。其余的默认值已经是大多数人想要的。

这张表单存下来是第二个小文件 —— 完整的任务配置：

```ini
# /etc/app-setup/params/backup-postgresql.conf
host=                 # 留空 = 本机 socket（不存密码）
port=5432
user=postgres
password=
databases=            # 留空 = 每个库，连角色一起
method=dump           # dump | binary | files
store=r2              # 第一步配好的存储源
folder=
schedule=daily        # off | hourly | daily | weekly | monthly
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

三种**方式**，最省事的先说：

<FigRows :rows="[
  [{ t: 'dump', tone: 'strong' }, { t: 'pg_dumpall / mysqldump —— 能读的文本。默认，也是该用的那个。', tone: 'mute' }],
  [{ t: 'binary', tone: 'strong' }, { t: '走复制协议的物理副本。唯一一个能真正备份远程机器的。', tone: 'mute' }],
  [{ t: 'files', tone: 'strong' }, { t: '停库、拷数据目录、启库。只能备本机，一定有停机。', tone: 'mute' }],
]" />

**保留**这几个数字是一道梯子，不是一个数量：每个小时、天、周、月里各留最新的那一份，只要那个
周期还在额度内。默认 `0 / 7 / 4 / 6` —— 一周的每日、一月的每周、半年的每月，加起来也就几个文件。

## 备份，和放回去

打开任务，它的按钮就是那四个动作：

<FigScreen title="PostgreSQL" :lines="[
  { pack: true, cols: [{ b: '▶ 立即备份' }, { b: '▤ 列出备份' }, { b: '✓ 校验' }, { b: '⟲ 恢复' }] },
  { pack: true, cols: [{ b: '参数设置' }, { b: '日志' }, { b: '使用说明' }] },
  [{ t: '需要 Backup 页里一个配置好并测试通过的存储源。', tone: 'mute', face: 'small' }],
]" />

写脚本用的同样四个 —— 每晚定时跑的就是它，你要盯它跑得怎样也用它：

<FigRows :head="['命令', '做什么']" :rows="[
  [{ m: 'app-setup backup backup-postgresql' }, { t: '打包一份并上传', tone: 'mute' }],
  [{ m: 'app-setup archives backup-postgresql' }, { t: '列出都有哪些，本地和桶里', tone: 'mute' }],
  [{ m: 'app-setup verify backup-postgresql' }, { t: '打开最新那份，看它能不能加载', tone: 'mute' }],
  [{ m: 'app-setup restore backup-postgresql' }, { t: '把最新的一份放回去', tone: 'mute' }],
]" />

**恢复一份 dump 是一个按钮。** 它从存储源拉最新那份、打开、加载。`dump` 和物理的
`binary`/`files` 恢复方式不同，工具会按档案实际是哪种来做对的那件事。

**恢复一份物理（`binary`）备份，故意不做成一个按钮。** 把 `pg_basebackup` 放回去，得判断
这是一次恢复还是要做一个新备库、再把对应的信号文件写对 —— 这件事在 PostgreSQL 12 变过一次，
对开了 WAL 归档的集群又不一样。猜错了，你会得到一个能启动、却悄悄少了最近一小时数据的服务器。
所以对物理档案，恢复会把它解到数据目录旁边、把你这个版本该敲的步骤打出来，然后停下。只要你
一直用 `dump`（单库单机就该用它），你根本碰不到这个。

还有一对不需要存储源的命令，用来留一份你自己拿着的快照：

```
root@box:~# app-setup dump postgresql    # 一个 .sql，写到 /data/app-setup/dumps/
root@box:~# app-setup load postgresql    # 把最新那份喂回去
```

## 怎么让数据库尽可能小

数据库出厂时，是按一台*唯一*任务就是当数据库的机器来配的。在容器里它是跟别的东西挤内存的，
放着不管，它一条查询没服务就先占掉几百兆。**app-setup 在安装时替你按容器实际的内存把它调小** ——
常见情况你什么都不用做。这一节是给你想再小一点的时候看的。

每个数据库脚本都问同一个问题 —— 这机器有多少内存 —— 而且答法一样，所以 MariaDB 和 PostgreSQL
永远不会对「小」是什么各说各话：

<FigRows :head="['你这份容器', '档位', '会怎样']" :rows="[
  [{ t: '不到 512M' }, { t: 'tiny', tone: 'strong' }, { t: '每个默认值都不对，狠狠砍', tone: 'mute' }],
  [{ t: '512M – 1G' }, { t: 'small', tone: 'strong' }, { t: '把最离谱的几个削掉', tone: 'mute' }],
  [{ t: '1G 及以上' }, { t: 'normal', tone: 'strong' }, { t: '不动 —— 到这份上默认值就对了', tone: 'mute' }],
]" />

到 1G 以下，它会多写一个配置文件，里面的大小是按这台机器算出来的，而且会告诉你它写了。
**MariaDB** 那个文件是 `/etc/mysql/mariadb.conf.d/90-app-setup.cnf`，最要紧的三行，就是默认
各自 128M 的那三个缓存：

```ini
# /etc/mysql/mariadb.conf.d/90-app-setup.cnf  —— 512M 容器上
[mysqld]
innodb_buffer_pool_size    = 64M    # 八分之一的内存（默认 128M）
aria_pagecache_buffer_size = 16M    # 一个不用也照收费的老缓存
key_buffer_size            = 16M
max_connections            = 64
tmp_table_size             = 16M
max_heap_table_size        = 16M
```

**PostgreSQL** 是往集群自己的 `postgresql.conf` 追加一段。挑大梁的是 `shared_buffers`
（启动时一次性预留）和 `work_mem`（*按每次排序、每个连接*收费 —— 真正的上限是它乘以同时在排的
排序数，所以才一直压得很小）：

```ini
# 追加到 /data/postgresql/postgresql.conf  —— 512M 容器上
shared_buffers = 32MB     # 八分之一的内存（默认 128MB）
work_mem = 1MB            # 按每次排序、每个连接 —— 故意压小
maintenance_work_mem = 16MB
max_connections = 16
effective_cache_size = 64MB
max_parallel_workers_per_gather = 0   # 这么小的机器上，并行的代价比收益大
max_parallel_workers = 0
autovacuum_max_workers = 1
jit = off
```

实测差别不小：一个原样的 PostgreSQL 一条查询没服务就占掉 100M 以上常驻内存；按 512M 调过的，
只占其中一小块。MariaDB 那三个 128M 的缓存 —— 一个连接都还没有就 384M —— 变成几十兆。

**想比你的内存暗示的还要小** —— 一台 1G 的机器上数据库只是个配角、别的东西要用内存 —— 安装时
指定档位：

```
root@box:~# APP_SETUP_PROFILE=tiny app-setup install postgresql
```

`tiny` 不管实际内存多少，都写最狠的那一档。配置文件头上写着是谁、为什么写的，删掉它再重启服务
就回到发行版自己的默认值。给机器加内存后再装一次，文件会重写来匹配 —— 到 1G 以上直接删掉。

调优还不够的话，还有两个旋钮：

<FigRows :rows="[
  [{ t: '减少连接数', tone: 'strong' }, { t: '每个连接是一个进程（PostgreSQL）或一套缓冲区（MariaDB）。max_connections 是个内存设置，不只是个上限。', tone: 'mute' }],
  [{ t: '把数据挪到 /data', tone: 'strong' }, { t: '不是内存，是磁盘 —— 而且是重装后还在的那块。脚本会主动帮你挪。', tone: 'mute' }],
]" />

## 每个配置文件，完整版

来来去去就这几个，全在一个路径下 —— `/etc/app-setup` —— 全是能读能改的纯文本。`params/` 是表单
存下来的；`secrets/` 是生成的密码，`0700`，每个文件 `0600`。

```ini
# /etc/app-setup/params/store-r2.conf         —— 一个 Cloudflare R2 目的地
account=<32 位十六进制账号 id>
bucket=web3
prefix=backups
access_key=<R2 access key>
secret_key=<R2 secret key>
```

```ini
# /etc/app-setup/params/store-scp.conf         —— 一台 SSH 机器（密钥认证，不用密码）
target=backup@nas.local:/volume1/backups
port=22
```

```ini
# /etc/app-setup/params/backup-postgresql.conf   —— PostgreSQL 任务
host=                 # 留空 = 本机 socket
port=5432
user=postgres
password=
databases=            # 留空 = 全部
method=dump
store=r2
folder=
schedule=daily
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

```ini
# /etc/app-setup/params/backup-mysql.conf        —— MySQL / MariaDB 任务
host=                 # 留空 = 本机 socket
port=3306
user=root
password=
databases=            # 留空 = 全部
method=dump
store=r2
folder=
schedule=daily
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

改一个，下次跑就生效；读它的服务重启一下就拾起来。这里没有藏起来的状态 —— 一个躺在 `600`
权限文件里的密码，是你能想明白的东西。

## 这到底简不简单？

对常见情况 —— 单库、单机、每晚 dump 到一个桶 —— 简单：装两个就自己跑了，放回去一条命令。
你要记住的只有一个概念，**存储源和任务**，就这一个。

它故意*不*做成一个按钮的地方，都是「按错了会悄悄丢数据」的地方：一个没通过五步测试的存储源
不会被任务接受，一个物理备份不会靠猜来恢复自己。这两个「拒绝」，都是功能在正常工作。

想要最短的一条路、别的都不管，就这个：

```
root@box:~# app-setup install store-r2          # 填桶，按测试
root@box:~# app-setup install backup-postgresql # 选库，按保存
root@box:~# app-setup backup backup-postgresql  # 现在先备一次，稳妥
root@box:~# app-setup restore backup-postgresql # 需要那天
```

## 另见

- [快速上手](/zh/quick-start) —— 一开始怎么把数据库装上。
- [使用你的容器](/using-your-container)（英文）—— `/data` 是什么，数据库为什么该放上面。
- `app-setup docs backup-postgresql` —— 脚本在机器上自己讲自己。
