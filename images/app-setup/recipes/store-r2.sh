#!/bin/sh
# app-setup: 1
# id: store-r2
# name: Cloudflare R2
# name.zh: Cloudflare R2
# category: backup
# category.name: Backup
# category.name.zh: 备份
# order: 11
# summary: Where backups go: R2's own form. S3's driver underneath, with the endpoint and region worked out for you.
# summary.zh: 备份存到哪：R2 自己的表单。底下还是 S3 那套，端点和区域替你算好。
# includes: rclone (or aws-cli), and a five-step connection test
# includes.zh: rclone（或 aws-cli），以及一个五步的连接测试
# disk: 60M
# memory: 64M
# requires: an R2 bucket and an R2 API token
# requires.zh: 一个 R2 存储桶，以及一个 R2 API 令牌
# param: account    |         | Cloudflare account id | Cloudflare 账号 id |
# param: bucket     |         | Bucket                | 存储桶     |
# param: prefix     | backups | Base folder           | 根目录     |
# param: access_key |         | Access key            | Access key |
# param: secret_key |         | Secret key            | Secret key |
# button: test | ✓ Test connection | ✓ 测试连接
#
# R2 earns a card rather than a line in store-s3's help text because of what
# its dashboard hands you: an account id, where store-s3 asks for an endpoint
# URL. Two derived values — the endpoint built out of the account id, and
# `region=auto`, which R2 requires and which is the single most common way an
# S3-shaped R2 configuration fails — and a form with two fewer boxes in it.
#
# Underneath it is store-s3, run with this card's id. Not a copy of it: a
# second implementation of "how do you talk to an S3 endpoint" is a second
# thing to fix when rclone changes a flag, and the one that gets missed is
# always the one on the timer that nobody watches.
. /usr/lib/app-setup/common.sh

STORE=store-r2

# The whole of R2's difference from S3, in two lines.
r2_endpoint() { printf 'https://%s.r2.cloudflarestorage.com' "$(param account)"; }

r2_s3() {   # r2_s3 <verb> [args…] — store-s3, wearing this card's id
	local _f
	_f="$(recipe_path store-s3)" || { err "store-s3 is not on this machine"; return 1; }
	# param_reset is *not* called here: these are the parameters, mapped from
	# this card's form onto the names store-s3 reads. Everything else in this
	# card's environment is one of the five below or irrelevant to it.
	BK_STORE_ID="$STORE" \
	APP_PARAM_BUCKET="$(param bucket)" \
	APP_PARAM_PREFIX="$(param prefix backups)" \
	APP_PARAM_ENDPOINT="$(r2_endpoint)" \
	APP_PARAM_REGION=auto \
	APP_PARAM_ACCESS_KEY="$(param access_key)" \
	APP_PARAM_SECRET_KEY="$(param secret_key)" \
	sh "$_f" "$@"
}

r2_configured() {
	[ -n "$(param account)" ] && [ -n "$(param bucket)" ] && [ -n "$(param access_key)" ]
}

r2_where() { printf 'r2:%s/%s' "$(param bucket)" "$(param prefix backups)"; }

# ------------------------------------------------------------- the verbs --
do_mkdir() { r2_s3 mkdir "$@"; }
do_put()   { r2_s3 put   "$@"; }
do_get()   { r2_s3 get   "$@"; }
do_ls()    { r2_s3 ls    "$@"; }
do_rm()    { r2_s3 rm    "$@"; }

do_test() {
	bk_unbless "$STORE"
	r2_configured ||
		die "no account id, bucket or key yet. Fill in Settings first."
	# store-s3's do_test writes the stamp under $BK_STORE_ID, so a pass here
	# blesses this card and not the S3 one.
	r2_s3 test
}

# ------------------------------------------------------------------ state --
is_installed() { r2_configured; }

do_status() {
	is_installed || exit 2
	bk_store_card "$STORE" "$(r2_where)"
}

do_install() {
	# The client, not `store-s3 install` — that one migrates params/backup.conf
	# into params/store-s3.conf, which is store-s3's business and not this
	# card's. Delegation is for the five verbs and the test, where there is one
	# right answer; an install writes files, and whose files matters.
	step "installing an S3 client"
	case "$PM" in dnf|yum) enable_epel ;; esac
	if have rclone || have aws; then
		ok "$(have rclone && echo rclone || echo aws-cli) is already here"
	else
		pkg_install rclone || die "could not install rclone here"
	fi
	chmod 600 "$APP_SETUP_CONF/params/$STORE.conf" 2>/dev/null || true
	if ! r2_configured; then
		warn "not filled in yet. Open Settings and put in the account id, the bucket"
		warn "and the two keys, then press ✓ Test connection."
		return 0
	fi
	do_test || warn "fix the above, then press ✓ Test connection again"
	save_note "$STORE" <<EOF
Backup destination — Cloudflare R2

  account     $(param account)
  bucket      $(param bucket)
  base folder $(param prefix backups)
  endpoint    $(r2_endpoint)      (derived — there is no field for it)
  region      auto                (R2 requires this; it is not a setting)

  Point a backup at it:
    app-setup test store-r2
    app-setup set backup store=r2
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
Cloudflare R2 备份存储源

  为什么它单独一张卡
    R2 底下就是 S3 协议，用的也是同一套驱动。但 Cloudflare 后台给你的是
    一个**账号 id**，不是一个端点地址；而且 R2 要求区域必须写 auto —— 把
    R2 按 S3 配却配不通，十次有九次就是这两件事之一。
    这张卡替你算好这两个值，表单也就少了两个框。

  从 Cloudflare 后台哪里抄
    账号 id      R2 页面右侧「Account ID」，一串 32 位十六进制
    存储桶       你建的桶名
    Access key   R2 → Manage R2 API Tokens → Create API Token
    Secret key   同上，**只在创建时显示一次**，关掉就再也看不到了

    令牌权限选「Object Read & Write」，并且限定到这一个桶。
    然后按「测试连接」。

  它替你填了什么
    端点   $(r2_endpoint)
    区域   auto

  测试连接做了什么
    建目录 → 写文件 → 列目录 → 读回来比对 → 删掉。五步，因为每一步都会
    单独失败 —— 一个只给了读权限的令牌，能连上、能列目录，然后在第一次
    备份时失败。

  用它
    app-setup test store-r2
    app-setup set backup store=r2
    app-setup backup mysql
EOF
	else
		cat <<EOF
Cloudflare R2 backup destination

  Why this has a card of its own
    R2 speaks S3 underneath and runs on the same driver. But what Cloudflare's
    dashboard hands you is an **account id**, not an endpoint URL — and R2
    requires the region to be \`auto\`. An S3-shaped R2 configuration that does
    not work is one of those two things nine times out of ten. This card
    derives both, and the form has two fewer boxes as a result.

  Where each field is in the dashboard
    Account id   R2 page, right-hand side, "Account ID" — 32 hex characters
    Bucket       the bucket you made
    Access key   R2 → Manage R2 API Tokens → Create API Token
    Secret key   the same screen. **Shown once, at creation.** Close it and it
                 is gone for good.

    Give the token "Object Read & Write" and scope it to this one bucket.
    Then press ✓ Test connection.

  What it fills in for you
    endpoint   $(r2_endpoint)
    region     auto

  What Test connection does
    Makes a folder, writes a file into it, lists it, reads it back and
    compares the bytes, then deletes it. Five steps because each one fails on
    its own — a read-only token connects, lists, and then fails at the first
    backup.

  Using it
    app-setup test store-r2
    app-setup set backup store=r2
    app-setup backup mysql
EOF
	fi
}

app_main "$@"
