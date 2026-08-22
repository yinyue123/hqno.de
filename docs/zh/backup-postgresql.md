# 备份和恢复 PostgreSQL

备份就是设置一次的两件事 —— **存到哪**，和**备什么** —— 之后它就定时自己跑，你不用再管。
恢复是一条命令。

这一页讲 **PostgreSQL**，从头到尾，配一个真实例子：备份到一个免费的 Cloudflare R2 桶，大约十分钟。
用到两个 recipe：`postgresql`（数据库）和 `backup-postgresql`（备份任务）。

> 其它数据库做法一样，各自有各自的一页：MySQL / MariaDB（`backup-mysql`）、MongoDB
> （`backup-mongodb`）、Redis（`backup-redis`）。下面的存储源、五步测试、四个动作按钮它们都共用，
> 只有导出工具不同。

---

## 完整例子：PostgreSQL → 免费 R2

### 第 0 步 —— 你有一个数据库在跑

按了[快速上手](/zh/quick-start)的话就已经有了。没有的话：

```
root@box:~# app-setup install postgresql
```

它装上来就已经按你这份容器的大小调好了（见[怎么调小](#怎么让数据库尽可能小)）。

### 第 1 步 —— 领一个免费的 R2 桶

备份要存到 Cloudflare R2，它的免费额度很大方 —— 这个羊毛值得薅：

<FigRows :head="['R2 免费额度', '每月']" :rows="[
  [{ t: '存储', tone: 'strong' }, { t: '10 GB —— 够存好几年的每晚数据库 dump', tone: 'mute' }],
  [{ t: '上传（Class A）', tone: 'strong' }, { t: '100 万次操作', tone: 'mute' }],
  [{ t: '下载（Class B）', tone: 'strong' }, { t: '1000 万次操作', tone: 'mute' }],
  [{ t: '出站流量 / 带宽', tone: 'strong' }, { t: '永远免费 —— R2 下载从不收费', tone: 'ok' }],
]" />

最后一行就是 R2 的意义所在：AWS 的 S3 桶，你*把备份拉回来*要收流量费，R2 不收。数据库 dump 很小，
10 GB 你怎么都用不到。

建桶：

1. 登录 **dash.cloudflare.com**，左边栏点 **R2**。（第一次开 R2 会让你绑张卡，但上面那个免费额度
   一分钱不扣。）
2. **Create bucket（创建存储桶）**。起个名 —— `my-backups` —— Location 留 **Automatic**，创建。

桶就好了。接下来是密钥。

### 第 2 步 —— 拿到 app-setup 要的三样东西

app-setup 要一个**存储桶**、一个**账号 id**、和一对 **access key / secret key**。桶你有了，
另外三样：

1. 在 R2 页面右侧，**Account ID** 是一串 32 位的十六进制。复制它。（它也是你 S3 端点的开头，
   `https://<账号 id>.r2.cloudflarestorage.com`。）
2. 点 **Manage R2 API Tokens（管理 R2 API 令牌）** → **Create API Token（创建）**。
3. **Permissions（权限）**选 **Object Read & Write（对象读写）**，在 **Specify bucket(s)（指定存储桶）**
   里选你刚建的那一个 —— 令牌限定到一个桶才安全。创建。
4. 下一个页面会**只显示一次** **Access Key ID** 和 **Secret Access Key**。现在就把两个都复制下来 ——
   secret 关掉就再也看不到了。

现在你手上有四个值，长这样：

```ini
账号 id      a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4     # 32 位十六进制，在 R2 页面
存储桶       my-backups
access key   1234567890abcdef1234567890abcdef     # 令牌页面给的
secret key   fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
```

### 第 3 步 —— 填进 app-setup

```
root@box:~# app-setup install store-r2
```

它弹出表单 —— 把四个值填进去（端点和区域它替你算，所以没有这两个框）：

