#!/bin/sh
# app-setup: 1
# id: store-s3
# name: S3 and anything like it
# name.zh: S3 及所有兼容它的
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 10
# summary: Where backups go: AWS, MinIO, Aliyun OSS, Tencent COS, Backblaze B2 — anything that speaks S3.
# summary.zh: 备份存到哪：AWS、MinIO、阿里云 OSS、腾讯云 COS、Backblaze B2 —— 任何说 S3 的地方。
# includes: rclone (or aws-cli), and a five-step connection test
# includes.zh: rclone（或 aws-cli），以及一个五步的连接测试
# disk: 60M
# memory: 64M
# requires: a bucket, and a key that can read, write and delete inside it
# requires.zh: 一个存储桶，以及一把能在里面读、写、删的密钥
# param: bucket     |           | Bucket          | 存储桶     |
# param: prefix     | backups   | Base folder     | 根目录     |
# param: endpoint   |           | S3 endpoint     | S3 地址    |
# param: region     | us-east-1 | Region          | 区域       |
# param: access_key |           | Access key      | Access key |
# param: secret_key |           | Secret key      | Secret key |
# button: test | ✓ Test connection | ✓ 测试连接
#
# A store answers five questions about a remote directory and nothing else:
# make this folder, put this file in it, get that one back, what is in there,
# delete that one. It has no schedule and knows nothing about databases —
# which is what lets a job point at any of them without a special case.
#
# S3 is four of the six stores' driver with a different backend name, and this
# is the one people already have. `Other` is the provider that works for every
# S3-compatible endpoint there is; AWS proper is the case where no endpoint is
# typed, and it is the only one where the region is load-bearing.
. /usr/lib/app-setup/common.sh

# The card this is running as. store-r2 is the same driver with two values
# derived and a form with two fewer boxes in it, so it runs this file with its
# own id — which is what keeps the test stamp, the state file and the card's
# own sentence pointing at the card somebody actually pressed.
STORE="${BK_STORE_ID:-store-s3}"

PKGS="rclone"
PKGS_apk="rclone"
PKGS_rpm="rclone"

# ------------------------------------------------------------ credentials --
# Configured entirely from the environment: nothing is written to
# ~/.config/rclone.conf, so the secret never outlives the process that needed
# it. A secret on disk in one place (params/store-s3.conf, mode 600) is a
# limitation somebody can reason about; the same secret copied into a second
# file by a tool they did not run is not.
#
# RCLONE_CONFIG=/dev/null says the same thing to rclone itself. Without it
# every transfer opens with `NOTICE: Config file "/root/.config/rclone/
# rclone.conf" not found - using defaults` — a timestamped line about a file
# nobody asked for, in the middle of the progress screen of a backup that is
# working perfectly. It also pins the configuration to this environment on a
# machine where somebody does keep an rclone.conf of their own.
s3_rclone() {
	RCLONE_CONFIG=/dev/null \
	RCLONE_CONFIG_BK_TYPE=s3 \
	RCLONE_CONFIG_BK_PROVIDER="$([ -n "$(param endpoint)" ] && echo Other || echo AWS)" \
	RCLONE_CONFIG_BK_ACCESS_KEY_ID="$(param access_key)" \
	RCLONE_CONFIG_BK_SECRET_ACCESS_KEY="$(param secret_key)" \
	RCLONE_CONFIG_BK_ENDPOINT="$(param endpoint)" \
	RCLONE_CONFIG_BK_REGION="$(param region us-east-1)" \
	rclone "$@"
}

s3_aws() {
	local _ep
	_ep="$(param endpoint)"
	AWS_ACCESS_KEY_ID="$(param access_key)" \
	AWS_SECRET_ACCESS_KEY="$(param secret_key)" \
	AWS_DEFAULT_REGION="$(param region us-east-1)" \
	aws ${_ep:+--endpoint-url "$_ep"} "$@"
}

# The store's base: bucket, then prefix if there is one. The job's folder goes
# under it and the archive under that.
s3_base() {  # s3_base [folder]
	local _b _p
	_b="$(param bucket)"
	_p="$(param prefix backups)"
	printf '%s' "$_b${_p:+/$_p}${1:+/$1}"
}

s3_have() {
	have rclone && return 0
	have aws    && return 0
	err "neither rclone nor aws-cli is here — run: app-setup install store-s3"
	return 1
}

s3_configured() { [ -n "$(param bucket)" ] && [ -n "$(param access_key)" ]; }

# ------------------------------------------------------------- the verbs --
# There are no directories on S3 at all: web01/backup-mysql/x.tgz is one flat
# key that happens to contain slashes, so this succeeds by doing nothing and
# the folder springs into existence with the first upload. It is still a verb,
# because WebDAV, FTP and SFTP all have to do real work here and the jobs must
# not have to know which kind they are pointed at.
do_mkdir() {  # do_mkdir <folder>
	return 0
}

