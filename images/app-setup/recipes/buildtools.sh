#!/bin/sh
# app-setup: 1
# id: buildtools
# name: C / C++ toolchain
# name.zh: C/C++ 编译工具链
# category: dev
# order: 10
# summary: gcc, g++, make, gdb and the headers. What "./configure && make" needs, and what pip needs to build wheels.
# summary.zh: gcc、g++、make、gdb 和头文件。./configure && make 靠它，pip 编译扩展也靠它。
# includes: gcc, g++, make, gdb, pkg-config, libc headers, autotools
# includes.zh: gcc、g++、make、gdb、pkg-config、libc 头文件、autotools
# disk: 300M
# memory: 512M
. /usr/lib/app-setup/common.sh

CHECK_BIN="gcc"

version_line() {
	printf '%s, make %s' \
		"$(gcc --version 2>/dev/null | head -1 | sed 's/ (.*)//')" \
		"$(make --version 2>/dev/null | head -1 | sed 's/GNU Make //')"
}

do_install() {
	case "$PMF" in
		deb) pkg_install build-essential
		     pkg_install_optional gdb pkg-config autoconf automake libtool patch file ;;
		rpm) enable_crb
		     pkg_install gcc gcc-c++ make
		     pkg_install_optional gdb pkgconf-pkg-config autoconf automake libtool patch file glibc-devel ;;
		apk) pkg_install build-base
		     pkg_install_optional gdb pkgconf autoconf automake libtool patch file linux-headers musl-dev ;;
	esac
	have gcc || die "gcc is still not on PATH"
	ok "$(version_line)"
}

do_uninstall() {
	case "$PMF" in
		deb) pkg_remove build-essential gdb ;;
		rpm) pkg_remove gcc gcc-c++ gdb ;;
		apk) pkg_remove build-base gdb ;;
	esac
	warn "other software may have been built against these headers; it keeps working, but will not rebuild."
}

do_help() { cat <<'EOF'
C / C++ toolchain

  What it is for
    Three quite different jobs, all of which fail without it:
      - building software from source: ./configure && make && make install
      - pip installing a Python package that has a C extension
      - npm installing a module with a native part (node-gyp)
    If you have seen "gcc: command not found" or "Python.h: No such file",
    this is the answer.

  Build something from source
    ./configure --prefix=/usr/local
    make -j$(nproc)
    make install

    -j$(nproc) uses every core. On a small container it also multiplies
    memory use — if the compiler is killed with no message, build with
    plain `make` instead.

  A CMake project
    Install the `cmake` source too, then:
      cmake -B build -DCMAKE_BUILD_TYPE=Release
      cmake --build build -j$(nproc)

  Missing library headers
    "fatal error: openssl/ssl.h: No such file" is not a missing compiler —
    it is a missing -dev package:
      Debian/Ubuntu   apt-get install libssl-dev
      AlmaLinux       dnf install openssl-devel      (with CRB enabled,
                                                      which this did)
      Alpine          apk add openssl-dev
    The pattern is lib<name>-dev, <name>-devel, <name>-dev respectively.

  Debugging
    gcc -g -O0 -o prog prog.c
    gdb ./prog
      run / bt / print x / quit
    In a container, ptrace may be restricted — if gdb cannot attach to a
    running process, that is the host's policy and not something you can
    fix from in here.

  Alpine is musl, not glibc
    Code that assumes glibc extensions will not compile unchanged. Common
    ones: no <execinfo.h> backtrace, no gnu_get_libc_version, different
    behaviour from strerror_r. This is the trade for Alpine's small size.
    linux-headers and musl-dev were installed here, which covers most of it.

  Disk
    Around 300MB, and it is the single largest thing in this catalogue after
    a JDK. Uninstalling it does not break already-built software.
EOF
}

app_main "$@"
