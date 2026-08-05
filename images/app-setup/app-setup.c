/*
 * app-setup — the software manager inside a hqnode container.
 *
 * Someone who has been handed a container wants LNMP, or WordPress, or just
 * vim, and does not want to read three blog posts to get it. This draws the
 * catalogue as cards they can arrow around and press a key on, and shells the
 * actual work out to one script per package under /etc/app-setup.
 *
 * The split matters. This binary knows nothing about nginx: it reads the
 * comment header of every *.sh it finds, asks each one `status`, and runs
 * `install` / `uninstall` / `start` / `stop` / `enable` / `disable` / `help`
 * when a key is pressed. Adding software is dropping a file in a directory —
 * see docs/app-setup-sources.md — and never touches this file.
 *
 * It is C with nothing but libc so it can be linked static and copied into
 * every image we publish, Alpine's musl included. That rules out ncurses, so
 * the screen is a grid of cells rendered to ANSI by hand. It also rules out
 * wcwidth() being trustworthy across libcs, so the CJK width table below is
 * ours: the UI is bilingual and a card border that drifts by one column on
 * every Chinese label looks broken.
 *
 *   cc -static -O2 -o app-setup app-setup.c
 */

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define APP_VERSION   "1.0.0"
#define MAX_PKGS      512
#define MAX_CATS      32
#define DEFAULT_PATH  "/etc/app-setup:/usr/local/etc/app-setup"
#define LOG_DIR       "/var/log/app-setup"

/* ------------------------------------------------------------------ text --
 *
 * Every string the chrome shows exists twice. Recipes carry their own pair in
 * their header (`name:` and `name.zh:`), so a third-party source is bilingual
 * the same way without patching anything here.
 */
typedef struct { const char *en, *zh; } L;
static int g_zh = 0;                       /* chosen from LANG, or --lang */
#define S(l) (g_zh ? (l).zh : (l).en)

static const L T_TITLE     = {"app-setup", "app-setup"};
static const L T_SUBTITLE  = {"software manager", "软件管家"};
static const L T_INSTALL   = {"Install",     "安装"};
static const L T_REINSTALL = {"Reinstall",   "重装"};
static const L T_REMOVE    = {"Remove",      "卸载"};
static const L T_START     = {"Start",       "启动"};
static const L T_STOP      = {"Stop",        "停止"};
static const L T_BOOT      = {"Boot",        "开机"};
static const L T_DOCS      = {"Docs",        "说明"};
static const L T_RUNNING   = {"running",     "运行中"};
static const L T_STOPPED   = {"stopped",     "未启动"};
static const L T_ABSENT    = {"not installed", "未安装"};
static const L T_INSTALLED = {"installed",   "已安装"};
static const L T_BROKEN    = {"error",       "出错"};
static const L T_CHECKING  = {"checking",    "检查中"};
static const L T_DISK      = {"Disk",        "磁盘"};
static const L T_RAM       = {"RAM",         "内存"};
static const L T_PORT      = {"Port",        "端口"};
static const L T_NEEDS     = {"Needs",       "依赖"};
static const L T_KEYS      = {"move",        "移动"};
static const L T_CATS      = {"category",    "分类"};
static const L T_REFRESH   = {"refresh",     "刷新"};
static const L T_HELPKEY   = {"keys",        "按键"};
static const L T_QUIT      = {"quit",        "退出"};
static const L T_SEARCH    = {"search",      "搜索"};
static const L T_EMPTY     = {"Nothing in this category.", "这个分类下没有软件。"};
static const L T_NORECIPE  = {"No software sources found. Put recipes in /etc/app-setup/*.sh.",
                             "没有找到软件源。把脚本放到 /etc/app-setup/*.sh。"};
static const L T_TIGHT_D   = {"not enough free disk", "磁盘空间不够"};
static const L T_TIGHT_M   = {"more RAM than this machine has", "内存比本机还大"};
static const L T_CONFIRM   = {"Enter to confirm, any other key to cancel",
                             "回车确认，其它键取消"};
static const L T_REMOVEQ   = {"Remove %s? Its data and config go too.",
                             "确定卸载 %s？它的数据和配置也会删除。"};
static const L T_TIGHTQ    = {"%s wants %s but this machine has %s. Install anyway?",
                             "%s 需要 %s，本机只有 %s。仍要安装吗？"};
static const L T_ANYKEY    = {"— done. Press Enter to go back —",
                             "— 完成，按回车返回 —"};
static const L T_WORKING   = {"working", "执行中"};
static const L T_OK        = {"%s: %s finished", "%s：%s 完成"};
static const L T_FAIL      = {"%s: %s failed (exit %d) — see %s",
                             "%s：%s 失败（退出码 %d）——详见 %s"};
static const L T_ROOTWARN  = {"not root: actions will be run through sudo",
                             "当前不是 root：操作会走 sudo"};
static const L T_HELPTITLE = {"Keys", "按键说明"};
static const L T_LANG      = {"中文", "English"};

/* The nav bar, in the order it is shown. A recipe naming a category that is
 * not here gets one appended, labelled by its own `category.name:` — which is
 * how somebody's private source adds "Game servers" without a code change. */
static struct { char id[24]; L label; int owned; } g_cats[MAX_CATS] = {
	{"stack",  {"Suites",     "套件安装"},     0},
	{"web",    {"Web servers","Web服务器"},    0},
	{"db",     {"Databases",  "数据库"},       0},
	{"dev",    {"Dev tools",  "开发插件"},     0},
	{"system", {"System",     "常用系统软件"}, 0},
};
static int g_ncat = 5;

/* ------------------------------------------------------------------ model */
enum { ST_UNKNOWN = 0, ST_RUNNING, ST_STOPPED, ST_ABSENT, ST_BROKEN, ST_INSTALLED };

typedef struct {
	char id[64];
	char path[512];
	char name[96], name_zh[128];
	char summary[320], summary_zh[400];
	char includes[224], includes_zh[280];
	char disk[32], memory[32], ports[64], requires[128];
	char service[64];
	char cats[6][24];
	int  ncats;
	int  order;
	long long disk_bytes, mem_bytes;

	int  status;          /* ST_* */
	int  enabled;         /* -1 unknown, 0 no, 1 yes */
	char detail[160];
} Pkg;

static Pkg g_pkg[MAX_PKGS];
static int g_npkg = 0;

/* ------------------------------------------------------------------ utils */
static void *xmalloc(size_t n)
{
	void *p = calloc(1, n ? n : 1);
	if (!p) { fprintf(stderr, "app-setup: out of memory\n"); exit(70); }
	return p;
}

static void copy_str(char *dst, size_t cap, const char *src)
{
	size_t n = strlen(src);
	if (n >= cap) n = cap - 1;
	memcpy(dst, src, n);
	dst[n] = '\0';
}

static void trim(char *s)
{
	size_t n = strlen(s);
	while (n && (s[n-1]=='\n' || s[n-1]=='\r' || s[n-1]==' ' || s[n-1]=='\t')) s[--n] = '\0';
	char *p = s;
	while (*p == ' ' || *p == '\t') p++;
	if (p != s) memmove(s, p, strlen(p) + 1);
}

static int ci_contains(const char *hay, const char *needle)
{
	if (!*needle) return 1;
	for (const char *h = hay; *h; h++) {
		const char *a = h, *b = needle;
		while (*a && *b && tolower((unsigned char)*a) == tolower((unsigned char)*b)) { a++; b++; }
		if (!*b) return 1;
	}
	return 0;
}

static int have_cmd(const char *name)
{
	const char *path = getenv("PATH");
	if (!path || !*path) path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
	char buf[1024];
	while (*path) {
		const char *sep = strchr(path, ':');
		size_t len = sep ? (size_t)(sep - path) : strlen(path);
		if (len && len < sizeof buf - strlen(name) - 2) {
			memcpy(buf, path, len);
			buf[len] = '/';
			strcpy(buf + len + 1, name);
			if (access(buf, X_OK) == 0) return 1;
		}
		if (!sep) break;
		path = sep + 1;
	}
	return 0;
}

/* "512M", "1.5G", "800K" -> bytes. Zero when a recipe leaves it blank, which
 * the resource check reads as "no claim made" rather than "needs nothing". */
static long long parse_size(const char *s)
{
	if (!s || !*s) return 0;
	char *end = NULL;
	double v = strtod(s, &end);
	if (end == s) return 0;
	while (*end == ' ') end++;
	switch (toupper((unsigned char)*end)) {
	case 'K': v *= 1024.0; break;
	case 'M': v *= 1024.0 * 1024.0; break;
	case 'G': v *= 1024.0 * 1024.0 * 1024.0; break;
	case 'T': v *= 1024.0 * 1024.0 * 1024.0 * 1024.0; break;
	default: break;
	}
	return (long long)v;
}

static void human_size(long long b, char *out, size_t cap)
{
	const char *u[] = {"B", "K", "M", "G", "T"};
	int i = 0;
	double v = (double)b;
	while (v >= 1024.0 && i < 4) { v /= 1024.0; i++; }
	if (v >= 100 || i == 0) snprintf(out, cap, "%.0f%s", v, u[i]);
	else                    snprintf(out, cap, "%.1f%s", v, u[i]);
}

/* ------------------------------------------------------------------- utf8 --
 *
 * Two things are needed of it: how many terminal columns a string occupies,
 * and where to cut it so the cut lands between characters. wcwidth() would do
 * the first if every libc agreed, and on musl with the C locale it does not.
 */
static const char *u8next(const char *s, unsigned int *cp)
{
	const unsigned char *p = (const unsigned char *)s;
	unsigned int c = *p;
	int extra;
	if (c < 0x80)        { *cp = c; return s + 1; }
	else if ((c & 0xE0) == 0xC0) { c &= 0x1F; extra = 1; }
	else if ((c & 0xF0) == 0xE0) { c &= 0x0F; extra = 2; }
	else if ((c & 0xF8) == 0xF0) { c &= 0x07; extra = 3; }
	else                 { *cp = 0xFFFD; return s + 1; }   /* stray byte */
	for (int i = 1; i <= extra; i++) {
		if ((p[i] & 0xC0) != 0x80) { *cp = 0xFFFD; return s + 1; }
		c = (c << 6) | (p[i] & 0x3F);
	}
	*cp = c;
	return s + extra + 1;
}

