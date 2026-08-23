# 备份文件

数据库有专门的脚本管它。你自己写的那个程序没有 —— 那些不用数据库、把东西全放在文件里的程序也没有。
一个跑在 `/opt/thing`、配置在 `/etc/thing`、上传的文件在 `/var/lib/thing` 的程序，这三个目录这里
没有任何别的东西会去保存。管这件事的就是这个 recipe：**`files`** —— 你把目录列出来，它就用和所有
数据库备份一样的方式、传到一样的地方、按一样的定时，把它们备走。

这一页就讲这个 recipe，从头到尾，配一个真实例子：一个跑 [`code`](https://github.com/yinyue123/code)
的 hqnode 容器 —— 它把会话、设置、每台设备的密码全存成 **`/data` 下的文件，一个数据库都没有** ——
通过 SSH 备到另一台机器上，再放回来。用到两个 recipe：`store-rsync`（备份存到哪）和 `files`
（备份什么、多久一次）。

> 这里的存储源、五步测试、四个动作按钮，和[备份 PostgreSQL](/zh/backup-postgresql) 完全一样，
> 只有*备什么*不同。那一页你要是看过了，这里大半都眼熟；可以直接跳到
> [到底多大：每次全量，还是增量](#到底多大-每次全量-还是增量) 和
> [两种数据，一个任务](#两种数据-一个任务) —— 全量还是增量、以及一台机器上同时有几 KB 的配置和
> 40 GB 的图片该怎么办，这两件事是文件备份有、而数据库 dump 没有的。

---

## 完整例子：容器的 `/data` → 另一台机器

### 第 0 步 —— 你有一批值得留住的文件

`code` 容器把所有东西都放在 `/data` 下，而且就这么两样，没别的：

<FigRows :head="['/data 下面', '是什么']" :rows="[
  [{ t: '/data/code.yaml', tone: 'strong' }, { t: '配置文件', tone: 'mute' }],
  [{ t: '/data/store', tone: 'strong' }, { t: '文件库 —— 会话、设置、每台设备的密码', tone: 'mute' }],
]" />

没有 `pg_dump` 要跑，也没有数据库大小要算，因为根本没有数据库：这个容器的备份就是**把那些文件拷一份**，
恢复就是把它们放回去。`files` 干的正是这件事。

### 第 1 步 —— 找个地方放

备份得放在这个容器之外的地方。Cloudflare R2 可以（[PostgreSQL 那一页](/zh/backup-postgresql)
从头讲了一遍，任务指到桶上的方式是一样的），但文件备份更常见的去处是**你手上已经有的一台机器** ——
一台 NAS、一台 VPS、另一台开着 `sshd` 的机器。这个例子用的就是后者，对应两张卡：

<FigRows :head="['卡片', '什么时候用']" :rows="[
  [{ t: 'store-rsync', tone: 'strong' }, { t: '对端有 rsync —— 传到 90% 断了能续，一个文件只发变了的那部分', tone: 'mute' }],
  [{ t: 'store-scp', tone: 'strong' }, { t: '对端只有 sshd —— 除了 OpenSSH，对端什么都不用装', tone: 'mute' }],
]" />

两个都用**密钥**登录，不用密码。任何地方都不存密码；唯一一次用到密码，是把公钥放到对端去的那一次。

### 第 2 步 —— 填目的地，让它自己生成密钥

```
root@box:~# app-setup install store-rsync
```

打开设置，把对端填进 **Target**，写成 `user@host:/path` —— 那个路径是备份存放的根目录：

<FigScreen title="rsync over SSH · 设置" :lines="[
  [{ t: 'Target', tone: 'mute' }, { f: 'root@192.0.2.10:/tmp', fw: 230 }],
  [{ t: 'SSH 端口', tone: 'mute' }, { f: '22', fw: 80 }],
  { align: 'right', cols: [{ b: '显示公钥' }, { b: '✓ 测试连接' }] },
]" />

