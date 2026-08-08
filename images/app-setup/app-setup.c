/*
 * app-setup — the software manager inside a hqnode container.
 *
 * Someone who has been handed a container wants LNMP, or WordPress, or just
 * vim, and does not want to read three blog posts to get it. This draws the
 * catalogue and shells the actual work out to one script per package under
 * /etc/app-setup.
 *
 * The split matters. This binary knows nothing about nginx: it reads the
 * comment header of every *.sh it finds, asks each one `status`, and runs
 * `install` / `uninstall` / `start` / `stop` / `enable` / `disable` / `help`
 * when a key is pressed. Adding software is dropping a file in a directory —
 * see docs/app-setup-sources.md — and never touches this file.
 *
 * The screen is nmtui's, deliberately: blue root, grey windows, a cyan bar on
 * the selected row, a help line along the bottom. Anyone who has configured a
 * network on a Red Hat box already knows how to drive it, and the ones who
 * have not can drive it with four arrow keys, Enter and Space and nothing
 * else. No letter accelerators to memorise, no mouse to hunt with: you walk
 * into a list, you press Enter on a thing, and you get a menu of what can be
 * done to that thing. A television remote, not a keyboard shortcut sheet.
 *
 * It is C with nothing but libc so it can be linked static and copied into
 * every image we publish, Alpine's musl included. That rules out ncurses, so
 * the screen is a grid of cells rendered to ANSI by hand. It also rules out
 * wcwidth() being trustworthy across libcs, so the CJK width table below is
 * ours: the UI is bilingual and a window border that drifts by one column on
 * every Chinese label looks broken. And it rules out libm — the progress
 * curve below is written with multiplication for that reason, because the
 * L1 test compiles this with a bare `cc` against glibc, where pow() needs -lm.
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

#define APP_VERSION   "2.0.0"
#define MAX_PKGS      512
#define MAX_CATS      32
#define MAX_PARAMS    12
#define DEFAULT_PATH  "/etc/app-setup:/usr/local/etc/app-setup"
#define DEFAULT_STATE "/var/lib/app-setup"
#define LOG_DIR       "/var/log/app-setup"
#define LOG_KEEP      400        /* lines of a running action held for the pane */
#define LOG_COLS      512

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
static const L T_INSTALLP  = {"Installed",    "已安装"};
static const L T_CATS      = {"Categories",   "分类"};
static const L T_INSTALL   = {"Install",      "安装"};
static const L T_UPDATE    = {"Update / reinstall", "更新（重新安装）"};
static const L T_REMOVE    = {"Uninstall",    "卸载"};
static const L T_START     = {"Start",        "启动"};
static const L T_STOP      = {"Stop",         "停止"};
static const L T_RESTART   = {"Restart",      "重启"};
static const L T_BOOT      = {"Start at boot","开机自启"};
static const L T_STATUS    = {"Running state","运行状态"};
static const L T_DETAILS   = {"Details",      "详细信息"};
static const L T_PARAMS    = {"Settings",     "参数设置"};
static const L T_DOCS      = {"How to use it","使用说明"};
static const L T_RUNNING   = {"running",      "运行中"};
static const L T_STOPPED   = {"stopped",      "已停止"};
static const L T_ABSENT    = {"not installed","未安装"};
static const L T_INSTALLED = {"installed",    "已安装"};
static const L T_BROKEN    = {"error",        "出错"};
static const L T_CHECKING  = {"checking",     "检查中"};
static const L T_DISK      = {"Disk",         "磁盘"};
static const L T_RAM       = {"RAM",          "内存"};
static const L T_PORT      = {"Port",         "端口"};
static const L T_NEEDS     = {"Needs",        "依赖"};
static const L T_YES       = {"yes",          "是"};
static const L T_NO        = {"no",           "否"};
static const L T_ON        = {"on",           "开"};
static const L T_OFF       = {"off",          "关"};
static const L T_BACK      = {"Back",         "返回"};
static const L T_OK        = {"OK",           "确定"};
static const L T_CANCEL    = {"Cancel",       "取消"};
static const L T_CLOSE     = {"Close",        "关闭"};
static const L T_DONE      = {"Done",         "完成"};
static const L T_EMPTY     = {"Nothing in this category.", "这个分类下没有软件。"};
static const L T_NOINST    = {"Nothing installed yet.",    "还没有装任何软件。"};
static const L T_NORECIPE  = {"No software sources found. Put recipes in /etc/app-setup/*.sh.",
                             "没有找到软件源。把脚本放到 /etc/app-setup/*.sh。"};
static const L T_CONFIRM   = {"Enter confirms, Esc cancels", "回车确认，Esc 取消"};
static const L T_REMOVEQ   = {"Uninstall %s? Its configuration goes too; data is kept.",
                             "确定卸载 %s？配置会一起删除，数据会保留。"};
static const L T_TIGHTQ    = {"%s wants %s but this machine has %s. Install anyway?",
                             "%s 需要 %s，本机只有 %s。仍要安装吗？"};
static const L T_KILLQ     = {"Stop it now? A half-finished package manager has to be repaired by hand.",
                             "现在强行中止？包管理器装到一半，之后要手工修。"};
static const L T_ROOTWARN  = {"not root: actions will be run through sudo",
                             "当前不是 root：操作会走 sudo"};
static const L T_LOGPANE   = {"Details", "详细日志"};
static const L T_STEPOF    = {"Step %d of %d", "第 %d 步，共 %d 步"};
static const L T_WORKING   = {"Working…", "正在处理…"};
static const L T_FAILED    = {"%s failed — exit %d. The log is %s",
                             "%s 失败，退出码 %d。日志在 %s"};
static const L T_VERB_INS  = {"Installing %s", "正在安装 %s"};
static const L T_VERB_REM  = {"Uninstalling %s", "正在卸载 %s"};
static const L T_VERB_STA  = {"Starting %s", "正在启动 %s"};
static const L T_VERB_STO  = {"Stopping %s", "正在停止 %s"};
static const L T_VERB_RES  = {"Restarting %s", "正在重启 %s"};
static const L T_VERB_BOOT = {"Changing boot setting for %s", "正在修改 %s 的开机自启"};
static const L T_NODOC     = {"This source ships no documentation.", "这个软件源没有写说明。"};
static const L T_NOPARAM   = {"This software has no settings to change.",
                             "这个软件没有可以改的参数。"};
static const L T_PARAMSAVED= {"Settings saved. They apply the next time it is installed.",
                             "参数已保存，下次安装时生效。"};
static const L T_HELPMAIN  = {"↑↓ move   ←→ pane   Enter open   L 中文   q quit",
                             "↑↓ 选择   ←→ 换栏   回车 打开   L English   q 退出"};
static const L T_HELPMENU  = {"↑↓ move   Enter / Space run   ← Esc back",
                             "↑↓ 选择   回车/空格 执行   ← Esc 返回"};
static const L T_HELPFORM  = {"↑↓ field   Space toggle   ←→ choose   Enter OK   Esc cancel",
                             "↑↓ 换行   空格 切换   ←→ 选值   回车 确定   Esc 取消"};
static const L T_HELPPAGE  = {"↑↓ scroll   Enter / Esc back", "↑↓ 滚动   回车/Esc 返回"};
static const L T_HELPRUN   = {"Working — Esc twice to force a stop", "执行中 —— 按两次 Esc 可强行中止"};
static const L T_HELPDONE  = {"Enter to go back", "回车返回"};

/* The nav list, in the order it is shown. A recipe naming a category that is
 * not here gets one appended, labelled by its own `category.name:` — which is
 * how somebody's private source adds "Game servers" without a code change. */
static struct { char id[24]; L label; int owned; } g_cats[MAX_CATS] = {
	{"stack",  {"Suites",     "套件安装"},     0},
	{"web",    {"Web servers","Web 服务器"},   0},
	{"db",     {"Databases",  "数据库"},       0},
	{"dev",    {"Dev tools",  "开发插件"},     0},
	{"system", {"System",     "常用系统软件"}, 0},
};
static int g_ncat = 5;

/* ------------------------------------------------------------------ model */
enum { ST_UNKNOWN = 0, ST_RUNNING, ST_STOPPED, ST_ABSENT, ST_BROKEN, ST_INSTALLED };

/* A tunable a recipe declares in its header and reads back with `param`. The
 * type is inferred: `bool` gets a checkbox, a comma list gets a left/right
 * chooser, everything else is a text field. Anything more than that wants a
 * config file, not a form. */
enum { PT_TEXT = 0, PT_BOOL, PT_ENUM, PT_NUMBER };

typedef struct {
	char name[32];
	char label[64], label_zh[96];
	char dflt[128];
	char value[128];
	int  type;
	char choices[8][32];
	int  nchoices;
} Param;

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

	Param params[MAX_PARAMS];
	int  nparams;

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

