#!/bin/sh
# app-setup: 1
# id: cdn
# name: CDN front node
# name.zh: CDN 前置缓存节点
# category: web
# order: 15
# summary: Puts this machine in front of a website that lives somewhere else. Images and video are answered from here; PHP and APIs are passed straight through.
# summary.zh: 把这台机器架到别处那个网站前面。图片、视频在本机答复，PHP 和接口原样转给源站。
# includes: nginx, a cache directory on the data disk, one config file, and eight worked examples commented into it
# includes.zh: nginx、放在数据盘上的缓存目录、一个配置文件，以及写在文件末尾的八段示例
# disk: 20M
# memory: 32M
# ports: 80
# requires: nginx, and a website already running on another machine
# requires.zh: nginx；以及一个已经跑在另一台机器上的网站
# service: nginx
# param: origin  |        | Origin — domain or IP | 源站地址（域名或 IP）
# action: origin | test   | ✓ Test the origin | ✓ 测试源站
# param: port    | 80     | Origin port | 源站端口 | number
# param: cache   | static | What to cache | 缓存哪些内容 | static,site,off
# param: domain  |        | Domain on this node (blank = any) | 本机域名（留空＝全部）
# group: adv | Advanced | 高级 | collapsed
# param: proto   | auto   | Origin protocol | 回源协议 | auto,http,https
# param: listen  | 80     | Listen on | 本机监听端口 | number
# param: host    |        | Host sent to the origin | 回源时发的 Host
# param: size    | 2g     | Cache size limit | 缓存上限
# action: size   | purge  | ✗ Empty the cache now | ✗ 立即清空缓存
# param: file_ttl | 30d   | Keep files for | 静态文件留多久
# param: page_ttl | 10m   | Keep pages for | 页面留多久
# param: nocache | /wp-admin,/wp-login,/wp-json,/xmlrpc.php,/api/,/admin,/login,/cart,/checkout,/my-account,/pay | Never cache these paths | 这些路径永不缓存
# param: private | wordpress_logged_in,wp_woocommerce_session,woocommerce_items_in_cart,comment_author,PHPSESSID,laravel_session | Signed-in cookies | 登录状态 Cookie
#
# What this is, and why it is a recipe rather than a page in the manual.
#
# docs/deploy-website-cdn.md sells two containers: a small one on a line that
# is fast into China, and a big cheap one that holds the actual site. The small
# one runs nginx, caches what it can and forwards the rest. That page ends in
# eighty lines of nginx config a person is asked to type correctly, into a file
# whose path differs by distro, with an upstream address, a cookie map and
# three location blocks — and the failure mode of getting one of them subtly
# wrong is not a 500. It is one customer being served another customer's cart,
# which nobody notices until it has happened for a week.
#
# So the eighty lines are written from four fields instead: where the site
# actually is, on which port, what to cache, and what name this machine answers
# for. Everything else has a default that is right for the common case.
#
# Three decisions worth knowing before reading the code.
#
# **`static` is the default, not `site`.** Only images, video, styles, scripts
# and fonts go on the shelf; every page, every PHP file and every API call goes
# straight to the origin with `proxy_cache off`. That is the setting nobody can
# get hurt by — the whole class of "logged-in visitor sees somebody else's
# page" needs a page to have been cached in the first place. Caching pages is a
# second decision, made deliberately, with the cookie list in front of you.
#
# **The holder's own locations live in /etc/nginx/cdn.d/, and this recipe never
# touches that directory.** Install and Save & Apply rewrite the generated file
# whole — that is what makes the Settings form honest — so a holder who edits
# it loses the edit at the next keypress. cdn.d is included inside the server
# block, before the generated locations, so what somebody puts there wins and
# survives. The eight examples at the bottom of the generated file are written
# to be copied into a file there.
#
# **The examples are in the config file, not only in `do_help`.** Somebody
# tuning a cache is already in an editor looking at the config; that is where
# the answer to "how do I stop caching /api" has to be. do_help says what to
# check when it is broken, which is the other question and a different moment.
. /usr/lib/app-setup/common.sh

SERVICE="nginx"

CDN_EXTRA=/etc/nginx/cdn.d

# The two long defaults, repeated from the `# param:` lines above. Giving the
# default twice is what the authoring contract asks for and it is not
# redundancy: the header is what the Settings form shows, and this is what
# `sh /etc/app-setup/cdn.sh install` uses when there is no form, no saved file
# and nothing in the environment. A recipe must never require that the form has
# been opened — and these two are the fields where an empty answer is not a
# harmless one. Change them in both places.
CDN_NOCACHE_D='/wp-admin,/wp-login,/wp-json,/xmlrpc.php,/api/,/admin,/login,/cart,/checkout,/my-account,/pay'
CDN_PRIVATE_D='wordpress_logged_in,wp_woocommerce_session,woocommerce_items_in_cart,comment_author,PHPSESSID,laravel_session'

cdn_conf()  { printf '%s/app-setup-cdn.conf' "$(nginx_conf_dir)"; }
cdn_cache() { data_path cache /var/cache/nginx/cdn; }

# Whoever nginx's workers actually run as, which is who has to be able to write
# the cache. web_user() answers php-fpm's question first and is the right
# answer for a document root; here it can differ — an Alpine box runs nginx as
# `nginx` while a php-fpm pool may be `nobody`, and a www-data left behind by
# some other package wins the fallback list. A cache directory owned by the
# wrong one is `mkdir() failed (13: Permission denied)` in the error log and a
# MISS that never becomes a HIT.
cdn_user() {
	local _u
	_u="$(awk '$1 == "user" { sub(/;.*/, "", $2); print $2; exit }' /etc/nginx/nginx.conf 2>/dev/null)"
	if [ -n "$_u" ] && id "$_u" >/dev/null 2>&1; then printf '%s' "$_u"; else web_user; fi
}

cdn_own_cache() {  # cdn_own_cache <dir>
	local _u
	_u="$(cdn_user)"
	chown -R "$_u":"$(id -gn "$_u" 2>/dev/null || printf '%s' "$_u")" "$1" 2>/dev/null || true
}