<FigScreen title="Cloudflare R2 · 设置" :lines="[
  [{ t: 'Cloudflare 账号 id', tone: 'mute' }, { f: 'a1b2c3d4e5f6…', fw: 190 }],
  [{ t: '存储桶', tone: 'mute' }, { f: 'my-backups', fw: 190 }],
  [{ t: '根目录', tone: 'mute' }, { f: 'backups', fw: 190 }],
  [{ t: 'Access key', tone: 'mute' }, { f: '1234567890abcdef…', fw: 190 }],
  [{ t: 'Secret key', tone: 'mute' }, { f: '••••••••••••••••', fw: 190 }],
  { align: 'right', cols: [{ b: '保存并应用' }, { b: '保存' }, { b: '取消' }] },
]" />

想用命令行？同样的事，不用菜单：

```
root@box:~# app-setup set store-r2 \
    account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4 \
    bucket=my-backups \
    access_key=1234567890abcdef1234567890abcdef \
    secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
```

不管哪种，它都落进一个小文件 —— 这就是存储源的全部配置，也是你密钥唯一存放的地方，权限 `600`：

```ini
# /etc/app-setup/params/store-r2.conf
account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
bucket=my-backups
prefix=backups
access_key=1234567890abcdef1234567890abcdef
secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
```

### 第 4 步 —— 验证（这一步大家爱跳过，然后后悔）

在表单里按 **✓ 测试连接**，或者：

```
root@box:~# app-setup test store-r2
```

它不是光登录一下。它建一个目录、写一个文件、列目录、读回来比对字节、再删掉 —— 五步，因为一个
权限配错的密钥能连上、能列目录，*然后*在第一次真备份时才挂，这一步就是在出事之前把它抓出来：

<FigScreen title="Cloudflare R2 · 测试" :lines="[
  [{ t: '✓', tone: 'ok' }, { t: '建目录', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '往里写文件', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '列目录', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '读回来比对', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '删掉', tone: 'mute' }],
  [{ t: '建、写、读、删全通过 —— s3://my-backups/backups', tone: 'ok' }],
]" />

哪一行标红了，先把它解决 —— 一般是令牌权限选错了、或者是只读。一个没通过全部五步的存储源，
下一步会拒绝用它，这是故意的。

### 第 5 步 —— 把备份打开

```
root@box:~# app-setup install backup-postgresql
```

它弹出任务表单。你只动三个地方：**主机**留空（那就是本机 socket —— 不用存密码），**数据库**留空
（全部），**目的地**设成 **r2**。保存。

<FigScreen title="PostgreSQL · 设置" :lines="[
  [{ t: '▸ 数据库', tone: 'accent' }],
  [{ t: '   主机', tone: 'mute' }, { f: '', note: '留空 = 本机 socket' }],
  [{ t: '   数据库', tone: 'mute' }, { f: '', note: '留空 = 全部' }],
  [{ t: '▸ 方式', tone: 'accent' }],
  [{ t: '   方式', tone: 'mute' }, { r: 'dump', on: true }, { r: 'binary' }, { r: 'files' }],
  [{ t: '▸ 存到哪', tone: 'accent' }],
  [{ t: '   目的地', tone: 'mute' }, { r: 'r2', on: true }],
  [{ t: '▸ 何时', tone: 'accent' }],
  [{ t: '   何时', tone: 'mute' }, { r: '每天', on: true }],
  { align: 'right', cols: [{ b: '保存并应用' }, { b: '保存' }, { b: '取消' }] },
]" />

到这儿，每晚一份 dump 就自己传 R2 了。搞定 —— 这一步剩下的是验证它。

### 第 6 步 —— 现在就证明它行

别等到今晚才发现它不行：

```
root@box:~# app-setup backup backup-postgresql
  ==> dumping every database, role and tablespace
  ==> packing backup-postgresql_20260822T140038Z.tgz  (4.0K)
  ==> uploading to r2:backups
  ok  uploaded

root@box:~# app-setup archives backup-postgresql
  backup-postgresql_20260822T140038Z.tgz   4.0K   just now   r2
```

就在桶里了。你已经有备份了。

### 第 7 步 —— 需要恢复那天

```
root@box:~# app-setup restore backup-postgresql
```

它从 R2 拉最新那份、打开、加载。一条命令，数据库就回到原样。

整个流程就这些。下面全是参考，想改什么再看。

---

## 背后只有一个概念：存储源，和备份任务