static int ci_eq(const char *a, const char *b)
{
	while (*a && *b && tolower((unsigned char)*a) == tolower((unsigned char)*b)) { a++; b++; }
	return !*a && !*b;
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

static const char *state_dir(void)
{
	const char *e = getenv("APP_SETUP_STATE");
	return e && *e ? e : DEFAULT_STATE;
}

static const char *log_dir(void)
{
	const char *e = getenv("APP_SETUP_LOGDIR");
	return e && *e ? e : LOG_DIR;
}

/* mkdir -p, for the two directories we own. */
static void mkdir_p(const char *path)
{
	char buf[512];
	copy_str(buf, sizeof buf, path);
	for (char *p = buf + 1; *p; p++) {
		if (*p != '/') continue;
		*p = '\0';
		mkdir(buf, 0755);
		*p = '/';
	}
	mkdir(buf, 0755);
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

/* Truncate to `cols` and mark it with an ellipsis when something was cut, so a
 * clipped summary does not read as a sentence that simply stops. */
static void u8ellipsis(char *dst, size_t cap, const char *src, int cols)
{
	if (u8width(src) <= cols) { copy_str(dst, cap, src); return; }
	if (cols < 2) { u8trunc(dst, cap, src, cols); return; }
	int w = u8trunc(dst, cap, src, cols - 1);
	(void)w;
	size_t n = strlen(dst);
	if (n + 4 < cap) strcpy(dst + n, "…");
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
			if (c == '\n') { p = nx; break; }
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
	if (f) {
		char line[256];
		while (fgets(line, sizeof line, f)) {
			long long kb;
			if (sscanf(line, "MemTotal: %lld kB", &kb) == 1)     g_sys.mem_total = kb * 1024;
			else if (sscanf(line, "MemAvailable: %lld kB", &kb) == 1) g_sys.mem_avail = kb * 1024;
		}
		fclose(f);
	}
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

/* -------------------------------------------------------------- subprocess --
 *
 * Three shapes. `run_capture` is for the fast, silent verbs — status and
 * help — and holds a deadline because one hung recipe must not freeze the
 * catalogue. `run_stream` is for the CLI: output straight through to the
 * terminal. `runner_*` is for the TUI's progress screen, which has to keep
 * drawing while the child runs and so cannot block on a read.
 */
static Pkg *g_env_pkg = NULL;      /* whose params to export to the child */

static void child_env(void)
{
	setenv("APP_SETUP", APP_VERSION, 1);
	setenv("APP_SETUP_LANG", g_zh ? "zh" : "en", 1);
	setenv("DEBIAN_FRONTEND", "noninteractive", 1);
	setenv("NEEDRESTART_MODE", "a", 1);
	if (!getenv("LC_ALL")) setenv("LC_ALL", "C.UTF-8", 0);

	/* Saved settings arrive as APP_PARAM_<NAME>. A recipe reads them with
	 * `param name`, and one that declares none never sees any. */
	if (g_env_pkg) {
		for (int i = 0; i < g_env_pkg->nparams; i++) {
			Param *pm = &g_env_pkg->params[i];
			char key[64];
			snprintf(key, sizeof key, "APP_PARAM_%s", pm->name);
			for (char *q = key + 10; *q; q++) *q = (char)toupper((unsigned char)*q);
			setenv(key, pm->value[0] ? pm->value : pm->dflt, 1);
		}
	}
}

/* Everything is `sh <recipe> <verb>`. When app-setup is not root — which is
 * the odd case, but somebody will do it — the same line goes through sudo,
 * and -E is what keeps APP_SETUP_LANG and the parameters across the border. */
static void exec_recipe(const char *script, const char *verb)
{
	if (geteuid() != 0 && have_cmd("sudo"))
		execlp("sudo", "sudo", "-E", "/bin/sh", script, verb, (char *)NULL);
	execl("/bin/sh", "sh", script, verb, (char *)NULL);
	_exit(127);
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

static int open_log(const char *logpath, const char *script, const char *verb)
{
	if (!logpath) return -1;
	mkdir_p(log_dir());
	int fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0640);
	if (fd < 0) return -1;
	char hdr[600];
	time_t now = time(NULL);
	struct tm tm;
	gmtime_r(&now, &tm);
	int n = snprintf(hdr, sizeof hdr,
	                 "\n===== %04d-%02d-%02dT%02d:%02d:%02dZ  %s %s =====\n",
	                 tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
	                 tm.tm_hour, tm.tm_min, tm.tm_sec, script, verb);
	if (write(fd, hdr, (size_t)n) < 0) { /* the log is best effort */ }
	return fd;
}

static int run_stream(const char *script, const char *verb, const char *logpath)
{
	int pfd[2];
	if (pipe(pfd) != 0) return -1;
	int logfd = open_log(logpath, script, verb);

	pid_t pid = fork();
	if (pid < 0) { close(pfd[0]); close(pfd[1]); if (logfd >= 0) close(logfd); return -1; }
	if (pid == 0) {
		close(pfd[0]);
		dup2(pfd[1], STDOUT_FILENO);
		dup2(pfd[1], STDERR_FILENO);
		close(pfd[1]);
		child_env();
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

/* `param: name | default | English label | 中文标签 | type-or-choices`
 *
 * Everything after the name is optional. The type field is `bool`, `number`,
 * or a comma-separated list of the values it may take; anything else, or
 * nothing, is a text field. */
static void add_param(Pkg *p, const char *spec)
{
	if (p->nparams >= MAX_PARAMS) return;
	char buf[512];
	copy_str(buf, sizeof buf, spec);

	char *f[5] = { buf, NULL, NULL, NULL, NULL };
	int nf = 1;
	for (char *q = buf; *q && nf < 5; q++)
		if (*q == '|') { *q = '\0'; f[nf++] = q + 1; }
	for (int i = 0; i < nf; i++) trim(f[i]);
	if (!*f[0]) return;

	Param *pm = &p->params[p->nparams];
	memset(pm, 0, sizeof *pm);
	copy_str(pm->name, sizeof pm->name, f[0]);
	/* The name becomes an environment variable, so it has to look like one. */
	for (char *q = pm->name; *q; q++)
		if (!isalnum((unsigned char)*q) && *q != '_') *q = '_';
	if (nf > 1) copy_str(pm->dflt, sizeof pm->dflt, f[1]);
	copy_str(pm->label, sizeof pm->label, nf > 2 && *f[2] ? f[2] : pm->name);
	copy_str(pm->label_zh, sizeof pm->label_zh, nf > 3 && *f[3] ? f[3] : pm->label);
	copy_str(pm->value, sizeof pm->value, pm->dflt);

	const char *ty = nf > 4 ? f[4] : "";
	if (!strcmp(ty, "bool"))        pm->type = PT_BOOL;
	else if (!strcmp(ty, "number")) pm->type = PT_NUMBER;
	else if (strchr(ty, ',')) {
		pm->type = PT_ENUM;
		char tmp[256];
		copy_str(tmp, sizeof tmp, ty);
		char *tok = strtok(tmp, ",");
		while (tok && pm->nchoices < 8) {
			trim(tok);
			if (*tok) copy_str(pm->choices[pm->nchoices++], sizeof pm->choices[0], tok);
			tok = strtok(NULL, ",");
		}
		if (pm->nchoices < 2) pm->type = PT_TEXT;
	} else pm->type = PT_TEXT;

	p->nparams++;
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
	else if (!strcmp(k, "param"))       add_param(p, v);
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
	while (fgets(line, sizeof line, f) && seen++ < 160) {
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

/* Saved settings live beside the state a recipe keeps, one file per package,
 * `NAME=value` a line. Written by the form, read here, and handed to every
 * verb as environment. A value the recipe no longer declares is dropped on
 * the next save rather than kept forever. */
static void params_path(const Pkg *p, char *out, size_t cap)
{
	snprintf(out, cap, "%.400s/params/%.64s.conf", state_dir(), p->id);
}

static void params_load(Pkg *p)
{
	if (!p->nparams) return;
	char path[600];
	params_path(p, path, sizeof path);
	FILE *f = fopen(path, "r");
	if (!f) return;
	char line[512];
	while (fgets(line, sizeof line, f)) {
		trim(line);
		if (!*line || *line == '#') continue;
		char *eq = strchr(line, '=');
		if (!eq) continue;
		*eq = '\0';
		trim(line);
		for (int i = 0; i < p->nparams; i++)
			if (ci_eq(p->params[i].name, line))
				copy_str(p->params[i].value, sizeof p->params[i].value, eq + 1);
	}
	fclose(f);
}

static int params_save(const Pkg *p)
{
	char dir[600], path[600];
	snprintf(dir, sizeof dir, "%s/params", state_dir());
	mkdir_p(dir);
	params_path(p, path, sizeof path);
	FILE *f = fopen(path, "w");
	if (!f) return 0;
	fprintf(f, "# app-setup settings for %s — edited by the Settings form.\n", p->id);
	for (int i = 0; i < p->nparams; i++)
		fprintf(f, "%s=%s\n", p->params[i].name, p->params[i].value);
	fclose(f);
	return 1;
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
	for (int i = 0; i < g_npkg; i++) params_load(&g_pkg[i]);
}

/* status: exit code carries the state, stdout carries `key=value` detail.
 * One fork per package rather than two, because `enabled` comes back in the
 * same breath. */
static void probe_pkg(Pkg *p)
{
	char out[2048];
	g_env_pkg = p;
	int rc = run_capture(p->path, "status", out, sizeof out, 8, 0);
	g_env_pkg = NULL;

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

static int pkg_installed(const Pkg *p)
{
	return p->status == ST_RUNNING || p->status == ST_STOPPED ||
	       p->status == ST_INSTALLED || p->status == ST_BROKEN;
}

/* ------------------------------------------------------------------ screen --
 *
 * Cells rather than a stream of escapes: one write per frame (no flicker), and
 * the same code path can dump a frame as plain text, which is how the layout
 * gets tested without a terminal.
 *
 * The palette is newt's, so that this and nmtui look like the same program.
 * The root window is white on blue; windows are black on light grey with a
 * black shadow; the row you are on is black on cyan; the help line is white
 * on black. Sixteen colours, because a container's terminal is whatever the
 * holder happened to ssh in with.
 */
enum {
	P_ROOT = 0, P_ROOTTITLE, P_ROOTDIM,
	P_WIN, P_BORDER, P_TITLE, P_SHADOW,
	P_SEL, P_SELDIM, P_IDLE,
	P_BTN, P_BTNACT,
	P_ENTRY, P_ENTRYACT,
	P_HELP,
	P_RUN, P_STOPPED, P_ABSENT, P_ERR, P_WARN, P_DIM,
	P_BARFULL, P_BAREMPTY,
	P_COUNT
};

static const char *SGR[P_COUNT] = {
	"0;37;44",       /* ROOT      white on blue                       */
	"0;1;37;44",     /* ROOTTITLE bold white on blue                  */
	"0;36;44",       /* ROOTDIM   cyan on blue — the facts line       */
	"0;30;47",       /* WIN       black on light grey                 */
	"0;30;47",       /* BORDER    black on light grey                 */
	"0;1;34;47",     /* TITLE     bold blue on light grey             */
	"0;30;40",       /* SHADOW    black on black                      */
	"0;30;46",       /* SEL       black on cyan — the row you are on  */
	"0;34;46",       /* SELDIM    blue on cyan — its second line      */
	"0;34;47",       /* IDLE      blue on grey — selected, not focused*/
	"0;30;46",       /* BTN       black on cyan                       */
	"0;1;37;46",     /* BTNACT    bold white on cyan                  */
	"0;30;47",       /* ENTRY     black on grey                       */
	"0;30;46",       /* ENTRYACT  black on cyan                       */
	"0;37;40",       /* HELP      white on black                      */
	"0;32;47",       /* RUN       green on grey                       */
	"0;33;47",       /* STOPPED   yellow on grey                      */
	"0;1;30;47",     /* ABSENT    grey on grey                        */
	"0;1;31;47",     /* ERR       bold red on grey                    */
	"0;31;47",       /* WARN      red on grey                         */
	"0;1;30;47",     /* DIM       grey on grey                        */
	"0;1;34;44",     /* BARFULL   blue on blue                        */
	"0;37;47",       /* BAREMPTY  grey on grey                        */
};

typedef struct { char ch[5]; unsigned char attr; unsigned char cont; } Cell;

static Cell *g_grid = NULL;
static int g_w = 80, g_h = 24, g_gw = 0, g_gh = 0;
static int g_color = 1, g_utf8 = 1;

static const char *BX_TL, *BX_TR, *BX_BL, *BX_BR, *BX_H, *BX_V;
static const char *BX_LT, *BX_RT;
static const char *MK_RUN, *MK_STOP, *MK_ABSENT, *MK_ERR, *MK_OK, *MK_DOT;
static const char *BAR_F, *BAR_E, *AR_L, *AR_R, *AR_UD;

static void pick_glyphs(void)
{
	if (g_utf8) {
		BX_TL = "┌"; BX_TR = "┐"; BX_BL = "└"; BX_BR = "┘";
		BX_H  = "─"; BX_V  = "│"; BX_LT = "├"; BX_RT = "┤";
		MK_RUN = "●"; MK_STOP = "○"; MK_ABSENT = "·";
		MK_ERR = "✗"; MK_OK = "✓"; MK_DOT = "·";
		BAR_F = "█"; BAR_E = "░";
		AR_L = "◄"; AR_R = "►"; AR_UD = "↑↓";
	} else {
		BX_TL = "+"; BX_TR = "+"; BX_BL = "+"; BX_BR = "+";
		BX_H = "-"; BX_V = "|"; BX_LT = "+"; BX_RT = "+";
		MK_RUN = "*"; MK_STOP = "o"; MK_ABSENT = "-";
		MK_ERR = "x"; MK_OK = "+"; MK_DOT = "-";
		BAR_F = "#"; BAR_E = "-";
		AR_L = "<"; AR_R = ">"; AR_UD = "^v";
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

static void grid_clear(int attr)
{
	for (int i = 0; i < g_gw * g_gh; i++) {
		g_grid[i].ch[0] = ' '; g_grid[i].ch[1] = '\0';
		g_grid[i].attr = (unsigned char)attr;
		g_grid[i].cont = 0;
	}
}

/* Rows outside this band are dropped, so a list that is taller than its pane
 * is clipped rather than drawn over the chrome below it. -1 is no clipping,
 * which is every caller outside a scrolling list. Bounds are inclusive. */
static int g_clip_top = -1, g_clip_bot = -1;

static int row_visible(int row)
{
	return g_clip_top < 0 || (row >= g_clip_top && row <= g_clip_bot);
}

/* Writes up to `maxw` columns and returns how many it used. */
static int gput(int row, int col, const char *s, int attr, int maxw)
{
	if (row < 0 || row >= g_gh) return 0;
	if (!row_visible(row)) return 0;
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

/* Paint a background without disturbing what is already written on it — used
 * to lay a selection bar under a row that has already been composed. */
static void gtint(int row, int col, int w, int attr)
{
	if (row < 0 || row >= g_gh || !row_visible(row)) return;
	for (int i = 0; i < w; i++) {
		int c = col + i;
		if (c < 0 || c >= g_gw) continue;
		g_grid[row * g_gw + c].attr = (unsigned char)attr;
	}
}

/* Every cell is emitted, background included: a blue root that stopped at the
 * last non-space column would show the terminal's own background for the rest
 * of the line, which is the one thing that makes this look unlike nmtui. */
static void grid_flush(void)
{
	static char *out = NULL;
	static size_t cap = 0;
	size_t need = (size_t)g_gw * (size_t)g_gh * 16 + 64;
	if (need > cap) { free(out); out = xmalloc(need); cap = need; }

	size_t n = 0;
	n += (size_t)sprintf(out + n, "\x1b[H");
	for (int r = 0; r < g_gh; r++) {
		int attr = -1;
		n += (size_t)sprintf(out + n, "\x1b[%d;1H", r + 1);
		for (int c = 0; c < g_gw; c++) {
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
	/* alt screen, cursor off. No mouse reporting: everything here is
	 * reachable from the arrow keys, and a terminal that grabs the mouse
	 * takes copy-and-paste away from the holder for no gain. */
	if (write(STDOUT_FILENO, "\x1b[?1049h\x1b[?25l\x1b[2J", 17) < 0) { }
}

static void term_cooked(void)
{
	if (!g_raw) return;
	if (write(STDOUT_FILENO, "\x1b[0m\x1b[?25h\x1b[?1049l", 18) < 0) { }
	tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_saved_tio);
	g_raw = 0;
}

static void on_fatal(int sig) { term_cooked(); _exit(128 + sig); }

enum {
	K_NONE = 0, K_UP = 256, K_DOWN, K_LEFT, K_RIGHT, K_PGUP, K_PGDN,
	K_HOME, K_END, K_TAB, K_BTAB, K_ENTER, K_ESC, K_BACK, K_RESIZE, K_TIMEOUT
};

static int read_byte(int timeout_ms, unsigned char *out)
{
	struct pollfd p = { STDIN_FILENO, POLLIN, 0 };
	int r = poll(&p, 1, timeout_ms);
	if (r <= 0) return r;
	return read(STDIN_FILENO, out, 1) == 1 ? 1 : -1;
}

/* timeout_ms < 0 blocks. A SIGWINCH lands as K_RESIZE straight away because
 * the handler is installed without SA_RESTART — with it, a resize would sit
 * unnoticed inside read() until the next keypress, which is exactly the bug
 * where you drag the window and nothing happens. */
static int read_key_to(int timeout_ms)
{
	unsigned char c;
	if (g_resized) { g_resized = 0; return K_RESIZE; }
	if (timeout_ms >= 0) {
		struct pollfd p = { STDIN_FILENO, POLLIN, 0 };
		int r = poll(&p, 1, timeout_ms);
		if (r < 0) { if (g_resized) { g_resized = 0; return K_RESIZE; } return K_NONE; }
		if (r == 0) return K_TIMEOUT;
	}
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
			if ((x >= 'A' && x <= 'Z') || x == '~') break;
		}
		seq[len] = '\0';
		if (len == 0) return K_ESC;
		switch (seq[len - 1]) {
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

static int read_key(void) { return read_key_to(-1); }

/* ------------------------------------------------------------- widgets ---*/

/* A newt window: a shadow one row down and two columns right, a border, and a
 * title sitting in the top edge. Everything modal in here is one of these. */
static void win_box(int row, int col, int w, int h, const char *title)
{
	for (int r = row + 1; r <= row + h; r++)
		gfill(r, col + w, 2, " ", P_SHADOW);
	gfill(row + h, col + 2, w - 2, " ", P_SHADOW);

	gput(row, col, BX_TL, P_BORDER, 1);
	gfill(row, col + 1, w - 2, BX_H, P_BORDER);
	gput(row, col + w - 1, BX_TR, P_BORDER, 1);
	for (int r = 1; r < h - 1; r++) {
		gput(row + r, col, BX_V, P_BORDER, 1);
		gfill(row + r, col + 1, w - 2, " ", P_WIN);
		gput(row + r, col + w - 1, BX_V, P_BORDER, 1);
	}
	gput(row + h - 1, col, BX_BL, P_BORDER, 1);
	gfill(row + h - 1, col + 1, w - 2, BX_H, P_BORDER);
	gput(row + h - 1, col + w - 1, BX_BR, P_BORDER, 1);

	if (title && *title) {
		char t[256];
		snprintf(t, sizeof t, " %s ", title);
		int tw = u8width(t);
		if (tw > w - 4) { u8ellipsis(t, sizeof t, title, w - 6); tw = u8width(t); }
		gput(row, col + (w - tw) / 2, t, P_TITLE, tw);
	}
}

/* A button in newt's shape — <Label>, cyan, brighter when it has the focus. */
static int btn_width(const char *label) { return u8width(label) + 2; }

static void btn_draw(int row, int col, const char *label, int focused)
{
	int a = focused ? P_BTNACT : P_BTN;
	char t[128];
	snprintf(t, sizeof t, "<%s>", label);
	gput(row, col, t, a, btn_width(label));
}

static void help_line(const char *text)
{
	gfill(g_h - 1, 0, g_w, " ", P_HELP);
	gput(g_h - 1, 1, text, P_HELP, g_w - 2);
}

/* The blue root, with the program name and what this machine is. Drawn under
 * every screen, so a dialog always sits on the same background. */
static void draw_root(void)
{
	grid_clear(P_ROOT);

	char left[256];
	snprintf(left, sizeof left, "%s %s  %s", S(T_TITLE), APP_VERSION, S(T_SUBTITLE));
	gput(0, 1, left, P_ROOTTITLE, g_w - 2);

	char right[128];
	const char *user = geteuid() == 0 ? "root" : (getenv("USER") ? getenv("USER") : "user");
	char host[64] = "";
	if (gethostname(host, sizeof host - 1) != 0) copy_str(host, sizeof host, "container");
	snprintf(right, sizeof right, "%s@%s", user, host);
	int rw = u8width(right);
	if (rw < g_w - u8width(left) - 4) gput(0, g_w - 1 - rw, right, P_ROOTDIM, rw);

	if (g_h >= 18) {
		char mem[16], disk[16], facts[320];
		human_size(g_sys.mem_total, mem, sizeof mem);
		human_size(g_sys.disk_free, disk, sizeof disk);
		snprintf(facts, sizeof facts, "%s %s %s %s %s %s %ld CPU %s %s %s %s %s %s %s",
		         g_sys.pretty, MK_DOT, g_sys.init, MK_DOT, g_sys.pm, MK_DOT,
		         g_sys.ncpu, MK_DOT, S(T_RAM), mem, MK_DOT, S(T_DISK), disk,
		         g_zh ? "可用" : "free");
		gput(1, 1, facts, P_ROOTDIM, g_w - 2);
	}
}

/* --------------------------------------------------------------- labels ---*/
static const char *pkg_name(const Pkg *p) { return g_zh && p->name_zh[0] ? p->name_zh : p->name; }
static const char *pkg_summary(const Pkg *p) { return g_zh && p->summary_zh[0] ? p->summary_zh : p->summary; }
static const char *pkg_includes(const Pkg *p) { return g_zh && p->includes_zh[0] ? p->includes_zh : p->includes; }
static const char *param_label(const Param *pm) { return g_zh && pm->label_zh[0] ? pm->label_zh : pm->label; }

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
	case ST_RUNNING: case ST_INSTALLED: return P_RUN;
	case ST_STOPPED: return P_STOPPED;
	case ST_BROKEN:  return P_ERR;
	case ST_ABSENT:  return P_ABSENT;
	default:         return P_DIM;
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
 * the list can say so before somebody spends ten minutes finding out. */
static int resource_short(const Pkg *p, int *disk_short, int *mem_short)
{
	*disk_short = (p->disk_bytes > 0 && g_sys.disk_free > 0 && p->disk_bytes > g_sys.disk_free);
	*mem_short  = (p->mem_bytes  > 0 && g_sys.mem_total > 0 && p->mem_bytes  > g_sys.mem_total);
	return *disk_short || *mem_short;
}

static void size_line(const Pkg *p, char *out, size_t cap)
{
	size_t n = 0;
	out[0] = '\0';
	/* A recipe that writes `memory: 0` means it does not care, not that it
	 * needs none — certbot does exactly this. Printing "RAM 0" is noise. */
	if (p->disk[0] && p->disk_bytes > 0)
		n += (size_t)snprintf(out + n, cap - n, "%s %s", S(T_DISK), p->disk);
	if (p->memory[0] && p->mem_bytes > 0 && n < cap - 24)
		n += (size_t)snprintf(out + n, cap - n, "%s%s %s", n ? " · " : "", S(T_RAM), p->memory);
	if (p->ports[0] && n < cap - 24)
		n += (size_t)snprintf(out + n, cap - n, "%s%s %s", n ? " · " : "", S(T_PORT), p->ports);
	if (p->requires[0] && n < cap - 24)
		snprintf(out + n, cap - n, "%s%s %s", n ? " · " : "", S(T_NEEDS), p->requires);
}

/* --------------------------------------------------------------- dialogs ---*/
static void pager(const char *title, const char *text)
{
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
		draw_root();

		int w = g_w - 8; if (w > 96) w = 96; if (w < 30) w = g_w - 2;
		int h = g_h - 4; if (h < 8) h = g_h - 2;
		int row = (g_h - h) / 2 - 1, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, title);

		int body = h - 3;
		int inner = w - 4;
		if (scroll > n - 1) scroll = n - 1;
		if (scroll < 0) scroll = 0;
		for (int i = 0; i < body && scroll + i < n; i++) {
			char cut[600];
			u8ellipsis(cut, sizeof cut, raw[scroll + i], inner);
			gput(row + 1 + i, col + 2, cut, P_WIN, inner);
		}
		if (n > body) {
			char sb[32];
			snprintf(sb, sizeof sb, " %d/%d ", scroll + 1, n);
			int sw = u8width(sb);
			gput(row + h - 1, col + w - 3 - sw, sb, P_TITLE, sw);
		}
		btn_draw(row + h - 1, col + 2, S(T_CLOSE), 1);
		help_line(S(T_HELPPAGE));
		grid_flush();

		int k = read_key();
		if (k == K_ENTER || k == K_ESC || k == ' ' || k == 'q' || k == K_LEFT) break;
		else if (k == K_DOWN) scroll++;
		else if (k == K_UP)   scroll--;
		else if (k == K_PGDN || k == K_RIGHT) scroll += body;
		else if (k == K_PGUP) scroll -= body;
		else if (k == K_HOME) scroll = 0;
		else if (k == K_END)  scroll = n - 1;
	}
	free(raw); free(copy);
}

/* Yes/no, with the buttons where nmtui puts them and Enter landing on the one
 * that is focused rather than always on yes. */
static int confirm(const char *title, const char *msg)
{
	int focus = 0;      /* 0 = OK, 1 = Cancel */
	for (;;) {
		term_measure();
		grid_size(g_w, g_h);
		draw_root();

		int w = u8width(msg) + 8;
		if (w > g_w - 6) w = g_w - 6;
		if (w < 34) w = 34;
		int inner = w - 4;
		char lines[4][512];
		int nl = u8wrap(msg, inner, lines, 4);
		int h = nl + 5;
		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, title);
		for (int i = 0; i < nl; i++) gput(row + 1 + i, col + 2, lines[i], P_WIN, inner);

		int bw = btn_width(S(T_OK)) + 2 + btn_width(S(T_CANCEL));
		int bx = col + (w - bw) / 2;
		btn_draw(row + h - 2, bx, S(T_OK), focus == 0);
		btn_draw(row + h - 2, bx + btn_width(S(T_OK)) + 2, S(T_CANCEL), focus == 1);
		help_line(S(T_CONFIRM));
		grid_flush();

		int k = read_key();
		if (k == K_ESC) return 0;
		if (k == K_LEFT || k == K_RIGHT || k == K_TAB) focus = !focus;
		else if (k == K_ENTER || k == ' ') return focus == 0;
	}
}

static void message(const char *title, const char *msg)
{
	for (;;) {
		term_measure();
		grid_size(g_w, g_h);
		draw_root();
		int w = u8width(msg) + 8;
		if (w > g_w - 6) w = g_w - 6;
		if (w < 30) w = 30;
		int inner = w - 4;
		char lines[5][512];
		int nl = u8wrap(msg, inner, lines, 5);
		int h = nl + 5;
		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, title);
		for (int i = 0; i < nl; i++) gput(row + 1 + i, col + 2, lines[i], P_WIN, inner);
		int bx = col + (w - btn_width(S(T_OK))) / 2;
		btn_draw(row + h - 2, bx, S(T_OK), 1);
		help_line(S(T_HELPDONE));
		grid_flush();
		int k = read_key();
		if (k == K_ENTER || k == K_ESC || k == ' ' || k == K_LEFT) return;
	}
}

/* -------------------------------------------------------- the progress run --
 *
 * A Ghost or Windows installer, and for the same reason: an install takes
 * minutes and a wall of scrolling package-manager output does not tell anyone
 * whether it is going well. Title, a bar, the sentence describing the step it
 * is on, and the detailed log underneath for when it goes wrong.
 *
 * The steps are real. `step()` in common.sh already prints `==> doing a thing`
 * before each phase of every recipe we ship, so the phase name and the count
 * come out of the recipe rather than being invented here — and a recipe that
 * declares `step_total 6` gets a bar that is a true fraction. One that does
 * not gets a curve that approaches the end without ever arriving, which is
 * honest about not knowing rather than pretending to.
 */
typedef struct {
	pid_t pid;
	int   fd;
	int   logfd;
	int   done, rc;
	int   step, total;
	int   lines_in_step;
	char  phase[256];
	char  buf[4096];
	size_t buflen;
	char  log[LOG_KEEP][LOG_COLS];
	int   nlog, logtop;      /* ring */
} Runner;

static void runner_push(Runner *r, const char *line)
{
	int slot = (r->logtop + r->nlog) % LOG_KEEP;
	if (r->nlog == LOG_KEEP) { r->logtop = (r->logtop + 1) % LOG_KEEP; slot = (r->logtop + r->nlog - 1) % LOG_KEEP; }
	else r->nlog++;
	copy_str(r->log[slot], LOG_COLS, line);
}

static const char *runner_line(const Runner *r, int i)
{
	return r->log[(r->logtop + i) % LOG_KEEP];
}

/* Recipes only colour when stdout is a terminal, and here it is a pipe — but a
 * package manager underneath may not be so careful, and an escape sequence
 * rendered as literal bytes wrecks the pane. */
static void strip_ansi(char *s)
{
	char *w = s;
	for (char *p = s; *p; ) {
		if (*p == '\x1b') {
			p++;
			if (*p == '[') { p++; while (*p && !(*p >= '@' && *p <= '~')) p++; if (*p) p++; }
			else if (*p) p++;
			continue;
		}
		if (*p == '\r') { p++; continue; }
		if ((unsigned char)*p < 32 && *p != '\t') { p++; continue; }
		*w++ = *p++;
	}
	*w = '\0';
}

static void runner_line_in(Runner *r, char *line)
{
	strip_ansi(line);
	trim(line);
	if (!*line) return;

	/* `==| total N` is the machine marker step_total emits. It stays in the
	 * log file — a log that explains its own progress is easier to read — but
	 * it is not a line anybody needs to see scrolling past. */
	if (!strncmp(line, "==| total ", 10)) { r->total = atoi(line + 10); return; }
	if (!strncmp(line, "==> ", 4)) {
		r->step++;
		r->lines_in_step = 0;
		copy_str(r->phase, sizeof r->phase, line + 4);
	} else {
		r->lines_in_step++;
	}
	runner_push(r, line);
}

static void runner_drain(Runner *r)
{
	char buf[4096];
	for (;;) {
		ssize_t n = read(r->fd, buf, sizeof buf);
		if (n < 0) { if (errno == EINTR) continue; return; }   /* EAGAIN: nothing more */
		if (n == 0) {
			if (r->buflen) { r->buf[r->buflen] = '\0'; runner_line_in(r, r->buf); r->buflen = 0; }
			close(r->fd);
			r->fd = -1;
			return;
		}
		if (r->logfd >= 0 && write(r->logfd, buf, (size_t)n) < 0) { /* best effort */ }
		for (ssize_t i = 0; i < n; i++) {
			if (buf[i] == '\n') {
				r->buf[r->buflen] = '\0';
				runner_line_in(r, r->buf);
				r->buflen = 0;
			} else if (r->buflen < sizeof r->buf - 1) {
				r->buf[r->buflen++] = buf[i];
			}
		}
	}
}

static int runner_start(Runner *r, Pkg *p, const char *verb)
{
	memset(r, 0, sizeof *r);
	r->fd = -1; r->logfd = -1; r->rc = -1;
	copy_str(r->phase, sizeof r->phase, S(T_WORKING));

	char logpath[600];
	snprintf(logpath, sizeof logpath, "%s/%s.log", log_dir(), p->id);
	r->logfd = open_log(logpath, p->path, verb);

	int pfd[2];
	if (pipe(pfd) != 0) return 0;
	pid_t pid = fork();
	if (pid < 0) { close(pfd[0]); close(pfd[1]); return 0; }
	if (pid == 0) {
		close(pfd[0]);
		dup2(pfd[1], STDOUT_FILENO);
		dup2(pfd[1], STDERR_FILENO);
		close(pfd[1]);
		int nul = open("/dev/null", O_RDONLY);
		if (nul >= 0) { dup2(nul, STDIN_FILENO); close(nul); }
		/* Its own process group, so a forced stop takes the whole tree —
		 * apt-get leaves dpkg behind otherwise. */
		setpgid(0, 0);
		g_env_pkg = p;
		child_env();
		exec_recipe(p->path, verb);
	}
	setpgid(pid, pid);
	close(pfd[1]);
	fcntl(pfd[0], F_SETFL, O_NONBLOCK);
	r->fd = pfd[0];
	r->pid = pid;
	return 1;
}

static void runner_reap(Runner *r)
{
	if (r->done) return;
	int status = 0;
	pid_t got = waitpid(r->pid, &status, WNOHANG);
	if (got != r->pid) return;
	/* Do not declare it finished until the pipe has been read to EOF, or the
	 * last few lines — usually the ones saying what went wrong — are lost. */
	if (r->fd >= 0) runner_drain(r);
	r->done = 1;
	r->rc = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
	if (r->logfd >= 0) { close(r->logfd); r->logfd = -1; }
	if (r->fd >= 0) { close(r->fd); r->fd = -1; }
}

/* No pow(): this has to link against glibc with a bare `cc`. */
static double decay(double base, int n)
{
	double v = 1.0;
	while (n-- > 0) v *= base;
	return v;
}

static int runner_percent(const Runner *r)
{
	if (r->done) return r->rc == 0 ? 100 : 100;
	double at, next;
	if (r->total > 0) {
		int s = r->step > r->total ? r->total : r->step;
		at   = (double)s / r->total;
		next = (double)(s + 1 > r->total ? r->total : s + 1) / r->total;
	} else {
		at   = 1.0 - decay(0.80, r->step);
		next = 1.0 - decay(0.80, r->step + 1);
	}
	/* Creep towards the next boundary with the log traffic, without ever
	 * reaching it — the bar moves while apt is talking, and stops moving when
	 * apt stops, which is information rather than decoration. */
	double creep = (next - at) * (1.0 - decay(0.97, r->lines_in_step)) * 0.9;
	double pct = (at + creep) * 100.0;
	if (pct > 97.0) pct = 97.0;
	if (pct < 0.0) pct = 0.0;
	return (int)pct;
}

static void draw_bar(int row, int col, int w, int pct)
{
	int full = w * pct / 100;
	if (full > w) full = w;
	for (int i = 0; i < w; i++)
		gput(row, col + i, i < full ? BAR_F : BAR_E, i < full ? P_BARFULL : P_BAREMPTY, 1);
}

static void verb_title(char *out, size_t cap, const char *verb, const Pkg *p)
{
	const L *t = &T_VERB_INS;
	if      (!strcmp(verb, "uninstall")) t = &T_VERB_REM;
	else if (!strcmp(verb, "start"))     t = &T_VERB_STA;
	else if (!strcmp(verb, "stop"))      t = &T_VERB_STO;
	else if (!strcmp(verb, "restart"))   t = &T_VERB_RES;
	else if (!strcmp(verb, "enable") || !strcmp(verb, "disable")) t = &T_VERB_BOOT;
	snprintf(out, cap, S(*t), pkg_name(p));
}

static void screen_progress(Pkg *p, const char *verb)
{
	Runner r;
	char title[256];
	verb_title(title, sizeof title, verb, p);

	if (!runner_start(&r, p, verb)) {
		message(title, g_zh ? "启动失败：无法 fork。" : "could not start: fork failed");
		return;
	}

	int esc_armed = 0;
	int log_scroll = -1;      /* -1 follows the tail */

	for (;;) {
		if (r.fd >= 0) runner_drain(&r);
		runner_reap(&r);

		term_measure();
		grid_size(g_w, g_h);
		draw_root();

		int w = g_w - 8; if (w > 100) w = 100; if (w < 36) w = g_w - 2;
		int h = g_h - 4; if (h > 26) h = 26; if (h < 12) h = g_h - 2;
		int row = (g_h - h) / 2 - 1, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		int inner = w - 4, x = col + 2;
		win_box(row, col, w, h, title);

		int y = row + 1;
		int pct = runner_percent(&r);

		char head[128];
		if (r.done)          snprintf(head, sizeof head, "%s", r.rc == 0 ? S(T_DONE) : S(T_BROKEN));
		else if (r.total > 0) snprintf(head, sizeof head, S(T_STEPOF), r.step > r.total ? r.total : r.step, r.total);
		else                  snprintf(head, sizeof head, "%s", S(T_WORKING));
		gput(y, x, head, r.done && r.rc ? P_ERR : P_DIM, inner);
		y++;

		char pctstr[16];
		snprintf(pctstr, sizeof pctstr, " %3d%%", pct);
		draw_bar(y, x, inner - 5, pct);
		gput(y, x + inner - 5, pctstr, P_WIN, 5);
		y += 2;

		char phase[600];
		u8ellipsis(phase, sizeof phase, r.done
		           ? (r.rc == 0 ? S(T_DONE) : r.phase)
		           : r.phase, inner);
		gput(y, x, phase, r.done && r.rc ? P_ERR : P_WIN, inner);
		y += 2;

		/* the detailed log, framed, at the bottom — where an installer puts it */
		int logh = row + h - 3 - y;
		if (logh < 3) logh = 3;
		gput(y, x, BX_TL, P_BORDER, 1);
		gfill(y, x + 1, inner - 2, BX_H, P_BORDER);
		gput(y, x + inner - 1, BX_TR, P_BORDER, 1);
		{
			char lt[64];
			snprintf(lt, sizeof lt, " %s ", S(T_LOGPANE));
			gput(y, x + 2, lt, P_TITLE, u8width(lt));
		}
		for (int i = 1; i < logh - 1; i++) {
			gput(y + i, x, BX_V, P_BORDER, 1);
			gput(y + i, x + inner - 1, BX_V, P_BORDER, 1);
		}
		gput(y + logh - 1, x, BX_BL, P_BORDER, 1);
		gfill(y + logh - 1, x + 1, inner - 2, BX_H, P_BORDER);
		gput(y + logh - 1, x + inner - 1, BX_BR, P_BORDER, 1);

		int rows = logh - 2;
		int first = log_scroll >= 0 ? log_scroll : (r.nlog > rows ? r.nlog - rows : 0);
		if (first > r.nlog - rows) first = r.nlog - rows;
		if (first < 0) first = 0;
		for (int i = 0; i < rows && first + i < r.nlog; i++) {
			char cut[600];
			u8ellipsis(cut, sizeof cut, runner_line(&r, first + i), inner - 4);
			gput(y + 1 + i, x + 2, cut, P_DIM, inner - 4);
		}

		if (r.done) {
			const char *lab = r.rc == 0 ? S(T_DONE) : S(T_CLOSE);
			btn_draw(row + h - 2, col + (w - btn_width(lab)) / 2, lab, 1);
			help_line(S(T_HELPDONE));
		} else {
			help_line(esc_armed
			          ? (g_zh ? "再按一次 Esc 强行中止" : "press Esc again to force a stop")
			          : S(T_HELPRUN));
		}
		grid_flush();

		/* While it runs the screen has to keep moving, so the wait is short
		 * and a timeout is just another redraw. When it is done, block. */
		int k = read_key_to(r.done ? -1 : 120);
		if (k == K_TIMEOUT || k == K_RESIZE || k == K_NONE) {
			if (k != K_TIMEOUT) esc_armed = 0;
			continue;
		}
		if (r.done) {
			if (k == K_ENTER || k == K_ESC || k == ' ' || k == K_LEFT) break;
			if (k == K_UP)   { if (first > 0) log_scroll = first - 1; }
			if (k == K_DOWN) { log_scroll = first + 1; if (log_scroll > r.nlog - rows) log_scroll = -1; }
			if (k == K_PGUP) { log_scroll = first - rows; if (log_scroll < 0) log_scroll = 0; }
			if (k == K_PGDN) { log_scroll = -1; }
			continue;
		}
		if (k == K_UP)   { if (first > 0) log_scroll = first - 1; esc_armed = 0; continue; }
		if (k == K_DOWN) { log_scroll = first + 1; if (log_scroll > r.nlog - rows) log_scroll = -1; esc_armed = 0; continue; }
		if (k == K_ESC) {
			/* Killing a package manager half way through is how a container
			 * ends up needing `dpkg --configure -a` by hand, so it takes two
			 * presses and then says so. */
			if (!esc_armed) { esc_armed = 1; continue; }
			esc_armed = 0;
			if (confirm(title, S(T_KILLQ))) {
				kill(-r.pid, SIGTERM);
				for (int i = 0; i < 20 && !r.done; i++) {
					struct timespec ts = { 0, 100 * 1000 * 1000 };
					nanosleep(&ts, NULL);
					if (r.fd >= 0) runner_drain(&r);
					runner_reap(&r);
				}
				if (!r.done) kill(-r.pid, SIGKILL);
			}
			continue;
		}
		esc_armed = 0;
	}

	if (!r.done) {           /* cannot happen, but never leave a zombie */
		kill(-r.pid, SIGKILL);
		waitpid(r.pid, NULL, 0);
	}
	if (r.logfd >= 0) close(r.logfd);
	if (r.fd >= 0) close(r.fd);

	if (r.rc != 0) {
		char msg[600], logpath[600];
		snprintf(logpath, sizeof logpath, "%s/%s.log", log_dir(), p->id);
		snprintf(msg, sizeof msg, S(T_FAILED), pkg_name(p), r.rc, logpath);
		message(S(T_BROKEN), msg);
	}
	probe_pkg(p);
}

/* ----------------------------------------------------------- the settings --
 *
 * nmtui's form: a column of labels, a column of fields, OK and Cancel at the
 * bottom. Text fields take typing; a bool is a checkbox that Space flips; a
 * list is a chooser that Left and Right walk. Nothing else is worth a form.
 */
static int screen_params(Pkg *p)
{
	if (!p->nparams) { message(pkg_name(p), S(T_NOPARAM)); return 0; }

	Param before[MAX_PARAMS];
	memcpy(before, p->params, sizeof before);

	int sel = 0;                       /* 0..nparams-1 fields, then OK, Cancel */
	int nitems = p->nparams + 2;
	char title[256];
	snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_PARAMS));

	for (;;) {
		term_measure();
		grid_size(g_w, g_h);
		draw_root();

		int labw = 12;
		for (int i = 0; i < p->nparams; i++) {
			int lw = u8width(param_label(&p->params[i]));
			if (lw > labw) labw = lw;
		}
		if (labw > 28) labw = 28;
		int fieldw = 30;
		int w = labw + fieldw + 8;
		if (w > g_w - 6) { w = g_w - 6; fieldw = w - labw - 8; }
		if (fieldw < 10) fieldw = 10;
		int h = p->nparams + 6;
		if (h > g_h - 2) h = g_h - 2;
		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, title);

		for (int i = 0; i < p->nparams && i < h - 5; i++) {
			Param *pm = &p->params[i];
			int y = row + 1 + i;
			int focused = (sel == i);
			gput(y, col + 2, param_label(pm), P_WIN, labw);

			int fx = col + 3 + labw;
			int a = focused ? P_ENTRYACT : P_ENTRY;
			if (pm->type == PT_BOOL) {
				int on = !strcmp(pm->value, "on") || !strcmp(pm->value, "1") ||
				         !strcmp(pm->value, "yes") || !strcmp(pm->value, "true");
				char box[32];
				snprintf(box, sizeof box, "[%s] %s", on ? MK_OK : " ", on ? S(T_ON) : S(T_OFF));
				gput(y, fx, box, a, fieldw);
			} else if (pm->type == PT_ENUM) {
				char ch[128];
				snprintf(ch, sizeof ch, "%s %s %s", AR_L, pm->value, AR_R);
				gfill(y, fx, fieldw, " ", a);
				gput(y, fx, ch, a, fieldw);
			} else {
				gfill(y, fx, fieldw, " ", a);
				char cut[256];
				u8ellipsis(cut, sizeof cut, pm->value, fieldw - 1);
				gput(y, fx, cut, a, fieldw - 1);
				if (focused) {
					int cw = u8width(cut);
					if (cw < fieldw) gput(y, fx + cw, "_", a, 1);
				}
			}
		}

		int bw = btn_width(S(T_OK)) + 2 + btn_width(S(T_CANCEL));
		int bx = col + (w - bw) / 2;
		btn_draw(row + h - 2, bx, S(T_OK), sel == p->nparams);
		btn_draw(row + h - 2, bx + btn_width(S(T_OK)) + 2, S(T_CANCEL), sel == p->nparams + 1);
		help_line(S(T_HELPFORM));
		grid_flush();

		int k = read_key();
		Param *pm = (sel < p->nparams) ? &p->params[sel] : NULL;

		if (k == K_ESC) { memcpy(p->params, before, sizeof before); return 0; }
		if (k == K_UP || k == K_BTAB) { sel = (sel - 1 + nitems) % nitems; continue; }
		if (k == K_DOWN || k == K_TAB) { sel = (sel + 1) % nitems; continue; }
		if (k == K_ENTER) {
			if (sel == p->nparams + 1) { memcpy(p->params, before, sizeof before); return 0; }
			if (sel == p->nparams) {
				if (!params_save(p)) {
					message(title, g_zh ? "保存失败：写不了参数文件。"
					                    : "could not write the settings file");
					return 0;
				}
				return 1;
			}
			sel = p->nparams;      /* Enter in a field moves on to OK */
			continue;
		}
		if (!pm) {
			if (k == K_LEFT)  sel = p->nparams;
			if (k == K_RIGHT) sel = p->nparams + 1;
			continue;
		}
		if (pm->type == PT_BOOL) {
			if (k == ' ' || k == K_LEFT || k == K_RIGHT) {
				int on = !strcmp(pm->value, "on") || !strcmp(pm->value, "1") ||
				         !strcmp(pm->value, "yes") || !strcmp(pm->value, "true");
				copy_str(pm->value, sizeof pm->value, on ? "off" : "on");
			}
		} else if (pm->type == PT_ENUM) {
			int at = 0;
			for (int i = 0; i < pm->nchoices; i++) if (!strcmp(pm->choices[i], pm->value)) at = i;
			if (k == K_LEFT)  at = (at - 1 + pm->nchoices) % pm->nchoices;
			if (k == K_RIGHT || k == ' ') at = (at + 1) % pm->nchoices;
			copy_str(pm->value, sizeof pm->value, pm->choices[at]);
		} else {
			if (k == K_BACK) {
				size_t n = strlen(pm->value);
				while (n && ((unsigned char)pm->value[n-1] & 0xC0) == 0x80) n--;
				if (n) n--;
				pm->value[n] = '\0';
			} else if (k >= 32 && k < 256) {
				if (pm->type == PT_NUMBER && !isdigit(k) && k != '.') continue;
				size_t n = strlen(pm->value);
				if (n < sizeof pm->value - 2) { pm->value[n] = (char)k; pm->value[n+1] = '\0'; }
			}
		}
	}
}

/* ------------------------------------------------------------ the details --*/
static void screen_details(Pkg *p)
{
	char t[4096];
	size_t n = 0;
	char cats[192] = "";
	for (int i = 0; i < p->ncats; i++) {
		int ci = cat_index(p->cats[i]);
		snprintf(cats + strlen(cats), sizeof cats - strlen(cats), "%s%s",
		         i ? ", " : "", ci >= 0 ? S(g_cats[ci].label) : p->cats[i]);
	}

	n += (size_t)snprintf(t + n, sizeof t - n, "%s\n\n", pkg_summary(p));
	n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s %s\n",
	                      g_zh ? "状态" : "State", S(*status_label(p)),
	                      p->detail[0] ? p->detail : "");
	if (pkg_includes(p)[0])
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n",
		                      g_zh ? "包含" : "Includes", pkg_includes(p));
	n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", g_zh ? "分类" : "Category", cats);
	if (p->disk[0])
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", S(T_DISK), p->disk);
	if (p->memory[0])
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", S(T_RAM), p->memory);
	if (p->ports[0])
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", S(T_PORT), p->ports);
	if (p->requires[0])
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", S(T_NEEDS), p->requires);
	if (p->service[0])
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s (%s %s)\n",
		                      g_zh ? "服务" : "Service", p->service, S(T_BOOT),
		                      p->enabled == 1 ? S(T_YES) : p->enabled == 0 ? S(T_NO) : "?");
	if (p->nparams) {
		n += (size_t)snprintf(t + n, sizeof t - n, "\n%s\n", S(T_PARAMS));
		for (int i = 0; i < p->nparams; i++)
			n += (size_t)snprintf(t + n, sizeof t - n, "  %-16s %s\n",
			                      param_label(&p->params[i]), p->params[i].value);
	}
	n += (size_t)snprintf(t + n, sizeof t - n, "\n%-10s %s\n", g_zh ? "脚本" : "Recipe", p->path);
	snprintf(t + n, sizeof t - n, "%-10s %s/%s.log\n", g_zh ? "日志" : "Log", log_dir(), p->id);

	char title[256];
	snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_DETAILS));
	pager(title, t);
}

static void screen_status(Pkg *p)
{
	probe_pkg(p);
	char out[8192];
	g_env_pkg = p;
	run_capture(p->path, "status", out, sizeof out, 8, 1);
	g_env_pkg = NULL;

	char t[9000];
	size_t n = 0;
	n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s %s\n",
	                      g_zh ? "状态" : "State", status_mark(p), S(*status_label(p)));
	if (p->detail[0])
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", g_zh ? "版本" : "Detail", p->detail);
	if (p->service[0]) {
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", g_zh ? "服务" : "Service", p->service);
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", S(T_BOOT),
		                      p->enabled == 1 ? S(T_YES) : p->enabled == 0 ? S(T_NO) : "?");
	}
	if (p->ports[0])
		n += (size_t)snprintf(t + n, sizeof t - n, "%-10s %s\n", S(T_PORT), p->ports);

	n += (size_t)snprintf(t + n, sizeof t - n, "\n%s\n",
	                      g_zh ? "── 脚本自己报告的 ──" : "── what the recipe reports ──");
	if (out[0]) {
		strip_ansi(out);
		snprintf(t + n, sizeof t - n, "%s", out);
	} else {
		snprintf(t + n, sizeof t - n, "%s\n", g_zh ? "（没有输出）" : "(no output)");
	}

	char title[256];
	snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_STATUS));
	pager(title, t);
}

