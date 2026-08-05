#!/bin/sh
# app-setup: 1
# id: rust
# name: Rust
# name.zh: Rust
# category: dev
# order: 15
# summary: Installed with rustup, the way the Rust project intends. cargo, rustc and rustfmt.
# summary.zh: 用官方的 rustup 安装。含 cargo、rustc、rustfmt。
# includes: rustup, cargo, rustc, clippy, rustfmt
# includes.zh: rustup、cargo、rustc、clippy、rustfmt
# disk: 1.2G
# memory: 1G
. /usr/lib/app-setup/common.sh

CHECK_FILE="/usr/local/rust/bin/cargo"
RUSTUP_HOME=/usr/local/rust
CARGO_HOME=/usr/local/rust
export RUSTUP_HOME CARGO_HOME

version_line() {
	_c="$CARGO_HOME/bin/rustc"
	[ -x "$_c" ] || _c="$(command -v rustc 2>/dev/null)"
	[ -n "$_c" ] && printf '%s' "$("$_c" --version 2>/dev/null)"
}

do_install() {
	# rustc shells out to cc for linking, always. Without a C toolchain the
	# install succeeds and then every single build fails at the link step,
	# which is a miserable way to find out.
	have cc || have gcc || {
		step "rust needs a C linker; installing the toolchain first"
		recipe buildtools install
	}
	ensure_downloader

	step "fetching rustup"
	_tmp="$(tmp_dir)"
	fetch https://sh.rustup.rs "$_tmp/rustup.sh" || die "could not reach sh.rustup.rs"
	sh "$_tmp/rustup.sh" -y --no-modify-path --profile default >/dev/null ||
		die "rustup failed; see $_tmp/rustup.sh"
	rm -rf "$_tmp"

	# Installed under /usr/local rather than one user's home, so a service
	# account and root see the same toolchain.
	cat > /etc/profile.d/rust.sh <<EOF
# written by app-setup
export RUSTUP_HOME=$RUSTUP_HOME
export CARGO_HOME=$CARGO_HOME
export PATH=\$PATH:$CARGO_HOME/bin
EOF
	chmod 644 /etc/profile.d/rust.sh
	for _b in cargo rustc rustup rustfmt clippy-driver cargo-clippy; do
		[ -x "$CARGO_HOME/bin/$_b" ] && ln -sf "$CARGO_HOME/bin/$_b" "/usr/local/bin/$_b"
	done

	ok "$(version_line)"
	info "open a new shell, or run:  . /etc/profile.d/rust.sh"
}

do_uninstall() {
	if [ -x "$CARGO_HOME/bin/rustup" ]; then
		"$CARGO_HOME/bin/rustup" self uninstall -y >/dev/null 2>&1 || true
	fi
	rm -rf "$RUSTUP_HOME" /etc/profile.d/rust.sh
	for _b in cargo rustc rustup rustfmt clippy-driver cargo-clippy; do
		rm -f "/usr/local/bin/$_b"
	done
}

do_help() { cat <<'EOF'
Rust

  Check it
    rustc --version
    cargo --version
    If those are not found straight after installing, your shell has not
    re-read the profile: . /etc/profile.d/rust.sh

  A first project
    cargo new hello && cd hello
    cargo run
    cargo build --release        the optimised binary, in target/release/

  Installing someone's tool
    cargo install ripgrep
    It compiles from source, which on a small container takes a while and a
    lot of memory. Many popular tools also ship a prebuilt binary on their
    GitHub releases page — check there first.

  Where it is installed
    /usr/local/rust      the toolchain, shared by every user on this machine
    That is deliberate: the default rustup layout puts everything in one
    user's home, and then a service running as another user cannot build.

  Updating
    rustup update

  Disk and memory, honestly
    A Rust toolchain is about 1.2GB installed, and `cargo build` on a
    medium project wants close to a gigabyte of RAM. Both numbers are
    larger than any other entry in this catalogue. On a 512MB container,
    linking will be killed. Build elsewhere and copy the binary across —
    a release binary has no runtime dependencies beyond libc, which is what
    makes Rust pleasant to deploy in the first place.

  Alpine
    Targets musl, which means `cargo build --release` produces a fully
    static binary with no extra flags. That is a genuine advantage of
    building here.

  target/ eats the disk
    Every project keeps its build artefacts in target/, and they are large.
    cargo clean, or delete the directory.
EOF
}

app_main "$@"
