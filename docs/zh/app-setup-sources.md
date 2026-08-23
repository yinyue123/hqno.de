# 添加你自己的软件

`app-setup` 并不知道 nginx 是什么。它读的是一个装着 shell 脚本的目录，一个脚本画一
条菜单，你按下去它就把那个脚本跑起来。所以把你自己的软件加进去 —— 自己编的一个私有
版本、一个游戏服务端、你们公司的 agent —— 就是写一个文件，丢进一个目录。没有重新编
译，没有注册登记，你的文件和镜像里自带的那些一模一样地被对待。

**这个文件别自己手写。** 现在已经没人这么干了，手写也换不来任何东西。整份约定就一页
—— 就是这一页 —— 把这一页连同仓库里现成四十九个配方中的任意一个丢给模型，它第一次或
者第二次就能写出一个能跑的配方。下面第 1 到第 4 节就是这条路，按顺序来，而且都很短。

- [1. 把配方拉下来](#_1-把配方拉下来)
- [2. 提示词](#_2-提示词)
- [3. 检查它写回来的东西](#_3-检查它写回来的东西)
- [4. 发出去](#_4-发出去)

这四节之后的所有内容就是那份约定本身，一个字没动。你不需要读它：它是给模型看的，也
是当模型给你的东西干了点你没预料到的事情时，你回来查的地方。

- [最短的一个配方](#最短的一个配方)
- [文件都放在哪](#文件都放在哪)
- [文件头](#文件头)
- [可以让人改的设置](#可以让人改的设置)
- [那些函数](#那些函数)
- [status 这个动作](#status-这个动作)
- [白送给你的那些工具函数](#白送给你的那些工具函数)
- [给你的软件做备份](#给你的软件做备份)
- [要照顾好几个发行版](#要照顾好几个发行版)
- [怎么测](#怎么测)
- [一个完整的例子](#一个完整的例子)
- [发布一整套配方](#发布一整套配方)
- [几条要守的规矩](#几条要守的规矩)

---

## 1. 把配方拉下来

```sh
git clone https://github.com/yinyue123/hqno.de.git
cd hqno.de/images/app-setup
```

里面有三样东西，前两样是模型要用的：

| | |
|---|---|
| `recipes/` | 每个镜像里都带的那四十九个，一个文件一个 |
| `lib/common.sh` | 所有配方都会 source 的那个工具库 |
| `install.sh` | 把整套东西装到一台你有 root 的 Linux 机器上，这样不用容器也能测 |

挑一个跟你要加的东西最像的配方，连同这一页一起给模型。这比你写多少描述都管用：

| 你的东西是… | 去读 |
|---|---|
| 一个包，没有服务 | `htop.sh`、`ncdu.sh` —— 十来行 |
| 一个包，带服务和配置文件 | `nginx.sh`，140 行，现有最好的参考 |
| 从 GitHub 上下的一个二进制，哪里都没有包 | 下面[一个完整的例子](#一个完整的例子)里的 `gitea` |
| 好几样东西挂在同一条菜单下面 | `lnmp.sh` —— nginx、MySQL、PHP 合成一条 |
| 带设置表单的 | `backup.sh`，以及[可以让人改的设置](#可以让人改的设置) |

---

## 2. 提示词

把下面这段贴过去，最后两行填上你自己的。顺便把这一页的地址也给它 —— 这一页就是一个
文件，模型会整页读完：`https://doc.hqno.de/app-setup-sources`。

```text
帮我写一个 hqnode 的 app-setup 配方文件。app-setup 是容器里的一个 TUI 软件选
装器：它读 /etc/app-setup/*.sh，按文件头的注释每个文件画一条菜单，人选了某个
操作它就调用文件里对应的函数。完整约定在
https://doc.hqno.de/app-setup-sources —— 动手之前先读完。

硬性要求：

- 只能用 POSIX sh。它要在 Alpine 的 busybox ash 下跑。不许用 [[ ]]、数组、
  ${x^^}、$'...'，任何 bash 特有的写法都不行。
- 文件开头是 `#!/bin/sh`，然后是注释文件头。`# app-setup: 1` 这一行才让这个
  文件成为一个配方；之后 id、name、summary、category、disk 是最低配。name、
  summary、includes 都再加一份 .zh —— 面板是双语的。
- source /usr/lib/app-setup/common.sh，并且要用它。pkg_install、make_service、
  svc_enable、fetch、rand_pass、param、data_path、guess_host、step、ok、die
  都已经有了。不要按发行版写 if/else，也不要手写 systemd unit 和 OpenRC 脚本
  —— make_service 会按这台机器实际用的那个生成。
- 文件最后一行是 `app_main "$@"`，顶层不要放别的东西。每次执行任何操作这个
  文件都会被整个跑一遍，所以函数外面裸写一个 exit，等于每个操作在解析阶段就
  被它掐掉。
- do_uninstall 只删程序，绝对不删数据。数据库、上传的文件、代码仓库都留着，
  并且打印出它们在哪、要删的话具体敲哪条命令。
- 连装两次必须能成。第二次不能因为第一次留下的用户、目录或者配置就失败。
- 每个临时变量都要 local。函数之间共用一个命名空间。
- do_status 每 8 秒就为屏幕上的每一条跑一次：读个文件、看个进程，仅此而已。
  退出码 0 在跑、1 停了、2 没装、3 坏了。
- disk 和 memory 要老实写。有人拿着一台 512MB 的机器就靠这两个数字做决定。

这是一个现成配方，风格照着它写：<从 images/app-setup/recipes/ 里贴一个文件>

我要加的是：<是什么东西、怎么装、听哪个端口、数据放在哪，以及装完之后还要人
手动做点什么>
```

最下面那两个占位才是真正干活的地方。「加个 Uptime Kuma」你会拿到一个看着像样的东
西；「加个 Uptime Kuma，它是个 Node 程序，npm install 到 /opt/uptime-kuma，听 3001，
数据在它自己目录里，没有任何发行版有这个包」你拿到的是一个真能装上的东西。

如果是你自己的私有软件，就明说，并且说清楚怎么取到它 —— 一个要 token 才能下的
tarball、内网某台机器上的一个 `.deb`、一次 git checkout。这是模型唯一猜不出来的部
分，也是唯一真正属于你的部分。

---

## 3. 检查它写回来的东西

六个错，而且就是真的会出现的那六个。花两分钟对一遍这个单子，比花一个小时去调一条半
死不活的菜单划算。

1. **bash 写法。** `[[ ]]` 和数组是最常见的两个，它们在模型脑子里那台 Ubuntu 上跑得
   好好的，到 Alpine 上就死。一条命令就能定：`busybox ash -n yourfile.sh`。
2. **手写的 systemd unit**，或者围着两份一样的东西写一圈
   `if [ "$OS_ID" = alpine ]`。`make_service` 一行就把两种 init 都覆盖了。如果它给
   你的答案里有个 heredoc 往 `/etc/systemd/system` 里写，退回去重写。
3. **`do_uninstall` 里的 `rm -rf`。** 有时候删的是数据目录，有时候删的是 `/data`。
   这一条是真会让人丢掉整个数据库的，所以就算别的都不看，这个函数也要看。
4. **不能重复执行** —— `useradd` 前面没有 `id … ||`，`mkdir` 没带 `-p`。装一遍、卸
   一遍、再装一遍；配方就是死在第二次装上。
5. **`do_status` 里起了个进程** —— 拿 `curl` 去戳端口、跑个 `docker ps`、来一整条
   `systemctl show`。每八秒一次，屏幕上每一条都跑。
6. **`summary` 漏了**，或者文件头里混进一个空行导致它提前结束。`app-setup doctor`
   会因为这个退出码非零，所以第 4 节里第一条要跑的就是它。

---

## 4. 发出去

两条路，回答的是不同的问题。

<FigRows :head="['', '就这一个容器', '你自己的镜像']" :rows="[
  [{ t: '你要做的', tone: 'mute' }, { t: '把文件拷进 /etc/app-setup/local/', tone: 'strong' }, { t: '在你 fork 里加到 images/app-setup/recipes/', tone: 'strong' }],
  [{ t: '要多久', tone: 'mute' }, { t: '几秒', tone: 'ok' }, { t: '推一次，等几分钟 CI', tone: 'mute' }],
  [{ t: '重装之后还在吗', tone: 'mute' }, { t: '不在 —— /etc 是镜像给的', tone: 'bad' }, { t: '在，它就在镜像里', tone: 'ok' }],
  [{ t: '谁能用上', tone: 'mute' }, { t: '这一个容器', tone: 'mute' }, { t: '所有从你镜像装出来的容器', tone: 'mute' }],
]" />

### 放进一个容器

```sh
scp myapp.sh you@container:/etc/app-setup/local/     # 从你自己电脑上
chmod +x /etc/app-setup/local/myapp.sh
app-setup doctor && app-setup info myapp && app-setup install myapp
```

`local/` 本来就在默认搜索路径上，而且排在自带的那个目录后面，所以你放一个 `id` 和我
们某个配方相同的文件进去，它就把那条替换掉，别的什么都不用改。最后那行的详细版本在
[怎么测](#怎么测)。

这是验证配方能不能跑的正确做法，但不是保存它的正确做法：`/etc/app-setup` 来自镜像，
重装一次就被换掉。把原件放在 `/data` 下面开机拷回去，或者干脆走另一条路。

### 放进你自己的镜像

那个 recipes 目录**就是**镜像里的 `/etc/app-setup` —— 三个 Dockerfile 里各有一行
`COPY app-setup/recipes/ /etc/app-setup/`。所以你 fork 里那个目录下的文件就在镜像里
了，不用再告诉任何东西一声。没有索引，没有注册，没有构建脚本要改。

1. **Fork** GitHub 上的 [`yinyue123/hqno.de`](https://github.com/yinyue123/hqno.de)，
   然后 clone 你自己的 fork，不是我们的。
2. **文件丢进去**：`images/app-setup/recipes/myapp.sh`，`chmod +x`，提交，推到
   `main`。
3. **把 Actions 打开。** fork 出来的仓库工作流是关着的 —— Actions 那一页会这么说，
   按钮就在上面。点一下，一次就行。
4. **然后流水线自己会跑。**
   [`.github/workflows/images.yml`](https://github.com/yinyue123/hqno.de/blob/main/.github/workflows/images.yml)
   只要有推送碰到 `images/**` 就触发，把
   [`systems.yml`](https://github.com/yinyue123/hqno.de/blob/main/images/systems.yml)
   里每一个系统都构建一遍，推到 `ghcr.io/<你>/hqnode:<tag>` —— `alpine-3.24`、
   `debian-13`，还有另外十八个。它不需要任何 secret：`GITHUB_TOKEN` 加
   `packages: write` 就够了。把 `systems.yml` 删到只剩你真正会用的那一两个系统，构建
   就从二十条腿变成两条。
5. **把这个 package 设成公开，手动，一次。** GHCR 上新建的 package 是私有的，而私有
   的 package 在机器去拉的时候就是一个 `401`。Settings → Packages → hqnode →
   Change visibility。流水线里没有任何东西能替你做这一步。
6. **拿它装一个容器。** 在面板里填镜像地址的地方粘上
   `ghcr.io/<你>/hqnode:alpine-3.24`。是机器去拉，不是面板也不是你的电脑 ——
   [让机器拉得到它](/zh/building-your-own-image#_7-让机器拉得到它)
   里是全部情况，私有仓库也在里面。

你的 fork 还会有自己的 `images/catalog.json`，由同一条流水线把刚推上去的 digest 写
回来。面板就是拉这个文件来填它的镜像市场的，所以一台指到你 fork 那个 raw 地址的主
机，给出的是你的系统列表而不是我们的。

**你自己的一整个分类页**，如果你的东西多到想要一个的话，在任意一个配方的文件头里加
一行就行：

```sh
# category: mycompany
# category.name: Our software
# category.name.zh: 我们的软件
```

---

## 最短的一个配方

存成 `/etc/app-setup/hello.sh`，`chmod +x`，然后跑 `app-setup`。它在「系统」那一页。

```sh
#!/bin/sh
# app-setup: 1
# id: hello
# name: Hello
# summary: The smallest possible app-setup source.
# category: system
# disk: 1M
. /usr/lib/app-setup/common.sh

PKGS="cowsay"
CHECK_BIN="cowsay"

do_help() { echo "Run: cowsay hello"; }

app_main "$@"
```

这就是一条完整可用的条目了，它打开的菜单里有「安装」「卸载」「怎么用」。安装和卸载
是白捡的 —— 一个包、没有服务的东西，`PKGS` 一个变量就够了。

`# app-setup: 1` 这一行才让这个文件成为一个配方。没有这一行的文件会被忽略，工具库
也正是靠这个，才能待在同一棵目录树里而不冒充成一个软件。

---

## 文件都放在哪

| 路径 | 是什么 |
|---|---|
| `/etc/app-setup/*.sh` | 自带的那些配方 |
| `/etc/app-setup/local/*.sh` | 你自己的。id 和自带的撞上了，你的赢 |
| `/etc/app-setup/params/<id>.conf` | 某个配方的设置表单存下来的东西 |
| `/etc/app-setup/secrets/<id>.txt` | 生成的密码，0700 目录里的 600 文件 |
| `/usr/lib/app-setup/common.sh` | 每个配方都 source 的工具库 |
| `/var/log/app-setup/<id>.log` | 每次操作的输出，往后追加 |
| `/var/lib/app-setup/` | 记账用的 —— 包索引的刷新时间戳在这儿 |

你可能想打开看看的东西全在 `/etc/app-setup` 下面，这也正是它的用意：就一个目录，而
且就是你本来也会去翻的那个。要把 `params/` 和 `secrets/` 挪到别处，改
`$APP_SETUP_CONF`。

搜索顺序是 `$APP_SETUP_PATH`，默认为
`/etc/app-setup:/etc/app-setup/local`。靠后的目录赢，所以
`/etc/app-setup/local/nginx.sh` 会顶掉自带的 `nginx` 那一条，什么都不用改。这就是覆
盖我们某一条的正确姿势：原件原封不动放着，这样镜像更新的时候还能照常替换它。而且
`local/` 也是 app-setup 重装自己那套配方时不会动的那一半 —— 它只替换上一级目录里的
`*.sh`。

想试一个配方又不想装到任何地方去：

```sh
APP_SETUP_PATH=/etc/app-setup:$HOME/my-sources app-setup
```

**配方能扛过容器重启，但扛不过重装。** 重装换的是镜像，而 `/etc/app-setup` 来自镜
像。把原件放在 `/data` 下面 —— 那个是留得住的 —— 然后开机拷回去，`/etc/rc.local` 里
加一行，或者一个 systemd unit，都够了。

---

## 文件头

文件最上面的注释行，`key: value`，到第一行不是注释的地方为止。app-setup 解析这些；
它从不为了画一条菜单去 source 这个文件。这是故意的 —— 画一次目录不该顺手执行四十个
shell 脚本，别人丢进来的一个文件也不该仅仅因为存在就获得运行的机会。它是在你按键的
时候才跑的。

| 键 | 必填 | 含义 |
|---|---|---|
| `app-setup: 1` | **是** | 标明这个文件是配方。没有它这个文件就是隐形的 |
| `id` | 否 | 命令行上用的名字。默认是去掉 `.sh` 的文件名 |
| `name` | 否 | 列表里的标题。默认就是 id |
| `name.zh` | 否 | 中文标题 |
| `category` | 否 | 哪个分类页。`stack`、`web`、`db`、`dev`、`system`，或者你自己起一个。默认 `system` |
| `category.name` | 否 | 你自己造的那个分类叫什么 |
| `category.name.zh` | 否 | 同上，中文 |
| `order` | 否 | 在分类页里的位置，小的在前。默认 100 |
| `summary` | 否 | 列表里那一行说明。说清楚它是**干什么用**的 |
| `summary.zh` | 否 | 同上，中文 |
| `includes` | 否 | 装完机器上多了什么，一句话 |
| `includes.zh` | 否 | 同上，中文 |
| `disk` | 否 | 装完占多大 —— `800M`、`2G`。会显示，也会和剩余空间比 |
| `memory` | 否 | 跑起来要多少内存。和这台机器的 RAM 比 |
| `ports` | 否 | 它听哪些端口，给列表看的 |
| `requires` | 否 | 它需要什么，给列表看的。是给人读的话，不是依赖求解器 |
| `service` | 否 | init 里的服务名，如果有的话 |
| `param` | 否 | 一项可以让人改的设置。可以写多行，最多 12 条 —— 见下 |

每一个 `.zh` 都是可选的。不写就是所有人都看英文，这比一句糟糕的翻译好。

`disk` 和 `memory` 是配得上这个位置的：当这台机器装不下你要装的东西时，那行尺寸会变
红，app-setup 会先问一句，而不是让人下到 400MB 的时候才发现。老实估 —— 一个在 95%
处失败的安装，比一个上来就警告的安装糟得多。

关于分类有两件事值得知道：

- 可以写多个：`category: dev, web` 会让它同时出现在两个列表里。
- 写一个谁都没听过的分类，就等于把它创建出来。`category: games` 加上
  `category.name: Game servers` 就多一个分类页，不用改任何代码。

---

## 可以让人改的设置

一行 `param:` 就在设置表单里放一个字段 —— 就是你在软件上按回车打开的那个菜单里的那
一项。

```sh
# param: port  | 8080          | Listen port      | 监听端口   | number
# param: root  | /var/www/demo | Document root    | 网站目录
# param: ssl   | off           | Enable HTTPS     | 启用 HTTPS | bool
# param: level | info          | Log level        | 日志级别   | debug,info,warn
```

五段，用 `|` 分开，名字之后的每一段都是可选的：

| | |
|---|---|
| 名字 | 在你的环境里变成 `APP_PARAM_PORT`。字母、数字、`_` |
| 默认值 | 在有人改它之前生效的值 |
| 标签 | 表单里显示的字 |
| 中文标签 | 同上，中文。不写就是所有人都看英文 |
| 类型 | `bool` 复选框，`number` 只能输数字，逗号列表是一个选择器，`@name` 是一个由这台机器现填的列表，不写就是文本框 |

**`@name` 是唯一一种你不用自己写出候选值的类型。** 逗号列表在你写配方的那一刻就定死
了；而 `@backup` 是拿**这台机器上**那些能被备份的软件来回答的 —— 这是你坐在这儿不可
能知道的事：

```sh
# param: targets | | What to back up | 备份哪些 | @backup
```

这个字段打开的是一个勾选列表而不是文本框 —— 空格勾，回车确认 —— 它存下来的值和你自
己手敲出来的那串逗号分隔的字符串一模一样，所以 `param targets` 读回来的东西是原样
的。已经装了的排在前面，每一条都会说明它在不在。今天只有 `@backup` 这一个来源；一个
这个二进制不认识的名字会退化成文本框，而不是退化成一个空列表，所以按新版 app-setup
写的配方在旧版上照样能用。

进没进那个列表不是你在文件头里设的一个字段。它取决于你的配方有没有定义 `do_backup`
—— 就是 `app-setup backup <id>` 调的那个函数。写了你就在里面，不用再声明什么，也没有
第二处要跟着同步。

用 `param` 把值读回来，每次都要把默认值再给一遍：

```sh
do_install() {
    pkg_install $(pmv PKGS)
    sed -i "s/^listen .*/listen $(param port 8080);/" /etc/myapp.conf
    param_on ssl && enable_tls
}
```

默认值给两遍不是冗余 —— 正是它让
`sh /etc/app-setup/myapp.sh install` 在你手动敲的时候行为完全一致：没有表单，哪里也
没有存过的文件。**一个配方绝对不能要求「表单必须被打开过」。**

存下来的值在 `/etc/app-setup/params/<id>.conf`，就挨着它配置的那个配方，一行一个
`name=value`，脚本里用 `app-setup set myapp port=9090` 改。

表单有三个按钮，是 LuCI 那三个：**保存并应用**写下设置然后跑你的 `install`，**保存**
只写下设置就停，**取消**把这次改动丢掉。所以 `do_install` 同时也是「重新配置」这条
路，值得把它做快一点 —— 如果二进制已经是对的版本，就重写配置、重启服务、返回。一个
只是改了端口的人不该等一次下载，一个又把它改回去的人不该等两次。

字段就四种，这是故意的。如果你的软件需要的配置比这还多，那它有配置文件，这时候有用
的做法是在 `do_help` 里说清楚它在哪，而不是在这里长出一个向导来。下面这两样 —— 把字
段折起来、给某个字段配一个按钮 —— 不是第五种字段类型；它们回答的是「我这六个字段里
到底哪些是人真得看一眼的」，而这个问题本来也不是加一种字段类型能解决的。

### 把连着的几个字段折起来

```sh
# param: port     | 8080 | Listen port      | 监听端口
# group: adv | Advanced | 高级 | collapsed
# param: workers  | 4    | Worker processes | 工作进程数 | number
# param: timeout  | 30   | Request timeout  | 超时时间   | number
```

`group:` 之后的每一行 `param:` 都归它，直到下一个 `group:` 为止 —— param 那一行上不
用写任何东西。第一个 `group:` 之前声明的字段保持不分组，待在最上面，所以一个从来不分
组的配方一个字都不用改。第四段是 `collapsed` 或者 `expanded`（默认）；人在表单里用回
车或者点一下就能折叠展开，和别的东西一样。旧的二进制 —— 2.9 之前的 —— 看到一行冒号
它不认识的注释就跳过，所以用了这个写法的配方在旧版上就是所有字段平铺一排，跟以前一
样。

### 挂在某个字段下面的按钮

```sh
# param: target  |      | Camouflage site   | 伪装网站
# action: target | scan | ↻ Refresh         | ↻ 重新扫描
```

`action: <它属于哪个字段> | <动作> | 标签 | 中文标签` 会在那个字段正下方单起一行画一
个按钮。字段必须已经声明过 —— 先写字段，再写刷新它的那个 action，和 `group:` 要求的
顺序一样。`<动作>` 就是你自己脚本里那个 `case "$1" in …` 在交给 `app_main "$@"` 之前
自己接住的东西：

```sh
[ "$1" = scan ] && { do_scan; exit $?; }   # 放在 app_main "$@" 前面
app_main "$@"
```

按下按钮就用「安装」那个一模一样的进度界面把这个动作跑一遍 —— 同一条进度条、同一句
步骤说明、同一份日志 —— 跑完回到设置界面并且重新加载表单。所以一个会改写你自己文件头
的动作（就是那种 `rewrite_choices` 式的、把刚扫到的东西填进选择器的代码），它填出来
的新选项有地方可显示，而不用人离开这个界面。
`private-pkg/realityscan.sh` 里「伪装网站」旁边那个 `↻ 重新扫描` 就是这套东西的原始
用例：按一下重扫一个网段，把下拉框刷新，同时不碰任何已经生效的配置。

还是没有子表单，这条界线没有挪：一个带按钮的字段可以跑一个脚本然后重新加载；它不能
打开属于自己的第二个表单。那还是配置文件的活。

---

## 那些函数

source 完 `common.sh` 之后，需要哪个写哪个。你不写的那些都会拿到一个默认实现，靠
`PKGS` 和 `SERVICE` 干活。

| 函数 | 什么时候跑 | 默认行为 |
|---|---|---|
| `do_install` | 「安装」那一行 | 装 `PKGS`，把 `SERVICE` 设成开机启动并启动 |
| `do_uninstall` | 「卸载」那一行 | 停掉并取消 `SERVICE` 的开机启动，删掉 `PKGS` |
| `do_start` | 「启动」那一行 | `svc_start` |
| `do_stop` | 「停止」那一行 | `svc_stop` |
| `do_restart` | 「重启」那一行 | 先停后起 |
| `do_enable` | 「开机启动」那一行 | `svc_enable` |
| `do_disable` | 还是那一行 | `svc_disable` |
| `do_status` | 一直在跑 —— 见下 | 从 `is_installed` 和 `SERVICE` 推出来 |
| `do_help` | 「怎么用」那一行 | 「这个配方没有带说明」 |
| `do_backup` | `app-setup backup <id>`，以及定时任务 | 「这个软件的配方里没有备份」 |
| `do_restore` | `app-setup restore <id>` | 同上 |
| `do_dump` | `app-setup dump <id>` | 「这个软件的配方里没有 dump」 |
| `do_load` | `app-setup load <id>` | 同上 |
| `do_list` | `app-setup archives <id>` —— 名字不一样是因为 `list` 已经是目录列表了 | 「这个软件的配方里没有备份」 |
| `do_verify` | `app-setup verify <id>` | 同上 |
| `do_test` | `app-setup test <id>`，以及一个 `# button: test` | 「这不是一个备份目的地」 |
| `is_installed` | 在 `do_status` 里面 | `CHECK_PKG`，其次 `CHECK_BIN`，其次 `CHECK_FILE`，最后是 `PKGS` 里的全部 |
| `version_line` | 在 `do_status` 里面 | 什么都不做 |

文件的最后一行必须是 `app_main "$@"`。就是它把 `$1` 里那个动作变成上面某一个调用。

有几个变量在驱动这些默认行为：

```sh
PKGS="nginx nginx-common"   # 装什么
SERVICE="nginx"             # 起什么
CHECK_BIN="nginx"           # 怎么判断它装了 —— PATH 上的一个命令
CHECK_FILE="/etc/nginx"     # ……或者一个路径，如果根本没有命令的话
CHECK_PKG="nginx"           # ……或者一个包名，当命令存在不足以说明问题的时候
```

**命令有可能本来就在的时候，用 `CHECK_PKG`。** 在 Alpine 上，busybox **在基础镜像里**
就提供了叫 `unzip`、`ping`、`wget`、`less` 等等三百来个 applet，所以
`CHECK_BIN="unzip"` 在一台什么都没装的机器上是成立的 —— 列表里写着「已安装」，「安
装」这个动作根本不会出现。`CHECK_PKG` 问的是包管理器，那是 busybox 替不了的。

**就算别的都不写，也要写 `do_help`。** 它是「有人装上了某个软件」和「有人能用这个软
件」之间的区别。说清楚配置在哪、日志叫什么、最常见的三个报错长什么样，以及卸载会删什
么、不会删什么。

---

## 安装界面上显示的是什么

一个动作跑起来的时候，app-setup 画一个标题、一条进度条、当前这一步，以及下面详细的日
志。这三样都出自你的脚本，而且你本来就在用的那个函数已经把大部分事情办了：

```sh
do_install() {
    step_total 4                       # 可选 —— 让进度条变成一个分数
    step "installing packages"         # 进度条下面那句话
    pkg_install $(pmv PKGS)
    step "writing the configuration"
    ...
}
```

`step` 就是那个普通的输出函数。它打的每一行都会变成屏幕上的当前阶段，所以人读到的那
句话是你写的 —— *正在下载 WordPress*、*正在建数据库* —— 而不是 app-setup 编出来的。
你脚本打的别的东西都落到日志窗格和 `/var/log/app-setup/<id>.log` 里。

`step_total N` 是多出来的那一行。有它，进度条就是「做完几步 / `N`」；没有它，进度条走
的是一条无限逼近终点但永远到不了的曲线 —— 对一个没说自己有多长的脚本来说，这才是诚
实的画法。数一数实际会走到的那条路上有几次 `step` 调用 —— 如果你的安装有分支、不同发
行版次数不一样，那就什么都别说，用那条曲线。一条在六步里的第三步就走满了的进度条，比
没有进度条更糟。

没有任何东西在数字节，也没有在问包管理器进行到哪了，因为这两件事它们自己也不知道。

---

## status 这个动作

唯一一个 app-setup 读它**输出的值**而不只是退出码的函数，也是唯一一个没人按任何键就
会跑的函数。屏幕上每一条都会调它，而且是反复调。

**退出码就是状态：**

| 退出码 | 卡片上显示 |
|---|---|
| `0` | 在跑 —— 或者，如果它根本没有服务，就是「已安装」 |
| `1` | 装了，但停着 |
| `2` | 没装 |
| `3` | 装了，坏的 |

**标准输出是若干行 `key=value`：**

| 键 | 效果 |
|---|---|
| `detail=` | 替换掉列表里那行说明。把版本号放这儿 |
| `enabled=1` / `enabled=0` | 填上「开机启动」那个勾 |

```sh
version_line() { printf 'nginx %s' "$(nginx -v 2>&1 | sed 's|.*nginx/||')"; }
```

……通常这就够了，因为默认的 `do_status` 会调它。

**它必须快。** app-setup 八秒之后就杀掉它，并把这条显示成「坏了」。不要在 `do_status`
里访问网络，不要在里面 `apt-get update`，也不要跑任何可能卡在别的安装正持有的锁上的
东西。

---

## 白送给你的那些工具函数

最上面一行 `. /usr/lib/app-setup/common.sh` 就把下面这些全带进来了。它是 POSIX sh ——
Alpine 的 `/bin/sh` 是 busybox ash，所以它里面、以及你写的任何东西里面，都没有数组、
没有 `[[ ]]`、没有任何 bash 特有的写法。

**告诉用户现在在干什么。** 所有东西同时进日志和屏幕，不是终端的时候颜色会去掉。

```sh
step "installing the thing"     # ==> installing the thing
info "a detail"                 #     a detail
ok   "it worked"                #   ok it worked
warn "this is odd"              #   !  this is odd
err  "this is wrong"            #   x  this is wrong
die  "stop here"                # 先 err，然后 exit 1
```

**装包**，不用管是哪个包管理器：

```sh
pkg_install nginx curl          # apt / dnf / yum / apk / zypper / pacman
pkg_remove  nginx
pkg_present nginx               # 装了吗？
pkg_exists  nginx               # 配好的那些源里有这个包吗？
pkg_install_first php8.3-fpm php8.2-fpm php-fpm   # 这台机器上存在的第一个
pkg_install_optional php-intl   # 有就装，没有就算了
pm_refresh                      # 整机最多一小时一次
pm_wait_unlocked                # 等别的 apt/dnf/apk 让开，最多 3 分钟
enable_epel                     # RHEL 那几个重打包把半个 userland 放在这里
```

`pkg_install` 和 `pkg_remove` 本来就会等别的包操作让开，所以你很少需要自己调
`pm_wait_unlocked`。它之所以重要，是因为你的配方很可能跑在一个几秒钟前才启动的容器
上，那时候镜像自己开机时那次索引拉取还占着 apt 的锁 —— 而 apt 对这种情况的回答，是用
一种读起来像「这个包不存在」的方式失败。

**服务**，不用管是哪个 init：

```sh
svc_start x; svc_stop x; svc_restart x; svc_reload x
svc_enable x; svc_disable x          # 开机启动
svc_running x; svc_enabled x         # 看退出码
svc_supported                        # 根本没有 init 的时候为假
make_service NAME "Description" "/usr/local/bin/thing --serve" user /var/lib/thing
remove_service NAME
```

`make_service` 从一段描述里生成一个 systemd unit 或者一个 OpenRC 脚本，这正是一个没
有任何打包的单二进制需要的东西。如果那个 unit 需要 `Environment=` 行，先设
`SVC_ENVIRON`。

**这是台什么机器：**

```sh
$OS_ID $OS_VERSION $OS_MAJOR $OS_NAME $OS_CODENAME   # debian、13、13、...
$PM      # apt dnf yum apk zypper pacman none
$PMF     # deb rpm apk arch none —— 家族，通常你要的是这个
$INIT    # systemd openrc sysv none
$ARCH    # amd64 arm64 armv7
in_container    # 在容器里为真，在这儿永远为真
have curl       # 这个命令在 PATH 上吗
lang_zh         # 用户在读中文吗
```

**下载**，curl 或者 wget，哪个在用哪个：

```sh
fetch https://example.com/x.tar.gz /tmp/x.tar.gz
fetch_stdout https://example.com/version.txt
ensure_downloader        # 两个都没有就装一个
run_bounded 180 sh /tmp/vendor-install.sh    # 180 秒还没完就放弃，退出码 124
```

`fetch` 自己会给 curl 加上界。`run_bounded` 是为它够不着的那种情况准备的：**别人的**
安装脚本 —— 你把控制权交出去，而它自己可能根本没有超时。Oh My Zsh 的 `install.sh` 最
后是一个 `git fetch`，而在 github.com 被丢包而不是被拒绝的地方 —— 一道防火墙、一个国
家、一条抽风的线路 —— 那个调用会一直等下去，人就看着一个永远装不完的安装。**每一个外
部厂商的脚本都要走 `run_bounded`。**

**Web 相关的东西**，因为每个发行版都放在不一样的地方：

```sh
$WEBROOT                 # /var/www/html，每个镜像上都是
nginx_conf_dir           # /etc/nginx/conf.d，Alpine 上是 http.d
nginx_drop_default       # 把自带的那个默认 server 删掉，不管它藏在哪
nginx_test_reload        # nginx -t，然后 reload —— 配置是坏的就拒绝 reload
php_service              # php8.2-fpm、php-fpm、php83-fpm……
php_fastcgi_pass         # 127.0.0.1:9000 或者 unix:/run/php/....sock
php_nginx_site [root]    # 一个完整的默认 server，PHP 已经接好
web_user; web_group      # www-data、nginx、apache —— php-fpm 用哪个身份跑
php_bin                  # php，或者带版本号的那个二进制
```

**数据库：**

```sh
mysql_root -e "SELECT 1"            # root，走 socket 或者用 .my.cnf
mysql_wait                          # 服务起来了，socket 还没好
db_mysql_create mydb myuser "$pw"   # utf8mb4，语法一路兼容到 5.5
db_mysql_drop   mydb myuser
```

**密码和留言条。** 绝对不要把生成的密码只打进安装日志里 —— 没人会翻回 900 行 `apt`
输出里去找。

```sh
pw="$(rand_pass 24)"
save_note myapp <<EOF          # /etc/app-setup/secrets/myapp.txt，权限 600
password   $pw
EOF
show_note myapp                # 安装结束时再打一遍
drop_note myapp                # 放在 do_uninstall 里
```

**把别的配方拼起来。** LNMP 之所以是四行而不是 nginx、PHP、MariaDB 的一份复制品，靠
的就是这个：

```sh
recipe nginx install         # 跑另一个配方的某个动作
recipe_ensure nginx          # ……但只在它还没装的时候
recipe_status nginx          # 0 在跑，1 停了，2 没装
```

`recipe_ensure` 几乎永远是你想要的那个。`recipe nginx install` 会重写默认站点，把当
时正在那儿提供服务的东西打下去。

**文件：**

```sh
backup_once /etc/nginx/nginx.conf     # 留一份 .app-setup-orig，一辈子就一次
restore_backup /etc/nginx/nginx.conf
tmp_dir                               # mktemp -d，带兜底
guess_host                            # 拼 URL 时该打印的那个地址
port_busy 80; require_ports 80 443
```

---

## 给你的软件做备份

如果你的配方存数据，就给它 `do_backup` 和 `do_restore`。你负责描述数据**是什么**；
工具库负责给归档起名、打包、上传、清理旧的，以及事后把服务放回去。

```sh
do_backup() {
        bk_begin myapp                 # 起名 myapp_20260819033240.tgz
        bk_quiesce                     # 方式是 files 的时候停掉 SERVICE
        myapp dump > "$(bk_path data.sql)"
        bk_add /etc/myapp              # 配置跟着数据一起走
        bk_finish                      # 打包、上传、清理、重启
}

do_restore() {
        bk_open myapp "${1-}"          # 最新的那份，或者指名的那份
        myapp load < "$BK_UNPACKED/data.sql"
        bk_restore_files "$BK_UNPACKED"
        bk_close
}
```

| 函数 | 干什么 |
|---|---|
| `bk_begin <前缀>` | 开一个归档，并装上那个「下面任何一步失败就把服务重新起来」的 trap |
| `bk_path <名字>` | 归档里的一个路径，给 dump 往里写 |
| `bk_add <路径>` | 把一个文件或目录拷进去，保留它的绝对路径。遵守 `$BK_EXCLUDE`，绝不会把备份目录自己打进去，拒绝 `/` 之类 |
| `bk_quiesce` / `bk_resume` | 停止和启动 `SERVICE`，但只在方式是 `files` 的时候 |
| `bk_finish` | 打包、重启、上传、清理 |
| `bk_open <前缀> [归档]` | 解包到 `$BK_UNPACKED` —— 本地没有就从桶里下 |
| `bk_restore_files <目录>` | 把 `bk_add` 存过的东西全放回去 |
| `bk_close` | 收尾 |
| `bk_mysql_db <库>` / `bk_mysql_load <目录>` | 一个 MySQL 库，给只有一个库的配方用 |
| `dump_target <前缀> <后缀> [指定]` | dump 该写到哪 —— 你指定的那个，或者 `/data/dumps` 下一个带日期的名字 |
| `dump_source <前缀> <后缀> [指定]` | 该读哪份 dump —— 指名的那个，或者最新的 |
| `mysql_dump_db <库> <文件>` / `mysql_load_file <文件>` | 同一个库，但落成一个普通文件 |
| `dump_tool_check <命令> <一句话>` | 在安装的时候就说清楚 dump 工具到底在不在 |

### `dump` 和 `load`

除了 `backup` 之外也值得有，而且它们不是一回事。备份是整条流水线 —— 打好包、带日期、
传上去、清理旧的、定时跑。dump 是一个普通文件，人能打开、能 `scp`、能喂给另一台服务
器：

```sh
do_dump() {
        local _f
        _f="$(dump_target myapp sql "${1-}")"
        myapp export > "$_f" || die "the export failed"
        [ -s "$_f" ] || die "the dump came out empty; that is not a backup"
        chmod 600 "$_f"
        ok "$_f"
}

do_load() {
        local _f
        _f="$(dump_source myapp sql "${1-}")"
        myapp import < "$_f" || die "the import failed"
}
```

让 `do_backup` 和 `do_dump` 去调**同一个**函数，只是目的地不同。「这个数据库怎么导出
来」写两份实现，早晚会漂开，而漂开的那一份永远是挂在定时任务上、没人盯着的那一份。

产出 dump 的那个工具必须真的装上了 —— 在 `PKGS` 里点名，别去指望某个 metapackage，并
且在 `do_install` 的末尾加一句 `dump_tool_check`，这样一个把客户端包拆得不一样的发行
版，是在安装那天被发现，而不是在有人急着要恢复的那个晚上。

有两条规矩值得守，两条都是花大代价学来的：

**要炸就大声炸，不要悄悄地。** 在让 `bk_finish` 打包之前，先确认 dump 不是空的。一个
零字节的文件躺在一个名字很漂亮的归档里，看上去像备份能看一年，然后在最坏的那个时刻被
发现它不是。

**绝不要把服务撂在停机状态。** `bk_begin` 捕获 `EXIT`、`INT` 和 `TERM`，所以一次失败
的 dump 或者一个 Ctrl-C，也照样会把 `bk_quiesce` 停掉的东西重新起来。如果是你自己动手
停的什么东西，把它的名字设进 `BK_SVC_WAS`，那个 trap 就也会管它。

`bk_open` 是设一个变量而不是把路径 echo 出来，这是故意的：写成
`d="$(bk_open myapp)"` 会让它在子 shell 里跑，那么命令替换一结束，trap 就立刻把解开
的归档删掉了。

配置文件，不只是数据：你的软件要原样回来还需要什么，就 `bk_add` 什么。一个在默认配置
下恢复出来的数据库，是另一台服务器。

如果你的软件在这儿根本没有配方 —— 你自己写的东西 —— 那你也不需要一个。自带的 `files`
配方在它的设置里接受一串路径和通配符，按同样的计划表备份它们；在备份卡片的列表里把
`files` 挑上，就挨着 `mysql`。

## 要照顾好几个发行版

包名是漂得最厉害的东西。`pmv` 会挑存在的那个里最具体的值 —— 先这个发行版，再它的包管
理器，再它的家族，最后是光板的那个：

```sh
PKGS="iputils-ping net-tools dnsutils"
PKGS_rpm="iputils net-tools bind-utils"
PKGS_apk="iputils net-tools bind-tools"
PKGS_centos="iputils net-tools bind-utils"   # 专门针对这个发行版

pkg_install $(pmv PKGS)
```

后缀，从最具体开始：`_<os_id>`、`_<pm>`、`_<pmf>`，然后是光板。所以是 `PKGS_ubuntu`、
`PKGS_apt`、`PKGS_deb`、`PKGS`。它对任何变量名都成立，不只是 `PKGS` —— 第二常用的通常
是 `SERVICE_rpm="httpd"`。

当名字是按**版本**变而不是按发行版变的时候，去问，别猜：

```sh
pkg_install_first php8.4-fpm php8.3-fpm php8.2-fpm php-fpm
```

四个系统，四件会绊到你的事：

- **Alpine** 没有 systemd、没有 glibc、没有 bash。`$INIT` 是 `openrc`，而从厂商官网下
  的预编译二进制多半根本跑不起来。
- **AlmaLinux、Rocky、CentOS** 把半个普通 userland —— `htop`、`atop`、`fail2ban` ——
  放在 EPEL 里。去找它们之前先调 `enable_epel`。
- **CentOS 7** 已经过了生命周期。它的 MariaDB 是 5.5，比大多数现代 SQL 语法都早；它的
  Python 是 2。
- **Debian 和 Ubuntu** 的 PHP 包名跟着发行版本走，而版本两年换一次。

---

## 怎么测

```sh
app-setup doctor                # 能解析吗？这台机器长什么样？
app-setup list                  # 你那条在不在，分类对不对？
app-setup info myapp            # 文件头每一个字段，解析之后的样子
app-setup status myapp          # 0 在跑，1 停了，2 没装，3 坏了
app-setup install myapp         # 来真的，输出直接打在终端上
app-setup docs myapp            # 你的 do_help
app-setup screenshot --width 80 # TUI 的一帧，纯文本，不需要终端
```

`doctor` 会把一个没有 `summary` 的配方算成问题并且退出码非零，所以它是该放进脚本里的
那个。

screenshot 这个子命令就是在没有终端的情况下按各种宽度检查列表长什么样的办法，
`--screen menu|params|progress` 对那几个对话框做同样的事：

```sh
for w in 130 88 46; do app-setup screenshot --width $w --category system | tail -1; done
```

拿 Alpine 真正在用的那个 shell 去查语法，不要只查你自己那个：

```sh
sh -n myapp.sh && dash -n myapp.sh && busybox ash -n myapp.sh
```

然后真的装一遍、卸一遍、再装一遍。第二次装才是配方出事的地方：有东西被留下来了，而这
个配方假设机器是干净的。

---

## 一个完整的例子

一个单二进制的服务端，这也正是那些工具函数真正为之准备的情况 —— 没有包、没有 unit 文
件，而且每个架构一个 tarball。

```sh
#!/bin/sh
# app-setup: 1
# id: gitea
# name: Gitea
# name.zh: Gitea 代码仓库
# category: dev
# order: 40
# summary: A git server with a web interface, in one binary. Your own GitHub, at about 200MB.
# summary.zh: 一个二进制文件的 Git 服务器，带网页界面。自己的 GitHub，占用约 200MB。
# includes: the gitea binary, a service, a git user, SQLite storage
# includes.zh: gitea 主程序、服务、git 用户、SQLite 存储
# disk: 250M
# memory: 200M
# ports: 3000
# service: gitea
. /usr/lib/app-setup/common.sh

SERVICE="gitea"
CHECK_FILE="/usr/local/bin/gitea"
GITEA_VER="1.22.3"

version_line() { printf 'Gitea %s on port 3000' "$GITEA_VER"; }

do_install() {
	# git 本身是个包，gitea 不是。一条配方，两样都管。
	pkg_install git

	id git >/dev/null 2>&1 || {
		step "creating the git user"
		# adduser 的参数在 shadow 和 busybox 之间不一样，所以两个都试。
		useradd --system --shell /bin/sh --home /var/lib/gitea --create-home git 2>/dev/null ||
		adduser -S -s /bin/sh -h /var/lib/gitea git 2>/dev/null ||
		die "could not create the git user"
	}

	step "downloading gitea $GITEA_VER for $ARCH"
	fetch "https://dl.gitea.com/gitea/$GITEA_VER/gitea-$GITEA_VER-linux-$ARCH" \
	      /usr/local/bin/gitea ||
		die "could not download gitea. Check this container has a route out."
	chmod 755 /usr/local/bin/gitea

	mkdir -p /var/lib/gitea/custom /var/lib/gitea/data /etc/gitea
	chown -R git:git /var/lib/gitea
	chown -R git:git /etc/gitea          # 它第一次跑的时候自己写配置

	# 一段描述进去，出来的是一个 systemd unit 或者一个 OpenRC 脚本。
	make_service gitea "Gitea" "/usr/local/bin/gitea web --config /etc/gitea/app.ini" \
	             git /var/lib/gitea
	svc_enable gitea
	svc_start  gitea

	ok "Gitea is running"
	info "finish the setup at http://$(guess_host):3000/"
}

do_uninstall() {
	remove_service gitea
	rm -f /usr/local/bin/gitea
	warn "/var/lib/gitea was NOT deleted — your repositories are still there."
	warn "Remove it yourself if you mean it:  rm -rf /var/lib/gitea /etc/gitea"
}

do_status() {
	[ -x /usr/local/bin/gitea ] || exit 2
	echo "detail=$(version_line)"
	if svc_enabled gitea; then echo "enabled=1"; else echo "enabled=0"; fi
	svc_running gitea && exit 0
	exit 1
}

do_help() { cat <<'EOF'
Gitea

  Finishing the install
    http://<your address>:3000/ — the first page is the setup form. The
    defaults are right for this machine; SQLite needs no database server.
    The first account you create is the administrator.

  Where things are
    /usr/local/bin/gitea    the program
    /etc/gitea/app.ini      the configuration, written on first run
    /var/lib/gitea          repositories, and the SQLite database

  Reaching it
    Port 3000 has to be published by the panel before your laptop can see
    it. A container's 3000 is not the host's 3000.

  Backing it up
    tar -czf /data/gitea.tar.gz /var/lib/gitea /etc/gitea
    /data is the only path that survives a reinstall.

  Uninstalling
    Removes the binary and the service. /var/lib/gitea is left behind,
    because it holds every repository you pushed.
EOF
}

app_main "$@"
```

注意里面**没有**什么：没有 `if [ "$OS_ID" = ... ]`，没有把 systemd unit 写两遍，没有
探测 init。这就是那个工具库的意义。

---

## 发布一整套配方

如果你手上有好几台机器，就把配方放在一个 git 仓库里，检出到一个自己的目录：

```sh
git clone https://example.com/my-app-setup.git /etc/app-setup/local
```

`/etc/app-setup/local` 本来就在默认的 `APP_SETUP_PATH` 上，而且排在
`/etc/app-setup` **后面**，所以里面一个和我们同名的文件就把它顶掉了。别的什么都不需要
—— 不用注册，也没有索引文件。

想让它们扛过一次容器重装，就 clone 到 `/data` 再做个链接：

```sh
git clone https://example.com/my-app-setup.git /data/app-setup
ln -s /data/app-setup /etc/app-setup/local
```

你自己的一个分类页，如果东西多到值得要一个，在任意一个配方里加一行文件头就行：

```sh
# category: mycompany
# category.name: Our software
# category.name.zh: 我们的软件
```

---

## 几条要守的规矩

容易搞错、而且搞错了很难受的那些事。

**`disk` 和 `memory` 要老实。** 有人拿着一台 512MB 的容器就靠这两个数字做决定。一个乐
观的数字，会变成一个装到两分钟就死掉的安装。

**卸载的时候绝不删数据。** 把程序删掉；数据库、上传的文件、代码仓库都留下，并且在输出
里明明白白说清楚它们在哪，以及如果他们真想删的话该怎么删。每一个自带的配方都是这么做
的，这也是唯一一条值得强制执行的约定。

**假设它会被跑两遍。** 第二次安装不能因为第一次留下的一个用户、一个目录或者一份配置就
失败。

**不要在动作函数外面 `exit`。** 每个动作都会把这个文件执行一遍，函数体外面裸写的一个
`exit`，在所有动作的解析阶段都会跑到。

**把互联网灌进 shell 之前先问一声。** 如果你的安装需要某个厂商的脚本，就在 `summary`
里说，在 `do_help` 里再说一遍。一个在菜单里选了一条的人，并没有同意运行第三方的任意代
码；告诉他们这一条就是干这个的。

**`do_status` 是挂在定时器上的。** 八秒，而且屏幕上每一条都要跑一遍。让它只读个文件或
者看个进程。

**临时变量都声明成 `local`。** shell 函数共用一个全局命名空间，所以一个拿 `_p` 做循环
的工具函数，和一个正把东西存在 `_p` 里的配方，用的是同一个变量。这不是假设 —— Alpine
上 `/usr/bin/php` 就是这么变成一个指向不存在文件的符号链接的：

```sh
do_install() {
	_p="$(alpine_php)"                     # php84
	pkg_install_optional "$_p-intl" "$_p-ctype"
	ln -sf "/usr/bin/$_p" /usr/bin/php     # ……链到了 php84-ctype
}
```

现在 `common.sh` 里的每一样东西都声明了自己的临时变量，所以工具库不会这么坑你。你自己
那些会调用别的东西的代码，也照做：

```sh
do_install() {
	local _p _svc
	…
}
```

而当你造出来的东西是个符号链接的时候，事后检查一下。`have php` 对一个断掉的链接照样答
「有」，所以真正的故障会在完全无关的地方冒出来 —— 在那次事故里，是四条毫不相干的条目
声称 PHP 没装。

**只用 POSIX sh。** 没有 `[[ ]]`，没有数组，没有 `local -a`，没有 `${x^^}`，没有
`$'...'`。`busybox ash -n yourfile.sh` 是能抓住这些的那条检查。

---

这一页里的每一件事，对镜像里自带的那些配方同样成立 —— 它们没有用任何私有接口。
`/etc/app-setup/nginx.sh` 是 140 行，是现有最好的参考；要看怎么把好几样东西拼成一条，
读 `lnmp.sh`。