static void screen_docs(Pkg *p)
{
	char out[32768];
	g_env_pkg = p;
	int rc = run_capture(p->path, "help", out, sizeof out, 20, 1);
	g_env_pkg = NULL;
	if (rc != 0 && !out[0]) snprintf(out, sizeof out, "%s", S(T_NODOC));
	strip_ansi(out);
	char title[256];
	snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_DOCS));
	pager(title, out);
}

/* --------------------------------------------------------- the app dialog --
 *
 * The one the whole redesign is for. You walk onto a thing and press Enter,
 * and you get a list of everything that can be done to that thing — install
 * it, look at what it is, see whether it is running, change its settings.
 * Choosing what to do is the same gesture as choosing what to do it to.
 */
enum { A_INSTALL = 1, A_REMOVE, A_START, A_STOP, A_RESTART, A_BOOT,
       A_STATUS, A_DETAILS, A_PARAMS, A_DOCS };

typedef struct { int act; char label[64]; char aux[32]; int dim; } Action;

static int build_actions(const Pkg *p, Action *a)
{
	int n = 0;
	int inst = pkg_installed(p);

	if (!inst) {
		a[n].act = A_INSTALL; copy_str(a[n].label, 64, S(T_INSTALL)); a[n].aux[0] = 0; a[n].dim = 0; n++;
	} else {
		if (p->service[0]) {
			if (p->status == ST_RUNNING) {
				a[n].act = A_STOP; copy_str(a[n].label, 64, S(T_STOP)); a[n].aux[0] = 0; a[n].dim = 0; n++;
			} else {
				a[n].act = A_START; copy_str(a[n].label, 64, S(T_START)); a[n].aux[0] = 0; a[n].dim = 0; n++;
			}
			a[n].act = A_RESTART; copy_str(a[n].label, 64, S(T_RESTART)); a[n].aux[0] = 0; a[n].dim = 0; n++;
		}
		a[n].act = A_STATUS; copy_str(a[n].label, 64, S(T_STATUS)); a[n].aux[0] = 0; a[n].dim = 0; n++;
		a[n].act = A_INSTALL; copy_str(a[n].label, 64, S(T_UPDATE)); a[n].aux[0] = 0; a[n].dim = 0; n++;
		if (p->service[0]) {
			a[n].act = A_BOOT; copy_str(a[n].label, 64, S(T_BOOT));
			snprintf(a[n].aux, sizeof a[n].aux, "%s",
			         p->enabled == 1 ? S(T_YES) : p->enabled == 0 ? S(T_NO) : "?");
			a[n].dim = 0; n++;
		}
	}
	a[n].act = A_PARAMS; copy_str(a[n].label, 64, S(T_PARAMS));
	snprintf(a[n].aux, sizeof a[n].aux, "%d", p->nparams);
	if (!p->nparams) a[n].aux[0] = '\0';
	a[n].dim = !p->nparams; n++;

	a[n].act = A_DETAILS; copy_str(a[n].label, 64, S(T_DETAILS)); a[n].aux[0] = 0; a[n].dim = 0; n++;
	a[n].act = A_DOCS;    copy_str(a[n].label, 64, S(T_DOCS));    a[n].aux[0] = 0; a[n].dim = 0; n++;
	if (inst) { a[n].act = A_REMOVE; copy_str(a[n].label, 64, S(T_REMOVE)); a[n].aux[0] = 0; a[n].dim = 0; n++; }
	return n;
}

