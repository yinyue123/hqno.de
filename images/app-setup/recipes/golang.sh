#!/bin/sh
# app-setup: 1
# id: golang
# name: Go
# name.zh: Go 语言
# category: dev
# order: 12
# summary: The current Go from go.dev, not the four-year-old one in the distro repository.
# summary.zh: 从 go.dev 装当前版本，不是发行版仓库里那个四年前的。
# includes: the go toolchain in /usr/local/go, on everyone's PATH
# includes.zh: Go 工具链装在 /usr/local/go，并加入所有用户的 PATH
# disk: 550M
# memory: 0
. /usr/lib/app-setup/common.sh

CHECK_FILE="/usr/local/go/bin/go"
CHECK_BIN_apk="go"
GOROOT=/usr/local/go

version_line() {
	_g="$GOROOT/bin/go"
	[ -x "$_g" ] || _g="$(command -v go 2>/dev/null)"
	[ -n "$_g" ] && printf '%s' "$("$_g" version 2>/dev/null | cut -d' ' -f3,4)"
}

do_install() {
	# Alpine's own package is current and links against musl, which the
	# official tarball does not: a cgo build there would fail confusingly.
	if [ "$PMF" = apk ]; then
		pkg_install go
		ok "$(version_line)"
		return 0
	fi

	ensure_downloader
	step "asking go.dev for the current release"
	_ver="$(fetch_stdout 'https://go.dev/VERSION?m=text' 2>/dev/null | head -1)"
	case "$_ver" in
		go*) ;;
		*)   die "could not reach go.dev — is this machine online?" ;;
	esac
	info "$_ver"

	if [ -x "$GOROOT/bin/go" ] && [ "$("$GOROOT/bin/go" version | cut -d' ' -f3)" = "$_ver" ]; then
		ok "$_ver is already installed"
		return 0
	fi

	_tmp="$(tmp_dir)"
	_url="https://go.dev/dl/${_ver}.linux-${ARCH}.tar.gz"
	step "downloading $_url"
	fetch "$_url" "$_tmp/go.tgz" || die "download failed"

	step "unpacking into $GOROOT"
	rm -rf "$GOROOT"
	tar -C /usr/local -xzf "$_tmp/go.tgz"
	rm -rf "$_tmp"

	# A login shell has to find it. /etc/profile.d is read by every shell we
	# ship; the symlinks are for anything that runs with a fixed PATH, like
	# a systemd unit.
	cat > /etc/profile.d/golang.sh <<'EOF'
# written by app-setup
export GOROOT=/usr/local/go
export PATH=$PATH:/usr/local/go/bin:${GOPATH:-$HOME/go}/bin
EOF
	chmod 644 /etc/profile.d/golang.sh
	ln -sf "$GOROOT/bin/go" /usr/local/bin/go
	ln -sf "$GOROOT/bin/gofmt" /usr/local/bin/gofmt

	ok "$(version_line)"
	info "open a new shell, or run:  . /etc/profile.d/golang.sh"
}

do_uninstall() {
	if [ "$PMF" = apk ]; then pkg_remove go; return 0; fi
	rm -rf "$GOROOT" /etc/profile.d/golang.sh /usr/local/bin/go /usr/local/bin/gofmt
	info "$HOME/go — modules you downloaded and binaries you installed — was left alone"
}

do_help() { cat <<'EOF'
Go

  Check it
    go version
    If that says "command not found" right after installing, your shell has
    not re-read the profile. Run: . /etc/profile.d/golang.sh

  A first program
    mkdir -p /opt/hello && cd /opt/hello
    go mod init hello
    cat > main.go <<'END'
    package main
    import "fmt"
    func main() { fmt.Println("hello") }
    END
    go run .
    go build -o hello .

  Building something for this machine from someone else's source
    git clone https://github.com/someone/thing
    cd thing
    go build ./...          or:  go install ./cmd/thing@latest

  Running it as a service
    A Go binary is one static file with no runtime to install, which makes
    the unit trivial:

      [Service]
      ExecStart=/usr/local/bin/mything
      Restart=on-failure
      User=nobody

    On Alpine, use the `supervisor` source or write an OpenRC script.

  Cross compiling — this is where Go earns its keep
    GOOS=linux GOARCH=arm64 go build -o mything-arm64 .
    GOOS=windows go build -o mything.exe .
    No toolchain to install for either.

  Where things are
    /usr/local/go      the toolchain      (on Alpine: the distro package)
    ~/go/pkg/mod       downloaded modules — this grows; `go clean -modcache`
    ~/go/bin           what `go install` puts on your PATH

  Behind a firewall or in a region where proxy.golang.org is slow
    export GOPROXY=https://goproxy.cn,direct
    Put it in /etc/profile.d/golang.sh to make it stick.

  Alpine
    You get Alpine's own package, which is current and — unlike the tarball
    from go.dev — is built against musl. Downloading the official build on
    Alpine produces a toolchain that cannot link anything using cgo.
EOF
}

app_main "$@"