static int cp_width(unsigned int c)
{
	if (c == 0) return 0;
	if (c < 32 || (c >= 0x7F && c < 0xA0)) return 0;
	/* combining marks */
	if ((c >= 0x0300 && c <= 0x036F) || (c >= 0x200B && c <= 0x200F) ||
	    (c >= 0xFE00 && c <= 0xFE0F)) return 0;
	if (c >= 0x1100 && (
	      c <= 0x115F ||                                  /* Hangul jamo   */
	      c == 0x2329 || c == 0x232A ||
	      (c >= 0x2E80 && c <= 0xA4CF && c != 0x303F) ||  /* CJK           */
	      (c >= 0xAC00 && c <= 0xD7A3) ||                 /* Hangul        */
	      (c >= 0xF900 && c <= 0xFAFF) ||                 /* compat ideo   */
	      (c >= 0xFE30 && c <= 0xFE6F) ||                 /* CJK forms     */
	      (c >= 0xFF00 && c <= 0xFF60) ||                 /* fullwidth     */
	      (c >= 0xFFE0 && c <= 0xFFE6) ||
	      (c >= 0x1F300 && c <= 0x1F64F) ||               /* emoji         */
	      (c >= 0x1F900 && c <= 0x1F9FF) ||
	      (c >= 0x20000 && c <= 0x3FFFD)))
		return 2;
	return 1;
}

static int u8width(const char *s)
{
	int w = 0;
	unsigned int c;
	while (*s) { s = u8next(s, &c); w += cp_width(c); }
	return w;
}

/* Copy at most `cols` columns of `src` into `dst`, never splitting a
 * character. Returns the columns actually written. */
static int u8trunc(char *dst, size_t cap, const char *src, int cols)
{
	int w = 0;
	size_t used = 0;
	unsigned int c;
	while (*src) {
		const char *nx = u8next(src, &c);
		int cw = cp_width(c);
		if (w + cw > cols) break;
		size_t len = (size_t)(nx - src);
		if (used + len >= cap) break;
		memcpy(dst + used, src, len);
		used += len;
		w += cw;
		src = nx;
	}
	dst[used] = '\0';
	return w;
}

/* Wrap to `cols`, breaking on spaces where there are any and between
 * characters where there are not — Chinese summaries have no spaces to break
 * on and would otherwise never wrap. */
static int u8wrap(const char *src, int cols, char out[][512], int maxlines)
{
	int line = 0;
	if (cols < 4) cols = 4;
	while (*src && line < maxlines) {
		while (*src == ' ') src++;
		if (!*src) break;
		int w = 0;
		size_t used = 0;
		const char *lastspace = NULL;
		size_t lastspace_used = 0;
		const char *p = src;
		unsigned int c;
		while (*p) {
			const char *nx = u8next(p, &c);
			int cw = cp_width(c);
			if (w + cw > cols) break;
			if (c == ' ') { lastspace = p; lastspace_used = used; }
			size_t len = (size_t)(nx - p);
			if (used + len >= 500) break;
			memcpy(out[line] + used, p, len);
			used += len;
			w += cw;
			p = nx;
		}
		/* Only rewind to a space if the break lands mid-word in the Latin
		 * sense; a CJK run has no space and must break where it filled. */
		if (*p && *p != ' ' && lastspace && lastspace_used > 0 &&
		    (unsigned char)*p < 0x80) {
			used = lastspace_used;
			p = lastspace;
		}
		out[line][used] = '\0';
		line++;
		src = p;
	}
	if (line == 0) { out[0][0] = '\0'; line = 1; }
	return line;
}

/* ------------------------------------------------------------ system facts */
static struct {
	char pretty[128];
	char id[64];
	char init[16];
	char pm[16];
	long ncpu;
	long long mem_total, mem_avail;
	long long disk_free;
} g_sys;

static void read_os_release(void)
{
	FILE *f = fopen("/etc/os-release", "r");
	copy_str(g_sys.pretty, sizeof g_sys.pretty, "Linux");
	copy_str(g_sys.id, sizeof g_sys.id, "linux");
	if (!f) return;
	char line[512];
	while (fgets(line, sizeof line, f)) {
		char *eq = strchr(line, '=');
		if (!eq) continue;
		*eq = '\0';
		char *v = eq + 1;
		trim(v);
		size_t n = strlen(v);
		if (n >= 2 && v[0] == '"' && v[n-1] == '"') { v[n-1] = '\0'; v++; }
		if (!strcmp(line, "PRETTY_NAME")) copy_str(g_sys.pretty, sizeof g_sys.pretty, v);
		else if (!strcmp(line, "ID"))     copy_str(g_sys.id, sizeof g_sys.id, v);
	}
	fclose(f);
}

static void read_meminfo(void)
{
	FILE *f = fopen("/proc/meminfo", "r");
	if (!f) return;
	char line[256];
	while (fgets(line, sizeof line, f)) {
		long long kb;
		if (sscanf(line, "MemTotal: %lld kB", &kb) == 1)     g_sys.mem_total = kb * 1024;
		else if (sscanf(line, "MemAvailable: %lld kB", &kb) == 1) g_sys.mem_avail = kb * 1024;
	}
	fclose(f);
	/* A container under a memory cgroup is smaller than the host's MemTotal,
	 * and installing by the host's number is how a 512M box gets told a 1G
	 * stack will fit. cgroup v2 first, then v1. */
	FILE *g = fopen("/sys/fs/cgroup/memory.max", "r");
	if (!g) g = fopen("/sys/fs/cgroup/memory/memory.limit_in_bytes", "r");
	if (g) {
		char buf[64];
		if (fgets(buf, sizeof buf, g)) {
			long long lim = atoll(buf);
			if (lim > 0 && (g_sys.mem_total == 0 || lim < g_sys.mem_total))
				g_sys.mem_total = lim;
		}
		fclose(g);
	}
}

static void probe_system(void)
{
	read_os_release();
	read_meminfo();
	g_sys.ncpu = sysconf(_SC_NPROCESSORS_ONLN);
	struct statvfs vfs;
	if (statvfs("/", &vfs) == 0)
		g_sys.disk_free = (long long)vfs.f_bavail * (long long)vfs.f_frsize;

	struct stat st;
	if (stat("/run/systemd/system", &st) == 0 && S_ISDIR(st.st_mode))
		copy_str(g_sys.init, sizeof g_sys.init, "systemd");
	else if (have_cmd("rc-service") || access("/etc/rc.conf", F_OK) == 0)
		copy_str(g_sys.init, sizeof g_sys.init, "openrc");
	else if (have_cmd("systemctl"))
		copy_str(g_sys.init, sizeof g_sys.init, "systemd");
	else
		copy_str(g_sys.init, sizeof g_sys.init, "sysv");

	if      (have_cmd("apt-get")) copy_str(g_sys.pm, sizeof g_sys.pm, "apt");
	else if (have_cmd("dnf"))     copy_str(g_sys.pm, sizeof g_sys.pm, "dnf");
	else if (have_cmd("yum"))     copy_str(g_sys.pm, sizeof g_sys.pm, "yum");
	else if (have_cmd("apk"))     copy_str(g_sys.pm, sizeof g_sys.pm, "apk");
	else if (have_cmd("zypper"))  copy_str(g_sys.pm, sizeof g_sys.pm, "zypper");
	else if (have_cmd("pacman"))  copy_str(g_sys.pm, sizeof g_sys.pm, "pacman");
	else                          copy_str(g_sys.pm, sizeof g_sys.pm, "?");
}

/* ------------------------------------------------------------- subprocess --
 *
 * Two shapes. `run_capture` is for the fast, silent verbs — status and help —
 * and holds a deadline because one hung recipe must not freeze the catalogue.
 * `run_stream` is for install and friends: it can take ten minutes, its output
 * is the point, and it goes to the terminal and a log at the same time.
 */
/* Everything is `sh <recipe> <verb>`. When app-setup is not root — which is
 * the odd case, but somebody will do it — the same line goes through sudo,
 * and -E is what keeps APP_SETUP_LANG and DEBIAN_FRONTEND across the border. */
static void exec_recipe(const char *script, const char *verb)
{
	if (geteuid() != 0 && have_cmd("sudo"))
		execlp("sudo", "sudo", "-E", "/bin/sh", script, verb, (char *)NULL);
	execl("/bin/sh", "sh", script, verb, (char *)NULL);
	_exit(127);
}

static void child_env(void)
{
	setenv("APP_SETUP", APP_VERSION, 1);
	setenv("APP_SETUP_LANG", g_zh ? "zh" : "en", 1);
	setenv("DEBIAN_FRONTEND", "noninteractive", 1);
	setenv("NEEDRESTART_MODE", "a", 1);
	if (!getenv("LC_ALL")) setenv("LC_ALL", "C.UTF-8", 0);
}

static int run_capture(const char *script, const char *verb, char *out, size_t cap,
                       int timeout_s, int want_stderr)
{
	int pfd[2];
	if (out && cap) out[0] = '\0';
	if (pipe(pfd) != 0) return -1;

	pid_t pid = fork();
	if (pid < 0) { close(pfd[0]); close(pfd[1]); return -1; }
	if (pid == 0) {
		close(pfd[0]);
		dup2(pfd[1], STDOUT_FILENO);
		if (want_stderr) dup2(pfd[1], STDERR_FILENO);
		else {
			int nul = open("/dev/null", O_WRONLY);
			if (nul >= 0) { dup2(nul, STDERR_FILENO); close(nul); }
		}
		close(pfd[1]);
		int nul = open("/dev/null", O_RDONLY);
		if (nul >= 0) { dup2(nul, STDIN_FILENO); close(nul); }
		child_env();
		exec_recipe(script, verb);
	}
	close(pfd[1]);

	size_t used = 0;
	time_t deadline = time(NULL) + timeout_s;
	int timed_out = 0;
	for (;;) {
		struct pollfd p = { pfd[0], POLLIN, 0 };
		int ms = (int)((deadline - time(NULL)) * 1000);
		if (ms <= 0) { timed_out = 1; break; }
		int r = poll(&p, 1, ms > 200 ? 200 : ms);
		if (r < 0) { if (errno == EINTR) continue; break; }
		if (r == 0) continue;
		char buf[1024];
		ssize_t n = read(pfd[0], buf, sizeof buf);
		if (n <= 0) break;
		if (out && used + (size_t)n < cap - 1) {
			memcpy(out + used, buf, (size_t)n);
			used += (size_t)n;
			out[used] = '\0';
		}
	}
	close(pfd[0]);
	if (timed_out) kill(pid, SIGKILL);

	int status = 0;
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR) { }
	if (timed_out) return -2;
	return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}