static void screen_app(Pkg *p)
{
	int sel = 0;
	for (;;) {
		Action acts[12];
		int na = build_actions(p, acts);
		if (sel >= na) sel = na - 1;
		if (sel < 0) sel = 0;

		term_measure();
		grid_size(g_w, g_h);
		draw_root();

		/* wide enough for the summary to be worth showing above the menu */
		int w = 54;
		if (w > g_w - 6) w = g_w - 6;
		int inner = w - 4;
		char sum[3][512];
		int ns = u8wrap(pkg_summary(p), inner, sum, 2);
		int h = na + ns + 7;
		if (h > g_h - 2) h = g_h - 2;
		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, pkg_name(p));

		int y = row + 1;
		char st[128];
		snprintf(st, sizeof st, "%s %s", status_mark(p), S(*status_label(p)));
		gput(y, col + 2, st, status_attr(p), inner);
		if (p->detail[0]) {
			int sw = u8width(st) + 2;
			char d[256];
			u8ellipsis(d, sizeof d, p->detail, inner - sw);
			gput(y, col + 2 + sw, d, P_DIM, inner - sw);
		}
		y++;
		for (int i = 0; i < ns; i++) { gput(y, col + 2, sum[i], P_DIM, inner); y++; }
		y++;

		for (int i = 0; i < na && y < row + h - 2; i++, y++) {
			int a = acts[i].dim ? P_DIM : P_WIN;
			if (i == sel) { gtint(y, col + 2, inner, P_SEL); a = acts[i].dim ? P_SELDIM : P_SEL; }
			gput(y, col + 3, acts[i].label, a, inner - 10);
			if (acts[i].aux[0]) {
				int aw = u8width(acts[i].aux);
				gput(y, col + 1 + inner - aw, acts[i].aux, i == sel ? P_SELDIM : P_DIM, aw);
			}
		}

		btn_draw(row + h - 2, col + 2, S(T_BACK), 0);
		help_line(S(T_HELPMENU));
		grid_flush();

		int k = read_key();
		if (k == K_ESC || k == K_LEFT || k == 'q') return;
		if (k == K_RESIZE) continue;
		if (k == K_UP)   { sel = (sel - 1 + na) % na; continue; }
		if (k == K_DOWN) { sel = (sel + 1) % na; continue; }
		if (k == K_HOME) { sel = 0; continue; }
		if (k == K_END)  { sel = na - 1; continue; }
		if (k != K_ENTER && k != ' ' && k != K_RIGHT) continue;
		if (acts[sel].dim) continue;

		switch (acts[sel].act) {
		case A_DETAILS: screen_details(p); break;
		case A_DOCS:    screen_docs(p); break;
		case A_STATUS:  screen_status(p); break;
		case A_PARAMS:  if (screen_params(p)) message(S(T_PARAMS), S(T_PARAMSAVED)); break;
		case A_INSTALL: {
			int ds = 0, ms = 0;
			if (resource_short(p, &ds, &ms)) {
				char have[16], q[500];
				human_size(ds ? g_sys.disk_free : g_sys.mem_total, have, sizeof have);
				snprintf(q, sizeof q, S(T_TIGHTQ), pkg_name(p), ds ? p->disk : p->memory, have);
				if (!confirm(pkg_name(p), q)) break;
			}
			screen_progress(p, "install");
			break;
		}
		case A_REMOVE: {
			char q[400];
			snprintf(q, sizeof q, S(T_REMOVEQ), pkg_name(p));
			if (confirm(pkg_name(p), q)) screen_progress(p, "uninstall");
			break;
		}
		case A_START:   screen_progress(p, "start"); break;
		case A_STOP:    screen_progress(p, "stop"); break;
		case A_RESTART: screen_progress(p, "restart"); break;
		case A_BOOT:    screen_progress(p, p->enabled == 1 ? "disable" : "enable"); break;
		}
	}
}

