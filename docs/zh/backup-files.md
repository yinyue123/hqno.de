# 备份文件

数据库有专门的脚本管。你自己写的程序没有，把数据全放在文件里的程序也没有。**`files`**
就是管这些的：你把目录列出来，它定时存走，要用的时候 `restore` 放回来。

大多数机器上有两类东西，它们要的做法正好相反。这一页一半讲一类：

<FigRows :head="['', '第一部分 · 配置', '第二部分 · 图片']" :rows="[
  [{ t: '举例', tone: 'mute' }, { t: '/etc/myapp、/data/code.yaml', tone: 'strong' }, { t: '/data/store/uploads', tone: 'strong' }],
  [{ t: '多大', tone: 'mute' }, { t: '几 MB', tone: 'mute' }, { t: '几十 GB', tone: 'mute' }],
  [{ t: '怎么备', tone: 'mute' }, { t: '每晚一次全量', tone: 'ok' }, { t: '增量镜像', tone: 'ok' }],
  [{ t: '备到哪', tone: 'mute' }, { t: 'S3 桶（R2）', tone: 'mute' }, { t: '你自己的机器，走 SSH', tone: 'mute' }],
  [{ t: '留多久', tone: 'mute' }, { t: '15 份，约 5 个月', tone: 'mute' }, { t: '1 份，或者一天一个快照', tone: 'mute' }],
  [{ t: '用什么', tone: 'mute' }, { t: 'files 任务', tone: 'mute' }, { t: 'rsync，你自己调', tone: 'mute' }],
]" />

**看你需要的那一半就行。** 两边共用的只有一个概念：**存储源**是备份存到哪，**任务**是备份什么。

---

# 第一部分 · 配置文件：全量备到 R2

东西小，但金贵，而且你希望能翻回几个月前。这种情况每晚存一份完整的正合适 —— 反正一份才几 KB。

## 第 0 步 · 要备份的是什么

一台跑着 `myapp` 的机器上，四样东西：

```
/etc/myapp/app.conf          listen 5080
/etc/myapp/log.conf          level=info
/data/code.yaml              port: 5080
/data/store/settings.json    {"device":"laptop"}
```

## 第 1 步 · 领一个免费的 R2 桶

备份必须离开这台机器。Cloudflare R2 的免费额度你拿配置文件是用不完的 —— 10 GB 存储，而且
**下载永远不收费**，这一条在你真要恢复的那天最值钱。

1. **dash.cloudflare.com** → **R2** → **Create bucket**，名字叫 `my-backups`，Location 留
   **Automatic**。
2. 右边把 **Account ID** 抄下来 —— 32 位十六进制。
3. **Manage R2 API Tokens** → **Create API Token**，权限选 **Object Read & Write**，在
   **Specify bucket(s)** 里限定到 `my-backups` 这一个桶。
4. 下一屏会**只显示一次** **Access Key ID** 和 **Secret Access Key**，两个现在就抄下来。

最后你手上是这四个值：

```ini
account id   a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
bucket       my-backups
access key   1234567890abcdef1234567890abcdef
secret key   fedcba0987654321fedcba0987654321fedcba0987654321fedcba09
```

## 第 2 步 · 填进去

```
root@box:~# app-setup install store-r2
root@box:~# app-setup set store-r2 \
    account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4 \
    bucket=my-backups \
    prefix=backups \
    access_key=1234567890abcdef1234567890abcdef \
    secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba09
```

它只写一个文件，你的密钥也只存在这一个地方：

```ini
# /etc/app-setup/params/store-r2.conf
account=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
bucket=my-backups
prefix=backups
access_key=1234567890abcdef1234567890abcdef
secret_key=fedcba0987654321fedcba0987654321fedcba0987654321fedcba09
```

> **别的 S3 用法一样** —— MinIO、阿里云 OSS、腾讯云 COS、Backblaze、AWS 都行。把 `store-r2`
> 换成 `store-s3`，多给一个 endpoint：
>
> ```
> root@box:~# app-setup set store-s3 \
>     bucket=my-backups endpoint=http://192.0.2.10:9000 region=us-east-1 \
>     prefix=backups access_key=… secret_key=…
> ```

## 第 3 步 · 先测，再信

```
root@box:~# app-setup test store-r2
==> making a folder
==> writing a file into it
==> listing it
==> reading it back
==> deleting it
  ok folder, write, read and delete all worked — s3://my-backups/backups
```