第一次安装时它会生成一把专门给备份用的 SSH 密钥，放在
`/etc/app-setup/secrets/backup_ed25519` —— 权限 `600`，没有 passphrase，因为它是凌晨四点由 cron
跑的，没人在旁边输密码。**这台机器上所有 SSH 存储源共用这一把钥匙**，所以不管你要备到几个对端，
这一步只做一次。

### 第 3 步 —— 把公钥放到对端

按**显示公钥**（在命令行里就是 `/etc/app-setup/secrets/backup_ed25519.pub` 这个文件），把那一行
加到 Target 里那个用户的 `~/.ssh/authorized_keys` 里。如果你本来就能用密码登录对端：

```
# 在对端上跑，或者在任何能用密码连上它的地方跑
ssh-copy-id -i /etc/app-setup/secrets/backup_ed25519.pub -p 22 root@192.0.2.10
```

或者在对端手动来：

```
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA…app-setup backup on <host>' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

> 这里最容易踩的坑是把目录也设成 `600` —— 没有执行位，sshd 就进不去这个目录、读不到里面的
> `authorized_keys`，密钥认证直接失败，而且客户端的输出里一个字都不会告诉你为什么。
> 记住：`~/.ssh` 是 `700`，里面那个文件是 `600`。

顺手还值得做一件事：限制这把钥匙能干什么，这样即使容器被人拿走，也不能拿它去开一个 shell。

```
# rsync 存储源 —— 限制成只能往一个目录里写：
command="rrsync /tmp",restrict ssh-ed25519 AAAA…
# scp 存储源 —— 没有 rrsync，但除了传文件之外的能力照样全拿掉：
restrict ssh-ed25519 AAAA…
```

### 第 4 步 —— 验证（这一步大家爱跳过，然后后悔）

按 **✓ 测试连接**，或者：

```
root@box:~# app-setup test store-rsync
```

它不是光登录一下。它建一个目录、往里写一个文件、列目录、读回来比对字节、再删掉 —— 五步，因为
「能写文件但在给它的那个目录下建不了目录」的账号配置很常见，而且看上去一切正常，直到第一次真备份
在它的第一个 `mkdir` 上挂掉：

<FigScreen title="rsync over SSH · 测试" :lines="[
  [{ t: '✓', tone: 'ok' }, { t: '建目录', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '往里写文件', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '列目录', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '读回来比对', tone: 'mute' }],
  [{ t: '✓', tone: 'ok' }, { t: '删掉', tone: 'mute' }],
  [{ t: '建目录、写、读、删 全过了 —— root@192.0.2.10:/tmp', tone: 'ok' }],
]" />

第一次测试还会**把对端的 host key 钉住**，并把指纹打出来；之后每次连接都要求它对得上，host key
变了会明着报错，而不是悄悄信任。没过完这五步的存储源，下一步会拒绝使用 —— 这是故意的。

### 第 5 步 —— 说清备份什么，然后打开它

```
root@box:~# app-setup install files
```

三个框干了全部的活 —— **备份哪些**（目录，逗号分隔）、**目的地**（刚配好的存储源）、和**定时**：

<FigScreen title="文件和目录 · 设置" :lines="[
  [{ t: '▸ 备份哪些', tone: 'accent' }],
  [{ t: '   路径', tone: 'mute' }, { f: '/data/code.yaml, /data/store', fw: 260 }],
  [{ t: '   跳过', tone: 'mute' }, { f: '*.log, *.tmp, node_modules, .git', fw: 260 }],
  [{ t: '   先停掉', tone: 'mute' }, { f: '', note: '拷贝期间要停的服务 —— 可选' }],
  [{ t: '▸ 存到哪', tone: 'accent' }],
  [{ t: '   目的地', tone: 'mute' }, { r: 'rsync', on: true }],
  [{ t: '▸ 定时', tone: 'accent' }],
  [{ t: '   定时', tone: 'mute' }, { r: '关', on: true }, { r: '每天' }],
  { align: 'right', cols: [{ b: '保存并应用' }, { b: '保存' }, { b: '取消' }] },
]" />

同样的事，在命令行里：

```
root@box:~# app-setup set files paths=/data/code.yaml,/data/store store=rsync
root@box:~# app-setup install files
  ==> measuring
  ok  2 paths, 8.0K
  ok  ready — press ▶ Back up now to take one