/* ------------------------------------------------------------ the main screen
 *
 * Three panes, left to right in the order somebody actually wants them: what
 * is already on this machine, what kinds of thing there are, and the things
 * themselves. Arrows walk within a pane, Left and Right step between panes,
 * Enter opens whatever is under the cursor. The installed pane is the first
 * column because managing what is running is what somebody comes back for —
 * installing is what they did once, on the first day.
 */
enum { F_INST = 0, F_CAT, F_APP };

static int g_focus = F_APP;
static int g_cat = 0;
static int g_sel_inst = 0, g_sel_cat = 0, g_sel_app = 0;
static int g_scr_inst = 0, g_scr_cat = 0, g_scr_app = 0;
static int g_view[MAX_PKGS], g_nview = 0;
static int g_inst[MAX_PKGS], g_ninst = 0;
static char g_msg[256] = "";

/* geometry, recomputed on every frame so a resize needs no special case */
static int L_top, L_h, L_instw, L_catw, L_appw, L_instx, L_catx, L_appx, L_showinst;

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

static void rebuild_lists(void)
{
	g_ninst = 0;
	for (int i = 0; i < g_npkg; i++)
		if (pkg_installed(&g_pkg[i])) g_inst[g_ninst++] = i;

	g_nview = 0;
	for (int i = 0; i < g_npkg; i++)
		if (pkg_in_cat(&g_pkg[i], g_cats[g_cat].id)) g_view[g_nview++] = i;

	if (g_sel_app >= g_nview) g_sel_app = g_nview ? g_nview - 1 : 0;
	if (g_sel_inst >= g_ninst) g_sel_inst = g_ninst ? g_ninst - 1 : 0;
	if (g_sel_app < 0) g_sel_app = 0;
	if (g_sel_inst < 0) g_sel_inst = 0;
}