do_put() {    # do_put <folder> <localfile>
	s3_have || return 1
	if have rclone; then
		# --s3-no-check-bucket: a key scoped to one bucket usually cannot call
		# HeadBucket, and rclone's pre-flight check would fail on a key that
		# can write perfectly well. That scoping is the thing we ask people to
		# do, so it must not be the thing that breaks them.
		s3_rclone copy --s3-no-check-bucket "$2" "BK:$(s3_base "$1")" ||
			{ err "upload failed"; return 1; }
	else
		s3_aws s3 cp "$2" "s3://$(s3_base "$1")/$(basename "$2")" >/dev/null ||
			{ err "upload failed"; return 1; }
	fi
}

do_get() {    # do_get <folder> <name> <localfile>
	s3_have || return 1
	if have rclone; then
		s3_rclone copyto "BK:$(s3_base "$1")/$2" "$3" ||
			{ err "could not fetch $2"; return 1; }
	else
		s3_aws s3 cp "s3://$(s3_base "$1")/$2" "$3" >/dev/null ||
			{ err "could not fetch $2"; return 1; }
	fi
}

# Bare names, one per line, sorted — the same strings a local directory gives,
# which is what lets one prune walk both. `lsf` without --recursive lists one
# level and marks sub-prefixes with a trailing slash; those are dropped, since
# a folder is not an archive.
do_ls() {     # do_ls <folder>
	s3_have || return 1
	if have rclone; then
		s3_rclone lsf "BK:$(s3_base "$1")" 2>/dev/null
	else
		s3_aws s3 ls "s3://$(s3_base "$1")/" 2>/dev/null | awk '{print $NF}'
	fi | grep -v '/$' | sort
}

