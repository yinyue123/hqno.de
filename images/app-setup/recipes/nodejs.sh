#!/bin/sh
# app-setup: 1
# id: nodejs
# name: Node.js
# name.zh: Node.js
# category: dev,web
# order: 10
# summary: JavaScript on the server, from NodeSource so it is a current LTS and not a museum piece.
# summary.zh: 服务端 JavaScript。走 NodeSource 装当前 LTS 版，不是仓库里那个老古董。
# includes: node, npm, npx, build tools for native modules
# includes.zh: node、npm、npx，以及编译原生模块要用的工具
# disk: 130M
# memory: 60M
. /usr/lib/app-setup/common.sh

CHECK_BIN="node"
NODE_MAJOR=22

version_line() {
	printf 'node %s, npm %s' "$(node -v 2>/dev/null)" "$(npm -v 2>/dev/null || echo '-')"
}

do_install() {
	case "$PMF" in
	apk)
		# Alpine tracks upstream closely enough that its own package is current.
		pkg_install nodejs npm
		;;
	deb)
		ensure_downloader
		step "adding the NodeSource repository for Node $NODE_MAJOR"
		if fetch_stdout "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" > /tmp/nodesource.sh 2>/dev/null; then
			pkg_install ca-certificates gnupg
			sh /tmp/nodesource.sh >/dev/null 2>&1 || warn "the NodeSource script failed"
			rm -f /tmp/nodesource.sh
			apt-get install -y nodejs || {
				warn "NodeSource install failed; falling back to the distro's own node"
				pkg_install nodejs npm
			}
		else
			warn "could not reach deb.nodesource.com; using the distro's node instead"
			pkg_install nodejs npm
		fi
		;;
	rpm)
		ensure_downloader
		step "adding the NodeSource repository for Node $NODE_MAJOR"
		if fetch_stdout "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" > /tmp/nodesource.sh 2>/dev/null; then
			sh /tmp/nodesource.sh >/dev/null 2>&1 || warn "the NodeSource script failed"
			rm -f /tmp/nodesource.sh
			$PM install -y nodejs || {
				warn "NodeSource install failed; falling back to the distro's own node"
				pkg_install nodejs npm
			}
		else
			warn "could not reach rpm.nodesource.com; using the distro's node instead"
			pkg_install nodejs npm
		fi
		;;
	esac

	have node || die "node is still not on PATH; the install did not take"

	# Half of npm install fails without a C toolchain, because half of npm is
	# a thin wrapper around a C library.
	case "$PMF" in
		deb) pkg_install_optional build-essential python3 ;;
		rpm) pkg_install_optional gcc gcc-c++ make python3 ;;
		apk) pkg_install_optional build-base python3 ;;
	esac

	# npm's global prefix defaults somewhere root-owned; this is the shape
	# that does not need sudo for `npm i -g` later.
	npm config set fund false --global >/dev/null 2>&1 || true
	npm config set audit false --global >/dev/null 2>&1 || true

	ok "$(version_line)"
}

do_uninstall() {
	pkg_remove nodejs npm
	rm -f /etc/apt/sources.list.d/nodesource.list /etc/yum.repos.d/nodesource*.repo
	info "anything under /usr/lib/node_modules that npm -g installed was left in place"
}

do_help() { cat <<'EOF'
Node.js

  Check it
    node -v
    npm -v

  Running an app so it survives you logging out
    Do not use `node app.js &`. Use one of:

    systemd (Debian, Ubuntu, AlmaLinux, Rocky, CentOS):
      /etc/systemd/system/myapp.service

        [Unit]
        Description=my app
        After=network.target
        [Service]
        WorkingDirectory=/opt/myapp
        ExecStart=/usr/bin/node /opt/myapp/index.js
        Restart=on-failure
        Environment=NODE_ENV=production
        [Install]
        WantedBy=multi-user.target

      systemctl daemon-reload && systemctl enable --now myapp

    Alpine, or if you prefer: install the `supervisor` source.

  Putting it on the internet
    Do not expose node's port directly. Install `nginx` or `caddy` and
    proxy to it — you get TLS, compression and a sane place for logs.

      Caddy:  example.com { reverse_proxy 127.0.0.1:3000 }
      Nginx:  location / { proxy_pass http://127.0.0.1:3000;
                           proxy_set_header Host $host;
                           proxy_set_header Upgrade $http_upgrade;
                           proxy_set_header Connection "upgrade"; }
      The two Upgrade lines are what makes websockets work; leaving them out
      is the most common "it works locally but not through nginx" report.

  Version
    This installs the current LTS (Node 22) from NodeSource, because the
    version in a distro's own repository is often years old. Alpine is the
    exception — its package is current, so that is what you get there.

  Several versions at once
    Install fnm or nvm as your normal user:
      curl -fsSL https://fnm.vercel.app/install | bash

  Memory
    A container with 512MB will kill `npm install` on a large project. If
    the build dies with no message, that is what happened — check the
    memory line at the top of app-setup.
EOF
}

app_main "$@"