要五步不是一步，因为「能写但不能列目录」的密钥配置很常见，而且在第一次真备份之前它看起来一切正常。
**五步没全过的存储源，下一步会拒绝使用。**

## 第 4 步 · 说清楚备份哪些

注意第三项是**通配符**，因为 `myapp` 的配置不止一个文件：

```
root@box:~# app-setup set files \
    paths='/data/code.yaml, /data/store, /etc/myapp/*.conf' \
    store=r2 schedule=daily
root@box:~# app-setup install files
  ==> measuring
  ok  4 paths, 20.0K
  ok  scheduled daily, minute 51
  ok  ready — press ▶ Back up now to take one
```

三项填进去，报的是 **4** —— 通配符已经展开成两个文件了。这个数字就是你检查通配符有没有匹配对的
办法：再往 `/etc/myapp/` 放一个 `extra.conf`，重跑 `install`，它会说 `5 paths`。列了但机器上没有的
路径，它会警告，并且不计进这个数：

```
root@box:~# app-setup set files paths='/data/code.yaml, /etc/typo'
root@box:~# app-setup install files
  !   listed but not on this machine: /etc/typo
  ok  1 path, 4.0K
```

## 第 5 步 · 现在就备一次

```
root@box:~# app-setup backup files
  ==> backing up files
  ==> copying /data/code.yaml
  ==> copying /data/store
  ==> copying /etc/myapp/app.conf
  ==> copying /etc/myapp/log.conf
  ==> packing files_20260823055612.tgz
  ok  /data/app-setup/backups/files/files_20260823055612.tgz  (4.0K)
  ==> uploading files_20260823055612.tgz to r2:box/files
  ok  uploaded

root@box:~# app-setup archives files
  on this machine   /data/app-setup/backups/files/
    files_20260823055612.tgz    4.0K   2026-08-23 05:56 UTC
  on r2             box/files/
    files_20260823055612.tgz           2026-08-23 05:56 UTC
  1 here, 1 there.
```

`/etc/myapp/*.conf` 变成两行 `copying` —— 和上一步那个路径数展开出来的是同一回事。

真出事之前，这一步值得跑一次：

```
root@box:~# app-setup verify files
  ok  this archive opens and holds 4 saved file(s). Nothing has been written back.
```

## 第 6 步 · 需要它回来的那天

真正的检验是本地什么都不剩 —— 文件删了，本地那份归档也删了，逼它从桶里拉：

```
root@box:~# rm -rf /etc/myapp /data/code.yaml /data/store
root@box:~# rm -rf /data/app-setup/backups/files

root@box:~# app-setup restore files
  ==> fetching files_20260823055612.tgz from r2:box/files
  This puts back, overwriting what is there now:
      /data
      /data/store
      /etc/myapp
  ==> putting the saved files back
  ok  restored

root@box:~# cat /etc/myapp/app.conf /data/code.yaml
listen 5080
workers 4
port: 5080
name: code
```

> **恢复是就地覆盖**，而且**命令不会停下来问你** —— 只有面板上的 **⟲ 恢复** 按钮会确认。
> `app-setup restore files` 把上面那串路径打出来，然后就直接做了。那串路径要在你按回车**之前**看。

## 留几个月的历史

四个数字，是一把梯子，不是一个份数 —— 每小时、每天、每周、每月各留最新的一份。拿一年的每晚备份
喂进去，最后稳定成这样：

| 设置 | 留下几份 | 最老的一份 |
|---|---|---|
| `0 / 7 / 4 / 6`（默认） | **15** | 约 5 个月前 |
| `0 / 7 / 4 / 12` | **21** | 约 11 个月前 |
| `0 / 7 / 0 / 0` | 7 | 6 天前 |
| `0 / 2 / 0 / 0` | 2 | 昨天 |

几档是重叠的 —— 昨晚那份既是最新的「每日」，也是最新的「每周」和「每月」—— 所以留下的份数
比四个数字加起来少。想要一年的配置历史，改一个数就够：

```
root@box:~# app-setup set files keep_daily=7 keep_weekly=4 keep_monthly=12
```

真要靠它之前，有两件事得知道：

**它是从最新那份往回数，不是按当前时间数。** 一台关了六周的机器开回来，「每天」那一档还是整的。

**`prune_remote=off` 是默认值，意思是桶那边根本不剪。** 上面那把梯子剪的是这台机器的磁盘；
传上去过的每一份都还在 R2 里。一晚几 KB 的话，这等于白送的历史。打开之后，它一次最多删一梯子：