```

**定时**设成 `daily`，每天夜里它就自己往对端拷一份。留在 `off`，就没有定时任务，但
**▶ 立即备份**照样能按 —— 下一步就是它。

### 第 6 步 —— 现在就验一次

```
root@box:~# app-setup backup files
  ==> backing up files
  ==> copying /data/code.yaml
  ==> copying /data/store
  ==> packing files_20260822172333.tgz
  ok  /data/app-setup/backups/files/files_20260822172333.tgz  (2.0K)
  ==> uploading files_20260822172333.tgz to rsync:dmit/files
  ok  uploaded

root@box:~# app-setup archives files
  on this machine   /data/app-setup/backups/files/
    files_20260822172333.tgz   2.0K   just now   rsync
  on rsync          dmit/files/
    files_20260822172333.tgz          just now
```

就是它 —— 本机一份，对端 `<主机名>/files/` 下面一份。路径里那个主机名，是两个容器共用一个目的地时
不会互相把对方的历史剪掉的原因。

### 第 7 步 —— 需要它回来的那天

```
root@box:~# app-setup restore files
  ==> fetching files_20260822172333.tgz from rsync:dmit/files
      restoring from files_20260822172333.tgz

  This puts back, overwriting what is there now:
      /data
      /data/store
      /data/store/projects

  ==> putting the saved files back
  ok  restored
```

它从对端拉最新那个归档下来，解开，把文件拷回它们原来的位置。一条命令，容器的数据就回到原样。

> **恢复是就地覆盖。** 一个网站有一个文档根目录，可以先挪走、再放回来；这里是散落在文件系统各处的
> 一堆路径，没有那么一个目录可以挪。那些路径上现在的东西是被**覆盖**，不是被挪开 —— 所以如果它重要，
> 先自己拷一份。这是 `files` 和数据库恢复唯一不同的地方，也是面板里只有 **⟲ 恢复** 这一个按钮要你
> 确认的原因。注意这里不对称：**按钮**会问，**命令**不会。在命令行上跑 `app-setup restore files`，
> 它把将要覆盖的路径列出来，然后就直接做了 —— 没有一个提示等你回答，所以那份清单要在按回车*之前*看，
> 不是之后。

到这就全了。下面都是参考，等你想改点什么的时候再看。

---

## 背后就一个想法：一个存储源，一个任务

你配的是两张卡，不是一张，而且这个想法和这台机器上所有备份都是同一个。**存储源**回答*备份存到哪* ——
刚配好的那台 SSH 机器，或者一个 R2 桶。**任务**回答*备份什么、多久一次* —— 这几个目录，每晚，
留两周。一个存储源可以装很多任务；一个任务指向一个存储源。

<FigRows :arrow="1" :head="['你要配的', '它回答的问题']" :rows="[
  [{ t: '存储源', tone: 'strong' }, { t: '备份存到哪？', tone: 'mute' }],
  [{ t: '任务', tone: 'strong' }, { t: '备哪些路径、多久一次、留几份？', tone: 'mute' }],
]" />

存储源要先配，因为一个「输出没地方去」的任务是装不上的。配完之后你就再也不用想它了。

## rsync 之外的存储源

下面这些都能装 `files` 的备份，任务指过去的方式完全一样 —— 你手上现成有哪个能放文件的地方就用哪个：

| 存储源 | 什么时候用 |
|---|---|
| **store-rsync** | 有一台装了 `rsync` 的机器 —— 能续传，一个文件只发变了的那部分 |
| **store-scp** | 有一台只有 `sshd` 的机器 —— 见下面那段说明 |
| **store-s3** / **store-r2** | 任何 S3 兼容的桶 —— AWS、MinIO、阿里云 OSS、腾讯云 COS、Backblaze、Cloudflare R2 |
| **store-webdav** / **store-ftp** | 一个 Nextcloud 共享，或者一块 FTP 空间 |

**关于 scp 存储源的一段，是踩出来的。** 现在的 OpenSSH `scp`（9 以上）走的是 SFTP 协议，所以 scp
存储源要求对端有一个能用的 `sftp-server` —— 任何正常的 `openssh-server` 都自带并且默认开着，所以在
一台普通机器上它直接就能用。用*不了*的情况，是对端的 SSH **不是**普通的 OpenSSH。hqnode 主机正好就是
这一种：它对外的 22 端口是 hqnode 网关在应答（`SSH-2.0-hqnode`），网关能转发 shell 和 `rsync`，但不提供
SFTP 子系统 —— 所以 scp 存储源在这里会报一个莫名其妙的 `sftp-server: No such file or directory`，而
rsync 存储源连同一个端口却好好的。解决办法是把 scp 存储源指到对端**真正的 OpenSSH 端口**上（hqnode
机器自己的 `sshd` 一般在一个高位端口，比如 36000），而不是 22 上的网关。拿不准就用 rsync 存储源：
它不需要 SFTP 子系统，而且能续传。

## `files` 任务的细节

任务的表单存成一个小文件 —— 这就是它的全部，值也就是上面例子里那些：

```ini
# /etc/app-setup/params/files.conf
paths=/data/code.yaml,/data/store    # 逗号分隔；可以用通配符
exclude=*.log, *.tmp, node_modules, .git
service=                             # 留空 = 拷贝期间不停任何东西
store=rsync                          # 你配好的存储源
folder=                              # 留空 = 对端上的 <主机名>/files
prune_remote=off                     # 是否也删对端的旧归档
schedule=off                         # off | hourly | daily | weekly | monthly
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