static int run_stream(const char *script, const char *verb, const char *logpath)
{
	int pfd[2];
	if (pipe(pfd) != 0) return -1;

	int logfd = -1;
	if (logpath) {
		mkdir(LOG_DIR, 0755);
		logfd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0640);
	}
	if (logfd >= 0) {
		char hdr[512];
		time_t now = time(NULL);
		struct tm tm;
		gmtime_r(&now, &tm);
		int n = snprintf(hdr, sizeof hdr,
		                 "\n===== %04d-%02d-%02dT%02d:%02d:%02dZ  %s %s =====\n",
		                 tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
		                 tm.tm_hour, tm.tm_min, tm.tm_sec, script, verb);
		if (write(logfd, hdr, (size_t)n) < 0) { /* the log is best effort */ }
	}

	pid_t pid = fork();
	if (pid < 0) { close(pfd[0]); close(pfd[1]); if (logfd >= 0) close(logfd); return -1; }
	if (pid == 0) {
		close(pfd[0]);
		dup2(pfd[1], STDOUT_FILENO);
		dup2(pfd[1], STDERR_FILENO);
		close(pfd[1]);
		child_env();
		/* stdin stays the terminal: a sudo password prompt or an apt
		 * question has to be answerable, and the screen is already back
		 * in cooked mode by the time we get here. */
		exec_recipe(script, verb);
	}
	close(pfd[1]);

	char buf[4096];
	ssize_t n;
	while ((n = read(pfd[0], buf, sizeof buf)) > 0) {
		if (write(STDOUT_FILENO, buf, (size_t)n) < 0) { /* terminal gone */ }
		if (logfd >= 0 && write(logfd, buf, (size_t)n) < 0) { /* ditto */ }
	}
	close(pfd[0]);
	if (logfd >= 0) close(logfd);

	int status = 0;
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR) { }
	return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}

/* -------------------------------------------------------------- recipes ---
 *
 * The header is parsed, not sourced. Drawing the catalogue must not run
 * thirty-odd shell scripts, and a file dropped in by a stranger should not get
 * to execute merely by existing — it executes when somebody presses a key.
 */
static int cat_index(const char *id)
{
	for (int i = 0; i < g_ncat; i++)
		if (!strcmp(g_cats[i].id, id)) return i;
	return -1;
}

static int cat_add(const char *id)
{
	int i = cat_index(id);
	if (i >= 0) return i;
	if (g_ncat >= MAX_CATS) return -1;
	i = g_ncat++;
	copy_str(g_cats[i].id, sizeof g_cats[i].id, id);
	/* Until a recipe says otherwise the id is the label; `category.name:`
	 * in any recipe of that category replaces it. */
	static char labels[MAX_CATS][2][48];
	copy_str(labels[i][0], sizeof labels[i][0], id);
	copy_str(labels[i][1], sizeof labels[i][1], id);
	g_cats[i].label.en = labels[i][0];
	g_cats[i].label.zh = labels[i][1];
	g_cats[i].owned = 1;
	return i;
}

static void cat_label(const char *id, const char *en, const char *zh)
{
	int i = cat_add(id);
	if (i < 0 || !g_cats[i].owned) return;
	if (en && *en) copy_str((char *)g_cats[i].label.en, 48, en);
	if (zh && *zh) copy_str((char *)g_cats[i].label.zh, 48, zh);
}

static void set_field(Pkg *p, const char *k, const char *v)
{
	if      (!strcmp(k, "id"))          copy_str(p->id, sizeof p->id, v);
	else if (!strcmp(k, "name"))        copy_str(p->name, sizeof p->name, v);
	else if (!strcmp(k, "name.zh"))     copy_str(p->name_zh, sizeof p->name_zh, v);
	else if (!strcmp(k, "summary"))     copy_str(p->summary, sizeof p->summary, v);
	else if (!strcmp(k, "summary.zh"))  copy_str(p->summary_zh, sizeof p->summary_zh, v);
	else if (!strcmp(k, "includes"))    copy_str(p->includes, sizeof p->includes, v);
	else if (!strcmp(k, "includes.zh")) copy_str(p->includes_zh, sizeof p->includes_zh, v);
	else if (!strcmp(k, "disk"))        { copy_str(p->disk, sizeof p->disk, v); p->disk_bytes = parse_size(v); }
	else if (!strcmp(k, "memory"))      { copy_str(p->memory, sizeof p->memory, v); p->mem_bytes = parse_size(v); }
	else if (!strcmp(k, "ports"))       copy_str(p->ports, sizeof p->ports, v);
	else if (!strcmp(k, "requires"))    copy_str(p->requires, sizeof p->requires, v);
	else if (!strcmp(k, "service"))     copy_str(p->service, sizeof p->service, v);
	else if (!strcmp(k, "order"))       p->order = atoi(v);
	else if (!strcmp(k, "category")) {
		char tmp[192];
		copy_str(tmp, sizeof tmp, v);
		char *tok = strtok(tmp, ", \t");
		while (tok && p->ncats < 6) {
			copy_str(p->cats[p->ncats], sizeof p->cats[0], tok);
			cat_add(tok);
			p->ncats++;
			tok = strtok(NULL, ", \t");
		}
	}
}

static int load_recipe(const char *path, Pkg *p)
{
	FILE *f = fopen(path, "r");
	if (!f) return 0;

	memset(p, 0, sizeof *p);
	p->order = 100;
	p->status = ST_UNKNOWN;
	p->enabled = -1;
	copy_str(p->path, sizeof p->path, path);

	char line[1024], cat_en[48] = "", cat_zh[48] = "", cat_for[24] = "";
	int marked = 0, seen = 0;
	while (fgets(line, sizeof line, f) && seen++ < 120) {
		char *s = line;
		while (*s == ' ' || *s == '\t') s++;
		if (*s == '\n' || *s == '\r' || *s == '\0') continue;
		if (*s != '#') break;                 /* header ends at the first code */
		s++;
		while (*s == ' ' || *s == '\t') s++;
		char *colon = strchr(s, ':');
		if (!colon) continue;
		*colon = '\0';
		char key[64];
		copy_str(key, sizeof key, s);
		trim(key);
		char *val = colon + 1;
		trim(val);
		for (char *q = key; *q; q++) *q = (char)tolower((unsigned char)*q);

		if (!strcmp(key, "app-setup")) { marked = 1; continue; }
		if (!strcmp(key, "category.name"))    { copy_str(cat_en, sizeof cat_en, val); continue; }
		if (!strcmp(key, "category.name.zh")) { copy_str(cat_zh, sizeof cat_zh, val); continue; }
		set_field(p, key, val);
		if (!strcmp(key, "category") && p->ncats)
			copy_str(cat_for, sizeof cat_for, p->cats[0]);
	}
	fclose(f);

	if (!marked) return 0;                    /* not a recipe; libs live here too */
	if (!p->id[0]) {
		const char *base = strrchr(path, '/');
		base = base ? base + 1 : path;
		copy_str(p->id, sizeof p->id, base);
		char *dot = strrchr(p->id, '.');
		if (dot && !strcmp(dot, ".sh")) *dot = '\0';
	}
	if (!p->name[0]) copy_str(p->name, sizeof p->name, p->id);
	if (!p->ncats) { copy_str(p->cats[0], sizeof p->cats[0], "system"); p->ncats = 1; }
	if (cat_for[0] && (cat_en[0] || cat_zh[0])) cat_label(cat_for, cat_en, cat_zh);
	return 1;
}

static int pkg_cmp(const void *a, const void *b)
{
	const Pkg *x = a, *y = b;
	if (x->order != y->order) return x->order - y->order;
	return strcmp(x->name, y->name);
}

static void scan_dir(const char *dir)
{
	DIR *d = opendir(dir);
	if (!d) return;
	struct dirent *e;
	while ((e = readdir(d))) {
		const char *dot = strrchr(e->d_name, '.');
		if (!dot || strcmp(dot, ".sh")) continue;
		if (e->d_name[0] == '.') continue;
		char path[512];
		snprintf(path, sizeof path, "%s/%s", dir, e->d_name);
		struct stat st;
		if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) continue;

		Pkg tmp;
		if (!load_recipe(path, &tmp)) continue;
		/* A later directory on the path shadows an earlier one by id, so a
		 * private source can replace a shipped recipe without deleting it. */
		int slot = -1;
		for (int i = 0; i < g_npkg; i++)
			if (!strcmp(g_pkg[i].id, tmp.id)) { slot = i; break; }
		if (slot < 0) {
			if (g_npkg >= MAX_PKGS) break;
			slot = g_npkg++;
		}
		g_pkg[slot] = tmp;
	}
	closedir(d);
}

static void scan_all(void)
{
	const char *env = getenv("APP_SETUP_PATH");
	char path[1024];
	copy_str(path, sizeof path, env && *env ? env : DEFAULT_PATH);
	char *tok = strtok(path, ":");
	while (tok) {
		scan_dir(tok);
		tok = strtok(NULL, ":");
	}
	qsort(g_pkg, (size_t)g_npkg, sizeof g_pkg[0], pkg_cmp);
}

/* status: exit code carries the state, stdout carries `key=value` detail.
 * One fork per package rather than two, because `enabled` comes back in the
 * same breath. */
static void probe_pkg(Pkg *p)
{
	char out[2048];
	int rc = run_capture(p->path, "status", out, sizeof out, 8, 0);

	p->detail[0] = '\0';
	p->enabled = -1;
	switch (rc) {
	case 0:  p->status = p->service[0] ? ST_RUNNING : ST_INSTALLED; break;
	case 1:  p->status = ST_STOPPED; break;
	case 2:  p->status = ST_ABSENT;  break;
	case 3:  p->status = ST_BROKEN;  break;
	case -2: p->status = ST_BROKEN;  copy_str(p->detail, sizeof p->detail, "status timed out"); return;
	default: p->status = ST_BROKEN;  break;
	}

	char *line = out;
	while (line && *line) {
		char *nl = strchr(line, '\n');
		if (nl) *nl = '\0';
		trim(line);
		if (!strncmp(line, "detail=", 7))       copy_str(p->detail, sizeof p->detail, line + 7);
		else if (!strncmp(line, "enabled=", 8)) p->enabled = atoi(line + 8) ? 1 : 0;
		else if (*line && !p->detail[0] && !strchr(line, '='))
			copy_str(p->detail, sizeof p->detail, line);
		line = nl ? nl + 1 : NULL;
	}
}

/* ------------------------------------------------------------------ screen --
 *
 * Cells rather than a stream of escapes: one write per frame (no flicker), and
 * the same code path can dump a frame as plain text, which is how the
 * three-columns-two-columns-one-column layout gets tested without a terminal.
 */
enum {
	A_NORM = 0, A_DIM, A_TITLE, A_NAV, A_NAVSEL, A_BORDER, A_BORDERSEL,
	A_NAME, A_RUN, A_STOP, A_ABSENT, A_ERR, A_WARN, A_BTN, A_BTNKEY,
	A_BTNOFF, A_FOOT, A_MSG, A_INV, A_COUNT
};

