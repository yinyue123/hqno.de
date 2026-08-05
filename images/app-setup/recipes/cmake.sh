#!/bin/sh
# app-setup: 1
# id: cmake
# name: CMake
# name.zh: CMake
# category: dev
# order: 14
# summary: The build system most C++ projects on GitHub use. Bring the compiler yourself.
# summary.zh: GitHub 上多数 C++ 项目用的构建系统。编译器要另外装。
# includes: cmake, ctest, ninja where available
# includes.zh: cmake、ctest，以及可用的 ninja
# disk: 60M
# memory: 0
# requires: buildtools
. /usr/lib/app-setup/common.sh

PKGS="cmake"
CHECK_BIN="cmake"

version_line() { printf '%s' "$(cmake --version 2>/dev/null | head -1)"; }

do_install() {
	enable_crb
	pkg_install $(pmv PKGS)
	case "$PMF" in
		deb) pkg_install_optional ninja-build ;;
		rpm) pkg_install_optional ninja-build ;;
		apk) pkg_install_optional samurai ninja ;;
	esac
	have gcc || warn "there is no C compiler here yet — install the 'buildtools' source too"
	ok "$(version_line)"
}

do_help() { cat <<'EOF'
CMake

  It does not compile anything
    CMake generates build files; make or ninja then does the work, using
    gcc. Install the `buildtools` source as well or nothing here will work.

  The modern three lines
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j$(nproc)
    cmake --install build

    -B build keeps generated files out of the source tree, which means you
    can delete `build/` to start over and nothing else is touched.

  Useful options
    -DCMAKE_INSTALL_PREFIX=/usr/local     where install puts things
    -DCMAKE_BUILD_TYPE=Debug              -g, no optimisation
    -G Ninja                              use ninja: faster, better output
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON    for clangd and editor tooling

  Tests
    ctest --test-dir build --output-on-failure

  "Could NOT find Foo (missing: Foo_DIR)"
    A dependency is not installed, and it is nearly always the -dev package
    rather than the library:
      Debian/Ubuntu   apt-get install libfoo-dev
      AlmaLinux       dnf install foo-devel
      Alpine          apk add foo-dev

  "CMake 3.x or higher is required"
    The distro's cmake is older than the project wants. Get a current one
    without touching the system package:
      pip install cmake            (in a venv)
    or download the official binary from cmake.org into /opt.

  Memory
    A parallel C++ build is the most memory-hungry thing you can do on a
    small container. Each g++ process on a template-heavy file can want a
    gigabyte. If the build dies silently, drop -j and build with one job.
EOF
}

app_main "$@"