其中几个值得单独说一句：

| 字段 | 干什么 |
|---|---|
| **路径** | 逗号分隔，通配符会展开 —— `/var/www/*/uploads` 是可以的。列了但这台机器上没有的路径，它会明着警告，不会悄悄跳过：一个打错的路径，和一个正常工作的备份，在出事那天之前是分辨不出来的。 |
| **跳过** | 是在拷贝的时候就排掉，不是拷完再删 —— 一个 `node_modules` 先被拷进来再被剪掉，磁盘和时间已经花掉了。规则是相对路径：`data/store/uploads` 能匹配上，`/data/store/uploads` 什么都匹配不上。 |
| **先停掉** | 拷贝期间要停的服务。一个普通目录没有「一致性快照」这回事，所以如果有东西正在不停地往里写，把服务名填在这。大多数配置目录凌晨四点没人写，所以这一栏通常是空的。 |

**保留**那几个数字是一把梯子，不是一个份数：每小时、每天、每周、每月各留最新的那一份，只要那个时间段
还在它的预算之内。几档是重叠的 —— 昨晚那份既是最新的「每日」，也是最新的「每周」和「每月」——
所以最后留下的份数比四个数字加起来要少。拿一年的每晚备份去喂它，默认的 `0 / 7 / 4 / 6`
最后稳定在 **15 份，最老的一份大约在五个月前**；`0 / 7 / 4 / 12` 稳定在 21 份，往回够到大约十一个月。
`keep_monthly` 要理解成*从最新那份归档往回数的自然月数*，想要更长的历史就调它。

### 两个已经替你防掉的错

| 已经替你防掉的 | 怎么防的 |
|---|---|
| **备份 `/data` 不会把自己吞进去** | `app-setup` 自己的归档写在 `/data/app-setup` 下面，这个目录永远被排除 —— 否则备份 `/data` 会把之前每一个归档都打进新的那个里，每一份都比上一份大，直到磁盘满。 |
| **`/`、`/proc`、`/sys`、`/dev`、`/run` 直接拒绝** | 它们不是该放进备份里的东西。 |

## 四个动作，菜单里按或者脚本里跑

<FigRows :head="['命令', '干什么']" :rows="[
  [{ m: 'app-setup backup files' }, { t: '打包这些路径并上传', tone: 'mute' }],
  [{ m: 'app-setup archives files' }, { t: '列出有哪些备份，本机和对端都列', tone: 'mute' }],
  [{ m: 'app-setup verify files' }, { t: '把最新那份解开看看 —— 什么都不写回去', tone: 'mute' }],
  [{ m: 'app-setup restore files' }, { t: '把最新那份放回去（就地覆盖）', tone: 'mute' }],
]" />