static void compute_layout(void)
{
	L_top = (g_h >= 18) ? 3 : 2;
	L_h = g_h - L_top - 1;
	if (L_h < 5) L_h = 5;

	/* The installed pane is worth a column of its own only when there is
	 * something in it and there is room; otherwise the categories pane takes
	 * the space and nothing is lost, because everything installed is still in
	 * its own category. */
	L_showinst = (g_ninst > 0 && g_w >= 86);
	L_instw = L_showinst ? 26 : 0;
	L_catw  = g_w >= 70 ? 18 : 16;
	L_appw = g_w - 2 - L_instw - L_catw;
	/* The listing is the pane that must stay usable: the installed column
	 * goes first when there is not room for everything, then the categories
	 * pane gives up what it can. */
	if (L_appw < 26 && L_showinst) {
		L_showinst = 0; L_instw = 0;
		L_appw = g_w - 2 - L_catw;
	}
	if (L_appw < 24) { L_catw = 12; L_appw = g_w - 2 - L_catw; }
	if (L_appw < 12) L_appw = 12;

	L_instx = 1;
	L_catx  = 1 + L_instw;
	L_appx  = L_catx + L_catw;
}

/* A pane: a window whose title says what it holds and, when it has the focus,
 * whose border is the thing your eye lands on. newt has no focused-border
 * colour, so the title carries it instead. */
static void pane_box(int col, int w, const char *title, int focused, int count)
{
	char t[128];
	if (count >= 0) snprintf(t, sizeof t, "%s (%d)", title, count);
	else            snprintf(t, sizeof t, "%s", title);
	win_box(L_top, col, w, L_h, t);
	if (focused) {
		int tw = u8width(t) + 2;
		char tt[132];
		snprintf(tt, sizeof tt, " %s ", t);
		gput(L_top, col + (w - tw) / 2, tt, P_BTNACT, tw);
	}
}

static void draw_installed_pane(void)
{
	pane_box(L_instx, L_instw, S(T_INSTALLP), g_focus == F_INST, g_ninst);
	int rows = L_h - 2, inner = L_instw - 4;
	if (g_sel_inst < g_scr_inst) g_scr_inst = g_sel_inst;
	if (g_sel_inst >= g_scr_inst + rows) g_scr_inst = g_sel_inst - rows + 1;
	if (g_scr_inst < 0) g_scr_inst = 0;

	g_clip_top = L_top + 1; g_clip_bot = L_top + L_h - 2;
	for (int i = 0; i < rows && g_scr_inst + i < g_ninst; i++) {
		Pkg *p = &g_pkg[g_inst[g_scr_inst + i]];
		int y = L_top + 1 + i;
		int on = (g_scr_inst + i == g_sel_inst);
		if (on) gtint(y, L_instx + 1, L_instw - 2, g_focus == F_INST ? P_SEL : P_IDLE);
		int a = on ? (g_focus == F_INST ? P_SEL : P_IDLE) : P_WIN;
		gput(y, L_instx + 2, status_mark(p), on ? a : status_attr(p), 1);
		char nm[128];
		const char *sw = S(*status_label(p));
		int stw = u8width(sw);
		/* one column short of the state word, so a truncated name never runs
		 * into it */
		u8ellipsis(nm, sizeof nm, pkg_name(p), inner - stw - 3);
		gput(y, L_instx + 4, nm, a, inner - stw - 3);
		gput(y, L_instx + 2 + inner - stw, sw, on ? a : status_attr(p), stw);
	}
	g_clip_top = g_clip_bot = -1;
	if (!g_ninst) gput(L_top + 1, L_instx + 2, S(T_NOINST), P_DIM, L_instw - 4);
}

