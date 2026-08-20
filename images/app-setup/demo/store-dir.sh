#!/bin/sh
# app-setup: 1
# id: store-dir
# name: Demo · a directory
# name.zh: 演示 · 本地目录
# category: demo
# order: 19
# summary: A store that is a directory on this machine. No network, no credentials — the one the tests run against.
# summary.zh: 一个「存到本地目录」的备份源。不走网络、不要密码 —— 测试用的就是它。
# includes: nothing at all
# includes.zh: 什么都不装
# disk: 0
# memory: 0
# param: path | /tmp/app-setup-store | Directory | 目录 |
# button: test | ✓ Test connection | ✓ 测试连接 | progress
#
# A seventh store, and the cheapest real test there is. `store-s3` against
# MinIO in a container is the only true S3 test and it needs a container;
# this one is `mkdir -p`, `cp`, `ls` and `rm` on a local directory, and it
# exercises every caller of the driver contract — make the folder, put, get,
# list, delete, prune, restore — with no network and no credentials.
#
# It lives in demo/ so the Dockerfiles cannot ship it: a store that writes
# backups to the same disk as the data is not a backup, and it must not be
# possible to pick one by accident from the tab.
#
# It is also the proof that the contract is a contract. Nothing in common.sh
# or in any job recipe knows this file exists, and adding it took no change to
# either — which is the same claim docs/app-setup.md §1 makes about adding
# nginx, and it should survive contact with this feature rather than be
# quietly dropped by it.
. /usr/lib/app-setup/common.sh

STORE=store-dir

sd_base() { printf '%s' "$(param path /tmp/app-setup-store)"; }
sd_dir()  { printf '%s/%s' "$(sd_base)" "$1"; }

# ------------------------------------------------------------- the verbs --
# Idempotent, like every other do_mkdir here: the second night's backup must
# not fail because the first night's made the folder.
do_mkdir() { mkdir -p "$(sd_dir "$1")" || { err "could not make $(sd_dir "$1")"; return 1; }; }

do_put() {
	do_mkdir "$1" || return 1
	cp "$2" "$(sd_dir "$1")/$(basename "$2")" || { err "copy failed"; return 1; }
}

do_get() { cp "$(sd_dir "$1")/$2" "$3" || { err "could not fetch $2"; return 1; }; }

# Bare names, sorted ascending — the contract's one hard requirement, because
# it is what lets one prune walk a bucket and a directory with the same code.
do_ls() { ls -1 "$(sd_dir "$1")" 2>/dev/null | sort; }

do_rm() {
	case "$2" in
		''|*/*|.|..) err "refusing to delete '$2' — a bare filename only"; return 1 ;;
	esac
	rm -f "$(sd_dir "$1")/$2"
}

bk_probe_cleanup() { rmdir "$(sd_dir "$1")" 2>/dev/null || true; }

do_test() {
	bk_unbless "$STORE"
	mkdir -p "$(sd_base)" || die "cannot write to $(sd_base)"
	bk_probe "$STORE" "$(sd_base)"
}

is_installed() { [ -n "$(param path)" ]; }

do_status() {
	is_installed || exit 2
	bk_store_card "$STORE" "$(sd_base)"
}

do_install() {
	mkdir -p "$(sd_base)"
	warn "this writes backups to a directory on this machine. One disk holding"
	warn "both the data and its backups is not a backup. This exists for tests."
	do_test
}

do_uninstall() { rm -f "$BK_STATE/$STORE.ok" "$BK_STATE/$STORE.state"; }

do_help() { cat <<EOF
Demo store — a local directory

  Five verbs on $(sd_base), so the job recipes and the retention ladder can be
  driven with no network and no credentials. It is in demo/ and is not shipped:
  a backup on the same disk as the data is not a backup.
EOF
}

app_main "$@"