第一次备份之后，`verify` 值得跑一次：它把最新那个归档拉下来，解到一个临时目录里，数一下文件个数，
再把临时那份扔掉 —— 「这个归档打得开，里面有 5 个保存的文件，什么都没有写回去」。一个你从来没打开过的
备份，是一个念想，不是一个备份。

## 到底多大：每次全量，还是增量？

**每一次 `files` 备份都是全量。** 它把那些路径打成一个新的、带日期的 `.tgz` 整个传上去 —— 没有跟
昨晚做差分。rsync 存储源那句「只发变了的部分」说的是*同一个文件*的续传；而这里每晚都是一个**新**的
tar 包、新的名字，rsync 看到的是一个全新的文件，于是整个都发。所以老实说是这样：

| 如果总量是 | 那每晚一次全量备份 |
|---|---|
| **小** —— 配置文件，几 MB | **完全正确，就这么干。** 保留梯子留下的是几个很小的文件，你根本不用想它。 |
| **大** —— 几十 GB 的上传文件 | 浪费：整棵目录树每次都要存一遍、发一遍，再乘上梯子留的份数。 |

小的那种情况 —— 大多数容器都是，上面 `code` 那个例子更是只有 8KB —— 看到这就可以停了；全量就是那个
简单又正确的答案。

真的很大的那种，三条出路，从最省事的开始：

**1. 少备一点。** 大多数很大的目录之所以大，是因为里面装的东西根本不需要备 —— 缓存、日志、
`node_modules`、缩略图，或者本来就已经在 S3 桶里的上传文件。把它们**跳过**。不做的那次备份，是最便宜的。

**2. 少留几份。** 把保留梯子降成 `keep_daily=2, keep_weekly=0, keep_monthly=0`，你手上就是两份全量，
而不是十五份。很多时候这就是全部的修法。

**3. 真正的增量镜像，用 rsync `--link-dest`。** 当你确实需要在一棵很大的树上留很多个恢复点时，
打包成全量 tar 的那个任务就是错的工具 —— 越过它，直接用 rsync。`--link-dest` 让每一晚在对端都是一个
**完整**的快照，但任何自昨晚起没变过的文件都是指向昨晚那份的硬链接，所以不多占一个字节。一棵 40 GB、
每天变 200 MB 的树，三十份每日快照占大约 46 GB，而不是 1.2 TB：

```sh
#!/bin/sh
# /usr/local/bin/snapshot —— 带日期的快照，没变的文件互相共用。
set -eu
SRC=/data/store/uploads/       # 末尾的斜杠：拷内容，不拷目录本身
SSH=$(app-setup sshcmd store-rsync)          # 这个存储源自己那条 ssh 命令
DEST=$(app-setup remote store-rsync snapshots)   # user@host:/base/snapshots
HOST=${DEST%%:*}; DIR=${DEST#*:}
today=$(date -u +%Y%m%d)
$SSH "$HOST" "mkdir -p '$DIR'"
rsync -a --delete -e "$SSH" \
  --link-dest="$DIR/latest" \
  --exclude='*.log' \
  "$SRC" "$HOST:$DIR/$today/"
$SSH "$HOST" "ln -sfn '$DIR/$today' '$DIR/latest'"
```

开头那两行是全部的窍门，也是这个脚本能这么短的原因：

| 命令 | 打印出 |
|---|---|
| `app-setup sshcmd store-rsync` | 这个存储源真正在用的那条 `ssh …` —— 它的密钥、**它的端口**、以及指向 `test` 钉住的那份 host key 的 `UserKnownHostsFile` |
| `app-setup remote store-rsync <目录>` | 那个目录在存储源 target 下解析出来的 `user@host:/路径` |

