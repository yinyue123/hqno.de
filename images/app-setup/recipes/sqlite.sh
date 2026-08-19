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
# param: paths | | Database files | 数据库文件 |
# param: backup | default | Backup | 备份 | default,dump,files
# action: paths | backup | ▶ Back up now | ▶ 立即备份
. /usr/lib/app-setup/common.sh

PKGS="sqlite3"
PKGS_rpm="sqlite"
PKGS_apk="sqlite"
CHECK_BIN="sqlite3"

version_line() { printf 'SQLite %s' "$(sqlite3 --version 2>/dev/null | cut -d' ' -f1)"; }

# -------------------------------------------------------- dump/load/backup --
# SQLite has no server, so there is nothing to stop and nothing to ask — but
# there is also no fixed place its data lives. A database is a file, and only
# the holder knows which files. So this one recipe has to be told, in Settings:
#
#   /data/app.db, /var/www/typecho/usr/*.db
#
# Copying a live SQLite file with cp is the classic way to get a corrupt
# backup: a writer mid-transaction leaves the copy torn. `.backup` goes through
# SQLite's own online backup API and is safe while something else has the file
# open, which is why nothing here uses cp.
sqlite_paths() {
	local _p _out
	_out=""
	# Unquoted on purpose — the setting may hold globs, and this is where they
	# are meant to expand.
	for _p in $(param paths | tr ',' ' '); do
		for _f in $_p; do [ -f "$_f" ] && _out="$_out $_f"; done
	done
	printf '%s' "${_out# }"
}

sqlite_safe_copy() {  # sqlite_safe_copy <db> <dest>
	sqlite3 "$1" ".backup '$2'" 2>/dev/null ||
		die "could not copy $1 — is it a SQLite database, and is the disk full?"
	# An unreadable backup that is the right size is the failure this catches.
	[ "$(sqlite3 "$2" 'PRAGMA integrity_check;' 2>/dev/null)" = ok ] ||
		die "the copy of $1 does not pass integrity_check; refusing to call that a backup"
}

do_backup() {
	local _dst _f _list _n
	_list="$(sqlite_paths)"
	[ -n "$_list" ] || die "no database files listed. Put them in Settings, comma separated — e.g. /data/app.db, /var/www/*/usr/*.db"
	bk_begin sqlite
	_n=0
	for _f in $_list; do
		_n=$((_n + 1))
		step "copying $_f"
		_dst="$BK_WORK/$BK_PREFIX/files$(dirname "$_f")"
		mkdir -p "$_dst"
		sqlite_safe_copy "$_f" "$_dst/$(basename "$_f")"
	done
	info "$_n database$([ "$_n" = 1 ] || printf s) checked and copied"
	bk_finish
}

do_restore() {
	local _d
	bk_open sqlite "${1-}"
	_d="$BK_UNPACKED"
	[ -d "$_d/files" ] || die "that archive has no databases in it"
	warn "this overwrites the files it saved, wherever they were"
	bk_restore_files "$_d"
	bk_close
	ok "restored"
}

# One .sql of plain CREATE/INSERT per database — readable, greppable, and the
# only form that survives a SQLite version old enough to refuse the file.
do_dump() {
	local _f _list _n _out
	_list="${1:-$(sqlite_paths)}"
	[ -n "$_list" ] || die "no database files listed. Name one, or put them in Settings: sh /etc/app-setup/sqlite.sh dump /data/app.db"
	_n=0
	for _f in $_list; do
		[ -f "$_f" ] || die "no such database: $_f"
		# printf rather than piping basename straight in: its trailing newline
		# is not in the allowed set, so tr would turn it into a second
		# underscore and every dump would be named app.db__20260819040230.sql.
		_out="$(dump_target "sqlite-$(printf '%s' "$(basename "$_f")" | tr -c 'a-zA-Z0-9._-' '_')" sql)"
		step "dumping $_f"
		sqlite3 "$_f" .dump > "$_out" || die "could not dump $_f"
		[ -s "$_out" ] || die "the dump of $_f came out empty"
		chmod 600 "$_out"
		ok "$_out  ($(du -h "$_out" 2>/dev/null | awk '{print $1}'))"
		_n=$((_n + 1))
	done
	info "put one back with:  sh /etc/app-setup/sqlite.sh load <file.sql> <target.db>"
}

# Both halves have to be named: a .sql does not say which database it came
# from, and guessing would be how somebody overwrites the wrong one.
do_load() {
	local _db _sql
	_sql="${1-}"; _db="${2-}"
	if [ -z "$_sql" ] || [ -z "$_db" ]; then
		echo "Loading a SQLite dump needs both halves — the .sql and where it goes:"
		echo
		echo "    sh /etc/app-setup/sqlite.sh load <file.sql> <target.db>"
		echo
		echo "Dumps in $DUMP_DIR:"
		ls -1 "$DUMP_DIR"/sqlite-*.sql 2>/dev/null | sed 's|^|    |' ||
			echo "    (none yet — app-setup dump sqlite)"
		echo
		echo "To put whole databases back exactly as they were, use the archive"
		echo "instead, which knows where each one lived:  app-setup restore sqlite"
		return 0
	fi
	[ -f "$_sql" ] || _sql="$DUMP_DIR/$_sql"
	[ -f "$_sql" ] || die "no such dump: ${1}"
	[ -e "$_db" ] && { mv "$_db" "$_db.before-load.$(date -u +%Y%m%d%H%M%S)"; warn "the old $_db was moved aside, not deleted"; }
	step "loading $_sql into $_db"
	sqlite3 "$_db" < "$_sql" || die "the import failed"
	ok "loaded"
}

do_help() { cat <<'EOF'
SQLite

  There is no server
    No service to start, no port, no password, no user accounts. A database
    is a file. Programs open it directly. That is the entire model, and for
    a blog, a small shop or anything with one machine and moderate traffic,
    it is the right one.

  Put the file on /data
    A reinstall of this container replaces the whole root filesystem and
    keeps /data. So a database at /data/mysite.db survives one and the same
    file at /var/lib/mysite.db does not. `app-setup doctor` says whether
    this container has a data disk at all; without one, nothing on it
    survives a reinstall and the only copy that does is a backup.

  Use it
    sqlite3 /data/mysite.db
    sqlite> CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);
    sqlite> INSERT INTO notes (body) VALUES ('hello');
    sqlite> SELECT * FROM notes;
    sqlite> .quit

  Backing it up
    A SQLite database is a file, so app-setup has to be told which files.
    Open Settings and list them, comma separated — globs are fine:

        /data/app.db, /var/www/*/usr/*.db

    Then:
      app-setup backup sqlite      all of them, into one dated .tgz
      app-setup restore sqlite     each one back where it came from
      app-setup dump sqlite        one plain .sql per database
      sh /etc/app-setup/sqlite.sh load <file.sql> <target.db>

    It copies with SQLite's own `.backup`, not `cp`. Copying a database
    file while something has it open gives you a torn file that looks
    perfectly fine until the day you need it; `.backup` goes through the
    online backup API and is safe on a live database. Every copy is then
    checked with PRAGMA integrity_check before it goes into the archive.

    Install `Backup` as well and this runs on a schedule and uploads.

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