is_installed() { [ -f "$(cdn_conf)" ]; }

# ------------------------------------------------------------- the fields --

# The Settings form takes comma lists where nginx wants an alternation: a `|`
# in a `# param:` line is the header parser's own field separator, so a default
# containing one would be cut in half before this script ever runs. A comma is
# also what somebody types without being told to.
cdn_alt() {
	printf '%s' "$1" | tr ',' '\n' |
		sed 's/^[ 	]*//; s/[ 	]*$//' | grep -v '^$' |
		tr '\n' '|' | sed 's/|$//'
}

# Brackets are stripped here and put back where they are needed: an IPv6
# literal must be bracketed in `upstream … server` and in a URL, and must not
# be in `proxy_ssl_name` or in a Host header.
cdn_origin() { param origin | tr -d '[] 	'; }

cdn_is_ip() {
	case "$1" in
		*:*)       return 0 ;;   # IPv6
		*[!0-9.]*) return 1 ;;   # a letter — it is a name
		*)         return 0 ;;
	esac
}

cdn_scheme() {
	case "$(param proto auto)" in
		http)  printf 'http' ;;
		https) printf 'https' ;;
		# Nobody sets `proto` for the ordinary two cases, so the ordinary two
		# cases have to be right without it.
		*)     if [ "$(param port 80)" = 443 ]; then printf 'https'; else printf 'http'; fi ;;
	esac
}

cdn_authority() {  # what goes after `server` in the upstream, and in a URL
	local _o
	_o="$(cdn_origin)"
	case "$_o" in
		*:*) printf '[%s]:%s' "$_o" "$(param port 80)" ;;
		*)   printf '%s:%s' "$_o" "$(param port 80)" ;;
	esac
}

# Which name the origin is asked for. The origin is a normal web server with
# normal virtual hosts, so this is the field that decides whether it answers
# with the site or with somebody's default page.
#
#   set by hand     → that, always. The escape hatch for an origin whose vhost
#                     is named something the visitors never type.
#   a domain here   → $host, the name the visitor asked for. The origin serves
#                     the same site under the same name, which is the design.
#   no domain here  → visitors are arriving by IP address, so $host is an IP
#                     and no vhost will match it. Send the origin's own name
#                     instead, which is the only name we know to be right.
#   …and the origin is an IP too → $host. There is nothing better to send, and
#                     an origin addressed by IP is usually serving one site.
cdn_host_header() {
	local _h
	_h="$(param host)"
	if   [ -n "$_h" ];              then printf '%s' "$_h"
	elif [ -n "$(param domain)" ];  then printf '$host'
	elif cdn_is_ip "$(cdn_origin)"; then printf '$host'
	else cdn_origin
	fi
}

# The same question with a literal answer, for curl in do_test — `$host` is an
# nginx variable and means nothing on a command line.
cdn_test_host() {
	local _h _d
	_h="$(param host)"
	[ -n "$_h" ] && { printf '%s' "$_h"; return 0; }
	_d="$(param domain | tr ',' ' ')"
	if [ -n "$_d" ]; then set -- $_d; printf '%s' "$1"; else cdn_origin; fi
}

cdn_names() { param domain | tr ',' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Blank domain on port 80 means "answer for anything", which is one nginx
# server per address and is the same slot the plain nginx site and the three
# suites compete for.
cdn_takes_default() {
	[ -z "$(cdn_names)" ] && [ "$(param listen 80)" = 80 ]
}

version_line() {
	local _o
	_o="$(cdn_origin)"
	[ -n "$_o" ] || { printf 'no origin set yet — open Settings'; return 0; }
	case "$(param cache static)" in
		off)  printf 'proxying to %s, caching nothing' "$(cdn_authority)" ;;
		site) printf 'in front of %s, files %s, pages %s' \
		             "$(cdn_authority)" "$(param file_ttl 30d)" "$(param page_ttl 10m)" ;;
		*)    printf 'in front of %s, files %s' "$(cdn_authority)" "$(param file_ttl 30d)" ;;
	esac
}

# ---------------------------------------------------------- the config file --