> **千万别自己手抄那些参数。** 自己写 `ssh -i /etc/app-setup/secrets/backup_ed25519
> -o StrictHostKeyChecking=yes` 看着没问题，实际会以 `No ED25519 host key is known …
> Host key verification failed` 失败 —— 因为 `app-setup test` 把对端的 host key 钉在了
> **存储源自己的** known_hosts 里，不是 root 的 `~/.ssh/known_hosts`。存储源如果用的是非标准端口，
> 还会再错一次：手抄的命令会默默去连 22。`sshcmd` 存在的意义，就是让脚本这两样都错不了。
>
> `mkdir -p` 也不是可有可无：`rsync` 只会创建目标路径的*最后一层*，所以对端只有基础目录时往
> `…/snapshots/20260823/` 发，会以 `mkdir "…" failed: No such file or directory` 挂掉。
>
> 另外，**只有第一次**跑的时候它会打一句 `--link-dest arg does not exist: …/latest`。这是正常的，
> 没关系 —— 还没有上一份快照可以做硬链接，所以第一晚本来就是一份完整拷贝。它退出码是 0，
> 这句话之后不会再出现。

拿 cron 指着它跑（`app-setup install cron`，或者往 `/etc/crontabs/root` 里加一行），之后每一个
`$BASE/<日期>/` 都是一棵完整的目录树，你可以直接翻、直接用一条反方向的 `rsync` 或 `scp` 拷回来。
这是故意放在存储源和任务这套模型*之外*的 —— 它不像 `app-setup backup` 那样帮你打包、标日期、剪旧的、
校验，放回来也是你自己的 `rsync`，不是一个按钮。这就是那笔交易：`--link-dest` 在大树上省了空间，
代价是丢掉了 `files` 任务在小树上白送给你的那套打包。

> 一句话的准则：**先一直用 `files`，直到每晚一个全量 tar 包真的开始疼** —— 它占的磁盘、它花的带宽，
> 都是你看得见的数字，`app-setup archives files` 会把大小告诉你。到那时候，`--link-dest` 镜像多出来的
> 那些零件才值。

而且大多数时候，答案并不是二选一，因为一台机器上这两种东西是同时存在的。下一节讲的就是这个。

## 两种数据，一个任务

大多数机器上两样都有：几 MB 的配置文件，你想留很长的历史；还有几十 GB 的上传文件或图片，你只想要
*一*份拷贝。这两个诉求是相反的，而第一件要知道的事是：你没法给它们各配一套设置 ——
**一台机器只有一个 `files` 任务。** 它的设置就是一个文件，`/etc/app-setup/params/files.conf`：
一份路径列表、一个定时、一把保留梯子。你在那里选的东西，对里面列的所有路径一视同仁。

所以分法不是两个任务，而是：**小而金贵的东西放进 `files` 任务；大而可以再来一份的东西留在任务外面，
单独做镜像。**

<FigRows :head="['', '配置 —— 几 MB', '图片、上传 —— 几十 GB']" :rows="[
  [{ t: '谁来备', tone: 'mute' }, { t: 'files 任务', tone: 'strong' }, { t: '直接用 rsync', tone: 'strong' }],
  [{ t: '在 files.conf 里', tone: 'mute' }, { t: '写在 paths 里', tone: 'mute' }, { t: '写在 exclude 里', tone: 'mute' }],
  [{ t: '每次跑发多少', tone: 'mute' }, { t: '整棵树打包发走 —— 反正很小', tone: 'mute' }, { t: '只发变过的部分', tone: 'mute' }],
  [{ t: '历史', tone: 'mute' }, { t: '几个月，十七个恢复点', tone: 'ok' }, { t: '一份当前拷贝，或者带日期的快照', tone: 'mute' }],
  [{ t: '怎么放回来', tone: 'mute' }, { t: 'app-setup restore files', tone: 'mute' }, { t: '反方向再 rsync 一次', tone: 'mute' }],
]" />

### 小的那一半：配置，留几个月

这正是 `files` 任务擅长的事，而且默认值已经在这么干了。拿一年的每晚备份去喂它，默认的
`0 / 7 / 4 / 6` 最后稳定在 15 份归档，最老的一份大约在五个月前 —— 对几 KB 的配置来说，这点代价
根本不值一提。想要接近一年？只改一个数字，`keep_monthly=12`，它会稳定在 21 份，往回够到大约十一个月：