static void draw_cat_pane(void)
{
	int shown[MAX_CATS], nshown = 0;
	for (int i = 0; i < g_ncat; i++) if (cat_count(i)) shown[nshown++] = i;

	pane_box(L_catx, L_catw, S(T_CATS), g_focus == F_CAT, -1);
	int rows = L_h - 2, inner = L_catw - 4;
	if (g_sel_cat >= nshown) g_sel_cat = nshown ? nshown - 1 : 0;
	if (g_sel_cat < g_scr_cat) g_scr_cat = g_sel_cat;
	if (g_sel_cat >= g_scr_cat + rows) g_scr_cat = g_sel_cat - rows + 1;
	if (g_scr_cat < 0) g_scr_cat = 0;

	g_clip_top = L_top + 1; g_clip_bot = L_top + L_h - 2;
	for (int i = 0; i < rows && g_scr_cat + i < nshown; i++) {
		int ci = shown[g_scr_cat + i];
		int y = L_top + 1 + i;
		int on = (ci == g_cat);
		int cursor = (g_scr_cat + i == g_sel_cat);
		if (cursor) gtint(y, L_catx + 1, L_catw - 2, g_focus == F_CAT ? P_SEL : P_IDLE);
		int a = cursor ? (g_focus == F_CAT ? P_SEL : P_IDLE) : (on ? P_TITLE : P_WIN);
		/* the marker eats two of the pane's columns before the label starts */
		char nm[128];
		u8ellipsis(nm, sizeof nm, S(g_cats[ci].label), inner - 2);
		gput(y, L_catx + 2, on ? MK_RUN : " ", a, 1);
		gput(y, L_catx + 4, nm, a, inner - 2);
	}
	g_clip_top = g_clip_bot = -1;
}

static void draw_app_pane(void)
{
	char title[128];
	snprintf(title, sizeof title, "%s", S(g_cats[g_cat].label));
	pane_box(L_appx, L_appw, title, g_focus == F_APP, g_nview);

	int inner = L_appw - 4;
	int rows = L_h - 2;
	/* Three lines a package — name and state, what it is, how big it is — is
	 * the cover of the thing. Below about forty columns or a short window
	 * there is no room for prose, so it collapses to a name and a state and
	 * the details live one Enter away. */
	int tall = (inner >= 36 && rows >= 9);
	int pitch = tall ? 4 : 1;
	int per = rows / pitch;
	if (per < 1) per = 1;

	if (g_sel_app < g_scr_app) g_scr_app = g_sel_app;
	if (g_sel_app >= g_scr_app + per) g_scr_app = g_sel_app - per + 1;
	if (g_scr_app < 0) g_scr_app = 0;

	if (!g_nview) { gput(L_top + 1, L_appx + 2, S(T_EMPTY), P_DIM, inner); return; }

	g_clip_top = L_top + 1; g_clip_bot = L_top + L_h - 2;
	for (int i = 0; i < per && g_scr_app + i < g_nview; i++) {
		Pkg *p = &g_pkg[g_view[g_scr_app + i]];
		int y = L_top + 1 + i * pitch;
		int on = (g_scr_app + i == g_sel_app);
		int selattr = g_focus == F_APP ? P_SEL : P_IDLE;
		int dimattr = g_focus == F_APP ? P_SELDIM : P_IDLE;

		if (on) for (int r = 0; r < (tall ? 3 : 1); r++)
			gtint(y + r, L_appx + 1, L_appw - 2, selattr);

		const char *sw = S(*status_label(p));
		int stw = u8width(sw);
		char nm[160];
		u8ellipsis(nm, sizeof nm, pkg_name(p), inner - stw - 4);
		gput(y, L_appx + 2, status_mark(p), on ? selattr : status_attr(p), 1);
		gput(y, L_appx + 4, nm, on ? selattr : P_WIN, inner - stw - 4);
		gput(y, L_appx + 2 + inner - stw, sw, on ? dimattr : status_attr(p), stw);

		if (!tall) continue;

		char sm[600];
		const char *src = (p->detail[0] && pkg_installed(p)) ? p->detail : pkg_summary(p);
		u8ellipsis(sm, sizeof sm, src, inner - 2);
		gput(y + 1, L_appx + 4, sm, on ? dimattr : P_DIM, inner - 2);

		int ds = 0, ms = 0;
		int tight = resource_short(p, &ds, &ms);
		char sz[256];
		size_line(p, sz, sizeof sz);
		char szcut[256];
		u8ellipsis(szcut, sizeof szcut, sz, inner - 2);
		gput(y + 2, L_appx + 4, szcut, on ? dimattr : (tight ? P_WARN : P_DIM), inner - 2);
	}
	g_clip_top = g_clip_bot = -1;

	if (g_nview > per) {
		char sb[32];
		snprintf(sb, sizeof sb, " %d/%d ", g_sel_app + 1, g_nview);
		int sw = u8width(sb);
		gput(L_top + L_h - 1, L_appx + L_appw - 3 - sw, sb, P_TITLE, sw);
	}
}

static void render_main(void)
{
	grid_size(g_w, g_h);
	draw_root();
	compute_layout();

	if (g_npkg == 0) {
		win_box(L_top, 1, g_w - 2, L_h, S(T_TITLE));
		gput(L_top + 1, 3, S(T_NORECIPE), P_WARN, g_w - 6);
		help_line(S(T_HELPMAIN));
		return;
	}

	if (L_showinst) draw_installed_pane();
	draw_cat_pane();
	draw_app_pane();

	if (g_msg[0]) {
		char m[300];
		snprintf(m, sizeof m, " %s ", g_msg);
		int mw = u8width(m);
		if (mw > g_w - 4) mw = g_w - 4;
		gput(L_top + L_h - 1, L_appx + 2, m, P_TITLE, mw);
	}
	help_line(S(T_HELPMAIN));
}

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

/* Move the category cursor and follow it with the listing. Selecting is what
 * the cursor does here — there is no separate "open" for a category, because
 * a category is not a thing you do anything to. */
static void cat_cursor(int dir)
{
	int shown[MAX_CATS], nshown = 0;
	for (int i = 0; i < g_ncat; i++) if (cat_count(i)) shown[nshown++] = i;
	if (!nshown) return;
	g_sel_cat += dir;
	if (g_sel_cat < 0) g_sel_cat = 0;
	if (g_sel_cat >= nshown) g_sel_cat = nshown - 1;
	g_cat = shown[g_sel_cat];
	g_sel_app = 0;
	g_scr_app = 0;
}

static void sync_cat_cursor(void)
{
	int shown[MAX_CATS], nshown = 0;
	for (int i = 0; i < g_ncat; i++) if (cat_count(i)) shown[nshown++] = i;
	for (int i = 0; i < nshown; i++) if (shown[i] == g_cat) { g_sel_cat = i; return; }
	if (nshown) { g_cat = shown[0]; g_sel_cat = 0; }
}

static void tui(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_winch;
	sa.sa_flags = 0;                   /* no SA_RESTART: read() must return */
	sigaction(SIGWINCH, &sa, NULL);
	sa.sa_handler = on_fatal;
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGHUP, &sa, NULL);
	signal(SIGPIPE, SIG_IGN);

	probe_all(0);
	if (geteuid() != 0) copy_str(g_msg, sizeof g_msg, S(T_ROOTWARN));

	term_raw();
	atexit(term_cooked);
	term_measure();
	sync_cat_cursor();
	rebuild_lists();
	if (g_ninst) g_focus = F_INST;

	for (;;) {
		term_measure();
		rebuild_lists();
		compute_layout();
		if (!L_showinst && g_focus == F_INST) g_focus = F_CAT;
		render_main();
		grid_flush();

		int k = read_key();
		if (k == K_NONE || k == K_RESIZE || k == K_TIMEOUT) continue;

		if (k == 'q' || k == 'Q') { term_cooked(); return; }
		if (k == 'L') { g_zh = !g_zh; continue; }
		if (k == 'r' || k == 'R') {
			copy_str(g_msg, sizeof g_msg, g_zh ? "正在刷新…" : "refreshing…");
			render_main(); grid_flush();
			probe_all(1);
			g_msg[0] = '\0';
			continue;
		}

		int rows = L_h - 2;
		switch (k) {
		case K_LEFT:
			if (g_focus == F_APP) g_focus = F_CAT;
			else if (g_focus == F_CAT && L_showinst) g_focus = F_INST;
			break;
		case K_RIGHT:
			if (g_focus == F_INST) g_focus = F_CAT;
			else if (g_focus == F_CAT) g_focus = F_APP;
			else if (g_focus == F_APP && g_nview) screen_app(&g_pkg[g_view[g_sel_app]]);
			break;
		case K_TAB:
			g_focus = (g_focus == F_APP) ? (L_showinst ? F_INST : F_CAT) : g_focus + 1;
			break;
		case K_BTAB:
			g_focus = (g_focus == F_INST || (g_focus == F_CAT && !L_showinst)) ? F_APP : g_focus - 1;
			break;
		case K_UP:
			if (g_focus == F_INST) { if (g_sel_inst > 0) g_sel_inst--; }
			else if (g_focus == F_CAT) cat_cursor(-1);
			else if (g_sel_app > 0) g_sel_app--;
			break;
		case K_DOWN:
			if (g_focus == F_INST) { if (g_sel_inst < g_ninst - 1) g_sel_inst++; }
			else if (g_focus == F_CAT) cat_cursor(1);
			else if (g_sel_app < g_nview - 1) g_sel_app++;
			break;
		case K_PGUP:
			if (g_focus == F_INST) { g_sel_inst -= rows; if (g_sel_inst < 0) g_sel_inst = 0; }
			else if (g_focus == F_CAT) cat_cursor(-3);
			else { g_sel_app -= 3; if (g_sel_app < 0) g_sel_app = 0; }
			break;
		case K_PGDN:
			if (g_focus == F_INST) { g_sel_inst += rows; if (g_sel_inst >= g_ninst) g_sel_inst = g_ninst - 1; }
			else if (g_focus == F_CAT) cat_cursor(3);
			else { g_sel_app += 3; if (g_sel_app >= g_nview) g_sel_app = g_nview - 1; }
			break;
		case K_HOME:
			if (g_focus == F_INST) g_sel_inst = 0;
			else if (g_focus == F_CAT) cat_cursor(-g_ncat);
			else g_sel_app = 0;
			break;
		case K_END:
			if (g_focus == F_INST) g_sel_inst = g_ninst ? g_ninst - 1 : 0;
			else if (g_focus == F_CAT) cat_cursor(g_ncat);
			else g_sel_app = g_nview ? g_nview - 1 : 0;
			break;
		case K_ENTER:
		case ' ':
			g_msg[0] = '\0';
			if (g_focus == F_INST && g_ninst) screen_app(&g_pkg[g_inst[g_sel_inst]]);
			else if (g_focus == F_CAT) g_focus = F_APP;
			else if (g_focus == F_APP && g_nview) screen_app(&g_pkg[g_view[g_sel_app]]);
			break;
		case K_ESC:
			g_msg[0] = '\0';
			break;
		}
		if (g_sel_inst < 0) g_sel_inst = 0;
		if (g_sel_app < 0) g_sel_app = 0;
	}
}

/* ------------------------------------------------------------------- CLI ---*/
static Pkg *find_pkg(const char *id)
{
	for (int i = 0; i < g_npkg; i++)
		if (!strcmp(g_pkg[i].id, id)) return &g_pkg[i];
	for (int i = 0; i < g_npkg; i++)
		if (ci_eq(g_pkg[i].name, id)) return &g_pkg[i];
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
	for (int i = 0; i < p->nparams; i++)
		printf("param:     %s=%s (%s)\n", p->params[i].name, p->params[i].value,
		       p->params[i].label);
	printf("recipe:    %s\n", p->path);
	printf("summary:   %s\n", p->summary);
	return 0;
}