你配的是两张卡，不是一张，搞懂这个「为什么」就等于搞懂了全部。**存储源（store）**是*备份往哪送* ——
你刚建的 R2 桶，或者一台开了 SSH 的机器。**备份任务（job）**是*备什么、多久一次* —— 这个数据库、
每晚、留两周。一个存储源能装很多任务；一个任务指向一个存储源。

<FigRows :arrow="1" :head="['你配的', '回答的问题']" :rows="[
  [{ t: '存储源', tone: 'strong' }, { t: '备份往哪送？', tone: 'mute' }],
  [{ t: '备份任务', tone: 'strong' }, { t: '备什么、多久一次、留几份？', tone: 'mute' }],
]" />

先配存储源，因为一个没地方送的任务装不上。配完之后，存储源你就再也不用想了。

## 除了 R2 之外的存储源

R2 最省事，但下面这些都行 —— 挑你已经有地方放文件的那个：

| 存储源 | 当你已经有 |
|---|---|
| **store-r2** | 一个 Cloudflare R2 桶 —— 上面那个例子 |
| **store-s3** | AWS、MinIO、阿里云 OSS、腾讯云 COS、Backblaze —— 任何说 S3 的 |
| **store-scp** | 任何一台只有 `sshd`、别的都没有的机器 |
| **store-rsync** | 同上，但对面还有 `rsync`（断了能续，只传变化的部分） |
| **store-webdav** / **store-ftp** | 一个 Nextcloud 共享，或者一块 FTP 空间 |

它们的测试都是同样那五步，任务指向哪个都一样。`store-scp` 值得说一句：

```ini
# /etc/app-setup/params/store-scp.conf   —— 一台 SSH 机器，密钥认证，不用密码
target=backup@nas.local:/volume1/backups
port=22
```

它用一把自己生成的密钥登录 —— 按 **显示公钥**，把那一行加到对面机器的 `~/.ssh/authorized_keys` 里，
按测试。偷到容器的人拿这个也换不到一个 shell。

## 备份任务，细说

任务表单存下来是第二个小文件 —— 全在这里：