```ini
# /etc/app-setup/params/files.conf —— 配置文件，留一年历史
paths=/etc/myapp, /data/code.yaml
exclude=*.log, *.tmp
schedule=daily
keep_daily=7          # 最近一周，每天都留
keep_weekly=4         # 再往前一个月，每周留一份
keep_monthly=12       # 再往前约一年，每月留一份
prune_remote=off      # 对端每一份都留着，永远
```

在把几个月的历史交给这把梯子之前，有两件事值得知道：

| 要知道的 | 为什么重要 |
|---|---|
| **它是从最新那份归档往回数，不是按当前时间数** | 一台关了六周的机器开回来，整个「每天」那一档还在 —— 这里的保留说的是留多少历史，不是文件最多能有多老。机器停过、而你最需要历史的那天，你要的正是这个行为。 |
| **`prune_remote=off` 意思是对端根本不剪** | 而这是默认值。上面那把梯子剪的是*这台*机器上的磁盘；传上去过的每一份归档都还在对端留着。对一晚几 KB 来说这是好事 —— 历史不要钱，你全都留着，远远超过本地梯子那五个月。只有当你担心的是对端的磁盘时，才需要把它打开。 |
| **把 `prune_remote=on` 打开，积压是慢慢清的，这是故意的** | 它一次最多删「一梯子」那么多 —— 就是四个 `keep_` 加起来，默认十七 —— 然后打印 `stopped after 17 deletions` 就停手。对端积了三百份旧归档的话，要好多个晚上才降下来。这正是那道保险在起作用：一个填错的目录只会删掉十七个你还能找回来的文件，而不是全部。 |

所以配置这一半，老实的答案是：别动它。每天一次、默认梯子、`prune_remote` 关着 ——
这本身就已经是*「往回好几个月的全量备份」*了，而且归档小到没有任何需要辩解的地方。

### 大的那一半：图片和上传，做成一个镜像

那些丢了也不至于哭的大文件 —— 用户上传、照片、生成的缩略图、别人还能再给你一份的素材 —— 要的是
反过来的待遇：不要带日期的 tar 包，不要十七份拷贝，只要有一份东西不在这台机器上就行。两步。

**第一步，把它们从任务里拿出来。** `paths` 里的东西每晚都会被整个打包，所以一个不该进 tar 包的目录
必须被排掉 —— 要么不列它的上级目录，要么在**跳过**里点它的名。

> **「跳过」的坑：不能带开头的斜杠。** 拷贝是从 `/` 出发、用相对路径名跑的，所以一个以 `/` 开头的
> 模式什么都匹配不上 —— 而且它是**不声不响**地失败：你以为排掉了的那个目录照样在归档里，唯一的症状
> 就是备份莫名其妙地大。把路径开头的斜杠去掉，或者干脆只写目录名。
>
> ```ini
> exclude=data/store/uploads, *.log     # 对 —— 这样能匹配上
> exclude=uploads                       # 也对 —— 按目录名匹配
> exclude=/data/store/uploads           # 错 —— 什么都排不掉
> ```
>
> 拿同一棵 200 张图的树实测，只改这一行：带斜杠那版打出来的归档是 **20,412,339 字节**，200 张图
> 一张不少地在里面；去掉斜杠，**338 字节**，一张都没有。

**第二步，直接用 rsync 给它们做镜像**，然后挑一下这棵大树到底需要多少历史 —— 这是唯一一个真正的决定：

| 你想要回什么 | 用 |
|---|---|
| 文件**现在**的样子 | **一个普通镜像** —— 对端一份拷贝，永远是最新的。40 GB 永远是 40 GB。 |
| 文件在**过去某一天**的样子 | **rsync `--link-dest`** —— 带日期的快照，没变的文件互相共用。40 GB 加每天 200 MB，三十份大约 46 GB。小规模实测：一棵 19.5 MB 的树做三份快照，看上去是 58.3 MB 的文件，实际只占 19.7 MB 磁盘。 |