/* `app-setup set nginx port=8080` — the form's job, for a script. */
static int cli_set(int argc, char **argv)
{
	if (argc < 1) { fprintf(stderr, "app-setup: set <id> [name=value ...]\n"); return 2; }
	Pkg *p = find_pkg(argv[0]);
	if (!p) { fprintf(stderr, "app-setup: no such software: %s\n", argv[0]); return 1; }
	if (argc == 1) {
		if (!p->nparams) printf("%s has no settings.\n", p->id);
		for (int i = 0; i < p->nparams; i++)
			printf("%-16s %-20s %s\n", p->params[i].name, p->params[i].value,
			       p->params[i].label);
		return 0;
	}
	for (int a = 1; a < argc; a++) {
		char *eq = strchr(argv[a], '=');
		if (!eq) { fprintf(stderr, "app-setup: not name=value: %s\n", argv[a]); return 2; }
		*eq = '\0';
		int hit = 0;
		for (int i = 0; i < p->nparams; i++)
			if (ci_eq(p->params[i].name, argv[a])) {
				copy_str(p->params[i].value, sizeof p->params[i].value, eq + 1);
				hit = 1;
			}
		if (!hit) { fprintf(stderr, "app-setup: %s has no setting called %s\n", p->id, argv[a]); return 2; }
	}
	if (!params_save(p)) { fprintf(stderr, "app-setup: could not write the settings file\n"); return 1; }
	return 0;
}

static int cli_run(const char *verb, int argc, char **argv)
{
	int rc = 0;
	for (int i = 0; i < argc; i++) {
		Pkg *p = find_pkg(argv[i]);
		if (!p) { fprintf(stderr, "app-setup: no such software: %s\n", argv[i]); rc = 1; continue; }
		char log[600];
		snprintf(log, sizeof log, "%s/%s.log", log_dir(), p->id);
		g_env_pkg = p;
		int r = run_stream(p->path, verb, log);
		g_env_pkg = NULL;
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
		if (!p) { fprintf(stderr, "app-setup: no such software: %s\n", argv[i]); rc = 4; continue; }
		probe_pkg(p);
		printf("%s %s%s%s\n", p->id, state_word(p), p->detail[0] ? " — " : "", p->detail);
		/* The same four codes a recipe's own `status` verb returns, so that
		 * `app-setup status nginx` and `sh /etc/app-setup/nginx.sh status`
		 * can be used interchangeably in a script. Asked about several at
		 * once, the worst one wins — a caller checking "is all of this up"
		 * wants a non-zero exit if any of it is not. */
		int one = p->status == ST_RUNNING || p->status == ST_INSTALLED ? 0 :
		          p->status == ST_STOPPED ? 1 :
		          p->status == ST_ABSENT  ? 2 : 3;
		if (one > rc) rc = one;
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
	printf("state       %s\n", state_dir());
	printf("recipes     %d\n", g_npkg);
	printf("logs        %s\n", log_dir());
	int bad = 0;
	for (int i = 0; i < g_npkg; i++) {
		if (access(g_pkg[i].path, R_OK) != 0) { printf("unreadable  %s\n", g_pkg[i].path); bad++; }
		if (!g_pkg[i].summary[0])             { printf("no summary  %s\n", g_pkg[i].id); bad++; }
	}
	printf("problems    %d\n", bad);
	return bad ? 1 : 0;
}

/* One frame as plain text. This is how the layout is tested without a
 * terminal: render at 130, 88 and 46 columns and look at what survived. */
static int cli_screenshot(int n, char **rest)
{
	int w = 100, h = 30;
	const char *cat = NULL, *screen = "main", *pick = NULL;
	for (int i = 1; i < n; i++) {
		if (!strcmp(rest[i], "--width") && i + 1 < n) w = atoi(rest[++i]);
		else if (!strcmp(rest[i], "--height") && i + 1 < n) h = atoi(rest[++i]);
		else if (!strcmp(rest[i], "--category") && i + 1 < n) cat = rest[++i];
		else if (!strcmp(rest[i], "--screen") && i + 1 < n) screen = rest[++i];
		else if (!strcmp(rest[i], "--id") && i + 1 < n) pick = rest[++i];
		else if (!strcmp(rest[i], "--probe")) probe_all(1);
	}
	g_w = w > 24 ? w : 24;
	g_h = h > 10 ? h : 10;
	if (cat) { int i = cat_index(cat); if (i >= 0) g_cat = i; }
	sync_cat_cursor();
	rebuild_lists();
	grid_size(g_w, g_h);
	compute_layout();

	Pkg *p = pick ? find_pkg(pick) : (g_nview ? &g_pkg[g_view[0]] : NULL);

	if (!strcmp(screen, "menu") && p) {
		/* the action dialog, drawn once — same code path, no event loop */
		render_main();
		Action acts[12];
		int na = build_actions(p, acts);
		int ww = 54; if (ww > g_w - 6) ww = g_w - 6;
		int inner = ww - 4;
		char sum[3][512];
		int ns = u8wrap(pkg_summary(p), inner, sum, 2);
		int hh = na + ns + 7; if (hh > g_h - 2) hh = g_h - 2;
		int row = (g_h - hh) / 2, col = (g_w - ww) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, ww, hh, pkg_name(p));
		int y = row + 1;
		char st[128];
		snprintf(st, sizeof st, "%s %s", status_mark(p), S(*status_label(p)));
		gput(y, col + 2, st, status_attr(p), inner); y++;
		for (int i = 0; i < ns; i++) { gput(y, col + 2, sum[i], P_DIM, inner); y++; }
		y++;
		for (int i = 0; i < na && y < row + hh - 2; i++, y++) {
			if (i == 0) gtint(y, col + 2, inner, P_SEL);
			gput(y, col + 3, acts[i].label, i == 0 ? P_SEL : P_WIN, inner - 10);
			if (acts[i].aux[0])
				gput(y, col + 1 + inner - u8width(acts[i].aux), acts[i].aux, P_DIM, 8);
		}
		btn_draw(row + hh - 2, col + 2, S(T_BACK), 0);
		help_line(S(T_HELPMENU));
	} else if (!strcmp(screen, "progress")) {
		/* a fabricated frame — the real one needs a child process */
		render_main();
		char title[256];
		snprintf(title, sizeof title, S(T_VERB_INS), p ? pkg_name(p) : "…");
		int ww = g_w - 8; if (ww > 100) ww = 100; if (ww < 36) ww = g_w - 2;
		int hh = g_h - 4; if (hh > 26) hh = 26; if (hh < 12) hh = g_h - 2;
		int row = (g_h - hh) / 2 - 1, col = (g_w - ww) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		int inner = ww - 4, x = col + 2;
		win_box(row, col, ww, hh, title);
		int y = row + 1;
		char head[128];
		snprintf(head, sizeof head, S(T_STEPOF), 3, 6);
		gput(y, x, head, P_DIM, inner); y++;
		draw_bar(y, x, inner - 5, 45);
		gput(y, x + inner - 5, "  45%", P_WIN, 5);
		y += 2;
		gput(y, x, g_zh ? "正在配置默认站点…" : "configuring the default site…", P_WIN, inner);
		y += 2;
		int logh = row + hh - 3 - y; if (logh < 3) logh = 3;
		gput(y, x, BX_TL, P_BORDER, 1);
		gfill(y, x + 1, inner - 2, BX_H, P_BORDER);
		gput(y, x + inner - 1, BX_TR, P_BORDER, 1);
		{ char lt[64]; snprintf(lt, sizeof lt, " %s ", S(T_LOGPANE));
		  gput(y, x + 2, lt, P_TITLE, u8width(lt)); }
		for (int i = 1; i < logh - 1; i++) {
			gput(y + i, x, BX_V, P_BORDER, 1);
			gput(y + i, x + inner - 1, BX_V, P_BORDER, 1);
		}
		gput(y + logh - 1, x, BX_BL, P_BORDER, 1);
		gfill(y + logh - 1, x + 1, inner - 2, BX_H, P_BORDER);
		gput(y + logh - 1, x + inner - 1, BX_BR, P_BORDER, 1);
		gput(y + 1, x + 2, "Setting up nginx (1.22.1-9) ...", P_DIM, inner - 4);
		gput(y + 2, x + 2, "==> configuring the default site", P_DIM, inner - 4);
		help_line(S(T_HELPRUN));
	} else if (!strcmp(screen, "params") && p) {
		render_main();
		int labw = 12;
		for (int i = 0; i < p->nparams; i++) {
			int lw = u8width(param_label(&p->params[i]));
			if (lw > labw) labw = lw;
		}
		int fieldw = 30, ww = labw + fieldw + 8;
		if (ww > g_w - 6) { ww = g_w - 6; fieldw = ww - labw - 8; }
		int hh = p->nparams + 6; if (hh > g_h - 2) hh = g_h - 2;
		int row = (g_h - hh) / 2, col = (g_w - ww) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		char title[256];
		snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_PARAMS));
		win_box(row, col, ww, hh, title);
		for (int i = 0; i < p->nparams && i < hh - 5; i++) {
			Param *pm = &p->params[i];
			int y = row + 1 + i, fx = col + 3 + labw;
			int a = i == 0 ? P_ENTRYACT : P_ENTRY;
			gput(y, col + 2, param_label(pm), P_WIN, labw);
			gfill(y, fx, fieldw, " ", a);
			if (pm->type == PT_BOOL) {
				int on = !strcmp(pm->value, "on") || !strcmp(pm->value, "1");
				char box[32];
				snprintf(box, sizeof box, "[%s] %s", on ? MK_OK : " ", on ? S(T_ON) : S(T_OFF));
				gput(y, fx, box, a, fieldw);
			} else if (pm->type == PT_ENUM) {
				char ch[128];
				snprintf(ch, sizeof ch, "%s %s %s", AR_L, pm->value, AR_R);
				gput(y, fx, ch, a, fieldw);
			} else gput(y, fx, pm->value, a, fieldw - 1);
		}
		int bw = btn_width(S(T_OK)) + 2 + btn_width(S(T_CANCEL));
		int bx = col + (ww - bw) / 2;
		btn_draw(row + hh - 2, bx, S(T_OK), 1);
		btn_draw(row + hh - 2, bx + btn_width(S(T_OK)) + 2, S(T_CANCEL), 0);
		help_line(S(T_HELPFORM));
	} else {
		render_main();
	}

	grid_dump(stdout);
	printf("\n[screen=%s panes=%d apps=%d/%d installed=%d %dx%d]\n",
	       screen, L_showinst ? 3 : 2, g_nview, g_npkg, g_ninst, g_w, g_h);
	return 0;
}

static void usage(FILE *f)
{
	fprintf(f,
	  "app-setup %s — install software into this container\n"
	  "\n"
	  "  app-setup                    the full-screen picker (this is the one you want)\n"
	  "  app-setup list [category]    everything, or one of: stack web db dev system\n"
	  "  app-setup info <id>          one package in detail\n"
	  "  app-setup status [id...]     state only. Exit: 0 running, 1 stopped,\n"
	  "                               2 not installed, 3 broken, 4 no such id\n"
	  "  app-setup install <id>...\n"
	  "  app-setup remove <id>...\n"
	  "  app-setup start|stop|restart <id>...\n"
	  "  app-setup enable|disable <id>...   start at boot, or stop doing that\n"
	  "  app-setup set <id> [k=v ...] show or change a recipe's settings\n"
	  "  app-setup docs <id>          what the recipe says about itself\n"
	  "  app-setup doctor             what this machine looks like to app-setup\n"
	  "  app-setup screenshot [--width N] [--height N] [--category C]\n"
	  "                       [--screen main|menu|params|progress] [--id ID]\n"
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
	mkdir_p(log_dir());
	{
		for (int i = 0; i < g_ncat; i++) if (cat_count(i)) { g_cat = i; break; }
	}

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
	else if (!strcmp(cmd, "set"))     rc = cli_set(na, aa);
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
		g_env_pkg = p;
		rc = run_stream(p->path, "help", NULL);
		g_env_pkg = NULL;
	} else if (!strcmp(cmd, "screenshot")) {
		g_color = 0;
		rc = cli_screenshot(n, rest);
	} else {
		fprintf(stderr, "app-setup: unknown command: %s\n\n", cmd);
		usage(stderr);
		rc = 2;
	}
	return rc;
}