static const char *SGR[A_COUNT] = {
	"0",           /* NORM      */
	"0;2",         /* DIM       */
	"0;1;36",      /* TITLE     */
	"0;2",         /* NAV       */
	"0;1;30;46",   /* NAVSEL    */
	"0;2;37",      /* BORDER    */
	"0;1;36",      /* BORDERSEL */
	"0;1",         /* NAME      */
	"0;32",        /* RUN       */
	"0;33",        /* STOP      */
	"0;2",         /* ABSENT    */
	"0;1;31",      /* ERR       */
	"0;33",        /* WARN      */
	"0;36",        /* BTN       */
	"0;1;33",      /* BTNKEY    */
	"0;2",         /* BTNOFF    */
	"0;2",         /* FOOT      */
	"0;1;33",      /* MSG       */
	"0;7",         /* INV       */
};

typedef struct { char ch[5]; unsigned char attr; unsigned char cont; } Cell;

static Cell *g_grid = NULL;
static int g_w = 80, g_h = 24, g_gw = 0, g_gh = 0;
static int g_color = 1, g_utf8 = 1;

static const char *BX_TL, *BX_TR, *BX_BL, *BX_BR, *BX_H, *BX_V;
static const char *MK_RUN, *MK_STOP, *MK_ABSENT, *MK_ERR, *MK_OK, *MK_NO, *MK_DOT;

static void pick_glyphs(void)
{
	if (g_utf8) {
		BX_TL = "┌"; BX_TR = "┐"; BX_BL = "└"; BX_BR = "┘";
		BX_H  = "─"; BX_V  = "│";
		MK_RUN = "●"; MK_STOP = "○"; MK_ABSENT = "·";
		MK_ERR = "✗"; MK_OK = "✓"; MK_NO = "✗"; MK_DOT = "·";
	} else {
		BX_TL = "+"; BX_TR = "+"; BX_BL = "+"; BX_BR = "+";
		BX_H = "-"; BX_V = "|";
		MK_RUN = "*"; MK_STOP = "o"; MK_ABSENT = "-";
		MK_ERR = "x"; MK_OK = "+"; MK_NO = "x"; MK_DOT = "-";
	}
}

static void grid_size(int w, int h)
{
	if (w < 20) w = 20;
	if (h < 8)  h = 8;
	if (w != g_gw || h != g_gh || !g_grid) {
		free(g_grid);
		g_grid = xmalloc((size_t)w * (size_t)h * sizeof(Cell));
		g_gw = w; g_gh = h;
	}
}

static void grid_clear(void)
{
	for (int i = 0; i < g_gw * g_gh; i++) {
		g_grid[i].ch[0] = ' '; g_grid[i].ch[1] = '\0';
		g_grid[i].attr = A_NORM;
		g_grid[i].cont = 0;
	}
}

/* Writes up to `maxw` columns and returns how many it used. */
static int gput(int row, int col, const char *s, int attr, int maxw)
{
	if (row < 0 || row >= g_gh) return 0;
	int used = 0;
	unsigned int c;
	while (*s && used < maxw) {
		const char *nx = u8next(s, &c);
		int cw = cp_width(c);
		if (cw == 0) { s = nx; continue; }
		if (used + cw > maxw) break;
		if (col + used >= 0 && col + used < g_gw) {
			Cell *cell = &g_grid[row * g_gw + col + used];
			size_t len = (size_t)(nx - s);
			if (len > 4) len = 4;
			memcpy(cell->ch, s, len);
			cell->ch[len] = '\0';
			cell->attr = (unsigned char)attr;
			cell->cont = 0;
			if (cw == 2 && col + used + 1 < g_gw) {
				Cell *k = &g_grid[row * g_gw + col + used + 1];
				k->ch[0] = '\0';
				k->attr = (unsigned char)attr;
				k->cont = 1;
			}
		}
		used += cw;
		s = nx;
	}
	return used;
}

static void gfill(int row, int col, int w, const char *glyph, int attr)
{
	for (int i = 0; i < w; i++) gput(row, col + i, glyph, attr, 1);
}

static void grid_flush(void)
{
	static char *out = NULL;
	static size_t cap = 0;
	size_t need = (size_t)g_gw * (size_t)g_gh * 12 + 64;
	if (need > cap) { free(out); out = xmalloc(need); cap = need; }

	size_t n = 0;
	n += (size_t)sprintf(out + n, "\x1b[H");
	int attr = -1;
	for (int r = 0; r < g_gh; r++) {
		n += (size_t)sprintf(out + n, "\x1b[%d;1H\x1b[K", r + 1);
		attr = -1;
		int last = -1;
		for (int c = 0; c < g_gw; c++) {
			Cell *cell = &g_grid[r * g_gw + c];
			if (cell->cont) continue;
			if (cell->ch[0] != ' ' || cell->ch[1] != '\0') last = c;
		}
		for (int c = 0; c <= last; c++) {
			Cell *cell = &g_grid[r * g_gw + c];
			if (cell->cont) continue;
			if (g_color && cell->attr != attr) {
				attr = cell->attr;
				n += (size_t)sprintf(out + n, "\x1b[%sm", SGR[attr]);
			}
			const char *ch = cell->ch[0] ? cell->ch : " ";
			size_t len = strlen(ch);
			memcpy(out + n, ch, len);
			n += len;
		}
		if (g_color) n += (size_t)sprintf(out + n, "\x1b[0m");
	}
	if (write(STDOUT_FILENO, out, n) < 0) { /* the terminal went away */ }
}

static void grid_dump(FILE *f)
{
	for (int r = 0; r < g_gh; r++) {
		int last = -1;
		for (int c = 0; c < g_gw; c++) {
			Cell *cell = &g_grid[r * g_gw + c];
			if (!cell->cont && (cell->ch[0] != ' ' || cell->ch[1] != '\0')) last = c;
		}
		for (int c = 0; c <= last; c++) {
			Cell *cell = &g_grid[r * g_gw + c];
			if (cell->cont) continue;
			fputs(cell->ch[0] ? cell->ch : " ", f);
		}
		fputc('\n', f);
	}
}

/* ------------------------------------------------------------- terminal ---*/
static struct termios g_saved_tio;
static int g_raw = 0;
static volatile sig_atomic_t g_resized = 0;

static void on_winch(int sig) { (void)sig; g_resized = 1; }

static void term_measure(void)
{
	struct winsize ws;
	if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
		g_w = ws.ws_col;
		g_h = ws.ws_row > 0 ? ws.ws_row : 24;
	}
	if (g_w < 24) g_w = 24;
	if (g_h < 10) g_h = 10;
}

static void term_raw(void)
{
	if (g_raw) return;
	struct termios t;
	if (tcgetattr(STDIN_FILENO, &g_saved_tio) != 0) return;
	t = g_saved_tio;
	t.c_lflag &= (tcflag_t)~(ECHO | ICANON | ISIG | IEXTEN);
	t.c_iflag &= (tcflag_t)~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
	t.c_oflag &= (tcflag_t)~(OPOST);
	t.c_cc[VMIN] = 1;
	t.c_cc[VTIME] = 0;
	tcsetattr(STDIN_FILENO, TCSAFLUSH, &t);
	g_raw = 1;
	/* alt screen, cursor off, SGR mouse clicks on */
	if (write(STDOUT_FILENO, "\x1b[?1049h\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[2J", 33) < 0) { }
}

static void term_cooked(void)
{
	if (!g_raw) return;
	if (write(STDOUT_FILENO, "\x1b[?1006l\x1b[?1000l\x1b[?25h\x1b[?1049l", 30) < 0) { }
	tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_saved_tio);
	g_raw = 0;
}

static void on_fatal(int sig) { term_cooked(); _exit(128 + sig); }

enum {
	K_NONE = 0, K_UP = 256, K_DOWN, K_LEFT, K_RIGHT, K_PGUP, K_PGDN,
	K_HOME, K_END, K_TAB, K_BTAB, K_ENTER, K_ESC, K_BACK, K_MOUSE, K_RESIZE
};

static int g_mx, g_my;

static int read_byte(int timeout_ms, unsigned char *out)
{
	struct pollfd p = { STDIN_FILENO, POLLIN, 0 };
	int r = poll(&p, 1, timeout_ms);
	if (r <= 0) return r;
	return read(STDIN_FILENO, out, 1) == 1 ? 1 : -1;
}

static int read_key(void)
{
	unsigned char c;
	if (g_resized) { g_resized = 0; return K_RESIZE; }
	ssize_t n = read(STDIN_FILENO, &c, 1);
	if (n < 0) {
		if (errno == EINTR) { if (g_resized) { g_resized = 0; return K_RESIZE; } return K_NONE; }
		return K_NONE;
	}
	if (n == 0) return K_NONE;

	if (c == '\r' || c == '\n') return K_ENTER;
	if (c == '\t') return K_TAB;
	if (c == 127 || c == 8) return K_BACK;
	if (c != 27) return c;

	/* ESC: a lone press, or the start of a sequence. */
	if (read_byte(60, &c) <= 0) return K_ESC;
	if (c == '[') {
		unsigned char seq[32];
		int len = 0;
		while (len < (int)sizeof seq - 1) {
			if (read_byte(60, &seq[len]) <= 0) break;
			unsigned char x = seq[len++];
			if ((x >= 'A' && x <= 'Z') || x == '~' || x == 'M' || x == 'm') break;
		}
		seq[len] = '\0';
		if (len == 0) return K_ESC;
		unsigned char fin = seq[len - 1];
		if (seq[0] == '<' && (fin == 'M' || fin == 'm')) {
			int b, x, y;
			if (sscanf((char *)seq + 1, "%d;%d;%d", &b, &x, &y) == 3 && fin == 'M') {
				g_mx = x - 1; g_my = y - 1;
				if (b == 64) return K_UP;      /* wheel up   */
				if (b == 65) return K_DOWN;    /* wheel down */
				if ((b & 3) == 0) return K_MOUSE;   /* left button, press */
			}
			return K_NONE;
		}
		switch (fin) {
		case 'A': return K_UP;
		case 'B': return K_DOWN;
		case 'C': return K_RIGHT;
		case 'D': return K_LEFT;
		case 'H': return K_HOME;
		case 'F': return K_END;
		case 'Z': return K_BTAB;
		case '~':
			switch (atoi((char *)seq)) {
			case 1: case 7: return K_HOME;
			case 4: case 8: return K_END;
			case 5: return K_PGUP;
			case 6: return K_PGDN;
			}
			return K_NONE;
		}
		return K_NONE;
	}
	if (c == 'O') {
		if (read_byte(60, &c) <= 0) return K_ESC;
		switch (c) {
		case 'A': return K_UP;   case 'B': return K_DOWN;
		case 'C': return K_RIGHT; case 'D': return K_LEFT;
		case 'H': return K_HOME; case 'F': return K_END;
		}
	}
	return K_ESC;
}

/* ------------------------------------------------------------------ view ---*/
static int g_cat = 0;
static int g_view[MAX_PKGS], g_nview = 0;
static int g_sel = 0, g_scroll = 0;
static char g_msg[256] = "";
static int g_msg_attr = A_MSG;
static char g_filter[64] = "";
static int g_searching = 0;

