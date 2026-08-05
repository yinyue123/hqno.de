#!/bin/sh
# app-setup: 1
# id: rsync
# name: rsync
# name.zh: rsync 同步备份
# category: system
# order: 17
# summary: Copy files here or away, resume where it stopped, and only send what changed.
# summary.zh: 传文件、做备份。断了能续，只传变化的部分。
# includes: rsync
# includes.zh: rsync 主程序
# disk: 2M
# memory: 0
. /usr/lib/app-setup/common.sh

PKGS="rsync"
CHECK_BIN="rsync"

version_line() { rsync --version 2>/dev/null | head -1 | cut -c1-46; }

do_help() { cat <<'EOF'
rsync

  From your laptop to here
    rsync -avz --progress ./site/ user@thishost:/var/www/html/

  From here to somewhere else (a backup)
    rsync -avz /data/ user@backup:/backups/thismachine/

  The flags, once
    -a   keep permissions, times, symlinks — nearly always what you want
    -v   say what it is doing
    -z   compress in flight; helps on a slow link, wastes CPU on a fast one
    --progress          show the transfer as it goes
    --delete            make the destination match exactly, removing extras
    --dry-run           show what would happen and change nothing

  The trailing slash is not decoration
    rsync -a src/ dst/     puts the *contents* of src into dst
    rsync -a src  dst/     puts a directory called src inside dst
    Getting this wrong is the most common rsync mistake there is. Use
    --dry-run the first time.

  Resuming a big file
    rsync -avz --partial --append-verify big.iso user@host:/data/

  Over a non-standard SSH port
    rsync -avz -e 'ssh -p 2222' ./site/ user@host:/var/www/html/
EOF
}

app_main "$@"
