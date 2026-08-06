#!/bin/sh
# app-setup: 1
# id: python
# name: Python 3
# name.zh: Python 3
# category: dev
# order: 11
# summary: Python with pip, venv and the headers that let pip build things that are not pure Python.
# summary.zh: Python，带 pip、venv，以及编译非纯 Python 包要用的头文件。
# includes: python3, pip, venv, python3-dev, setuptools
# includes.zh: python3、pip、venv、开发头文件、setuptools
# disk: 120M
# memory: 0
. /usr/lib/app-setup/common.sh

CHECK_BIN="python3"

version_line() {
	local _py _pip
	_py="$(python3 -V 2>&1)"
	# `... | cut -f2 || echo -` is a fallback that can never fire: when pip is
	# missing the pipeline's *last* command is cut, which succeeds on empty
	# input and exits 0. The card read "Python 3.9.25, pip" on a machine where
	# `remove python` had just taken pip away. Test the value, not the pipe.
	_pip="$(python3 -m pip --version 2>/dev/null | cut -d' ' -f2)"
	if [ -n "$_pip" ]; then printf '%s, pip %s' "$_py" "$_pip"
	else                    printf '%s, no pip' "$_py"; fi
}

do_install() {
	case "$PMF" in
		deb) pkg_install python3 python3-pip python3-venv python3-dev
		     pkg_install_optional python3-setuptools python3-wheel build-essential ;;
		rpm) pkg_install python3 python3-pip python3-devel
		     pkg_install_optional python3-setuptools python3-wheel gcc gcc-c++ make ;;
		apk) pkg_install python3 py3-pip python3-dev
		     pkg_install_optional py3-setuptools py3-wheel py3-virtualenv build-base ;;
	esac

	have python3 || die "python3 is still not on PATH"
	# `python` meaning python2 has been gone for years, and scripts that say
	# `#!/usr/bin/env python` are still everywhere.
	[ -e /usr/bin/python ] || ln -sf "$(command -v python3)" /usr/bin/python 2>/dev/null || true

	ok "$(version_line)"
	# PEP 668. The marker file is what makes `pip install` outside a venv
	# refuse, and telling somebody that now is much kinder than letting them
	# meet "error: externally-managed-environment" on their own.
	#
	# The glob has to be walked rather than tested: `[ -f /usr/lib/python3*/X ]`
	# is a syntax error the moment two Python versions are installed, because
	# the shell expands it into two arguments before `[` ever runs.
	for _m in /usr/lib/python3*/EXTERNALLY-MANAGED /usr/lib/python3/EXTERNALLY-MANAGED; do
		[ -f "$_m" ] || continue
		info "this Python refuses system-wide pip installs; use a venv — see the docs button"
		break
	done
}

do_uninstall() {
	case "$PMF" in
		deb) pkg_remove python3-pip python3-venv python3-dev ;;
		rpm) pkg_remove python3-pip python3-devel ;;
		apk) pkg_remove py3-pip python3-dev ;;
	esac
	warn "python3 itself was left installed: the package manager on this system is written in it."
}

do_help() { cat <<'EOF'
Python 3

  Check it
    python3 -V
    python3 -m pip --version

  "error: externally-managed-environment"
    On Debian 12+, Ubuntu 24.04+ and Fedora, pip refuses to install into
    the system Python. This is not a fault and the fix is not --break-
    system-packages. Make a virtual environment:

      python3 -m venv ~/myapp
      . ~/myapp/bin/activate
      pip install requests flask
      deactivate                    when you are done

    Everything installs inside ~/myapp and nothing can break the system's
    own Python — which matters here, because apt and dnf are written in it.
    Breaking the system Python on a container you cannot console into is a
    reinstall.

  Running an app permanently
    Use the venv's interpreter directly in the service file; there is no
    need to "activate" anything:

      ExecStart=/root/myapp/bin/python /opt/myapp/main.py

  A package will not build
    "fatal error: Python.h: No such file" means the headers are missing —
    python3-dev is installed here, so this usually means you are in a venv
    built against a different Python.
    "error: command 'gcc' failed" means no compiler; install the
    `buildtools` source.

  Faster installs
    pip install uv     then use `uv pip install` — the same thing, an order
    of magnitude quicker, and it makes venvs too:  uv venv

  Memory
    pip builds a wheel from source when there is no prebuilt one, and a
    large package (numpy, pandas, cryptography) can want more RAM than a
    small container has. If pip dies with no error, that is the
    out-of-memory killer. Try: pip install --only-binary :all: thepackage
EOF
}

app_main "$@"