static const char *pkg_name(const Pkg *p) { return g_zh && p->name_zh[0] ? p->name_zh : p->name; }
static const char *pkg_summary(const Pkg *p) { return g_zh && p->summary_zh[0] ? p->summary_zh : p->summary; }
static const char *pkg_includes(const Pkg *p) { return g_zh && p->includes_zh[0] ? p->includes_zh : p->includes; }

static int pkg_in_cat(const Pkg *p, const char *cat)
{
	for (int i = 0; i < p->ncats; i++)
		if (!strcmp(p->cats[i], cat)) return 1;
	return 0;
}

static int cat_count(int i)
{
	int n = 0;
	for (int j = 0; j < g_npkg; j++)
		if (pkg_in_cat(&g_pkg[j], g_cats[i].id)) n++;
	return n;
}

/* Tab must not stop on a category nothing declares. An image that ships only
 * the system recipes, or a machine where someone deleted the rest, would
 * otherwise have tabs that lead to an empty screen. */
static int cat_step(int from, int dir)
{
	for (int n = 1; n <= g_ncat; n++) {
		int i = ((from + dir * n) % g_ncat + g_ncat) % g_ncat;
		if (cat_count(i)) return i;
	}
	return from;
}

static int cat_nth_shown(int n)
{
	for (int i = 0; i < g_ncat; i++)
		if (cat_count(i) && n-- == 0) return i;
	return -1;
}

static void rebuild_view(void)
{
	g_nview = 0;
	for (int i = 0; i < g_npkg; i++) {
		Pkg *p = &g_pkg[i];
		if (!g_filter[0] && !pkg_in_cat(p, g_cats[g_cat].id)) continue;
		if (g_filter[0] && !(ci_contains(p->name, g_filter) || ci_contains(p->id, g_filter) ||
		                     ci_contains(p->name_zh, g_filter) || ci_contains(p->includes, g_filter) ||
		                     ci_contains(p->summary, g_filter) || ci_contains(p->summary_zh, g_filter)))
			continue;
		g_view[g_nview++] = i;
	}
	if (g_sel >= g_nview) g_sel = g_nview ? g_nview - 1 : 0;
	if (g_sel < 0) g_sel = 0;
}

/* -------------------------------------------------------------- buttons ---*/
enum { ACT_NONE = 0, ACT_INSTALL, ACT_REMOVE, ACT_SVC, ACT_BOOT, ACT_DOCS, ACT_SELECT, ACT_TAB };

typedef struct { int row, col, w, act, arg; } Hit;
static Hit g_hits[512];
static int g_nhits = 0;

typedef struct { char key; char label[48]; int act; int on; int dim; } Btn;

static int build_buttons(const Pkg *p, Btn *b)
{
	int n = 0;
	int installed = (p->status != ST_ABSENT && p->status != ST_UNKNOWN);

	b[n].key = 'i'; b[n].act = ACT_INSTALL; b[n].on = 0; b[n].dim = 0;
	copy_str(b[n].label, sizeof b[n].label, installed ? S(T_REINSTALL) : S(T_INSTALL));
	n++;

	b[n].key = 'x'; b[n].act = ACT_REMOVE; b[n].on = 0; b[n].dim = !installed;
	copy_str(b[n].label, sizeof b[n].label, S(T_REMOVE));
	n++;

	if (p->service[0]) {
		b[n].key = 's'; b[n].act = ACT_SVC; b[n].on = 0; b[n].dim = !installed;
		copy_str(b[n].label, sizeof b[n].label,
		         p->status == ST_RUNNING ? S(T_STOP) : S(T_START));
		n++;

		b[n].key = 'b'; b[n].act = ACT_BOOT; b[n].on = (p->enabled == 1); b[n].dim = !installed;
		snprintf(b[n].label, sizeof b[n].label, "%s%s",
		         p->enabled == 1 ? MK_OK : (p->enabled == 0 ? MK_NO : MK_DOT), S(T_BOOT));
		n++;
	}

	b[n].key = 'd'; b[n].act = ACT_DOCS; b[n].on = 0; b[n].dim = 0;
	copy_str(b[n].label, sizeof b[n].label, S(T_DOCS));
	n++;
	return n;
}

static int button_width(const Btn *b) { return 1 + 1 + 1 + u8width(b->label) + 1; } /* [k label] */

/* Buttons flow left to right and wrap; the caller uses the row count to make
 * every card the same height, so a grid never looks ragged. */
static int button_rows(const Btn *b, int n, int inner)
{
	int rows = 1, x = 0;
	for (int i = 0; i < n; i++) {
		int w = button_width(&b[i]);
		if (x && x + 1 + w > inner) { rows++; x = w; }
		else x += (x ? 1 : 0) + w;
	}
	return rows;
}

/* ----------------------------------------------------------------- cards ---*/
#define CARD_MIN 34
#define CARD_MAX 52
#define GAP 2

static int g_cols, g_cardw, g_cardh, g_top, g_viewh;

static const L *status_label(const Pkg *p)
{
	switch (p->status) {
	case ST_RUNNING:   return &T_RUNNING;
	case ST_STOPPED:   return &T_STOPPED;
	case ST_ABSENT:    return &T_ABSENT;
	case ST_INSTALLED: return &T_INSTALLED;
	case ST_BROKEN:    return &T_BROKEN;
	default:           return &T_CHECKING;
	}
}

static int status_attr(const Pkg *p)
{
	switch (p->status) {
	case ST_RUNNING: case ST_INSTALLED: return A_RUN;
	case ST_STOPPED: return A_STOP;
	case ST_BROKEN:  return A_ERR;
	case ST_ABSENT:  return A_ABSENT;
	default:         return A_DIM;
	}
}

static const char *status_mark(const Pkg *p)
{
	switch (p->status) {
	case ST_RUNNING:   return MK_RUN;
	case ST_INSTALLED: return MK_OK;
	case ST_STOPPED:   return MK_STOP;
	case ST_BROKEN:    return MK_ERR;
	case ST_ABSENT:    return MK_ABSENT;
	default:           return MK_DOT;
	}
}

/* Does this machine have the disk and memory the recipe asks for? Returned so
 * the card can say so before somebody spends ten minutes finding out. */
static int resource_short(const Pkg *p, int *disk_short, int *mem_short)
{
	*disk_short = (p->disk_bytes > 0 && g_sys.disk_free > 0 && p->disk_bytes > g_sys.disk_free);
	*mem_short  = (p->mem_bytes  > 0 && g_sys.mem_total > 0 && p->mem_bytes  > g_sys.mem_total);
	return *disk_short || *mem_short;
}

static void compute_layout(void)
{
	int avail = g_w - 2;
	g_cols = 3;
	while (g_cols > 1 && g_cols * CARD_MIN + (g_cols - 1) * GAP > avail) g_cols--;
	g_cardw = (avail - (g_cols - 1) * GAP) / g_cols;
	if (g_cardw > CARD_MAX) g_cardw = CARD_MAX;
	if (g_cardw < 24) g_cardw = avail > 24 ? avail : 24;

	int inner = g_cardw - 4;
	int brows = 1;
	for (int i = 0; i < g_nview; i++) {
		Btn b[8];
		int n = build_buttons(&g_pkg[g_view[i]], b);
		int r = button_rows(b, n, inner);
		if (r > brows) brows = r;
	}
	/* border, name, includes, 2 summary, resources, buttons, border */
	g_cardh = 6 + brows + 1;

	g_top = (g_h >= 14) ? 5 : 4;
	g_viewh = g_h - g_top - 1;
	if (g_viewh < g_cardh) g_viewh = g_cardh;
}

static void draw_card(int row, int col, Pkg *p, int selected)
{
	int inner = g_cardw - 4;
	int battr = selected ? A_BORDERSEL : A_BORDER;

	gput(row, col, BX_TL, battr, 1);
	gfill(row, col + 1, g_cardw - 2, BX_H, battr);
	gput(row, col + g_cardw - 1, BX_TR, battr, 1);
	for (int r = 1; r < g_cardh - 1; r++) {
		gput(row + r, col, BX_V, battr, 1);
		gput(row + r, col + g_cardw - 1, BX_V, battr, 1);
	}
	gput(row + g_cardh - 1, col, BX_BL, battr, 1);
	gfill(row + g_cardh - 1, col + 1, g_cardw - 2, BX_H, battr);
	gput(row + g_cardh - 1, col + g_cardw - 1, BX_BR, battr, 1);

	int x = col + 2, r = row + 1;

	/* name on the left, state on the right of the same line */
	char st[64];
	snprintf(st, sizeof st, "%s %s", status_mark(p), S(*status_label(p)));
	int stw = u8width(st);
	char nm[128];
	int nmw = u8trunc(nm, sizeof nm, pkg_name(p), inner - stw - 1);
	gput(r, x, nm, selected ? A_BORDERSEL : A_NAME, nmw);
	gput(r, x + inner - stw, st, status_attr(p), stw);
	r++;

	/* what it puts on the box, or what the recipe said when asked */
	char inc[320];
	const char *src = p->detail[0] && p->status != ST_ABSENT ? p->detail : pkg_includes(p);
	u8trunc(inc, sizeof inc, src, inner);
	gput(r, x, inc, A_DIM, inner);
	r++;

	char lines[2][512];
	int nl = u8wrap(pkg_summary(p), inner, lines, 2);
	for (int i = 0; i < 2; i++) {
		gput(r, x, i < nl ? lines[i] : "", A_NORM, inner);
		r++;
	}

	/* the size line, which is the point of the whole card for anyone on a
	 * small box: red when this machine cannot hold it */
	int ds = 0, ms = 0;
	resource_short(p, &ds, &ms);
	char res[256] = "";
	size_t rn = 0;
	if (p->disk[0]) rn += (size_t)snprintf(res + rn, sizeof res - rn, "%s %s", S(T_DISK), p->disk);
	if (p->memory[0]) rn += (size_t)snprintf(res + rn, sizeof res - rn, "%s%s %s",
	                                         rn ? " " : "", S(T_RAM), p->memory);
	if (p->ports[0]) rn += (size_t)snprintf(res + rn, sizeof res - rn, "%s%s %s",
	                                        rn ? " " : "", S(T_PORT), p->ports);
	if (p->requires[0] && rn < sizeof res - 32)
		snprintf(res + rn, sizeof res - rn, "%s%s %s", rn ? " " : "", S(T_NEEDS), p->requires);
	gput(r, x, res, (ds || ms) ? A_WARN : A_DIM, inner);
	r++;

	Btn b[8];
	int nb = build_buttons(p, b);
	int bx = 0, br = r;
	for (int i = 0; i < nb; i++) {
		int w = button_width(&b[i]);
		if (bx && bx + 1 + w > inner) { br++; bx = 0; }
		else if (bx) bx += 1;
		if (br >= row + g_cardh - 1) break;
		int attr = b[i].dim ? A_BTNOFF : A_BTN;
		gput(br, x + bx, "[", attr, 1);
		char kb[2] = { b[i].key, 0 };
		gput(br, x + bx + 1, kb, b[i].dim ? A_BTNOFF : A_BTNKEY, 1);
		gput(br, x + bx + 2, " ", attr, 1);
		int lw = gput(br, x + bx + 3, b[i].label, attr, inner - bx - 4);
		gput(br, x + bx + 3 + lw, "]", attr, 1);
		if (g_nhits < (int)(sizeof g_hits / sizeof g_hits[0])) {
			g_hits[g_nhits].row = br; g_hits[g_nhits].col = x + bx;
			g_hits[g_nhits].w = w; g_hits[g_nhits].act = b[i].act;
			g_hits[g_nhits].arg = (int)(p - g_pkg);
			g_nhits++;
		}
		bx += w;
	}
}

