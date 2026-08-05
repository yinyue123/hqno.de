#!/bin/sh
# app-setup: 1
# id: sqlite
# name: SQLite
# name.zh: SQLite
# category: db
# order: 15
# summary: A database that is one file and no service. For most small sites this is the right answer.
# summary.zh: 一个文件就是一个数据库，不用起服务。小站点其实用它就够了。
# includes: the sqlite3 command line tool
# includes.zh: sqlite3 命令行工具
# disk: 8M
# memory: 0
. /usr/lib/app-setup/common.sh

PKGS="sqlite3"
PKGS_rpm="sqlite"
PKGS_apk="sqlite"
CHECK_BIN="sqlite3"

version_line() { printf 'SQLite %s' "$(sqlite3 --version 2>/dev/null | cut -d' ' -f1)"; }

do_help() { cat <<'EOF'
SQLite

  There is no server
    No service to start, no port, no password, no user accounts. A database
    is a file. Programs open it directly. That is the entire model, and for
    a blog, a small shop or anything with one machine and moderate traffic,
    it is the right one.

  Use it
    sqlite3 /data/mysite.db
    sqlite> CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);
    sqlite> INSERT INTO notes (body) VALUES ('hello');
    sqlite> SELECT * FROM notes;
    sqlite> .quit

  Commands worth knowing
    .tables            list tables
    .schema notes      show how a table was made
    .headers on        column names in the output
    .mode column       readable output      (.mode csv for exporting)
    .backup /data/copy.db      a consistent copy while it is in use
    .quit

  Backup
    sqlite3 /data/mysite.db ".backup /data/mysite-backup.db"
    Do not copy the file with cp while something is writing to it. Use
    .backup, which takes the right locks.
    Put the file in /data — that is the path that survives a reinstall.

  Where it stops being the right answer
    Many processes writing at once. SQLite takes a lock on the whole
    database for a write, so concurrent writers queue up and eventually
    time out. Turning on WAL mode helps a great deal and costs nothing:

      sqlite3 /data/mysite.db "PRAGMA journal_mode=WAL;"

    Readers no longer block the writer after that. If you still see
    "database is locked", you have outgrown it — install PostgreSQL.

  It will not work on a network filesystem
    NFS and SMB do not implement the locking SQLite relies on, and the
    result is a corrupted file rather than an error. Keep it on local disk.
EOF
}

app_main "$@"