cdn_write_conf() {
	local _f _pp _sni _default _names _said _nocache _private _files
	_f="$(cdn_conf)"
	_pp="$(cdn_scheme)://cdn_origin"
	_names="$(cdn_names)"
	if [ -n "$_names" ]; then _said="$_names"; else _names="_"; _said="any name (no domain set)"; fi
	_nocache="$(cdn_alt "$(param nocache "$CDN_NOCACHE_D")")"
	_private="$(cdn_alt "$(param private "$CDN_PRIVATE_D")")"
	if cdn_takes_default; then _default=" default_server"; else _default=""; fi

	# The extensions that are the same bytes for every visitor. Deliberately
	# no .json and no .xml: an API that answers at /orders.json is the exact
	# thing this recipe exists not to cache, and "it ends in .json" cannot
	# tell that apart from a static feed.
	_files='jpe?g|png|gif|webp|avif|svg|ico|bmp|css|js|mjs|map|woff2?|ttf|otf|eot|mp4|webm|ogv|mov|m4v|mp3|m4a|ogg|wav|flac|zip|tar|t?gz|bz2|xz|7z|rar|pdf|apk|ipa|exe|dmg|iso|txt'

	cat > "$_f" <<EOF
# ---------------------------------------------------------------------------
#  Written by app-setup — the \`cdn\` recipe. Install, and Save & Apply in the
#  Settings form, rewrite this file whole: edits made here do not survive.
#  本文件由 app-setup 生成，每次「保存并应用」都会被整个重写，改在这里不会保留。
#
#  Your own locations go in $CDN_EXTRA/*.conf, which is included inside the
#  server block below and which app-setup never touches. The examples at the
#  bottom of this file are written to be copied into a file there.
#  自己写的配置放到 $CDN_EXTRA/*.conf，那个目录不会被覆盖。
#
#  This machine answers for  $_said  on port $(param listen 80), and fetches
#  what it does not already have from  $(cdn_scheme)://$(cdn_authority).
#
#      app-setup docs cdn      how to use it, and what to check when it breaks
#      app-setup test cdn      is the origin reachable from here, right now
# ---------------------------------------------------------------------------

# The shelf. levels=1:2 keeps any one directory small, inactive drops what
# nobody has asked for in a week even when there is room to spare, and
# max_size is the ceiling — nginx evicts the least recently used to stay under
# it, so this never fills a disk.
proxy_cache_path $(cdn_cache) levels=1:2 keys_zone=cdn:20m
                 max_size=$(param size 2g) inactive=7d use_temp_path=off;

# A request carrying one of these cookies belongs to one person, and its answer
# must never be handed to anybody else. This is the list that stops "one
# customer sees another customer's cart" — add your own session cookie to it in
# Settings before you switch page caching on.
map \$http_cookie \$cdn_private {
    default 0;
EOF
	[ -n "$_private" ] && printf '    "~*(%s)" 1;\n' "$_private" >> "$_f"
	cat >> "$_f" <<EOF
}

# The container's front door terminates HTTPS and hands nginx plain HTTP on 80,
# so \$scheme reads http even for a visitor who typed https. Believe the header
# the front door set, and fall back to our own scheme when there is none.
map \$http_x_forwarded_proto \$cdn_scheme {
    default    \$scheme;
    "~*^https" https;
    "~*^http"  http;
}

# WebSocket, SSE and long polling pass through untouched: an upgrade request
# needs \`Connection: upgrade\`, and every other request wants \`Connection: ""\`
# so that the keepalive pool below is actually reused instead of re-handshaking.
map \$http_upgrade \$cdn_connection {
    default upgrade;
    ''      '';
}

upstream cdn_origin {
    # A name here is resolved once, when nginx starts. After a DNS change:
    #   nginx -s reload
    server $(cdn_authority);
    keepalive 32;
}

server {
    listen      $(param listen 80)$_default;
    listen      [::]:$(param listen 80)$_default;
    server_name $_names;

    access_log /var/log/nginx/cdn-access.log;
    error_log  /var/log/nginx/cdn-error.log;

    # Uploads travel to the origin through here, so this is the ceiling on what
    # a visitor may push. 0 removes the limit.
    client_max_body_size 512m;

    # ---- everything below is inherited by every location, ours and yours ----

    proxy_http_version 1.1;
    proxy_set_header Connection \$cdn_connection;
    proxy_set_header Upgrade    \$http_upgrade;

    proxy_set_header Host              $(cdn_host_header);
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$cdn_scheme;
    proxy_set_header X-Forwarded-Host  \$host;
EOF

	if [ "$(cdn_scheme)" = https ]; then
		_sni="$(param host)"
		if [ -z "$_sni" ] && ! cdn_is_ip "$(cdn_origin)"; then _sni="$(cdn_origin)"; fi
		cat >> "$_f" <<EOF

    # This hop is TLS. nginx does not verify the origin's certificate unless
    # told to (proxy_ssl_verify), which is the right trade for two containers
    # in one building — and the reason not to run this hop over the internet.
EOF
		if [ -n "$_sni" ]; then
			cat >> "$_f" <<EOF
    proxy_ssl_server_name on;
    proxy_ssl_name        $_sni;
EOF
		else
			cat >> "$_f" <<EOF

    # The origin is an IP address, so there is no name to put in the TLS
    # handshake. If it answers with the wrong site or refuses the handshake,
    # put its certificate's name in the "Host sent to the origin" field.
    proxy_ssl_server_name off;
EOF
		fi
	fi

	cat >> "$_f" <<EOF

    proxy_connect_timeout 10s;
    proxy_send_timeout    60s;
    proxy_read_timeout    60s;

    proxy_cache     cdn;
    # \$host is in the key so two domains on this node cannot collide, and
    # \$request_uri carries the query string — /list?page=2 is its own entry.
    proxy_cache_key \$host\$request_uri;
    # Ten people ask for the same uncached file: one of them goes to the origin.
    proxy_cache_lock on;
    # On expiry, ask the origin whether it changed rather than downloading it
    # again. A 304 costs nothing and this is metered traffic.
    proxy_cache_revalidate on;
    # Origin having a bad day: hand over the stale copy instead of an error,
    # and refresh it in the background rather than making somebody wait.
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
    proxy_cache_background_update on;
    # Signed in, or carrying a token: never read from the shelf, never write
    # to it. Both directions, because either one alone is the same bug.
    proxy_cache_bypass \$cdn_private \$http_authorization;
    proxy_no_cache     \$cdn_private \$http_authorization;
    # HIT / MISS / BYPASS / EXPIRED / STALE. The one header worth curling for.
    add_header X-Cache \$upstream_cache_status always;

    # Yours, and never rewritten. A prefix or regex location in here wins over
    # the generated ones below, because nginx takes the longest prefix match
    # and then the first matching regex.
    include $CDN_EXTRA/*.conf;
EOF

	if [ "$(param cache static)" = off ]; then
		cat >> "$_f" <<EOF

    # "What to cache" is off: this is a plain reverse proxy. Nothing is kept,
    # every request reaches the origin.
    location / {
        proxy_pass $_pp;
        proxy_cache off;
    }
}
EOF
	else
		if [ -n "$_nocache" ]; then
			cat >> "$_f" <<EOF

    # Never on the shelf, whatever else is: the paths where one visitor's
    # answer is wrong for everybody else. The list is a field in Settings.
    location ~* ($_nocache) {
        proxy_pass $_pp;
        proxy_cache off;
    }
EOF
		fi
		cat >> "$_f" <<EOF

    # The same bytes for every visitor, so they can sit here for $(param file_ttl 30d).
    # 206 is listed for the video-slicing example at the bottom of this file.
    # An ordinary Range request needs nothing here: with caching on, nginx
    # drops the client's Range, stores the whole file, and cuts the piece out
    # of its own copy.
    location ~* \\.($_files)\$ {
        proxy_pass $_pp;
        proxy_cache_valid 200 206 301 302 $(param file_ttl 30d);
        proxy_cache_valid 404 1m;
    }
EOF
		if [ "$(param cache static)" = site ]; then
			cat >> "$_f" <<EOF

    # Pages, for a visitor carrying none of the cookies in the map above. A
    # signed-in visitor falls through to the origin every time — that is what
    # proxy_cache_bypass is doing, and it is the whole safety of this block.
    location / {
        proxy_pass $_pp;
        proxy_cache_valid 200 301 302 $(param page_ttl 10m);
        proxy_cache_valid 404 1m;
    }
}
EOF
		else
			cat >> "$_f" <<EOF

    # Everything else — pages, PHP, APIs, anything that can be different for
    # two people — goes to the origin untouched. Switch "What to cache" to
    # \`site\` to keep pages here too, and read the cookie list first.
    location / {
        proxy_pass $_pp;
        proxy_cache off;
    }
}
EOF
		fi
	fi

	cdn_examples "$_pp" >> "$_f"
}

# The eight cases people actually arrive with. Written as comments, in the file
# somebody is already looking at, because "how do I stop caching /api" is asked
# with an editor open and not with a browser open.
cdn_examples() {
	sed "s|@PP@|$1|g" <<'EOF'

# ===========================================================================
#  EXAMPLES — everything below is a comment. Nothing here is switched on.
#  以下全部是注释，没有任何一行生效。
#
#  Copy the block you need into a file of your own, then check and reload:
#      vi /etc/nginx/cdn.d/mysite.conf
#      nginx -t && nginx -s reload
#  把需要的那一段抄进 /etc/nginx/cdn.d/mysite.conf，再执行上面两条命令。
#
#  Three things to know before copying anything:
#
#   * cdn.d is included inside the server block above, so what you write there
#     wins over the generated locations and survives Save & Apply.
#     cdn.d 里的配置优先级更高，而且「保存并应用」不会覆盖它。
#
#   * Do not write another `location / { }` there. nginx refuses to start on a
#     duplicate location. To change what the catch-all does, use the
#     "What to cache" setting instead.
#     不要在 cdn.d 里再写一个 `location / { }`，会和上面那个重复，nginx 起不来。
#     要改「其余请求」的行为，请到设置里改「缓存哪些内容」。
#
#   * Every location must repeat its own `proxy_pass`. Everything else —
#     headers, timeouts, the cookie rules — is inherited from the server block.
#     每个 location 都要自己写一行 proxy_pass；请求头、超时、Cookie 规则会自动继承。
# ===========================================================================


# --- 1 --- An API, or PHP that returns data. Never cache it.
#           API 接口、返回数据的 PHP：一律不缓存。
#
#     A cached API answer is how one customer ends up reading another
#     customer's order. While "What to cache" is `static` this is already true
#     of everything that is not a file — write it out when you move to `site`,
#     or when your API lives somewhere the "never cache" list does not name.
#     接口被缓存 = 一个用户看到另一个用户的数据。「缓存哪些内容」选 static 时，
#     除了静态文件以外本来就不缓存；改成 site 之后，或者接口路径不在「这些路径
#     永不缓存」名单里时，才需要这一段。
#
# location ~* ^/(api|v[0-9]+|graphql|rpc|webhook|oauth)/ {
#     proxy_pass @PP@;
#     proxy_cache off;
# }
#
# location ~* \.php$ {
#     proxy_pass @PP@;
#     proxy_cache off;
# }
#
#     Careful with that second block on a site whose pages *are* .php —
#     Typecho, phpBB, an old CMS with index.php in every URL. There it turns
#     page caching off completely, which may be what you want, but say it on
#     purpose.
#     注意：如果你的页面本身就是 .php（Typecho、老论坛这类），第二段会把页面
#     缓存整个关掉。可能正是你要的，但要想清楚再加。


# --- 2 --- An image host, a media library, a downloads folder: hold it for a year.
#           图床、素材库、下载目录：缓存久一点。
#
#     Files under one path that never change once uploaded. A year is not too
#     long for content that is only ever added to, and ignoring the origin's
#     own cache headers is safe *here* precisely because nothing under this
#     path is per-visitor.
#     这类目录里的文件传上去就不会变了，缓存一年也没关系；这里可以无视源站自己
#     的缓存头，因为这个目录下的东西对谁都是一样的。
#
# location ^~ /uploads/ {
#     proxy_pass @PP@;
#     proxy_cache_valid    200 206 365d;
#     proxy_ignore_headers Set-Cookie Cache-Control Expires;
#     proxy_hide_header    Set-Cookie;
# }
#
#     Changed a file and visitors still see the old one? That is the shelf
#     working. Change the filename — logo.v2.png — and you never think about
#     it again. Or empty the cache from Settings.
#     改了图片但访客还看到旧的？这就是缓存生效了。最省事的办法是换文件名
#     （logo.v2.png），或者到设置里点「立即清空缓存」。


# --- 3 --- Video on demand: mp4 and HLS.
#           点播视频：mp4 和 HLS 切片。
#
#     Without `slice`, a viewer who seeks forty minutes into a 2GB film makes
#     this node pull all 2GB from the origin before it can answer: caching
#     strips the Range header and fetches the complete file. With it, the film
#     is fetched and stored in 1MB pieces, and only the pieces somebody
#     actually watched ever cross the expensive link.
#     不加 slice 的话，有人拖到片子中间，这台机器要先把整个 2GB 从源站拉完
#     才能回答 —— 开了缓存之后 Range 头会被去掉，回源拿的是整个文件。加上
#     之后按 1MB 分块回源，只有真被人看过的那些块才走那条贵线路。
#
#     Check the module is in your build first:  nginx -V 2>&1 | grep -o slice
#     先确认 nginx 编译了这个模块：nginx -V 2>&1 | grep -o slice
#
# location ~* \.(mp4|m4v|mov|webm|mkv|ts|m4s)$ {
#     proxy_pass @PP@;
#     slice             1m;
#     proxy_set_header  Range $slice_range;
#     proxy_cache_key   $host$uri$is_args$args$slice_range;
#     proxy_cache_valid 200 206 30d;
# }
#
# location ~* \.(m3u8|mpd)$ {
#     proxy_pass @PP@;
#     proxy_cache_valid 200 5s;      # live streaming: 1s, or proxy_cache off
# }
#
#     The playlist changes and the pieces do not, so they get different rules.
#     Cache an HLS playlist for thirty days and the stream freezes on the
#     segment list it had when you started.
#     m3u8 播放列表会变、ts 切片不会变，所以规则不同。播放列表缓存久了，直播
#     会卡在你开播那一刻的切片列表上。


# --- 4 --- WordPress, WooCommerce, any shop with a login.
#           WordPress、商城，凡是有登录和购物车的站。
#
#     Most of this is settings, not config. In Settings:
#       What to cache      → site
#       Signed-in cookies  → add your own session cookie if the theme sets one
#       Never cache        → the defaults already name wp-admin, cart, checkout
#     大部分是在设置里点，不用写配置：「缓存哪些内容」改成 site，把主题自己
#     用的 session Cookie 加进「登录状态 Cookie」，「永不缓存」的默认名单已经
#     包含了 wp-admin、cart、checkout。
#
#     Then test it, and test it in this exact order — this is the one failure
#     that costs a customer rather than a second:
#       1. log in, put something in the cart
#       2. open the same page in a private window
#       3. if it shows your cart, stop and fix the cookie list
#     然后一定要这样验一遍：登录、加购物车，再开一个无痕窗口打开同一个页面。
#     如果无痕窗口里看到了你的购物车，立刻回去改 Cookie 名单。
#
#     The comment feed and the sitemap are the two that surprise people:
#
# location ~* ^/(feed/?|.*sitemap.*\.xml)$ {
#     proxy_pass @PP@;
#     proxy_cache_valid 200 1h;
# }


# --- 5 --- Always MISS, never HIT.
#           一直是 MISS，从来没有 HIT。
#
#     Nearly always the origin: it sends `Set-Cookie` or `Cache-Control:
#     no-cache` on every response, often because a plugin starts a session on
#     every page. nginx obeys, correctly.
#     基本都是源站的问题：它给每个响应都带了 Set-Cookie 或者 no-cache，多半是
#     某个插件每页都开 session。nginx 照做了，这是对的。
#
#     Overriding it for *files* is safe — a PNG is the same PNG for everybody.
#     Overriding it for pages is how you leak one visitor's page to the next.
#     对静态文件可以强行忽略，图片对谁都一样；对页面这么干，就会把一个人的页面
#     发给下一个人。
#
# location ~* \.(jpe?g|png|gif|webp|avif|svg|ico|css|js|woff2?)$ {
#     proxy_pass @PP@;
#     proxy_ignore_headers Set-Cookie Cache-Control Expires;
#     proxy_hide_header    Set-Cookie;
#     proxy_cache_valid    200 30d;
# }
#
#     Check which it is before changing anything:
#     先看清楚到底是哪一种：
#       curl -sI https://your-origin/logo.png | grep -iE 'set-cookie|cache-control'


# --- 6 --- Big downloads, WebSocket, SSE: pass through, do not spool.
#           大文件下载、WebSocket、SSE：直接穿过去，不要缓冲。
#
#     With buffering on, nginx reads from the origin as fast as the origin will
#     go and spools whatever the visitor has not taken yet — into memory, then
#     onto this node's disk. That is right for a 40KB page, and wrong for a 4GB
#     ISO and for a connection meant to stay open and dribble one event at a
#     time. WebSocket upgrades already work everywhere on this node, from the
#     Connection/Upgrade map at the top of this file; these two locations only
#     turn off the spooling and the timeout.
#     开着缓冲的时候，nginx 会用源站给得起的最快速度读，访客还没取走的部分先
#     堆在内存里、再堆到本机磁盘上。对 40KB 的页面这是对的，对 4GB 的镜像、
#     以及需要一直开着一条一条往外吐的长连接就不对了。WebSocket 的升级握手本来
#     就能过（文件开头那个 map 管的），这两段只是关掉落盘和超时。
#
# location ^~ /download/ {
#     proxy_pass @PP@;
#     proxy_cache off;
#     proxy_buffering off;
#     proxy_max_temp_file_size 0;
#     proxy_read_timeout 1h;
# }
#
# location ^~ /ws/ {
#     proxy_pass @PP@;
#     proxy_cache off;
#     proxy_buffering off;
#     proxy_read_timeout 1h;
# }


# --- 7 --- The origin answers with the wrong site, or with a redirect loop.
#           源站返回了别的站点，或者一直在跳转。
#
#     Both are the Host header. The origin is a normal web server with normal
#     virtual hosts and it picks the site by the name it is asked for.
#     两个都是 Host 头的问题。源站是普通的 web 服务器，靠 Host 决定给哪个站。
#
#       wrong site   → the origin has several vhosts and none matched. Put the
#                      right name in "Host sent to the origin" in Settings.
#       redirect loop→ the origin is redirecting to its own name. Leave the
#                      Host field blank so visitors' own name is forwarded.
#       返回了别的站 → 在设置里把「回源时发的 Host」填成源站上那个站点的域名。
#       一直在跳转   → 把那个字段留空，让访客用的域名原样转过去。
#
#     See what the origin actually thinks it is:
#     直接问源站它以为自己是谁：
#       curl -sI -H 'Host: www.example.com' http://ORIGIN-IP/ | head -5


# --- 8 --- Hotlink protection, and fonts blocked by CORS.
#           防盗链，以及字体被跨域拦下来。
#
#     Somebody else's page embedding your images is your traffic quota paying
#     for their site. `none` and `blocked` keep direct hits and stripped
#     referers working, which is what a browser sends for a bookmark.
#     别人的网页直接引你的图，花的是你的流量。none 和 blocked 两项保证直接访问、
#     以及浏览器没带 referer 的情况仍然正常。
#
# location ~* \.(jpe?g|png|gif|webp|mp4)$ {
#     valid_referers none blocked server_names *.example.com;
#     if ($invalid_referer) { return 403; }
#     proxy_pass @PP@;
#     proxy_cache_valid 200 206 30d;
# }
#
#     A font served from this node to a page on another name needs the header.
#     `always` puts it on the error responses too — without it a 403 from the
#     rule above, or a 404, comes back bare, and the browser reports a CORS
#     failure instead of the status that actually happened.
#     跨域引用的字体需要这个头。always 的意思是错误响应上也带 —— 不加的话，
#     上面那条防盗链返回的 403、或者一个 404，头上什么都没有，浏览器只会报
#     跨域失败，看不到真正发生了什么。
#
# location ~* \.(woff2?|ttf|otf|eot)$ {
#     proxy_pass @PP@;
#     add_header Access-Control-Allow-Origin "*" always;
#     add_header X-Cache $upstream_cache_status always;
#     proxy_cache_valid 200 365d;
# }
#
#     Note the second add_header. A location that declares one stops inheriting
#     the server's, so X-Cache has to be repeated or it disappears from exactly
#     the responses you were trying to debug.
#     注意那第二行：一个 location 只要自己写了 add_header，就不再继承 server 里
#     的，所以 X-Cache 要重写一遍，否则你正想调试的那些响应上恰好没有它。
EOF
}

# --------------------------------------------------------------- the verbs --

do_install() {
	local _o _cache
	_o="$(cdn_origin)"
	[ -n "$_o" ] || die "no origin yet. Open Settings and type the domain or IP of the machine your website is actually on."

	# The trap from docs/deploy-website-cdn.md §10, caught before it is built
	# rather than explained afterwards: a front node pointed at its own address
	# proxies to itself, and every request loops until nginx gives up. It looks
	# like the origin being down, which is the wrong thing to go and check.
	if [ "$(param port 80)" = "$(param listen 80)" ]; then
		case "$_o" in
			127.0.0.1|localhost|::1|"$(guess_host)")
				die "the origin is this machine on the port this machine listens on, which would proxy to itself in a loop. The origin is the *other* container — the one the website is on." ;;
		esac
	fi

	# Before anything is downloaded. Refusing here is the difference between a
	# sentence and an nginx that will not start.
	cdn_takes_default && web_claim_default cdn

	# Five steps with the default-site one, four without. A bar that stops at
	# four fifths is worse than no bar.
	if cdn_takes_default; then step_total 5; else step_total 4; fi
	step "making sure nginx is here"
	recipe_ensure nginx

	_cache="$(cdn_cache)"
	step "cache directory: $_cache"
	# A cache is by definition re-fetchable, so it does not get the
	# data_warn treatment the databases get — but on a container with a data
	# disk it belongs there anyway, because that is the disk with room on it.
	mkdir -p "$_cache"
	cdn_own_cache "$_cache"
	mkdir -p "$CDN_EXTRA"

	if cdn_takes_default; then
		# No domain given, so this node answers for whatever arrives — which
		# is the same single slot nginx's own default site holds. Two
		# `default_server` blocks on one port is a config nginx refuses to
		# load at all, so the plain one goes.
		step "taking the default site on port 80"
		rm -f "$(nginx_conf_dir)/app-setup.conf"
		nginx_drop_default
	fi

	step "writing $(cdn_conf)"
	cdn_write_conf

	step "checking the config and reloading"
	svc_enable nginx
	if nginx_test_reload; then
		svc_start nginx 2>/dev/null || true
	else
		die "nginx refused the generated config; nothing is being served. The file is $(cdn_conf) and the message above says which line."
	fi

	ok "$(guess_host) is now in front of $(cdn_scheme)://$(cdn_authority)"
	case "$(param cache static)" in
		off)  info "nothing is being cached — this is a plain reverse proxy" ;;
		site) info "files are kept $(param file_ttl 30d), pages $(param page_ttl 10m) for visitors who are not signed in" ;;
		*)    info "images, video, styles and scripts are kept $(param file_ttl 30d); pages, PHP and APIs are not cached at all" ;;
	esac
	info "check it with:  app-setup test cdn"
	info "the eight worked examples are at the bottom of $(cdn_conf)"
	if [ "$(param cache static)" = site ]; then
		warn "page caching is on. Log in, add something to the cart, then open"
		warn "the same page in a private window before you point DNS at this."
	fi
}

do_uninstall() {
	local _cache
	warn "this stops proxying. The website on the origin is not touched."

	rm -f "$(cdn_conf)"

	# Put a default site back before reloading, or nginx on this container
	# answers everything with whatever is left over — and if what is left over
	# is nothing, with a 404 from no server block at all.
	if have nginx && [ ! -f "$(nginx_conf_dir)/app-setup.conf" ] && ! default_site_holder >/dev/null; then
		mkdir -p "$WEBROOT"
		cat > "$(nginx_conf_dir)/app-setup.conf" <<EOF
# written by app-setup when the cdn recipe was removed — the plain default
# site, the same one \`install nginx\` writes.
server {
    listen      80 default_server;
    listen      [::]:80 default_server;
    server_name _;
    root        $WEBROOT;
    index       index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\\. { deny all; }
}
EOF
	fi
	have nginx && { nginx_test_reload || true; }

	_cache="$(cdn_cache)"
	if [ -d "$_cache" ]; then
		rm -rf "${_cache:?}"/*
		info "the cache in $_cache was emptied — every byte in it is a copy of"
		info "something the origin still has."
	fi
	info "$CDN_EXTRA was left alone — the locations you wrote are still there."
}

# `test` is app_main's own verb, so the ✓ button in Settings needs nothing
# intercepted: `# action: origin | test | …` and `app-setup test cdn` are the
# same call. It answers the only question worth asking before pointing DNS at
# this machine — can this container reach the origin, and what does the origin
# say when it does.
do_test() {
	local _o _url _host _out _code _hdr _i
	_o="$(cdn_origin)"
	[ -n "$_o" ] || die "no origin yet. Type the domain or IP of the machine your website is on, then press this again."
	_host="$(cdn_test_host)"
	_url="$(cdn_scheme)://$(cdn_authority)/"

	have curl || have wget || ensure_downloader

	step "asking $_url for its front page, as $_host"
	if have curl; then
		_out="$(curl -sS -o /dev/null -D - -k -m 20 -H "Host: $_host" "$_url" 2>&1)"
	else
		_out="$(wget -S -O /dev/null --no-check-certificate -T 20 \
		            --header="Host: $_host" "$_url" 2>&1 | sed 's/^  //')"
	fi
	_code="$(printf '%s\n' "$_out" | awk '/^HTTP\//{c=$2} END{print c}')"

	printf '%s\n' "$_out" | grep -iE '^(HTTP/|server:|content-type:|location:|set-cookie:|cache-control:|x-cache:)' |
		sed 's/^/    /' || true

	case "$_code" in
		200)
			ok "the origin answers. This container can reach it."
			# The two answers that decide whether anything will ever be a HIT,
			# read off the response we already have rather than left for
			# somebody to discover as "always MISS" a week later.
			if printf '%s\n' "$_out" | grep -qiE '^set-cookie:'; then
				warn "it sets a cookie on its front page — pages will not cache while it does. Example 5 in $(cdn_conf) is the fix, and it is only safe for files."
			fi
			if printf '%s\n' "$_out" | grep -qiE '^cache-control:.*(no-cache|no-store|private)'; then
				warn "it says Cache-Control: no-cache, and nginx obeys that. Expect MISS on everything until the origin stops saying it, or until you override it for files the way example 5 does."
			fi
			;;
		301|302|307|308)
			ok "the origin answers, with a redirect to $(printf '%s\n' "$_out" | awk 'tolower($1)=="location:"{print $2; exit}')"
			info "that is fine if it redirects to your site's own name. If it redirects to"
			info "the origin's name, visitors will end up bypassing this node — leave the"
			info "\"Host sent to the origin\" field blank so their own name is forwarded."
			;;
		404)
			err "the origin is up but has no site under the name '$_host'."
			err "That is the Host header: put the right name in \"Host sent to the origin\"."
			return 1 ;;
		50*)
			err "the origin answered $_code — it is up, and its own site is broken."
			err "Nothing on this node can fix that. Go and look at the origin's error log."
			return 1 ;;
		"")
			err "no answer at all from $_url:"
			printf '%s\n' "$_out" | sed 's/^/    /'
			err "  · is $(cdn_origin) the address of the *other* container, and is it up?"
			err "  · is port $(param port 80) published on it? A container's own 80 is not the internet's 80."
			err "  · does it want https rather than http? Set \"Origin protocol\" in Settings."
			return 1 ;;
		*)  warn "the origin answered $_code. Not a failure, but not a page either." ;;
	esac

	# The second half: is this node itself serving, and is the shelf being used.
	is_installed || { info "nothing installed on this node yet — press Install."; return 0; }
	svc_running nginx || { warn "nginx on this node is not running, so nothing is being served here."; return 0; }

	step "asking this node twice, to see the shelf work"
	_hdr=""
	for _i in 1 2; do
		if have curl; then
			_out="$(curl -sS -o /dev/null -D - -m 20 -H "Host: $_host" \
			        "http://127.0.0.1:$(param listen 80)/" 2>&1)"
		else
			_out="$(wget -S -O /dev/null -T 20 --header="Host: $_host" \
			        "http://127.0.0.1:$(param listen 80)/" 2>&1)"
		fi
		_hdr="$_hdr $(printf '%s\n' "$_out" | awk 'tolower($1)=="x-cache:"{print $2; exit}')"
	done
	info "X-Cache:$_hdr"
	case "$_hdr" in
		*HIT*)    ok "MISS then HIT is the whole thing working." ;;
		*BYPASS*) info "BYPASS is correct for a page while \"What to cache\" is static — the"
		          info "files are what gets cached. Check one: curl -sI http://127.0.0.1:$(param listen 80)/logo.png | grep -i x-cache" ;;
		*)        info "ask for an image rather than the front page to see a HIT:"
		          info "  curl -sI -H 'Host: $_host' http://127.0.0.1:$(param listen 80)/logo.png | grep -i x-cache" ;;
	esac
}

# Not one of app_main's verbs, and not one of the CLI's either — it exists
# because the ✗ button next to "Cache size limit" has to run something.
# Intercepted at the bottom of this file, which is a recipe's own business;
# common.sh does not need to know the verb exists for the button to work. From
# a shell it is `sh /etc/app-setup/cdn.sh purge`, because `app-setup <verb>`
# has a fixed table and nothing falls through it.
do_purge() {
	local _cache
	_cache="$(cdn_cache)"
	[ -d "$_cache" ] || { ok "nothing to empty — $_cache does not exist yet."; return 0; }
	step "emptying $_cache"
	rm -rf "${_cache:?}"/*
	mkdir -p "$_cache"
	cdn_own_cache "$_cache"
	svc_running nginx && { svc_reload nginx || svc_restart nginx || true; }
	ok "the shelf is empty. The next visitor for each file fetches it from the origin again."
}

do_help() {
	if lang_zh; then
		cat <<EOF
CDN 前置缓存节点

  这是什么
    把这台机器架在你网站前面。访客连的是这台，这台把没见过的内容去源站取
    回来、存一份、再发给访客；下一个人要同一个东西，就直接从这台发，不再
    麻烦源站。

    为什么要这么干：能进中国的线路又贵又小，能装下整个网站的机器又便宜又
    慢。所以租两台 —— 小的快的摆在前面，大的慢的放网站 —— 两台放在同一个
    城市。完整的道理在 docs/deploy-website-cdn.md。

  最少要填什么
    「源站地址」填你网站真正在的那台机器的域名或者 IP，「源站端口」填它的
    端口。按安装，就跑起来了。其余的字段都有默认值。

    注意源站必须是**另一台机器**。容器连自己机器的公网地址，连到的是它自己，
    不是隔壁那台 —— 填成自己会转圈，装的时候会直接拦下来。

  「缓存哪些内容」这三个值
    static  只缓存图片、视频、CSS、JS、字体这些静态文件。页面、PHP、接口
            一律直接转给源站，不缓存。**默认，也是最安全的一个** —— 「一个
            用户看到另一个用户的页面」这种事，前提是页面被缓存过。
    site    静态文件照旧，另外把未登录访客看到的页面也缓存起来。带登录
            Cookie 的请求会跳过缓存。**改成这个之前，请先把「登录状态
            Cookie」这一栏改对。**
    off     只做反向代理，什么都不缓存。

  怎么确认它在干活
    app-setup test cdn        测源站通不通，再看本机缓存有没有命中
    curl -sI http://127.0.0.1/logo.png | grep -i x-cache
    第一次 MISS、第二次 HIT，就对了。

  文件在哪
    $(cdn_conf)
        生成的配置，末尾有八段示例（接口不缓存、视频切片、WordPress、
        防盗链……），照着抄就行。**每次「保存并应用」都会重写这个文件。**
    $CDN_EXTRA/*.conf
        你自己写的配置放这里，永远不会被覆盖，而且优先级更高。
    $(cdn_cache)
        缓存本体。
    /var/log/nginx/cdn-access.log · cdn-error.log

  想清掉某一个文件的缓存
    整个清空：设置里点「立即清空缓存」，或者在命令行上
      sh /etc/app-setup/cdn.sh purge
    只清一个文件（缓存的 key 是 域名+路径 的 md5）：
      key=\$(printf '%s' 'www.example.com/logo.png' | md5sum | cut -d' ' -f1)
      find $(cdn_cache) -name "\$key" -delete
    更省事的办法是改文件名：logo.v2.png，以后再也不用管。

  常见的四种情况
    一直 MISS       源站每个响应都带 Set-Cookie 或 no-cache。配置文件里的
                    示例 5 是解法，但只对静态文件用，别对页面用。
    看到别人的购物车 页面被缓存了，而「登录状态 Cookie」没写全。立刻把
                    「缓存哪些内容」改回 static，再补 Cookie 名单。
    502             这台连不上源站。app-setup test cdn 会告诉你卡在哪。
    一直在跳转       源站在往它自己的域名跳。把「回源时发的 Host」留空。

  卸载会做什么
    停止代理，删掉生成的配置，清空缓存目录，把普通的默认站点放回去。
    源站上的网站一个字都不会动，$CDN_EXTRA 里你写的东西也不会动。
EOF
	else
		cat <<EOF
CDN front node

  What this is
    This machine sits in front of your website. Visitors connect here; this
    node fetches anything it has not seen from the origin, keeps a copy, and
    hands it over. The next person asking for the same thing gets it from
    here, and the origin is never told.

    Why bother: the lines that are fast into China are small and expensive,
    and the machines big enough to hold a website are cheap and slow. So rent
    two, in the same city, and put the small fast one in front. The whole
    argument is in docs/deploy-website-cdn.md.

  The least you have to fill in
    "Origin" is the domain or IP of the machine your website is actually on,
    and "Origin port" is the port it answers on. Press Install. Everything
    else has a default that is right for the common case.

    The origin must be a *different machine*. A container connecting to its
    own machine's public address reaches itself, not its neighbour, so a node
    pointed at itself proxies in a loop — install refuses that outright.

  The three values of "What to cache"
    static  Only files — images, video, CSS, JS, fonts. Pages, PHP and APIs
            go straight to the origin, uncached. **The default, and the safe
            one:** every "a visitor saw somebody else's page" bug needs a
            page to have been cached in the first place.
    site    Files as above, plus pages, for visitors carrying none of the
            signed-in cookies. **Get the cookie list right before choosing
            this**, and test it with a private window.
    off     A plain reverse proxy. Nothing is kept.

  Checking that it works
    app-setup test cdn        the origin, then the shelf on this node
    curl -sI http://127.0.0.1/logo.png | grep -i x-cache
    MISS the first time and HIT the second is the whole thing working.

  Where things are
    $(cdn_conf)
        the generated config, with eight worked examples at the bottom of it:
        never caching an API, slicing video, WordPress, hotlink protection.
        **Save & Apply rewrites this file whole.**
    $CDN_EXTRA/*.conf
        yours. Included inside the server block, never overwritten, and it
        wins over the generated locations.
    $(cdn_cache)
        the cache itself.
    /var/log/nginx/cdn-access.log · cdn-error.log

  Throwing away one file
    All of it — the ✗ button in Settings, or on the command line:
      sh /etc/app-setup/cdn.sh purge
    One file (the key is the md5 of host + path):
      key=\$(printf '%s' 'www.example.com/logo.png' | md5sum | cut -d' ' -f1)
      find $(cdn_cache) -name "\$key" -delete
    Renaming the file — logo.v2.png — is easier and permanent.

  The four things that go wrong
    always MISS        the origin sends Set-Cookie or Cache-Control: no-cache
                       on everything. Example 5 in the config file is the fix,
                       and it is only ever safe for files, never for pages.
    one customer sees  pages were cached and the signed-in cookie list is
    another's cart     incomplete. Set "What to cache" back to static now,
                       then fix the list.
    502                this node cannot reach the origin. app-setup test cdn
                       says which half is broken.
    redirect loop      the origin redirects to its own name. Leave "Host sent
                       to the origin" blank so the visitor's name is forwarded.

  What uninstall does
    Stops proxying, removes the generated config, empties the cache and puts
    the plain default site back. The website on the origin is untouched, and
    so is anything you wrote in $CDN_EXTRA.
EOF
	fi
}

if [ "${1-}" = purge ]; then need_root; do_purge; exit $?; fi

app_main "$@"