/* ------------------------------------------------------------------ chrome */
static void draw_header(void)
{
	char left[256];
	snprintf(left, sizeof left, "%s %s", S(T_TITLE), APP_VERSION);
	int x = gput(0, 1, left, A_TITLE, g_w - 2);
	gput(0, 1 + x + 1, S(T_SUBTITLE), A_DIM, g_w - x - 4);

	char right[128];
	const char *user = geteuid() == 0 ? "root" : (getenv("USER") ? getenv("USER") : "user");
	char host[64] = "";
	if (gethostname(host, sizeof host - 1) != 0) copy_str(host, sizeof host, "container");
	snprintf(right, sizeof right, "%s@%s", user, host);
	int rw = u8width(right);
	if (rw < g_w - 4) gput(0, g_w - 1 - rw, right, A_DIM, rw);

	if (g_h >= 14) {
		char mem[16], memf[16], disk[16], facts[320];
		human_size(g_sys.mem_total, mem, sizeof mem);
		human_size(g_sys.mem_avail, memf, sizeof memf);
		human_size(g_sys.disk_free, disk, sizeof disk);
		snprintf(facts, sizeof facts,
		         "%s %s %s %s %s %s %ld CPU %s %s %s (%s %s) %s %s %s",
		         g_sys.pretty, MK_DOT, g_sys.init, MK_DOT, g_sys.pm, MK_DOT,
		         g_sys.ncpu, MK_DOT, S(T_RAM), mem, memf,
		         g_zh ? "可用" : "free", MK_DOT, S(T_DISK), disk);
		gput(1, 1, facts, A_DIM, g_w - 2);
	}
}

static void draw_nav(void)
{
	int row = (g_h >= 14) ? 2 : 1;
	int x = 1;
	for (int i = 0; i < g_ncat; i++) {
		char lab[64];
		if (!cat_count(i)) continue;
		snprintf(lab, sizeof lab, " %s ", S(g_cats[i].label));
		int w = u8width(lab);
		if (x + w >= g_w - 1) break;
		gput(row, x, lab, (i == g_cat && !g_filter[0]) ? A_NAVSEL : A_NAV, w);
		if (g_nhits < (int)(sizeof g_hits / sizeof g_hits[0])) {
			g_hits[g_nhits].row = row; g_hits[g_nhits].col = x;
			g_hits[g_nhits].w = w; g_hits[g_nhits].act = ACT_TAB;
			g_hits[g_nhits].arg = i;
			g_nhits++;
		}
		x += w + 1;
	}

	int line = row + 1;
	gfill(line, 1, g_w - 2, BX_H, A_BORDER);
	if (g_searching || g_filter[0]) {
		char q[128];
		snprintf(q, sizeof q, " %s: %s%s ", S(T_SEARCH), g_filter, g_searching ? "_" : "");
		gput(line, 2, q, A_MSG, g_w - 4);
	} else if (g_msg[0]) {
		char m[300];
		snprintf(m, sizeof m, " %s ", g_msg);
		gput(line, 2, m, g_msg_attr, g_w - 4);
	}
}

static void draw_footer(void)
{
	char f[512];
	snprintf(f, sizeof f,
	         "%s %s  Tab %s  i %s  x %s  s %s  b %s  d %s  / %s  r %s  L %s  ? %s  q %s",
	         g_utf8 ? "↑↓←→" : "arrows", S(T_KEYS), S(T_CATS), S(T_INSTALL), S(T_REMOVE),
	         g_zh ? "启停" : "start/stop", S(T_BOOT), S(T_DOCS),
	         S(T_SEARCH), S(T_REFRESH), S(T_LANG), S(T_HELPKEY), S(T_QUIT));
	gput(g_h - 1, 1, f, A_FOOT, g_w - 2);
}

static void render(void)
{
	grid_size(g_w, g_h);
	grid_clear();
	g_nhits = 0;
	compute_layout();

	draw_header();
	draw_nav();
	draw_footer();

	if (g_npkg == 0) {
		gput(g_top + 1, 2, S(T_NORECIPE), A_WARN, g_w - 4);
		grid_flush();
		return;
	}
	if (g_nview == 0) {
		gput(g_top + 1, 2, S(T_EMPTY), A_DIM, g_w - 4);
		grid_flush();
		return;
	}

	int pitch = g_cardh + 1;
	int rows = (g_nview + g_cols - 1) / g_cols;
	int selrow = g_sel / g_cols;

	/* keep the selected card whole and on screen */
	int maxscroll = rows * pitch - g_viewh;
	if (maxscroll < 0) maxscroll = 0;
	if (selrow * pitch < g_scroll) g_scroll = selrow * pitch;
	if ((selrow + 1) * pitch - 1 > g_scroll + g_viewh)
		g_scroll = (selrow + 1) * pitch - g_viewh;
	if (g_scroll > maxscroll) g_scroll = maxscroll;
	if (g_scroll < 0) g_scroll = 0;

	for (int i = 0; i < g_nview; i++) {
		int r = (i / g_cols) * pitch - g_scroll;
		int c = 1 + (i % g_cols) * (g_cardw + GAP);
		if (r + g_cardh <= 0 || r >= g_viewh) continue;
		draw_card(g_top + r, c, &g_pkg[g_view[i]], i == g_sel);
		if (g_nhits < (int)(sizeof g_hits / sizeof g_hits[0])) {
			g_hits[g_nhits].row = g_top + r; g_hits[g_nhits].col = c;
			g_hits[g_nhits].w = g_cardw; g_hits[g_nhits].act = ACT_SELECT;
			g_hits[g_nhits].arg = i;
			g_nhits++;
		}
	}

	if (maxscroll > 0) {
		char sb[32];
		snprintf(sb, sizeof sb, " %d/%d ", g_sel + 1, g_nview);
		int w = u8width(sb);
		gput(g_h - 1, g_w - 1 - w, sb, A_DIM, w);
	}
	grid_flush();
}

/* -------------------------------------------------------------- overlays ---*/
static void pager(const char *title, const char *text)
{
	/* split into lines once; wrapping happens against the current width */
	int nline = 1;
	for (const char *p = text; *p; p++) if (*p == '\n') nline++;
	char **raw = xmalloc((size_t)nline * sizeof(char *));
	char *copy = xmalloc(strlen(text) + 1);
	strcpy(copy, text);
	int n = 0;
	char *save = copy;
	for (char *p = copy;; p++) {
		if (*p == '\n' || *p == '\0') {
			int end = (*p == '\0');
			*p = '\0';
			raw[n++] = save;
			save = p + 1;
			if (end) break;
		}
	}

	int scroll = 0;
	for (;;) {
		term_measure();
		grid_size(g_w, g_h);
		grid_clear();
		gput(0, 1, title, A_TITLE, g_w - 2);
		gfill(1, 1, g_w - 2, BX_H, A_BORDER);
		int body = g_h - 3;
		for (int i = 0; i < body && scroll + i < n; i++)
			gput(2 + i, 2, raw[scroll + i], A_NORM, g_w - 4);
		char foot[160];
		snprintf(foot, sizeof foot, g_zh ? "↑↓ 滚动   q/回车 返回   (%d/%d)"
		                                 : "↑↓ scroll   q/Enter back   (%d/%d)",
		         scroll + 1, n);
		gput(g_h - 1, 1, foot, A_FOOT, g_w - 2);
		grid_flush();

		int k = read_key();
		if (k == 'q' || k == K_ENTER || k == K_ESC) break;
		else if (k == K_DOWN || k == 'j') { if (scroll < n - 1) scroll++; }
		else if (k == K_UP || k == 'k')   { if (scroll > 0) scroll--; }
		else if (k == K_PGDN || k == ' ') scroll += body;
		else if (k == K_PGUP)             scroll -= body;
		else if (k == K_HOME)             scroll = 0;
		else if (k == K_END)              scroll = n - 1;
		if (scroll > n - 1) scroll = n - 1;
		if (scroll < 0) scroll = 0;
	}
	free(raw); free(copy);
}

static int confirm(const char *msg)
{
	term_measure();
	int w = u8width(msg) + 6;
	if (w > g_w - 4) w = g_w - 4;
	int h = 6;
	int row = (g_h - h) / 2, col = (g_w - w) / 2;

	for (int r = 0; r < h; r++) gfill(row + r, col, w, " ", A_INV);
	gput(row, col, BX_TL, A_BORDERSEL, 1);
	gfill(row, col + 1, w - 2, BX_H, A_BORDERSEL);
	gput(row, col + w - 1, BX_TR, A_BORDERSEL, 1);
	for (int r = 1; r < h - 1; r++) {
		gput(row + r, col, BX_V, A_BORDERSEL, 1);
		gfill(row + r, col + 1, w - 2, " ", A_NORM);
		gput(row + r, col + w - 1, BX_V, A_BORDERSEL, 1);
	}
	gput(row + h - 1, col, BX_BL, A_BORDERSEL, 1);
	gfill(row + h - 1, col + 1, w - 2, BX_H, A_BORDERSEL);
	gput(row + h - 1, col + w - 1, BX_BR, A_BORDERSEL, 1);

	char lines[2][512];
	int nl = u8wrap(msg, w - 4, lines, 2);
	for (int i = 0; i < nl; i++) gput(row + 1 + i, col + 2, lines[i], A_NORM, w - 4);
	gput(row + h - 2, col + 2, S(T_CONFIRM), A_DIM, w - 4);
	grid_flush();

	int k = read_key();
	return k == K_ENTER || k == 'y' || k == 'Y';
}