```
root@box:~# app-setup set files prune_remote=on
root@box:~# app-setup backup files
  ==> pruning r2:box/files
  !   stopped after 17 deletions — that is more than one ladder's worth.
      287 kept there
```

所以桶里积了三百份旧归档的话，是好几个晚上慢慢降下来，不是一次清完。这是那道保险在起作用。

## 要备份的东西不止一个

`paths` 是逗号分隔的列表，通配符会展开，所以下面这些是同一个任务：

```ini
paths=/etc/myapp/*.conf, /data/code.yaml, /data/store, /opt/thing, /var/lib/thing
```

三条能省事的规则：

```ini
# 「跳过」是在拷贝的时候就排掉，不是拷完再删：
exclude=*.log, *.tmp, node_modules, .git

# /data/app-setup 永远被排除，所以备份 /data 不会把之前每一份归档都打进新的那份里。
# /、/proc、/sys、/dev、/run 直接拒绝。
```

**一台机器只有一个 `files` 任务** —— 一个 `files.conf`、一份路径列表、一个定时、一把梯子。
配置目录再多也没关系。但其中一个要是 40 GB 的图片，就不行了 —— 那是第二部分。

---

# 第二部分 · 图片和上传：走 SSH 做增量

## 为什么不能直接塞进第一部分

因为 **`files` 每一次备份都是全量**。它打一个新的、带日期的 `.tgz`，整个传上去，跟昨晚不做差分。
把一个 40 GB 的上传目录加进那个任务，就是每晚存 40 GB、发 40 GB，再乘上梯子留的份数。

拿同一棵 100 个文件、9.8 MB 的树，两种做法实测：

| | 第一次之后，每晚发多少 |
|---|---|
| `files` 任务（全量 tar 包） | **9.8 MB** —— 整棵树重新打包重新发 |
| rsync 镜像 | **104,217 字节** —— 只发变了的那一个文件 |

所以分法是：**配置放进 `files` 任务；图片留在任务外面，用 rsync 单独做镜像。**

## 第 1 步 · 找一台机器收

任何开着 `sshd` 的机器都行 —— NAS、VPS、另一个容器。两张卡：

| 卡片 | 什么时候用 |
|---|---|
| **store-rsync** | 对端有 `rsync` —— 传到 90% 断了能续 |
| **store-scp** | 对端只有 `sshd`，什么都不用装 —— 但要看后面参考里那段说明 |

```
root@box:~# app-setup install store-rsync
root@box:~# app-setup set store-rsync target=root@192.0.2.10:/backups port=36000
```

`port` 很重要。很多机器的 sshd 不在 22 上 —— 这个例子就是真实的 **36000**，后面所有命令都会
自己把它带上。

## 第 2 步 · 把密钥放到对端

装的时候生成了 `/etc/app-setup/secrets/backup_ed25519`。任何地方都不存密码；唯一一次要用密码，
就是现在把公钥送过去：

```
root@box:~# app-setup showkey store-rsync
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFaPoXIBQczYNhTI5LQ... app-setup backup

# 在对端上：
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA…' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

> 把**目录**也设成 `chmod 600` 是这里的坑。没有执行位，sshd 进不去这个目录、读不到里面的文件，
> 密钥认证就失败，而且客户端输出里一个字都不会告诉你为什么。`~/.ssh` 是 `700`，里面的文件是 `600`。

然后跑和第一部分一样的五步测试：

```
root@box:~# app-setup test store-rsync
  ok  folder, write, read and delete all worked — root@192.0.2.10:/backups
```

> **那堆 post-quantum 警告不是失败。** 客户端的 OpenSSH 比对端新的话，*每一次*连接都会打一行
> `WARNING: connection is not using a post-quantum key exchange algorithm` —— 所以这个测试会打
> 五遍。没出问题。

## 第 3 步 · 把大目录从 `files` 任务里踢出去

`/data/store` 在 `paths` 里的话，`/data/store/uploads` 就在每晚的 tar 包里。排掉它：

```
root@box:~# app-setup set files exclude='data/store/uploads, *.log, *.tmp'
```

> **不能带开头的斜杠。** 拷贝是从 `/` 出发、用相对路径名跑的，所以以 `/` 开头的模式什么都匹配
> 不上 —— 而且不声不响。同一棵树、同一个任务，只差这一行：
>
> ```ini
> exclude=/data/store/uploads    →  归档 20,412,339 字节，200 张图一张不少
> exclude=data/store/uploads     →  归档 338 字节，一张都没有
> exclude=uploads                →  也是 338 字节 —— 按目录名匹配同样有效
> ```

## 第 4 步 · 做镜像

对端一份拷贝，永远是最新的。40 GB 永远是 40 GB。

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

那两行 `app-setup` 就是全部的窍门。它们针对这个存储源打印出：

```
root@box:~# app-setup sshcmd store-rsync
ssh -i /etc/app-setup/secrets/backup_ed25519 -p 36000 -o IdentitiesOnly=yes \
    -o UserKnownHostsFile=/etc/app-setup/secrets/backup_known_hosts \
    -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10