do_rm() {     # do_rm <folder> <name>
	# A bare filename only. Everything that calls this passes a name that came
	# out of do_ls, and the one thing that must never be possible is a name
	# with a path in it reaching back out of the job's own folder.
	case "$2" in
		''|*/*|.|..) err "refusing to delete '$2' — a bare filename only"; return 1 ;;
	esac
	s3_have || return 1
	if have rclone; then
		s3_rclone deletefile "BK:$(s3_base "$1")/$2" 2>/dev/null
	else
		s3_aws s3 rm "s3://$(s3_base "$1")/$2" >/dev/null 2>&1
	fi
}

do_test() {
	bk_unbless "$STORE"
	s3_configured || die "no bucket or key yet. Fill in Settings first."
	s3_have || return 1
	bk_probe "$STORE" "s3://$(s3_base)"
}

# ------------------------------------------------------------------ state --
is_installed() { s3_configured; }

do_status() {
	is_installed || exit 2
	bk_store_card "$STORE" "s3://$(s3_base)"
}

do_install() {
	step "installing an S3 client"
	# Neither tool is in a RHEL rebuild's base repos, so the enterprise
	# distros need EPEL first — the same thing htop and atop already do here.
	case "$PM" in dnf|yum) enable_epel ;; esac
	if have rclone || have aws; then
		ok "$(have rclone && echo rclone || echo aws-cli) is already here"
	else
		pkg_install $(pmv PKGS) || die "could not install rclone here"
	fi
	chmod 600 "$APP_SETUP_CONF/params/$STORE.conf" 2>/dev/null || true

	# Migration that happens without being asked for is the only kind anybody
	# performs. Somebody has a bucket configured on the old `backup` card
	# today; if this one is empty, it comes across.
	if ! s3_configured && [ -n "$(bk_conf remote)" ]; then
		step "taking the bucket already configured on the Backup card"
		mkdir -p "$APP_SETUP_CONF/params"
		( umask 077; cat > "$APP_SETUP_CONF/params/$STORE.conf" <<EOF
bucket=$(printf '%s' "$(bk_conf remote)" | sed 's#^s3://##' | cut -d/ -f1)
prefix=$(printf '%s' "$(bk_conf remote)" | sed 's#^s3://##' | cut -s -d/ -f2-)
endpoint=$(bk_conf endpoint)
region=$(bk_conf region us-east-1)
access_key=$(bk_conf access_key)
secret_key=$(bk_conf secret_key)
EOF
		)
		chmod 600 "$APP_SETUP_CONF/params/$STORE.conf"
		ok "copied from params/backup.conf — check it, then press ✓ Test connection"
		return 0
	fi

	if ! s3_configured; then
		warn "no bucket yet. Open Settings, fill in the bucket and the two keys,"
		warn "then press ✓ Test connection."
	else
		do_test || warn "fix the above, then press ✓ Test connection again"
	fi
	save_note "$STORE" <<EOF
Backup destination — S3

  bucket      $(param bucket)
  base folder $(param prefix backups)
  endpoint    $(param endpoint)
  region      $(param region us-east-1)

  Point a backup at it:
    app-setup test store-s3
    app-setup set backup store=s3
    app-setup backup mysql
EOF
	ok "ready."
}

do_uninstall() {
	drop_note "$STORE"
	rm -f "$BK_STATE/$STORE.ok" "$BK_STATE/$STORE.state"
	info "the bucket was left alone — nothing in it was deleted."
}

do_help() {
	if lang_zh; then
		cat <<EOF
S3 备份存储源

  它是什么
    把打包好的备份传到任何一个说 S3 协议的地方。这不只是 AWS：
      AWS S3            端点留空，区域填对
      MinIO             端点填 http://ip:9000
      阿里云 OSS        端点填 https://oss-cn-hangzhou.aliyuncs.com
      腾讯云 COS        端点填 https://cos.ap-guangzhou.myqcloud.com
      Backblaze B2      端点填 https://s3.us-west-004.backblazeb2.com
    Cloudflare R2 也走这套驱动，但它单独有一张卡 —— 因为 R2 后台给你的
    是一个账号 id，不是一个端点地址。

  怎么配
    存储桶      桶名，不要带 s3:// 前缀
    根目录      桶里的起始目录，默认 backups
    S3 地址     AWS 留空；其它全都要填
    区域        AWS 必填；MinIO 之类随便填一个
    Access key / Secret key

    然后按「测试连接」。

  测试连接做了什么
    建目录 → 写文件 → 列目录 → 读回来比对 → 删掉。五步，因为每一步都会
    单独失败：一把只能 PutObject 不能 ListBucket 的密钥，是 S3 上最常见的
    半残配置，而且在第一次要恢复之前都看着正常。

    它是在一个临时子目录里探测，不是在根目录 —— 因为备份就是这么写的。

  密钥的范围
    这把密钥存在 $APP_SETUP_CONF/params/$STORE.conf，权限 600。
    容器里的 root 能读到它 —— 能读到它的人本来也能读到它保护的那个数据库，
    所以在这台机器上不算扩大了影响面。但一把对你整个账号有 s3:DeleteObject
    权限的密钥，在别处就是扩大了。**只给这一个桶、这一个前缀发密钥。**

  备份文件在桶里长什么样
    $(param bucket)/$(param prefix backups)/<主机名>/<任务>/<任务>_<时间>.tgz
    带主机名，是因为两台机器共用一个桶时，谁也不能删掉对方的历史。

  用它
    app-setup test store-s3
    app-setup set backup store=s3
    app-setup backup mysql
EOF
	else
		cat <<EOF
S3 backup destination

  What it is
    Sends packed backups to anything that speaks the S3 protocol, which is a
    great deal more than AWS:
      AWS S3          leave the endpoint blank, get the region right
      MinIO           endpoint http://ip:9000
      Aliyun OSS      endpoint https://oss-cn-hangzhou.aliyuncs.com
      Tencent COS     endpoint https://cos.ap-guangzhou.myqcloud.com
      Backblaze B2    endpoint https://s3.us-west-004.backblazeb2.com
    Cloudflare R2 uses this same driver and has a card of its own, because
    what R2's dashboard hands you is an account id rather than an endpoint.

  Setting it up
    Bucket        the name, with no s3:// in front of it
    Base folder   where in the bucket to start, backups by default
    S3 endpoint   blank for AWS; required for everything else
    Region        required by AWS; anything at all for MinIO and friends
    Access key / Secret key

    Then press ✓ Test connection.

  What Test connection does
    Makes a folder, writes a file into it, lists it, reads it back and
    compares the bytes, then deletes it. Five steps because each one fails on
    its own: a key that can PutObject and not ListBucket is the single most
    common half-working S3 configuration, and it looks fine until the first
    time somebody needs to restore.

    It probes inside a folder rather than at the base, because that is what a
    backup does.

  How wide to make the key
    It is kept in $APP_SETUP_CONF/params/$STORE.conf at mode 600. Root in the
    container can read it — and anybody who can read it can also read the
    database it protects, so that does not widen the blast radius on this
    machine. A key with s3:DeleteObject across your whole account does widen
    it elsewhere. **Issue one scoped to this bucket and this prefix.**

  What it looks like in the bucket
    $(param bucket)/$(param prefix backups)/<hostname>/<job>/<job>_<stamp>.tgz
    The hostname is there so that two machines sharing one bucket cannot
    prune each other's history.

  Using it
    app-setup test store-s3
    app-setup set backup store=s3
    app-setup backup mysql
EOF
	fi
}

app_main "$@"