```ini
# /etc/app-setup/params/backup-postgresql.conf
host=                 # 留空 = 本机 socket（不存密码）
port=5432
user=postgres
password=
databases=            # 留空 = 每个库，连角色一起
method=dump           # dump | binary | files
store=r2              # 你配好的存储源
folder=
schedule=daily        # off | hourly | daily | weekly | monthly
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

三种**方式**，最省事又最好的先说：

<FigRows :rows="[
  [{ t: 'dump', tone: 'strong' }, { t: 'pg_dumpall —— 能读的文本。默认，也是该用的那个。', tone: 'mute' }],
  [{ t: 'binary', tone: 'strong' }, { t: 'pg_basebackup，走复制协议的物理副本。唯一一个能真正备份远程机器的。', tone: 'mute' }],
  [{ t: 'files', tone: 'strong' }, { t: '停库、拷数据目录、启库。只能备本机，一定有停机。', tone: 'mute' }],
]" />

**保留**这几个数字是一道梯子，不是一个数量：每个小时、天、周、月里各留最新的那一份，只要那个周期
还在额度内。默认 `0 / 7 / 4 / 6` —— 一周的每日、一月的每周、半年的每月，加起来也就几个文件。

## 四个动作，菜单里点或脚本里敲

打开任务，它的按钮就是你会用到的四件事：

<FigScreen title="PostgreSQL" :lines="[
  { pack: true, cols: [{ b: '▶ 立即备份' }, { b: '▤ 列出备份' }, { b: '✓ 校验' }, { b: '⟲ 恢复' }] },
  { pack: true, cols: [{ b: '参数设置' }, { b: '日志' }, { b: '使用说明' }] },
]" />

<FigRows :head="['命令', '做什么']" :rows="[
  [{ m: 'app-setup backup backup-postgresql' }, { t: '打包一份并上传', tone: 'mute' }],
  [{ m: 'app-setup archives backup-postgresql' }, { t: '列出都有哪些，本地和桶里', tone: 'mute' }],
  [{ m: 'app-setup verify backup-postgresql' }, { t: '打开最新那份，看它能不能加载', tone: 'mute' }],
  [{ m: 'app-setup restore backup-postgresql' }, { t: '把最新的一份放回去', tone: 'mute' }],
]" />

**恢复一份 `dump` 是一个按钮** —— 就是上面第 7 步。

**恢复一份物理（`binary`）备份，故意不做成一个按钮。** 把 `pg_basebackup` 放回去，得判断这是一次
恢复还是要做一个新备库、再把对应的信号文件写对 —— 这件事在 PostgreSQL 12 变过一次。猜错了，你会
得到一个能启动、却悄悄少了最近一小时数据的服务器。所以对物理档案，恢复会把它解到数据目录旁边、
把你这个版本该敲的步骤打出来，然后停下。用 `dump` —— 单库单机你根本碰不到这个。

还有一对不需要存储源的命令，用来留一份你自己拿着的快照：

```
root@box:~# app-setup dump postgresql    # 一个 .sql，写到 /data/app-setup/dumps/
root@box:~# app-setup load postgresql    # 把最新那份喂回去
```

## 怎么让数据库尽可能小

数据库出厂时，是按一台*唯一*任务就是当数据库的机器来配的。在容器里它跟别的东西挤内存，放着不管，
它一条查询没服务就先占掉几百兆。**app-setup 在安装时替你按容器实际的内存把它调小** —— 常见情况
你什么都不用做。这一节是给你想再小一点的时候看的。

`postgresql` 脚本在安装时问一个问题 —— 这机器有多少内存 —— 按答案挑一个档位：

<FigRows :head="['你这份容器', '档位', '会怎样']" :rows="[
  [{ t: '不到 512M' }, { t: 'tiny', tone: 'strong' }, { t: '每个默认值都不对，狠狠砍', tone: 'mute' }],
  [{ t: '512M – 1G' }, { t: 'small', tone: 'strong' }, { t: '把最离谱的几个削掉', tone: 'mute' }],
  [{ t: '1G 及以上' }, { t: 'normal', tone: 'strong' }, { t: '不动 —— 到这份上默认值就对了', tone: 'mute' }],
]" />

到 1G 以下，它往集群自己的 `postgresql.conf` 追加一段，大小按这台机器算，而且会告诉你它写了。
挑大梁的是 `shared_buffers`（启动时一次性预留）和 `work_mem`（*按每次排序、每个连接*收费 ——
真正的上限是它乘以同时在排的排序数，所以才一直压得很小）：

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
jit = off                 # 用 LLVM 编译查询计划，是单次最大的一笔内存
```

实测差别不小：一个原样的 PostgreSQL 一条查询没服务就占掉 100M 以上常驻内存；按 512M 调过的，
只占其中一小块。

**想比你的内存暗示的还要小** —— 一台 1G 的机器上数据库只是个配角 —— 安装时指定档位：

```
root@box:~# APP_SETUP_PROFILE=tiny app-setup install postgresql
```

`tiny` 不管实际内存多少，都写最狠的那一档。那段配置头上写着是谁写的；删掉它再重启服务就回到
PostgreSQL 自己的默认值。给机器加内存后再装一次，它会重写来匹配 —— 到 1G 以上直接删掉。

调优还不够的话，还有两个旋钮：

<FigRows :rows="[
  [{ t: '减少连接数', tone: 'strong' }, { t: '每个 PostgreSQL 连接都是一个进程。max_connections 是个内存设置，不只是个上限。', tone: 'mute' }],
  [{ t: '把数据挪到 /data', tone: 'strong' }, { t: '不是内存，是磁盘 —— 而且是重装后还在的那块。脚本会主动帮你挪。', tone: 'mute' }],
]" />

## 每个配置文件，完整版

两个文件，都在一个路径下 —— `/etc/app-setup` —— 都是能读能改的纯文本。`params/` 是表单存下来的；
`secrets/` 是生成的密码，`0700`，每个文件 `0600`。