static void keys_overlay(void)
{
	char t[2048];
	if (g_zh) {
		snprintf(t, sizeof t,
		  "移动        ← → ↑ ↓  或 h j k l\n"
		  "切换分类    Tab / Shift+Tab，或数字 1-%d\n"
		  "安装        i        （已装则是重装）\n"
		  "卸载        x        会问一次\n"
		  "启动/停止   s\n"
		  "开机自启    b        对号表示开机会启动\n"
		  "使用说明    d 或回车  软件自己写的用法\n"
		  "搜索        /        输入后回车，Esc 清空\n"
		  "刷新状态    r\n"
		  "中英切换    L\n"
		  "退出        q\n"
		  "\n"
		  "鼠标也能用：点卡片选中，直接点按钮就执行。\n"
		  "\n"
		  "每次操作的完整输出都写到 %s/<软件>.log。\n"
		  "软件源在 /etc/app-setup/*.sh，自己加软件看\n"
		  "docs/app-setup-sources.md。", g_ncat, LOG_DIR);
	} else {
		snprintf(t, sizeof t,
		  "move          ← → ↑ ↓  or h j k l\n"
		  "category      Tab / Shift+Tab, or the digits 1-%d\n"
		  "install       i       (reinstall when already there)\n"
		  "remove        x       asks first\n"
		  "start/stop    s\n"
		  "start at boot b       the tick means it will\n"
		  "docs          d or Enter — what the recipe says about itself\n"
		  "search        /       Enter to keep it, Esc to clear\n"
		  "refresh       r\n"
		  "language      L\n"
		  "quit          q\n"
		  "\n"
		  "The mouse works too: click a card to select, click a button to run it.\n"
		  "\n"
		  "Every action's full output is appended to %s/<id>.log.\n"
		  "Sources live in /etc/app-setup/*.sh — to add your own, see\n"
		  "docs/app-setup-sources.md.", g_ncat, LOG_DIR);
	}
	pager(S(T_HELPTITLE), t);
}

/* ---------------------------------------------------------------- actions --*/
static const char *verb_for(int act, const Pkg *p)
{
	switch (act) {
	case ACT_INSTALL: return "install";
	case ACT_REMOVE:  return "uninstall";
	case ACT_SVC:     return p->status == ST_RUNNING ? "stop" : "start";
	case ACT_BOOT:    return p->enabled == 1 ? "disable" : "enable";
	}
	return NULL;
}

static void do_action(Pkg *p, int act)
{
	if (act == ACT_DOCS) {
		char out[16384];
		int rc = run_capture(p->path, "help", out, sizeof out, 20, 1);
		if (rc != 0 && !out[0])
			snprintf(out, sizeof out, "%s", g_zh ? "这个软件源没有写说明。"
			                                     : "This source ships no documentation.");
		char title[160];
		snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_DOCS));
		pager(title, out);
		return;
	}

	const char *verb = verb_for(act, p);
	if (!verb) return;

	if (act == ACT_REMOVE) {
		char q[300];
		snprintf(q, sizeof q, S(T_REMOVEQ), pkg_name(p));
		if (!confirm(q)) return;
	}
	if (act == ACT_INSTALL) {
		int ds = 0, ms = 0;
		if (resource_short(p, &ds, &ms)) {
			char have[16], q[400];
			human_size(ds ? g_sys.disk_free : g_sys.mem_total, have, sizeof have);
			snprintf(q, sizeof q, S(T_TIGHTQ), pkg_name(p),
			         ds ? p->disk : p->memory, have);
			if (!confirm(q)) {
				snprintf(g_msg, sizeof g_msg, "%s", ds ? S(T_TIGHT_D) : S(T_TIGHT_M));
				g_msg_attr = A_WARN;
				return;
			}
		}
	}

	char log[600];
	snprintf(log, sizeof log, "%s/%s.log", LOG_DIR, p->id);

	term_cooked();
	printf("\x1b[2J\x1b[H");
	printf("==> %s %s %s\n", S(T_WORKING), pkg_name(p), verb);
	printf("    %s\n\n", p->path);
	fflush(stdout);

	int rc = run_stream(p->path, verb, log);

	printf("\n");
	if (rc == 0) {
		printf("==> ");
		printf(S(T_OK), pkg_name(p), verb);
		printf("\n");
		snprintf(g_msg, sizeof g_msg, S(T_OK), pkg_name(p), verb);
		g_msg_attr = A_RUN;
	} else {
		printf("==> ");
		printf(S(T_FAIL), pkg_name(p), verb, rc, log);
		printf("\n");
		snprintf(g_msg, sizeof g_msg, S(T_FAIL), pkg_name(p), verb, rc, log);
		g_msg_attr = A_ERR;
	}
	printf("%s\n", S(T_ANYKEY));
	fflush(stdout);

	/* cooked mode is back, so this is an ordinary line read */
	int c;
	while ((c = getchar()) != '\n' && c != EOF) { }

	term_raw();
	probe_pkg(p);
}

/* ------------------------------------------------------------------- TUI ---*/
static void probe_all(int quiet)
{
	for (int i = 0; i < g_npkg; i++) {
		if (!quiet) {
			fprintf(stderr, "\r%s %d/%d  %-24s",
			        g_zh ? "检查已装软件" : "checking installed software",
			        i + 1, g_npkg, g_pkg[i].id);
			fflush(stderr);
		}
		probe_pkg(&g_pkg[i]);
	}
	if (!quiet) fprintf(stderr, "\r\x1b[K");
}

static void tui(void)
{
	signal(SIGWINCH, on_winch);
	signal(SIGTERM, on_fatal);
	signal(SIGHUP, on_fatal);
	signal(SIGPIPE, SIG_IGN);

	probe_all(0);
	if (geteuid() != 0) {
		copy_str(g_msg, sizeof g_msg, S(T_ROOTWARN));
		g_msg_attr = A_WARN;
	}

	term_raw();
	atexit(term_cooked);
	term_measure();
	rebuild_view();

	for (;;) {
		term_measure();
		rebuild_view();
		render();

		int k = read_key();
		if (k == K_NONE) continue;
		if (k == K_RESIZE) continue;

		if (g_searching) {
			if (k == K_ENTER) { g_searching = 0; }
			else if (k == K_ESC) { g_searching = 0; g_filter[0] = '\0'; }
			else if (k == K_BACK) {
				size_t n = strlen(g_filter);
				/* step back over a whole UTF-8 character */
				while (n && ((unsigned char)g_filter[n-1] & 0xC0) == 0x80) n--;
				if (n) n--;
				g_filter[n] = '\0';
			} else if (k >= 32 && k < 256) {
				size_t n = strlen(g_filter);
				if (n < sizeof g_filter - 2) { g_filter[n] = (char)k; g_filter[n+1] = '\0'; }
			}
			g_sel = 0; g_scroll = 0;
			continue;
		}

		Pkg *cur = g_nview ? &g_pkg[g_view[g_sel]] : NULL;
		switch (k) {
		case 'q': case 'Q': term_cooked(); return;
		case K_ESC:
			if (g_filter[0]) { g_filter[0] = '\0'; g_sel = 0; }
			break;
		case '/': g_searching = 1; g_filter[0] = '\0'; break;
		case 'r': case 'R':
			copy_str(g_msg, sizeof g_msg, g_zh ? "正在刷新…" : "refreshing…");
			g_msg_attr = A_DIM;
			render();
			for (int i = 0; i < g_nview; i++) probe_pkg(&g_pkg[g_view[i]]);
			g_msg[0] = '\0';
			break;
		case 'L': g_zh = !g_zh; break;
		case '?': case 'H': keys_overlay(); break;
		case K_TAB:  g_filter[0] = '\0'; g_cat = cat_step(g_cat,  1); g_sel = 0; g_scroll = 0; break;
		case K_BTAB: g_filter[0] = '\0'; g_cat = cat_step(g_cat, -1); g_sel = 0; g_scroll = 0; break;
		case K_LEFT: case 'h': if (g_sel > 0) g_sel--; break;
		case K_RIGHT: case 'l': if (g_sel < g_nview - 1) g_sel++; break;
		case K_UP: case 'k':
			if (g_sel - g_cols >= 0) g_sel -= g_cols;
			else g_sel = 0;
			break;
		case K_DOWN: case 'j':
			if (g_sel + g_cols < g_nview) g_sel += g_cols;
			else g_sel = g_nview ? g_nview - 1 : 0;
			break;
		case K_HOME: g_sel = 0; break;
		case K_END:  g_sel = g_nview ? g_nview - 1 : 0; break;
		case K_PGUP: g_sel -= g_cols * 2; if (g_sel < 0) g_sel = 0; break;
		case K_PGDN: g_sel += g_cols * 2; if (g_sel >= g_nview) g_sel = g_nview ? g_nview - 1 : 0; break;
		case 'i': if (cur) do_action(cur, ACT_INSTALL); break;
		case 'x': if (cur) do_action(cur, ACT_REMOVE); break;
		case 's': if (cur && cur->service[0]) do_action(cur, ACT_SVC); break;
		case 'b': if (cur && cur->service[0]) do_action(cur, ACT_BOOT); break;
		case 'd': case K_ENTER: if (cur) do_action(cur, ACT_DOCS); break;
		case K_MOUSE:
			for (int i = 0; i < g_nhits; i++) {
				Hit *ht = &g_hits[i];
				if (g_my != ht->row || g_mx < ht->col || g_mx >= ht->col + ht->w) continue;
				if (ht->act == ACT_TAB) { g_filter[0] = '\0'; g_cat = ht->arg; g_sel = 0; g_scroll = 0; }
				else if (ht->act == ACT_SELECT) g_sel = ht->arg;
				else { g_sel = -1;
					for (int v = 0; v < g_nview; v++) if (g_view[v] == ht->arg) g_sel = v;
					if (g_sel < 0) g_sel = 0;
					do_action(&g_pkg[ht->arg], ht->act);
				}
				break;      /* buttons are drawn after cards, so first hit wins */
			}
			break;
		default:
			if (k >= '1' && k <= '9') {
				int i = cat_nth_shown(k - '1');
				if (i >= 0) { g_filter[0] = '\0'; g_cat = i; g_sel = 0; g_scroll = 0; }
			}
			break;
		}
	}
}

/* ------------------------------------------------------------------- CLI ---*/
static Pkg *find_pkg(const char *id)
{
	for (int i = 0; i < g_npkg; i++)
		if (!strcmp(g_pkg[i].id, id)) return &g_pkg[i];
	for (int i = 0; i < g_npkg; i++)
		if (!strcasecmp(g_pkg[i].name, id)) return &g_pkg[i];
	return NULL;
}

static const char *state_word(const Pkg *p)
{
	switch (p->status) {
	case ST_RUNNING:   return "running";
	case ST_STOPPED:   return "stopped";
	case ST_ABSENT:    return "absent";
	case ST_INSTALLED: return "installed";
	case ST_BROKEN:    return "error";
	default:           return "unknown";
	}
}