「也不咋重要」的那种，普通镜像就是全部答案，而且只有一行 —— 用的还是 `app-setup` 已经生成好的那把
钥匙，所以没有任何新东西要配：

```sh
#!/bin/sh
# /usr/local/bin/mirror-uploads —— 一份当前拷贝，不留历史。
set -eu
SRC=/data/store/uploads/       # 末尾的斜杠：拷内容，不拷目录本身
SSH=$(app-setup sshcmd store-rsync)
DEST=$(app-setup remote store-rsync uploads)
$SSH "${DEST%%:*}" "mkdir -p '${DEST#*:}'"
rsync -a --delete -e "$SSH" "$SRC" "$DEST/"
```

干活的还是上面快照脚本里那两条命令，理由也一样：密钥路径、端口、host key 参数、IP 地址，
一个都不用手写死，所以存储源的设置一改，这里不会跟着过期。

第一次跑完之后 —— 那一次会把整棵树发一遍 —— 之后每晚只发变过的那些文件，因为这一次 rsync 比的是
两端*同样的路径*，而不是一个新名字的新 tar 包。在容器里拿一棵 200 个文件、19.5 MB 的树实测：第一次跑发
19.5 MB，改了一个 100 KB 的文件之后再跑，只发 **106 KB**。这就是它和 `files` 任务的区别，也是要用它
的全部理由。

> **`--delete` 是双刃的。** 这边删掉一个文件，下一次跑那边也就没了 —— 正是这一点让它成为镜像，
> 也正是这一点让它一直停在 40 GB。它防的是磁盘挂掉，不是你一周后才发现的一次误 `rm`。如果后面这件事
> 也重要，那就正是上面
> [`--link-dest` 快照](#到底多大-每次全量-还是增量)的用武之地，或者把 `--delete` 去掉，自己手动清理。

跟别的东西挂在同一个定时上就行（`app-setup install cron`，或者往 `/etc/crontabs/root` 里加一行），
恢复就是把这条命令的两端换个位置。

## 全部的配置文件

两个小文件，都是 `/etc/app-setup` 下的纯文本，都能读能改。改完下一次跑就生效。

```ini
# /etc/app-setup/params/store-rsync.conf   —— 备份存到哪
target=root@192.0.2.10:/tmp
port=22
```

```ini
# /etc/app-setup/params/store-scp.conf     —— 一个真正的 OpenSSH 对端（hqnode
target=root@192.0.2.10:/tmp                 # 主机上不要用 :22，见上面 scp 那段）
port=36000
```

```ini
# /etc/app-setup/params/files.conf         —— 任务本身
paths=/data/code.yaml,/data/store
exclude=*.log, *.tmp, node_modules, .git
service=
store=rsync
folder=
prune_remote=off
schedule=daily
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=6
```

钥匙在 `/etc/app-setup/secrets/backup_ed25519`（权限 `600`），所有 SSH 存储源共用。这里没有任何密码 ——
钥匙就是凭证的全部，而且只要你从对端的 `authorized_keys` 里删掉那一行，把容器拿走的人就什么都拿不到。

## 这真的算简单吗？

对常见的那种情况 —— 一个把数据存成文件的容器，每晚拷到一台你自己的机器上 —— 算：就是上面那七步，
其中大部分只是一条命令，走完之后它自己跑。要记住的想法只有**存储源和任务**这一个，而它就是一个想法。

最短的一条路，全在这：

```
root@box:~# app-setup install store-rsync        # 填目的地，按测试
root@box:~# app-setup install files              # 填路径，选存储源
root@box:~# app-setup backup files               # 现在先备一次，稳妥
root@box:~# app-setup restore files              # 需要那天
```

## 另见

- [备份 PostgreSQL](/zh/backup-postgresql) —— 同一套存储源、测试和动作，只是换成数据库。
  这里配好的存储源两边都能用。
- [使用你的容器](/using-your-container)（英文）—— `/data` 是什么，值得备份的东西为什么该放上面。
- `app-setup docs files` —— 脚本在机器上自己讲自己。