root@box:~# app-setup remote store-rsync uploads
root@192.0.2.10:/backups/uploads
```

> **别自己手写那些参数。** 有两个是猜不出来的：`-p 36000`，手抄的命令会默默掉回 22；还有
> `UserKnownHostsFile`，因为 `app-setup test` 把对端的 host key 钉在了**存储源自己的**
> known_hosts 里，不是 `~/.ssh/known_hosts`。少了它就是
> `No ED25519 host key is known … Host key verification failed`。
>
> `mkdir -p` 也不能省：`rsync` 只会创建目标路径的**最后一层**。

然后挂到定时上（`app-setup install cron`，或者往 `/etc/crontabs/root` 里加一行）。

## 第 5 步 · 或者一天留一个快照

镜像回答的是「文件现在什么样」。要是你还想问「上周二什么样」，就用 `--link-dest`：每一天都是
一棵**完整**的树，但没变过的文件是指向昨天那份的硬链接，不多占空间。

```sh
#!/bin/sh
# /usr/local/bin/snapshot —— 带日期的快照，没变的文件互相共用。
set -eu
SRC=/data/store/uploads/
SSH=$(app-setup sshcmd store-rsync)
DEST=$(app-setup remote store-rsync snapshots)
HOST=${DEST%%:*}; DIR=${DEST#*:}
today=$(date -u +%Y%m%d)
$SSH "$HOST" "mkdir -p '$DIR'"
rsync -a --delete -e "$SSH" \
  --link-dest="$DIR/latest" \
  --exclude='*.log' \
  "$SRC" "$HOST:$DIR/$today/"
$SSH "$HOST" "ln -sfn '$DIR/$today' '$DIR/latest'"
```

那棵 9.8 MB 的树存两天，在对端上是这样：

```
root@far:~# du -shl /backups/snapshots     # 共用的文件重复计算
20M
root@far:~# du -sh  /backups/snapshots     # 磁盘真正付出的
11M
root@far:~# stat -c '%h %n' /backups/snapshots/*/img50.jpg   # 从没改过的那个
2 /backups/snapshots/20260101/img50.jpg
2 /backups/snapshots/20260102/img50.jpg
```

链接数是 2，就是说磁盘上一份文件同时给两天用。放大来看：一棵 40 GB、每天变 200 MB 的树，
三十份快照大约占 46 GB，而不是 1.2 TB。

> **只有第一次**跑会打一句 `--link-dest arg does not exist: …/latest`。正常 —— 还没有上一份
> 快照可以做硬链接，所以第一晚本来就是完整拷一份。它退出码是 0，之后不再出现。

## 第 6 步 · 怎么拿回来

这一半没有 **⟲ 恢复** 按钮，所以下面两条命令要留着。都是把 `rsync` 的两端调过来，而且都不带
`--delete` —— 恢复不该把「本地有、备份里没有」的文件删掉。

**从镜像恢复** —— 拿回它最后一次跑时的样子：

```sh
SSH=$(app-setup sshcmd store-rsync)
DEST=$(app-setup remote store-rsync uploads)
mkdir -p /data/store/uploads
rsync -a -e "$SSH" "$DEST/" /data/store/uploads/
```

**从快照恢复** —— 先问有哪几天，再挑一天。列出来的 `latest` 是符号链接，不是某一天：

```sh
SSH=$(app-setup sshcmd store-rsync)
DEST=$(app-setup remote store-rsync snapshots)
$SSH "${DEST%%:*}" "ls -1 ${DEST#*:}"
# 20260101
# 20260102
# latest
rsync -a -e "$SSH" "$DEST/20260101/" /data/store/uploads/
```

同一个 `img1.jpg`，从两天分别拿回来，确实是不同的文件：

```
从 20260101 取 →  md5 2a0cd6684b9b5f03969a44eee3aef831
从 20260102 取 →  md5 53f285bb426b69c1247e8cfc1fc8805b
```

> **镜像只新到它最后一次跑的那一刻。** 同一次测试里，镜像手上还是 `2a0cd668…`，也就是旧版本 ——
> 因为那个文件改了之后还没再跑过镜像。快照每一天也是这个性质，区别在于快照那边昨天还在，你回得去。

## 要备份的目录不止一个

给每个目录一个自己的远端目录，密钥和存储源都还是同一套：

```sh
for d in uploads avatars exports; do
  SSH=$(app-setup sshcmd store-rsync)
  DEST=$(app-setup remote store-rsync "$d")
  $SSH "${DEST%%:*}" "mkdir -p '${DEST#*:}'"
  rsync -a --delete -e "$SSH" "/data/store/$d/" "$DEST/"
done
```

对端上就是：

```
/backups/uploads/    /backups/avatars/    /backups/exports/
```

---

# 参考

## 就一个概念：存储源，和任务

<FigRows :arrow="1" :head="['你要配的', '它回答的问题']" :rows="[
  [{ t: '存储源', tone: 'strong' }, { t: '备份存到哪？', tone: 'mute' }],
  [{ t: '任务', tone: 'strong' }, { t: '备哪些路径、多久一次、留几份？', tone: 'mute' }],
]" />

存储源要先配 —— 一个「输出没地方去」的任务是装不上的。一个存储源可以装很多任务；一个任务指向
一个存储源。

## 所有存储源

| 存储源 | 什么时候用 |
|---|---|
| **store-r2** / **store-s3** | 任何 S3 桶 —— R2、AWS、MinIO、阿里云 OSS、腾讯云 COS、Backblaze |
| **store-rsync** | 有 `rsync` 的机器 —— 能续传，一个文件只发变了的部分 |
| **store-scp** | 只有 `sshd` 的机器 —— 见下面 |
| **store-webdav** / **store-ftp** | 一个 Nextcloud 共享，或者一块 FTP 空间 |

**scp 存储源和 hqnode 主机。** 现在的 OpenSSH `scp`（9 以上）走 SFTP，所以对端要有能用的
`sftp-server` —— 正常的 `openssh-server` 都自带。hqnode 主机不正常：它的 22 端口是 hqnode 网关
（`SSH-2.0-hqnode`），网关能转发 shell 和 `rsync`，但不提供 SFTP 子系统，所以 `store-scp` 在这里会报
`sftp-server: No such file or directory`，而同一个端口上的 `store-rsync` 好好的。把 `store-scp`
指到那台机器真正的 sshd 上（常常是 36000 这种高位端口），或者干脆用 `store-rsync`。

## 四个动作

| 命令 | 干什么 |
|---|---|
| `app-setup backup files` | 打包这些路径并上传 |
| `app-setup archives files` | 列出有哪些备份，本机和远端都列 |
| `app-setup verify files` | 把最新那份解开看看 —— 什么都不写回去 |
| `app-setup restore files` | 把最新那份放回去（就地覆盖） |

## 任务文件全文

```ini
# /etc/app-setup/params/files.conf
paths=/data/code.yaml, /data/store, /etc/myapp/*.conf
exclude=data/store/uploads, *.log, *.tmp, node_modules, .git
service=                 # 拷贝期间要停的服务；留空 = 不停
store=r2                 # 你配好的存储源
folder=                  # 留空 = 远端的 <主机名>/files
prune_remote=off         # 是否也删远端的旧归档
schedule=daily           # off | hourly | daily | weekly | monthly
keep_hourly=0
keep_daily=7
keep_weekly=4
keep_monthly=12
```

`service` 是给「一直有东西在往里写」的目录用的 —— 普通目录没有「一致性快照」这回事，
所以把服务名填上，拷贝这段时间它会被停掉。大多数配置目录凌晨四点没人写，所以通常留空。

## 另见

- [备份 PostgreSQL](/zh/backup-postgresql) —— 同一套存储源、测试和动作，只是换成数据库。
  一个存储源两边都能用。
- [使用你的容器](/using-your-container)（英文）—— `/data` 是什么，值得备份的东西为什么该放上面。
- `app-setup docs files` —— 脚本在机器上自己讲自己。