```ini
# /etc/app-setup/params/store-r2.conf          —— 一个 Cloudflare R2 目的地
account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
bucket=my-backups
prefix=backups
access_key=1234567890abcdef1234567890abcdef
secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
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

改一个，下次跑就生效。这里没有藏起来的状态 —— 一个躺在 `600` 权限文件里的密码，是你能想明白的东西。

## 这到底简不简单？

对常见情况 —— 单库、单机、每晚 dump 到一个桶 —— 简单：就是上面那七步，大半是一条命令，走完它就
自己跑了。你要记住的只有一个概念，**存储源和任务**，就这一个。

它故意*不*做成一个按钮的地方，都是「按错了会悄悄丢数据」的地方：一个没通过五步测试的存储源不会被
任务接受，一个物理备份不会靠猜来恢复自己。这两个「拒绝」，都是功能在正常工作。

最短的一条路，全在这：

```
root@box:~# app-setup install store-r2          # 填桶，按测试
root@box:~# app-setup install backup-postgresql # 选库，按保存
root@box:~# app-setup backup backup-postgresql  # 现在先备一次，稳妥
root@box:~# app-setup restore backup-postgresql # 需要那天
```

## 把老数据库迁进来

如果你已经有数据在别处 —— 另一个容器里的 PostgreSQL、一台老机器上的、或者一个云托管数据库 ——
把它搬到 app-setup 现在管的这个库里，就是**一次性的先导出、再导入**，用的还是那两个工具。搬一次
就好；搬完之后，上面配好的备份任务就顺带保护它了。

让这件事不痛的那条规律：**逻辑导出**（`pg_dump` / `pg_dumpall`）在一个版本上导出、能在另一个版本上
导入。从 PostgreSQL 17 导出的，直接能进 app-setup 装的 18 —— 实测过，这也正是为什么要这样迁，而不是
去拷数据文件。

### 常见情况：老库是本机上的另一个容器

只搬你应用那一个数据库。这样只带走表和数据、**别的都不带** —— 角色、密码都不跟过来，这正是你要的：
老容器有它自己那套凭证，你正好把它留在原地：

```
# 1. 只从老容器导出你那个库。--no-owner --no-privileges 把老的属主和授权去掉，
#    所以不会有老账号跟过来。（只读：老库里什么都不动。）
root@box:~# podman exec 老容器 \
    pg_dump -U 老用户 -d 老库名 --no-owner --no-privileges > /root/olddata.sql

# 2. 在 app-setup 管的那个库里，建一个同名的空库。
root@box:~# podman exec 新容器 su postgres -c "createdb 老库名"

# 3. 把数据导进去。
root@box:~# podman cp /root/olddata.sql 新容器:/tmp/olddata.sql
root@box:~# podman exec 新容器 su postgres -c "psql -d 老库名 -f /tmp/olddata.sql"

# 4. 看它到没到。
root@box:~# podman exec 新容器 su postgres -c "psql -d 老库名 -c '\dt'"
```

`\dt` 应该列出你的表。把应用指向新库，再跑一次 `app-setup backup backup-postgresql` —— 你刚搬进来的
数据现在在桶里也有一份了。

### 老库是另一台机器，或者一个云托管数据库

同样三步，只有导出那条变一下，用你手上老库的凭证走网络连过去：

```
root@box:~# pg_dump -h 老主机 -p 5432 -U 老用户 -d 老库名 \
              --no-owner --no-privileges > /root/olddata.sql
```

然后照上面一样 `createdb` 再 `psql -f` 进 app-setup 的库。（老主机要 SSL 的话，把你应用在用的那个
`?sslmode=…` 加上。）

### 如果你想把整个集群一起搬

角色加每个库一次全搬 —— 用 `pg_dumpall`，但要注意它会把老角色的**密码哈希**一起带过来，所以只有
你确实想把那些账号也搬过去时才这么做：

```
root@box:~# podman exec 老容器 pg_dumpall -U 老用户 > /root/old-all.sql
root@box:~# podman exec -i 新容器 su postgres -c psql < /root/old-all.sql
```

## 另见

- [快速上手](/zh/quick-start) —— 一开始怎么把 PostgreSQL 装上。
- [使用你的容器](/using-your-container)（英文）—— `/data` 是什么，数据库为什么该放上面。
- `app-setup docs backup-postgresql` —— 脚本在机器上自己讲自己。