static int cli_list(const char *cat)
{
	printf("%-16s %-11s %-9s %-8s %s\n", "ID", "STATE", "DISK", "RAM", "NAME");
	for (int i = 0; i < g_npkg; i++) {
		Pkg *p = &g_pkg[i];
		if (cat && !pkg_in_cat(p, cat)) continue;
		probe_pkg(p);
		printf("%-16s %-11s %-9s %-8s %s\n", p->id, state_word(p),
		       p->disk[0] ? p->disk : "-", p->memory[0] ? p->memory : "-", p->name);
	}
	return 0;
}

static int cli_info(const char *id)
{
	Pkg *p = find_pkg(id);
	if (!p) { fprintf(stderr, "app-setup: no such software: %s\n", id); return 1; }
	probe_pkg(p);
	printf("id:        %s\n", p->id);
	printf("name:      %s%s%s\n", p->name, p->name_zh[0] ? " / " : "", p->name_zh);
	printf("category:  ");
	for (int i = 0; i < p->ncats; i++) printf("%s%s", i ? "," : "", p->cats[i]);
	printf("\n");
	printf("state:     %s%s%s\n", state_word(p), p->detail[0] ? " — " : "", p->detail);
	if (p->service[0])  printf("service:   %s (boot: %s)\n", p->service,
	                           p->enabled == 1 ? "yes" : p->enabled == 0 ? "no" : "unknown");
	if (p->includes[0]) printf("includes:  %s\n", p->includes);
	if (p->disk[0])     printf("disk:      %s\n", p->disk);
	if (p->memory[0])   printf("memory:    %s\n", p->memory);
	if (p->ports[0])    printf("ports:     %s\n", p->ports);
	if (p->requires[0]) printf("requires:  %s\n", p->requires);
	printf("recipe:    %s\n", p->path);
	printf("summary:   %s\n", p->summary);
	return 0;
}

static int cli_run(const char *verb, int argc, char **argv)
{
	int rc = 0;
	for (int i = 0; i < argc; i++) {
		Pkg *p = find_pkg(argv[i]);
		if (!p) { fprintf(stderr, "app-setup: no such software: %s\n", argv[i]); rc = 1; continue; }
		char log[600];
		snprintf(log, sizeof log, "%s/%s.log", LOG_DIR, p->id);
		int r = run_stream(p->path, verb, log);
		if (r != 0) {
			fprintf(stderr, "app-setup: %s %s failed (exit %d), see %s\n", verb, p->id, r, log);
			rc = r;
		}
	}
	return rc;
}

static int cli_status(int argc, char **argv)
{
	if (argc == 0) return cli_list(NULL);
	int rc = 0;
	for (int i = 0; i < argc; i++) {
		Pkg *p = find_pkg(argv[i]);
		if (!p) { fprintf(stderr, "app-setup: no such software: %s\n", argv[i]); rc = 1; continue; }
		probe_pkg(p);
		printf("%s %s%s%s\n", p->id, state_word(p), p->detail[0] ? " — " : "", p->detail);
		if (p->status == ST_ABSENT) rc = rc ? rc : 2;
	}
	return rc;
}

static int cli_doctor(void)
{
	char mem[16], memf[16], disk[16];
	human_size(g_sys.mem_total, mem, sizeof mem);
	human_size(g_sys.mem_avail, memf, sizeof memf);
	human_size(g_sys.disk_free, disk, sizeof disk);
	printf("app-setup   %s\n", APP_VERSION);
	printf("system      %s (%s)\n", g_sys.pretty, g_sys.id);
	printf("init        %s\n", g_sys.init);
	printf("packages    %s\n", g_sys.pm);
	printf("cpu         %ld\n", g_sys.ncpu);
	printf("memory      %s total, %s available\n", mem, memf);
	printf("disk free   %s on /\n", disk);
	printf("root        %s\n", geteuid() == 0 ? "yes" : (have_cmd("sudo") ? "no, sudo present" : "no, and no sudo"));
	printf("sources     %s\n", getenv("APP_SETUP_PATH") ? getenv("APP_SETUP_PATH") : DEFAULT_PATH);
	printf("recipes     %d\n", g_npkg);
	printf("logs        %s\n", LOG_DIR);
	int bad = 0;
	for (int i = 0; i < g_npkg; i++) {
		if (access(g_pkg[i].path, R_OK) != 0) { printf("unreadable  %s\n", g_pkg[i].path); bad++; }
		if (!g_pkg[i].summary[0])             { printf("no summary  %s\n", g_pkg[i].id); bad++; }
	}
	printf("problems    %d\n", bad);
	return bad ? 1 : 0;
}

static void usage(FILE *f)
{
	fprintf(f,
	  "app-setup %s — install software into this container\n"
	  "\n"
	  "  app-setup                    the full-screen picker (this is the one you want)\n"
	  "  app-setup list [category]    everything, or one of: stack web db dev system\n"
	  "  app-setup info <id>          one package in detail\n"
	  "  app-setup status [id...]     state only; exit 2 when absent\n"
	  "  app-setup install <id>...\n"
	  "  app-setup remove <id>...\n"
	  "  app-setup start|stop|restart <id>...\n"
	  "  app-setup enable|disable <id>...   start at boot, or stop doing that\n"
	  "  app-setup docs <id>          what the recipe says about itself\n"
	  "  app-setup doctor             what this machine looks like to app-setup\n"
	  "  app-setup screenshot [--width N] [--height N] [--category C]\n"
	  "                               render one frame as plain text\n"
	  "\n"
	  "  --lang en|zh    override the language guessed from LANG\n"
	  "  --no-color      no escape sequences in the CLI output\n"
	  "  --version\n"
	  "\n"
	  "Sources are /etc/app-setup/*.sh; APP_SETUP_PATH overrides where they are\n"
	  "read from. Action output is appended to %s/<id>.log.\n",
	  APP_VERSION, LOG_DIR);
}

/* ------------------------------------------------------------------ main ---*/
int main(int argc, char **argv)
{
	const char *lang = getenv("APP_SETUP_LANG");
	if (!lang) lang = getenv("LC_ALL");
	if (!lang) lang = getenv("LC_MESSAGES");
	if (!lang) lang = getenv("LANG");
	if (lang && (strstr(lang, "zh") || strstr(lang, "ZH"))) g_zh = 1;

	const char *enc = getenv("LC_ALL");
	if (!enc) enc = getenv("LANG");
	g_utf8 = !enc || strstr(enc, "UTF-8") || strstr(enc, "utf8") ||
	         strstr(enc, "UTF8") || strstr(enc, "utf-8");
	if (!g_utf8) g_zh = 0;              /* a non-UTF-8 terminal cannot show it */
	if (getenv("NO_COLOR")) g_color = 0;
	if (getenv("APP_SETUP_ASCII")) g_utf8 = 0;
	pick_glyphs();

	/* global flags first, so they work in front of any subcommand */
	int n = 0;
	char *rest[64];
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--lang") && i + 1 < argc) {
			g_zh = !strncmp(argv[++i], "zh", 2);
		} else if (!strcmp(argv[i], "--no-color")) g_color = 0;
		else if (!strcmp(argv[i], "--ascii")) { g_utf8 = 0; g_zh = 0; pick_glyphs(); }
		else if (!strcmp(argv[i], "--version")) { printf("app-setup %s\n", APP_VERSION); return 0; }
		else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(stdout); return 0; }
		else if (n < 63) rest[n++] = argv[i];
	}
	rest[n] = NULL;

	probe_system();
	scan_all();
	mkdir(LOG_DIR, 0755);
	{ int first = cat_nth_shown(0); if (first >= 0) g_cat = first; }

	if (n == 0) {
		if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) {
			fprintf(stderr, "app-setup: not a terminal; try `app-setup list`\n");
			return 1;
		}
		tui();
		return 0;
	}

	const char *cmd = rest[0];
	int rc = 2, na = n - 1;
	char **aa = rest + 1;

	if (!strcmp(cmd, "list"))         rc = cli_list(na ? aa[0] : NULL);
	else if (!strcmp(cmd, "info"))    rc = na ? cli_info(aa[0]) : (usage(stderr), 2);
	else if (!strcmp(cmd, "status"))  rc = cli_status(na, aa);
	else if (!strcmp(cmd, "doctor"))  rc = cli_doctor();
	else if (!strcmp(cmd, "install")) rc = na ? cli_run("install", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "remove") || !strcmp(cmd, "uninstall"))
	                                  rc = na ? cli_run("uninstall", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "start"))   rc = na ? cli_run("start", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "stop"))    rc = na ? cli_run("stop", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "restart")) rc = na ? cli_run("restart", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "enable"))  rc = na ? cli_run("enable", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "disable")) rc = na ? cli_run("disable", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "docs") || !strcmp(cmd, "help")) {
		if (!na) { usage(stdout); return 0; }
		Pkg *p = find_pkg(aa[0]);
		if (!p) { fprintf(stderr, "app-setup: no such software: %s\n", aa[0]); return 1; }
		rc = run_stream(p->path, "help", NULL);
	} else if (!strcmp(cmd, "screenshot")) {
		/* One frame, no terminal needed. This is how the responsive layout is
		 * tested: render at 120, 80 and 40 columns and count the cards. */
		int w = 100, h = 30;
		const char *cat = NULL;
		for (int i = 1; i < n; i++) {
			if (!strcmp(rest[i], "--width") && i + 1 < n) w = atoi(rest[++i]);
			else if (!strcmp(rest[i], "--height") && i + 1 < n) h = atoi(rest[++i]);
			else if (!strcmp(rest[i], "--category") && i + 1 < n) cat = rest[++i];
			else if (!strcmp(rest[i], "--probe")) probe_all(1);
		}
		g_w = w > 24 ? w : 24;
		g_h = h > 10 ? h : 10;
		if (cat) { int i = cat_index(cat); if (i >= 0) g_cat = i; }
		g_color = 0;
		rebuild_view();
		grid_size(g_w, g_h);
		grid_clear();
		g_nhits = 0;
		compute_layout();
		draw_header();
		draw_nav();
		draw_footer();
		int pitch = g_cardh + 1;
		for (int i = 0; i < g_nview; i++) {
			int r = (i / g_cols) * pitch;
			int c = 1 + (i % g_cols) * (g_cardw + GAP);
			if (r >= g_viewh) break;
			draw_card(g_top + r, c, &g_pkg[g_view[i]], i == g_sel);
		}
		grid_dump(stdout);
		printf("\n[%d columns, card %d wide, %d of %d shown]\n",
		       g_cols, g_cardw, g_nview, g_npkg);
		rc = 0;
	} else {
		fprintf(stderr, "app-setup: unknown command: %s\n\n", cmd);
		usage(stderr);
		rc = 2;
	}
	return rc;
}
