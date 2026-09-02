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
 * The screen is a video site's, deliberately: a strip of categories along the
 * top with Installed as the first of them, and under it a grid of cards, each
 * with a coloured cover, a name, a line saying what it is for and a line
 * saying where it stands. Press Enter on a card and everything that can be
 * done to that thing is laid along the top of the next screen. Nobody has to
 * be taught this; they have been driving it in a browser for years.
 *
 * Two ways in, neither a patch over the other. Four arrow keys and Enter reach
 * every control, which is the path that always works — over ssh, on a terminal
 * with no mouse, or with both hands already on the keys. And the mouse clicks
 * whatever it can see, which is faster when it is there. Back is a button in
 * the top right corner of every screen rather than a key you have to know, so
 * holding Up walks you out of the program.
 *
 * The palette is still newt's, so this and nmtui look like the same family:
 * white on blue for the page, black on cyan for whatever the cursor is on, a
 * help line along the bottom naming the keys that do something here.
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
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define APP_VERSION   "2.12.0"
#define MAX_PKGS      512
#define MAX_CATS      32
#define MAX_PARAMS    12
#define DEFAULT_PATH  "/etc/app-setup:/etc/app-setup/local"
#define DEFAULT_CONF  "/etc/app-setup"
#define DEFAULT_STATE "/var/lib/app-setup"
#define LOG_DIR       "/var/log/app-setup"
#define LOG_KEEP      400        /* lines of a running action held for the pane */
#define LOG_TAIL      60000      /* bytes of a log file the viewer reads back */
#define LOG_COLS      512

/* ------------------------------------------------------------------ text --
 *
 * Every string the chrome shows exists twice. Recipes carry their own pair in
 * their header (`name:` and `name.zh:`), so a third-party source is bilingual
 * the same way without patching anything here.
 */
typedef struct { const char *en, *zh; } L;
static int g_zh = 0;                       /* English unless asked otherwise */
#define S(l) (g_zh ? (l).zh : (l).en)

/* The label of the *other* language, which is what a switch should be called:
 * pressing a button that says 中文 gets you 中文. Never S()'d — it is the one
 * string in here that must not follow the current language. */
static const char *lang_other(void) { return g_zh ? "English" : "中文"; }

static const L T_TITLE     = {"app-setup", "app-setup"};
static const L T_SUBTITLE  = {"software manager", "软件管家"};
/* The same binary answers to `helppage`, and the blue bar has to say which
 * program you are looking at. Two pointers rather than a copy of draw_root:
 * every screen in here draws that bar, and a second one would drift. */
static const L T_GTITLE    = {"helppage", "helppage"};
static const L T_GSUBTITLE = {"guide to your container", "容器使用指南"};
static const L T_CONTENTS  = {"Contents", "目录"};
static const L T_NOGUIDE   = {"No pages found. They live in /etc/helppage/*.txt",
                              "没有找到任何文档。它们在 /etc/helppage/*.txt"};
/* Two lines, because the two panes are driven differently and somebody who has
 * just walked the cursor into one wants to know what *that* one does. Neither
 * names `L`: the switch is on the screen now, in the pane, with the cursor
 * able to land on it — a key for it is a shortcut, not the way in. */
static const L T_GKEYSNAV  = {"↑↓ move   → to the text   Enter open   q quit",
                              "↑↓ 移动   → 进入正文   Enter 打开   q 退出"};
static const L T_GKEYSBODY = {"↑↓ jk scroll   ^F/^B page   ← back to contents   q quit",
                              "↑↓ jk 滚动   ^F/^B 翻页   ← 回到目录   q 退出"};
/* One pane, so there is nothing to cross to and the pair that would have done
 * it turn the chapters instead. */
static const L T_GKEYSONE  = {"↑↓ jk scroll   ^F/^B page   ←→ chapter   q quit",
                              "↑↓ jk 滚动   ^F/^B 翻页   ←→ 换章   q 退出"};
static const L T_INSTALLP  = {"Installed",    "已安装"};
static const L T_INSTALL   = {"Install",      "安装"};
static const L T_UPDATE    = {"Update",       "更新"};
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
static const L T_SHOW      = {"Show",         "展开"};
static const L T_HIDE      = {"Hide",         "收起"};
static const L T_DONE      = {"Done",         "完成"};
static const L T_EMPTY     = {"Nothing in this category.", "这个分类下没有软件。"};
static const L T_NOINST    = {"Nothing installed yet.",    "还没有装任何软件。"};
static const L T_NORECIPE  = {"No software sources found. Put recipes in /etc/app-setup/*.sh.",
                             "没有找到软件源。把脚本放到 /etc/app-setup/*.sh。"};
static const L T_CONFIRM   = {"Enter confirms, Esc cancels", "回车确认，Esc 取消"};
static const L T_REMOVEQ   = {"Uninstall %s? Its configuration goes too; data is kept.",
                             "确定卸载 %s？配置会一起删除，数据会保留。"};
/* A destructive `# button:` verb, named along with what it will act on. The
 * sentence is the whole point of the dialog, so it says both: which verb, and
 * on which card — "⟲ Restore on MySQL / MariaDB" rather than "Are you sure?".
 * What exactly gets overwritten is the recipe's own business and is in the
 * text it prints on the progress screen a moment later. */
static const L T_BUTTONQ   = {"%s on %s? This overwrites what is there now.",
                             "「%s」—— 在 %s 上执行？现在的内容会被覆盖。"};
static const L T_TIGHTQ    = {"%s wants %s but this machine has %s. Install anyway?",
                             "%s 需要 %s，本机只有 %s。仍要安装吗？"};
static const L T_KILLQ     = {"Stop it now? A half-finished package manager has to be repaired by hand.",
                             "现在强行中止？包管理器装到一半，之后要手工修。"};
static const L T_ROOTWARN  = {"not root: actions will be run through sudo",
                             "当前不是 root：操作会走 sudo"};
static const L T_LOGPANE   = {"Details", "详细日志"};
static const L T_STEPOF    = {"Step %d of %d", "第 %d 步，共 %d 步"};
static const L T_WORKING   = {"Working…", "正在处理…"};
static const L T_FINISHED  = {"%s finished. The full output is in %s",
                             "%s 完成了。完整输出在 %s"};
static const L T_FAILED    = {"%s failed — exit %d. The log is %s",
                             "%s 失败，退出码 %d。日志在 %s"};
/* The same dialog, for the common case where the recipe said why before it
 * gave up. `die` is the last thing most failures print, and it is already a
 * whole sentence aimed at the person reading it — "no origin yet. Open
 * Settings and type the domain or IP of the machine your website is on."
 * Leaving that in the log and showing only an exit code turns a recipe's own
 * instruction into a dead end: the box says something went wrong, and the one
 * thing that would fix it is three commands away. The log path stays, because
 * the sentence is rarely the whole story. */
static const L T_FAILEDWHY = {"%s failed — %s\n\nExit %d. The full log is %s",
                             "%s 失败了 —— %s\n\n退出码 %d，完整日志在 %s"};
static const L T_VERB_INS  = {"Installing %s", "正在安装 %s"};
static const L T_VERB_REM  = {"Uninstalling %s", "正在卸载 %s"};
static const L T_VERB_STA  = {"Starting %s", "正在启动 %s"};
static const L T_VERB_STO  = {"Stopping %s", "正在停止 %s"};
static const L T_VERB_RES  = {"Restarting %s", "正在重启 %s"};
static const L T_VERB_BOOT = {"Changing boot setting for %s", "正在修改 %s 的开机自启"};
static const L T_NODOC     = {"This source ships no documentation.", "这个软件源没有写说明。"};
static const L T_NOPARAM   = {"This software has no settings to change.",
                             "这个软件没有可以改的参数。"};
static const L T_REQFIELD  = {"This one has to be filled in before it can be applied.",
                             "这一项必须填了才能应用。"};
static const L T_PARAMSAVED= {"Settings saved, but not in effect yet. Use Save & Apply, or install again.",
                             "参数已保存，但还没生效。用「保存并应用」，或下次安装时生效。"};

/* The form's three buttons, which are LuCI's: the primary one writes the
 * settings *and* runs the install verb, because for every recipe here that
 * verb is also the reconfigure path — it rewrites the config from the
 * parameters and restarts the service. Save on its own is for somebody
 * setting up three things before applying any of them, and for the case where
 * applying means a download they would rather start later. */
static const L T_SAVEAPPLY = {"Save & Apply", "保存并应用"};
static const L T_SAVE      = {"Save",         "保存"};

/* The home screen and the detail page. Both say which way is out, because the
 * way out is a button you walk to rather than a key you have to know. */
static const L T_ALL       = {"All",           "全部"};
static const L T_FIND      = {"Find", "查找"};
static const L T_FINDHINT  = {"type to search", "直接打字搜索"};
static const L T_VLIST     = {"List", "列表"};
static const L T_VCARDS    = {"Cards", "卡片"};
static const L T_NOMATCH   = {"Nothing matches. Backspace, or Esc to clear.",
                             "没有匹配的。退格删字，或按 Esc 清空。"};
static const L T_HELPHOME  = {"type to search   ↑↓←→ move   Enter open   F3 view   F2 中文   Esc clear/quit",
                             "直接打字搜索   ↑↓←→ 移动   回车 打开   F3 视图   F2 English   Esc 清空/退出"};
static const L T_HELPDET   = {"←→ tab   ↓ into it   Enter run   F2 中文   Esc back",
                             "←→ 切换标签   ↓ 进入内容   回车 执行   F2 English   Esc 返回"};
static const L T_SERVICE   = {"Service",      "服务"};
static const L T_VERSION   = {"Version",      "版本"};
static const L T_INCLUDES  = {"Includes",     "包含"};
static const L T_LOG       = {"Log",          "日志"};
/* The tab bar of the app screen. `Status` when there is something running to
 * have a state, `Not installed` when there is not — the first tab names what
 * this screen is showing rather than what the software would do. */
static const L T_TSTATUS   = {"Status",        "状态"};
static const L T_EDITHINT  = {"Enter opens the form. * marks what must be filled in.",
                             "回车打开编辑表单。带 * 的是必填项。"};
static const L T_TABSENT   = {"Not installed", "未安装"};
static const L T_REMOVEBODY= {"Uninstalling stops the service, removes the packages this recipe installed and deletes the configuration it wrote. Data is kept: databases, document roots and anything under /data stay where they are. What exactly each recipe keeps is in its own How to use it.",
                             "卸载会停掉服务、删掉这个配方装的软件包和它写的配置。数据会保留：数据库、网站目录以及 /data 下的东西都不动。具体每个配方保留什么，看它自己的「使用说明」。"};
static const L T_NOLOG     = {"No log yet. One appears at %s the first time something is run on it.",
                             "还没有日志。对它做过一次操作之后，日志就在 %s。"};
static const L T_LOGEMPTY  = {"The log file is empty.", "日志文件是空的。"};
static const L T_LOGTAIL   = {"── the last %s of %s ──", "── %s／共 %s，只显示末尾 ──"};
static const L T_NITEMS    = {"%d",           "%d 项"};
static const L T_HELPFORM  = {"↑↓ field   ←→ move / choose   ^U clear   ^W drop word   Enter save & apply   Esc cancel",
                             "↑↓ 换行   ←→ 移动光标 / 选值   ^U 清空   ^W 删一段   回车 保存并应用   Esc 取消"};
static const L T_HELPPAGE  = {"↑↓ scroll   Enter / Esc back", "↑↓ 滚动   回车/Esc 返回"};
static const L T_HELPPICK  = {"↑↓ move   Space tick   Enter done   Esc cancel",
                              "↑↓ 移动   空格 勾选   回车 完成   Esc 取消"};
static const L T_PICKEMPTY = {"nothing chosen — Enter to pick", "还没选 —— 回车来选"};
/* The honest answer when the list would be empty, and it names the reason
 * rather than the symptom: an empty popup tells somebody the program is
 * broken, and what is actually true is that there is nothing here to save. */
static const L T_PICKNONE  = {"Nothing installed here can be backed up yet. Install a "
                              "database or Files and folders first, then come back.",
                              "这台机器上还没有能备份的东西。先装一个数据库，或者装「文件和目录」，再回来。"};
static const L T_HELPRUN   = {"Working — Esc twice to force a stop", "执行中 —— 按两次 Esc 可强行中止"};
static const L T_HELPDONE  = {"Enter to go back", "回车返回"};

/* The nav list, in the order it is shown. A recipe naming a category that is
 * not here gets one appended, labelled by its own `category.name:` — which is
 * how somebody's private source adds "Game servers" without a code change. */
static struct { char id[24]; L label; int owned; } g_cats[MAX_CATS] = {
	{"stack",  {"Suites",     "套件安装"},     0},
	{"web",    {"Web servers","Web 服务器"},   0},
	{"db",     {"Databases",  "数据库"},       0},
	/* Beside Databases and not at the end, because the two chips are read as
	 * a pair: the tab you install a database from, and the tab you protect it
	 * from. A recipe naming `backup` would be appended here anyway — this only
	 * decides where it sits. */
	{"backup", {"Backup",     "备份"},         0},
	{"dev",    {"Dev tools",  "开发插件"},     0},
	{"system", {"System",     "常用系统软件"}, 0},
};
static int g_ncat = 6;

/* ------------------------------------------------------------------ model */
enum { ST_UNKNOWN = 0, ST_RUNNING, ST_STOPPED, ST_ABSENT, ST_BROKEN, ST_INSTALLED };

/* A tunable a recipe declares in its header and reads back with `param`. The
 * type is inferred: `bool` gets a checkbox, a comma list gets a left/right
 * chooser, everything else is a text field. Anything more than that wants a
 * config file, not a form. */
/* PT_LIST is the one type whose choices this file works out rather than reads:
 * a `# param: … | @backup` field is answered with the packages on *this*
 * machine that can be backed up, which is not something a recipe author in
 * another country can write down. See list_options. */
enum { PT_TEXT = 0, PT_BOOL, PT_ENUM, PT_NUMBER, PT_LIST };

typedef struct {
	char name[32];
	char label[64], label_zh[96];
	/* LuCI's line under the control, which is the thing this form missed most:
	 * `Keep pages for = 10m` says nothing about the unit or about what blank
	 * does. Filled by `# help:`; empty on every recipe that has not written
	 * one, which costs those recipes nothing. */
	char help[160], help_zh[200];
	char dflt[128];
	char value[256];
	int  type;
	char choices[8][32];
	int  nchoices;
	/* PT_LIST only: what to fill the popup with, from the `@name` the recipe
	 * wrote. One source today; the mechanism is here because a hard-coded
	 * list of ids in a recipe is exactly the thing that goes stale. */
	char source[16];

	/* Which `# group:` this field belongs to (index into Pkg.groups), or -1
	 * for ungrouped — every field declared before the first `# group:` line,
	 * which is every recipe today. Set once, at parse time, in add_param. */
	int  group;

	/* `# action: <this param> | verb | label | label.zh` — a button drawn on
	 * its own row beneath this field, running <verb> through the same
	 * progress screen Install uses (screen_progress) and returning to this
	 * form with the field's choices reloaded. Empty verb means no button. */
	char action_verb[32];
	char action_label[64], action_label_zh[96];
} Param;

#define MAX_GROUPS 4

typedef struct {
	char id[32];
	char label[64], label_zh[96];
	int  folded;    /* the header's own `collapsed` keyword; toggled live too */
} Group;

#define MAX_BUTTONS 6

/* A package-level control, declared by `# button:` (add_button). Unlike
 * `# action:`, which belongs to one field inside Settings, this sits on the
 * app screen's own verb row — see build_actions for what declaring even one
 * of these does to that row. */
/* How the verb is run, from the fourth field of the `# button:` line:
 *   (blank)    B_PAGE     capture stdout, page it — a verb that prints
 *   progress   B_PROG     the streaming progress screen — a verb that works
 *   confirm    B_CONFIRM  the confirm dialog, then the progress screen */
enum { B_PAGE = 0, B_PROG, B_CONFIRM };

typedef struct {
	char verb[32];
	char label[64], label_zh[96];
	int  mode;
} Btn;

typedef struct {
	char id[64];
	char path[512];
	char name[96], name_zh[128];
	char summary[320], summary_zh[400];
	char includes[224], includes_zh[280];
	char disk[32], memory[32], ports[64], requires[128];
	char service[64];
	/* `# require: origin, port` — the fields the recipe cannot run without.
	 * A comma list rather than a flag on the param line, because the param
	 * line is full at five fields and because one line reads as one rule. */
	char require[160];
	char cats[6][24];
	int  ncats;
	int  order;
	long long disk_bytes, mem_bytes;

	Param params[MAX_PARAMS];
	int  nparams;

	Group groups[MAX_GROUPS];
	int  ngroups;
	/* Parse-time only: which group the next `# param:` line joins. -1 until
	 * the header's first `# group:` line, meaningless once load_recipe
	 * returns — nothing reads it after parsing finishes. */
	int  cur_group;

	/* Whether this recipe defines do_backup, read out of the file rather than
	 * declared in its header. The header would be a second place to keep in
	 * sync and a thing an author can forget; the function either exists or it
	 * does not, and that is the contract app-setup-sources.md already states.
	 * It is what fills the Backup card's list of what can be backed up. */
	int  can_backup;

	Btn  buttons[MAX_BUTTONS];
	int  nbuttons;

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

/* Two directories, and the difference is who is expected to open them.
 *
 * conf_dir() is configuration — the recipes themselves and the settings the
 * form saves for them — and it is /etc, because that is the first place
 * anybody looks and the only place worth telling somebody to look. state_dir()
 * is what app-setup keeps for its own bookkeeping, the package-index refresh
 * stamp above all, which nobody edits and nobody should have to step over on
 * the way to a port number. */
static const char *conf_dir(void)
{
	const char *e = getenv("APP_SETUP_CONF");
	return e && *e ? e : DEFAULT_CONF;
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

/* Whether the terminal can be sent UTF-8 and colour at all. Declared up here
 * rather than with the screen because the width and truncation helpers below
 * need it: what they emit has to be drawable, not merely the right width. */
static int g_color = 1, g_utf8 = 1;

/* The cursor highlight moves; see "the cursor" below for why. Declared here
 * because the key reader needs the tick length and it comes first. */
#define ANIM_MS    90            /* ~11 frames a second */
#define SWEEP_MS 1100            /* one pass along an element */

static int g_anim = 1;
static unsigned g_phase = 0;

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
 * clipped summary does not read as a sentence that simply stops.
 *
 * The mark is one column of UTF-8 or three of ASCII, and the budget is taken
 * off before the truncation either way — the whole point of this file's own
 * width table is that nothing it draws is allowed to be one column out, and a
 * `…` emitted to a Latin-1 terminal is three bytes of mojibake. */
static void u8ellipsis(char *dst, size_t cap, const char *src, int cols)
{
	if (u8width(src) <= cols) { copy_str(dst, cap, src); return; }
	const char *mark = g_utf8 ? "…" : "...";
	int mw = g_utf8 ? 1 : 3;
	if (cols <= mw) { u8trunc(dst, cap, src, cols); return; }
	u8trunc(dst, cap, src, cols - mw);
	size_t n = strlen(dst);
	if (n + strlen(mark) + 1 < cap) strcpy(dst + n, mark);
}

/* The other end of u8ellipsis: keep the *last* `cols` columns and mark the
 * front. The form's text fields append and backspace and have no caret to
 * move, so the cursor is always at the end of the value — and drawing the head
 * of something longer than its field hides the exact part somebody is typing
 * into. A hundred-character comma list was being edited blind. */
static void u8tail(char *dst, size_t cap, const char *src, int cols)
{
	if (u8width(src) <= cols) { copy_str(dst, cap, src); return; }
	const char *mark = g_utf8 ? "…" : "...";
	int mw = g_utf8 ? 1 : 3;
	if (cols <= mw) { u8trunc(dst, cap, src, cols); return; }

	/* Walk forward to the first character whose remainder fits. Quadratic in
	 * the length, and the length is one form field, so it costs nothing and
	 * saves keeping an index of every character in the string. */
	int want = cols - mw;
	const char *q = src;
	while (*q && u8width(q) > want) { unsigned int c; q = u8next(q, &c); }

	copy_str(dst, cap, mark);
	size_t n = strlen(dst);
	if (n < cap) copy_str(dst + n, cap - n, q);
}

/* Wrap to `cols`, breaking on spaces where there are any and between
 * characters where there are not — Chinese summaries have no spaces to break
 * on and would otherwise never wrap. */
/* `label` followed by spaces out to `cols` display columns. printf's %-*s pads
 * to a byte count, and every label in here has a Chinese form that is fewer
 * columns per byte than its English one — so a column laid out with %-*s lines
 * up in one language and not the other. */
static void u8pad(char *dst, size_t cap, const char *label, int cols)
{
	size_t n = 0;
	while (label[n] && n + 1 < cap) { dst[n] = label[n]; n++; }
	for (int i = u8width(label); i < cols && n + 1 < cap; i++) dst[n++] = ' ';
	dst[n] = '\0';
}

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

/* The same, with one argument handed through to the recipe — `remote <folder>`
 * needs it, and a NULL folder collapses back to the two-argument form because
 * the first NULL ends the list either way. */
static void exec_recipe_arg(const char *script, const char *verb, const char *arg)
{
	if (geteuid() != 0 && have_cmd("sudo"))
		execlp("sudo", "sudo", "-E", "/bin/sh", script, verb, arg, (char *)NULL);
	execl("/bin/sh", "sh", script, verb, arg, (char *)NULL);
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
	/* `@name` — the choices are this machine's answer, not the recipe's. An
	 * unknown name is left as a text field rather than as an empty chooser:
	 * a recipe written against a newer app-setup should degrade to something
	 * a person can still type into. */
	else if (ty[0] == '@' && ty[1]) {
		pm->type = PT_LIST;
		copy_str(pm->source, sizeof pm->source, ty + 1);
	}
	else if (strchr(ty, ',')) {
		pm->type = PT_ENUM;
		char tmp[256];
		copy_str(tmp, sizeof tmp, ty);
		/* strtok_r here too: this runs while scan_all is walking the
		 * search path, and one global cursor cannot serve both. */
		char *sv = NULL;
		char *tok = strtok_r(tmp, ",", &sv);
		while (tok && pm->nchoices < 8) {
			trim(tok);
			if (*tok) copy_str(pm->choices[pm->nchoices++], sizeof pm->choices[0], tok);
			tok = strtok_r(NULL, ",", &sv);
		}
		if (pm->nchoices < 2) pm->type = PT_TEXT;
	} else pm->type = PT_TEXT;

	pm->group = p->cur_group;
	p->nparams++;
}

/* `group: id | English label | 中文标签 | collapsed-or-expanded`
 *
 * Every `# param:` line after this one, until the next `# group:` line,
 * joins it — nothing to write on the param line itself. A field declared
 * before the first `# group:` stays ungrouped, at the top: this is why a
 * recipe with no groups at all needs no change to keep rendering exactly as
 * it always has (docs/app-setup.edit.md §5). `collapsed` is the only
 * fourth field that means anything; anything else, or nothing, is
 * `expanded` — an author who names a group but forgets to fold it gets
 * today's behaviour, not a hidden field. */
static void add_group(Pkg *p, const char *spec)
{
	if (p->ngroups >= MAX_GROUPS) return;
	char buf[256];
	copy_str(buf, sizeof buf, spec);

	char *f[4] = { buf, NULL, NULL, NULL };
	int nf = 1;
	for (char *q = buf; *q && nf < 4; q++)
		if (*q == '|') { *q = '\0'; f[nf++] = q + 1; }
	for (int i = 0; i < nf; i++) trim(f[i]);
	if (!*f[0]) return;

	Group *g = &p->groups[p->ngroups];
	memset(g, 0, sizeof *g);
	copy_str(g->id, sizeof g->id, f[0]);
	copy_str(g->label, sizeof g->label, nf > 1 && *f[1] ? f[1] : f[0]);
	copy_str(g->label_zh, sizeof g->label_zh, nf > 2 && *f[2] ? f[2] : g->label);
	g->folded = (nf > 3 && !strcmp(f[3], "collapsed"));

	p->cur_group = p->ngroups;
	p->ngroups++;
}

/* `action: param | verb | English label | 中文标签`
 *
 * A button belonging to a field already declared earlier in this header —
 * recipes name the field before the action that refreshes it, the same
 * order `# group:` already requires. A name that does not match any
 * `# param:` parsed so far is silently dropped, same as every other line
 * this parser cannot use — no button, not a crash and not a load failure. */
static void add_action(Pkg *p, const char *spec)
{
	char buf[512];
	copy_str(buf, sizeof buf, spec);

	char *f[4] = { buf, NULL, NULL, NULL };
	int nf = 1;
	for (char *q = buf; *q && nf < 4; q++)
		if (*q == '|') { *q = '\0'; f[nf++] = q + 1; }
	for (int i = 0; i < nf; i++) trim(f[i]);
	if (!*f[0] || nf < 2 || !*f[1]) return;

	char name[32];
	copy_str(name, sizeof name, f[0]);
	for (char *q = name; *q; q++)
		if (!isalnum((unsigned char)*q) && *q != '_') *q = '_';

	Param *pm = NULL;
	for (int i = 0; i < p->nparams; i++)
		if (!strcmp(p->params[i].name, name)) { pm = &p->params[i]; break; }
	if (!pm) return;

	copy_str(pm->action_verb, sizeof pm->action_verb, f[1]);
	copy_str(pm->action_label, sizeof pm->action_label, nf > 2 && *f[2] ? f[2] : f[1]);
	copy_str(pm->action_label_zh, sizeof pm->action_label_zh,
	         nf > 3 && *f[3] ? f[3] : pm->action_label);
}

/* `button: verb | English label | 中文标签`
 *
 * A control on the app screen's own verb row — Install/Start/Stop/Log/
 * Settings/Details/Uninstall live there because that state machine is right
 * for a service. It is not right for a recipe that is not one: private-pkg/
 * clients.sh installs nothing, has no service, and is always "installed", so
 * every one of those seven verbs is either always the same answer or
 * actively misleading (do_install's only effect was dumping the guide text
 * into a log file nobody asked to keep). Declaring even one `# button:`
 * replaces that whole computed row with exactly the buttons named here, in
 * the order named here — build_actions is where that swap happens.
 *
 * Each one runs through screen_docs_verb: the verb's stdout, captured and
 * paged, the same mechanism `# How to use it` already runs `help` through.
 * Nothing here touches /var/log/app-setup — that log is for verbs that take
 * real time and can fail (install, start, stop); a button that only prints
 * text should not leave a growing file behind every time somebody reads it.
 * A verb that needs the streaming/progress screen instead is what
 * `# action:` (add_action, field-scoped) is for. */
static void add_button(Pkg *p, const char *spec)
{
	if (p->nbuttons >= MAX_BUTTONS) return;
	char buf[256];
	copy_str(buf, sizeof buf, spec);

	char *f[4] = { buf, NULL, NULL, NULL };
	int nf = 1;
	for (char *q = buf; *q && nf < 4; q++)
		if (*q == '|') { *q = '\0'; f[nf++] = q + 1; }
	for (int i = 0; i < nf; i++) trim(f[i]);
	if (!*f[0]) return;

	Btn *b = &p->buttons[p->nbuttons];
	memset(b, 0, sizeof *b);
	copy_str(b->verb, sizeof b->verb, f[0]);
	copy_str(b->label, sizeof b->label, nf > 1 && *f[1] ? f[1] : f[0]);
	copy_str(b->label_zh, sizeof b->label_zh, nf > 2 && *f[2] ? f[2] : b->label);
	b->mode = B_PAGE;
	if (nf > 3 && *f[3]) {
		if      (!strcmp(f[3], "progress")) b->mode = B_PROG;
		else if (!strcmp(f[3], "confirm"))  b->mode = B_CONFIRM;
	}
	p->nbuttons++;
}

/* `help: <field> | English | 中文` — the line shown under the form while that
 * field has the cursor. The field has to be declared before it, the same order
 * `# group:` and `# action:` already ask for, so a header reads top to bottom.
 * An app-setup that predates this skips the key and shows no description,
 * which is exactly what a recipe without one shows. */
static void add_help(Pkg *p, const char *spec)
{
	char buf[512];
	copy_str(buf, sizeof buf, spec);
	char *f[3] = { buf, NULL, NULL };
	int nf = 1;
	for (char *q = buf; *q && nf < 3; q++)
		if (*q == '|') { *q = '\0'; f[nf++] = q + 1; }
	for (int i = 0; i < nf; i++) trim(f[i]);
	if (!*f[0] || nf < 2) return;
	for (int i = 0; i < p->nparams; i++)
		if (!strcmp(p->params[i].name, f[0])) {
			copy_str(p->params[i].help, sizeof p->params[i].help, f[1]);
			if (nf > 2) copy_str(p->params[i].help_zh, sizeof p->params[i].help_zh, f[2]);
			return;
		}
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
	else if (!strcmp(k, "require"))     copy_str(p->require, sizeof p->require, v);
	else if (!strcmp(k, "help"))        add_help(p, v);
	else if (!strcmp(k, "order"))       p->order = atoi(v);
	else if (!strcmp(k, "param"))       add_param(p, v);
	else if (!strcmp(k, "group"))       add_group(p, v);
	else if (!strcmp(k, "action"))      add_action(p, v);
	else if (!strcmp(k, "button"))      add_button(p, v);
	else if (!strcmp(k, "category")) {
		char tmp[192];
		copy_str(tmp, sizeof tmp, v);
		char *sv = NULL;
		char *tok = strtok_r(tmp, ", \t", &sv);
		while (tok && p->ncats < 6) {
			copy_str(p->cats[p->ncats], sizeof p->cats[0], tok);
			cat_add(tok);
			p->ncats++;
			tok = strtok_r(NULL, ", \t", &sv);
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
	p->cur_group = -1;
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
	/* The header stops at the first line of code; this does not. What a
	 * recipe can do is in its functions, and the one thing a card elsewhere
	 * needs to know — can this be backed up — is `do_backup`. Reading on for
	 * it costs one pass over a file already open and already in the page
	 * cache, and it cannot fall out of step with the recipe the way a header
	 * field would. Bounded, because a recipe is a recipe and not a tarball. */
	if (marked) {
		int bytes = 0;
		do {
			if (!strncmp(line, "do_backup(", 10)) { p->can_backup = 1; break; }
			bytes += (int)strlen(line);
		} while (bytes < 512 * 1024 && fgets(line, sizeof line, f));
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

/* Saved settings live beside the recipe they configure — /etc/app-setup/params
 * next to /etc/app-setup/nginx.sh — one file per package, `NAME=value` a line.
 * Written by the form, read here, and handed to every verb as environment. A
 * value the recipe no longer declares is dropped on the next save rather than
 * kept forever.
 *
 * These were under /var/lib for a while, which was defensible and unfindable:
 * somebody who had set a port in the form and wanted to see it again had no
 * reason to guess /var/lib, and every other answer to "where is the config"
 * on this machine is /etc. */
static void params_path(const Pkg *p, char *out, size_t cap)
{
	snprintf(out, cap, "%.400s/params/%.64s.conf", conf_dir(), p->id);
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
	snprintf(dir, sizeof dir, "%s/params", conf_dir());
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
	/* strtok_r, and not strtok, because scan_dir parses a recipe on the way
	 * past and every recipe with a `category:` line splits it — with strtok
	 * that inner call resets this loop's cursor and the walk ends after the
	 * first directory. Which meant the second entry was never read:
	 * no overriding a shipped recipe, and no keeping your own under /data.
	 * The one-directory case looked perfect, so it survived a long time. */
	char *save = NULL;
	for (char *tok = strtok_r(path, ":", &save); tok; tok = strtok_r(NULL, ":", &save))
		scan_dir(tok);
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
	/* the card screen: chips along the top, cards under them, and the two
	 * buttons that live on the root itself */
	P_CHIP, P_CHIPSEL,
	P_CARDB, P_CARDBSEL, P_CARDBHOT, P_BTNDIM,
	P_RBTN, P_CURSOR, P_CURSORHOT,
	/* Back is red wherever it appears — it is the one control that leaves,
	 * and it should not have to share the cursor's cyan to be found. It keeps
	 * its own cursor pair so the underline and the sweep still work on it. */
	P_BACK, P_BACKCUR, P_BACKHOT,
	/* the scroll indicator, in the two places anything scrolls: down the
	 * right of the card grid, which is on the root, and inside a window */
	P_SBTHUMB, P_SBTRACK, P_SBTHUMBW, P_SBTRACKW,
	/* the two things still drawn straight onto the root and needing a
	 * blue-backed colour: "nothing in this category", and "no recipes at all" */
	P_ABSENTB, P_WARNB,
	/* one cover colour per category — a solid background rather than coloured
	 * text, so the cover reads as a block of colour the way a thumbnail does —
	 * and the same background bold for the wordmark printed on it. Indexed by
	 * cover_of(); six is one more than the built-in categories, so a source
	 * that invents its own still gets a colour. */
	P_COV0, P_COV1, P_COV2, P_COV3, P_COV4, P_COV5, P_COV6,
	P_LOGO0, P_LOGO1, P_LOGO2, P_LOGO3, P_LOGO4, P_LOGO5, P_LOGO6,
	P_COUNT
};
#define N_COVERS 7

static const char *SGR[P_COUNT] = {
	"0;37;44",       /* ROOT      white on blue                       */
	"0;1;37;44",     /* ROOTTITLE bold white on blue                  */
	"0;1;36;44",     /* ROOTDIM   bold cyan on blue — the facts line  */
	"0;30;47",       /* WIN       black on light grey                 */
	"0;30;47",       /* BORDER    black on light grey                 */
	"0;1;34;47",     /* TITLE     bold blue on light grey             */
	"0;30;40",       /* SHADOW    black on black                      */
	"0;30;46",       /* SEL       black on cyan — the row you are on  */
	"0;34;46",       /* SELDIM    blue on cyan — its second line      */
	"0;34;47",       /* IDLE      blue on grey — selected, not focused*/
	"0;30;46",       /* BTN       black on cyan                       */
	"0;1;4;37;46",   /* BTNACT    the cursor, on a grey window        */
	"0;30;47",       /* ENTRY     black on grey                       */
	"0;4;30;46",     /* ENTRYACT  the cursor, in a form field         */
	"0;37;40",       /* HELP      white on black                      */
	"0;32;47",       /* RUN       green on grey                       */
	"0;33;47",       /* STOPPED   yellow on grey                      */
	"0;1;30;47",     /* ABSENT    grey on grey                        */
	"0;1;31;47",     /* ERR       bold red on grey                    */
	"0;31;47",       /* WARN      red on grey                         */
	"0;1;30;47",     /* DIM       grey on grey                        */
	"0;1;34;44",     /* BARFULL   blue on blue                        */
	"0;37;47",       /* BAREMPTY  grey on grey                        */
	"0;30;47",       /* CHIP      a category, on the grey bar         */
	"0;1;34;47",     /* CHIPSEL   the current category, on the grey bar */
	"0;30;47",       /* CARDB     card border, on the card's own grey */
	"0;30;46",       /* CARDBSEL  the whole frame lights up cyan      */
	"0;1;37;46",     /* CARDBHOT  …the band sweeping around it        */
	"0;1;30;47",     /* BTNDIM    a button that cannot be pressed yet */
	"0;37;44",       /* RBTN      Back / language, on the root        */
	"0;4;30;46",     /* CURSOR    the cursor is on this               */
	"0;1;4;37;46",   /* CURSORHOT …the band sweeping along it         */
	"0;1;37;41",     /* BACK      white on red — the way out          */
	"0;1;4;37;41",   /* BACKCUR   …with the cursor on it              */
	"0;1;4;33;41",   /* BACKHOT   …and the band sweeping along it     */
	"0;1;37;44",     /* SBTHUMB   where you are, on the root          */
	"0;34;44",       /* SBTRACK   how far there is to go              */
	"0;1;34;47",     /* SBTHUMBW  the same, inside a grey window      */
	"0;1;30;47",     /* SBTRACKW                                      */
	"0;1;30;44",     /* ABSENTB   grey on blue                        */
	"0;1;31;44",     /* WARNB     red on blue                         */
	"0;37;45",       /* COV0      suites      on magenta              */
	"0;30;46",       /* COV1      web servers on cyan                 */
	"0;30;42",       /* COV2      databases   on green                */
	"0;30;43",       /* COV3      backup      on yellow               */
	"0;37;44",       /* COV4      dev tools   on blue                 */
	"0;37;41",       /* COV5      system      on red                  */
	"0;37;100",      /* COV6      anything else on grey               */
	"0;1;37;45",     /* LOGO0..6  the wordmark, bold, same background */
	"0;1;37;46",
	"0;1;37;42",
	"0;1;30;43",
	"0;1;37;44",
	"0;1;37;41",
	"0;1;37;100",
};

typedef struct { char ch[5]; unsigned char attr; unsigned char cont; } Cell;

static Cell *g_grid = NULL;
/* What the terminal is currently showing, so a frame can send only the cells
 * that differ from it. Invalidated whenever the size changes or the terminal
 * has been written to behind our back. */
static Cell *g_shadow = NULL;
static int g_dirty_all = 1;
static int g_w = 80, g_h = 24, g_gw = 0, g_gh = 0;

static const char *BX_TL, *BX_TR, *BX_BL, *BX_BR, *BX_H, *BX_V;
static const char *BX_LT, *BX_RT;
/* The same box in double rule, which is what a card under the cursor is drawn
 * in. Colour says it too, but a monochrome terminal is still a terminal. */
static const char *B2_TL, *B2_TR, *B2_BL, *B2_BR, *B2_H, *B2_V;
static const char *B2_LT, *B2_RT;
static const char *MK_RUN, *MK_STOP, *MK_ABSENT, *MK_ERR, *MK_OK, *MK_DOT;
static const char *BAR_F, *BAR_E, *AR_L, *AR_R, *AR_UD;
static const char *TH_COVER, *CH_MORE;
static const char *GL_LIST, *GL_CARDS;

static void pick_glyphs(void)
{
	if (g_utf8) {
		BX_TL = "┌"; BX_TR = "┐"; BX_BL = "└"; BX_BR = "┘";
		BX_H  = "─"; BX_V  = "│"; BX_LT = "├"; BX_RT = "┤";
		B2_TL = "╔"; B2_TR = "╗"; B2_BL = "╚"; B2_BR = "╝";
		B2_H  = "═"; B2_V  = "║"; B2_LT = "╟"; B2_RT = "╢";
		MK_RUN = "●"; MK_STOP = "○"; MK_ABSENT = "·";
		MK_ERR = "✗"; MK_OK = "✓"; MK_DOT = "·";
		BAR_F = "█"; BAR_E = "░";
		AR_L = "◄"; AR_R = "►"; AR_UD = "↑↓";
		TH_COVER = "▒"; CH_MORE = "›";
		GL_LIST = "▤"; GL_CARDS = "⊞";
	} else {
		BX_TL = "+"; BX_TR = "+"; BX_BL = "+"; BX_BR = "+";
		BX_H = "-"; BX_V = "|"; BX_LT = "+"; BX_RT = "+";
		B2_TL = "+"; B2_TR = "+"; B2_BL = "+"; B2_BR = "+";
		B2_H = "="; B2_V = "|"; B2_LT = "+"; B2_RT = "+";
		MK_RUN = "*"; MK_STOP = "o"; MK_ABSENT = "-";
		MK_ERR = "x"; MK_OK = "+"; MK_DOT = "-";
		BAR_F = "#"; BAR_E = "-";
		AR_L = "<"; AR_R = ">"; AR_UD = "^v";
		TH_COVER = ":"; CH_MORE = ">";
		GL_LIST = "="; GL_CARDS = "#";
	}
}

static void grid_size(int w, int h)
{
	if (w < 20) w = 20;
	if (h < 8)  h = 8;
	if (w != g_gw || h != g_gh || !g_grid) {
		free(g_grid);
		free(g_shadow);
		g_grid = xmalloc((size_t)w * (size_t)h * sizeof(Cell));
		g_shadow = xmalloc((size_t)w * (size_t)h * sizeof(Cell));
		g_gw = w; g_gh = h;
		g_dirty_all = 1;         /* nothing on screen can be relied on now */
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

			/* A wide character occupies two cells: a lead holding the glyph
			 * and a continuation holding nothing. Anything drawn on top of
			 * one half has to repair the other, and both directions were
			 * wrong here — invisible until something with a dialog over it
			 * was rendered in Chinese, which is to say until a recipe put
			 * CJK at exactly the column an overlay started.
			 *
			 * Landing on a continuation: the lead to the left keeps its
			 * two-column glyph and no longer has a continuation, so the row
			 * emits one column too many and every rule to its right sits a
			 * column off. */
			if (cell->cont && col + used - 1 >= 0) {
				Cell *lead = &g_grid[row * g_gw + col + used - 1];
				lead->ch[0] = ' '; lead->ch[1] = '\0'; lead->cont = 0;
			}
			/* Landing on a lead with a narrow glyph: its continuation is
			 * orphaned, and the flush skips continuations — so that column
			 * is dropped and the row comes out one short. */
			if (cw == 1 && col + used + 1 < g_gw) {
				Cell *k = &g_grid[row * g_gw + col + used + 1];
				if (k->cont) { k->ch[0] = ' '; k->ch[1] = '\0'; k->cont = 0; }
			}

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

/* Repaint a run's colour without disturbing the characters already composed on
 * it — how the moving band of the cursor highlight is laid over a label that
 * has already been drawn and centred. */
static void gtint(int row, int col, int w, int attr)
{
	if (row < 0 || row >= g_gh || !row_visible(row)) return;
	for (int i = 0; i < w; i++) {
		int c = col + i;
		if (c < 0 || c >= g_gw) continue;
		g_grid[row * g_gw + c].attr = (unsigned char)attr;
	}
}

/* Only what changed, because the cursor highlight now moves and so the screen
 * redraws about eleven times a second whether or not anybody typed. A full
 * frame is six kilobytes; over ssh, at that rate, it would be a visible waste
 * of somebody's link for an animation. A frame in which only the highlight
 * moved is a few dozen bytes.
 *
 * Every cell is still emitted the first time and after a resize, background
 * included: a blue root that stopped at the last non-space column would show
 * the terminal's own background for the rest of the line, which is the one
 * thing that makes this look unlike nmtui. */
static void grid_flush(void)
{
	static char *out = NULL;
	static size_t cap = 0;
	size_t need = (size_t)g_gw * (size_t)g_gh * 16 + 64;
	if (need > cap) { free(out); out = xmalloc(need); cap = need; }

	size_t n = 0;
	int attr = -1;                    /* what the terminal is set to */
	int at_r = -1, at_c = -1;         /* and where its cursor is */

	for (int r = 0; r < g_gh; r++) {
		for (int c = 0; c < g_gw; c++) {
			Cell *cell = &g_grid[r * g_gw + c];
			if (cell->cont) continue;
			int wide = (c + 1 < g_gw && g_grid[r * g_gw + c + 1].cont);

			if (!g_dirty_all) {
				Cell *was = &g_shadow[r * g_gw + c];
				if (was->attr == cell->attr && was->cont == cell->cont &&
				    !memcmp(was->ch, cell->ch, sizeof cell->ch))
					continue;
			}

			if (r != at_r || c != at_c)
				n += (size_t)sprintf(out + n, "\x1b[%d;%dH", r + 1, c + 1);
			if (g_color && cell->attr != attr) {
				attr = cell->attr;
				n += (size_t)sprintf(out + n, "\x1b[%sm", SGR[attr]);
			}
			const char *ch = cell->ch[0] ? cell->ch : " ";
			size_t len = strlen(ch);
			memcpy(out + n, ch, len);
			n += len;

			at_r = r;
			at_c = c + (wide ? 2 : 1);
			/* Writing the last column leaves the cursor somewhere the
			 * terminal decides — wrapped or not — so stop trusting it. */
			if (at_c >= g_gw) at_c = -1;
		}
	}

	if (n) {
		if (g_color) n += (size_t)sprintf(out + n, "\x1b[0m");
		if (write(STDOUT_FILENO, out, n) < 0) { /* the terminal went away */ }
	}
	memcpy(g_shadow, g_grid, (size_t)g_gw * (size_t)g_gh * sizeof(Cell));
	g_dirty_all = 0;
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

/* Mouse. `g_mouse` is the wish, `g_mouse_on` is whether the terminal is
 * currently reporting; the last click lands in g_mx/g_my as a 0-based cell. */
static int g_mouse = 1, g_mouse_on = 0;
static int g_mx = 0, g_my = 0;

static void on_winch(int sig) { (void)sig; g_resized = 1; }

/* Escape sequences go out by length, never by a counted literal. The entry
 * sequence below used to be written as 17 bytes when it is 18, so the terminal
 * got `ESC [ 2` and the clear it ends with never happened — the sort of thing
 * that hides for a year behind a program that repaints every cell anyway. */
static void emit(const char *s)
{
	if (write(STDOUT_FILENO, s, strlen(s)) < 0) { /* the terminal went away */ }
}

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
	/* alt screen, cursor off, and click reporting in SGR coordinates.
	 *
	 * 1000 is presses and releases only — not 1002 or 1003, which also report
	 * motion. Nothing here needs to follow a drag, and the fewer events the
	 * terminal sends the less there is to go wrong. 1006 is what makes a click
	 * past column 223 arrive intact; without it the coordinates are a single
	 * byte and a wide terminal silently stops responding down its right-hand
	 * side.
	 *
	 * Turning this on costs the terminal's own drag-to-select. Shift-drag
	 * still selects in every terminal we know of, and `--no-mouse` is there
	 * for the one that does not — the keyboard path is unaffected either way,
	 * which is why this can be on by default. */
	emit("\x1b[?1049h\x1b[?25l\x1b[H\x1b[2J");
	g_dirty_all = 1;                   /* the screen just got wiped */
	if (g_mouse) {
		if (write(STDOUT_FILENO, "\x1b[?1000h\x1b[?1006h", 16) < 0) { }
		g_mouse_on = 1;
	}
}

static void term_cooked(void)
{
	if (!g_raw) return;
	if (g_mouse_on) {
		emit("\x1b[?1006l\x1b[?1000l");
		g_mouse_on = 0;
	}
	/* Reset, show the cursor, leave the alternate screen — and then clear,
	 * because the alternate screen is not universal. A terminal that ignored
	 * ?1049h drew the whole program on its main screen, and ignores ?1049l
	 * too, so quitting left the last frame sitting there with a shell prompt
	 * printed over the top of it. Clearing afterwards costs a screenful on the
	 * terminals where the alternate screen did work, and is the only thing
	 * that comes out clean on the ones where it did not. */
	emit("\x1b[0m\x1b[?25h\x1b[?1049l\x1b[H\x1b[2J");
	tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_saved_tio);
	g_raw = 0;
}

static void on_fatal(int sig) { term_cooked(); _exit(128 + sig); }

enum {
	K_NONE = 0, K_UP = 256, K_DOWN, K_LEFT, K_RIGHT, K_PGUP, K_PGDN,
	K_HOME, K_END, K_TAB, K_BTAB, K_ENTER, K_ESC, K_BACK, K_RESIZE, K_TIMEOUT,
	K_CLICK, K_WHEELUP, K_WHEELDN,
	/* Once the home screen filters on every printable key, the letters it
	 * used for language, view and refresh are no longer free. Function keys
	 * are what is left that a terminal sends and a person can find. */
	K_F1, K_F2, K_F3, K_F4, K_F5
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
			/* A mouse report is `<b;x;yM` for a press and `…m` for the
			 * release, so lowercase 'm' has to end the sequence too — but
			 * only for that shape, or an ordinary CSI would stop early. */
			if ((x >= 'A' && x <= 'Z') || x == '~') break;
			if (x == 'm' && seq[0] == '<') break;
		}
		seq[len] = '\0';
		if (len == 0) return K_ESC;

		if (seq[0] == '<') {
			int b = 0, x = 0, y = 0;
			if (sscanf((char *)seq + 1, "%d;%d;%d", &b, &x, &y) != 3) return K_NONE;
			if (seq[len - 1] != 'M') return K_NONE;   /* release: nothing to do */
			g_mx = x - 1; g_my = y - 1;               /* the wire is 1-based */
			if (b & 64) return (b & 1) ? K_WHEELDN : K_WHEELUP;
			if ((b & 3) == 0) return K_CLICK;         /* left button only */
			return K_NONE;
		}

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
			case 11: return K_F1;   case 12: return K_F2;
			case 13: return K_F3;   case 14: return K_F4;
			case 15: return K_F5;
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
		/* xterm's application-mode F1..F4, which is what most terminals
		 * still send for those four. */
		case 'P': return K_F1;   case 'Q': return K_F2;
		case 'R': return K_F3;   case 'S': return K_F4;
		}
	}
	return K_ESC;
}

/* Blocks for a key, but wakes on the animation tick so the cursor keeps
 * moving while nobody is typing. Callers treat K_TIMEOUT as "redraw". With
 * --no-blink there is no tick and this blocks the way it always did. */
static int read_key(void)
{
	int k = read_key_to(g_anim ? ANIM_MS : -1);
	if (k == K_TIMEOUT) g_phase++;
	return k;
}

/* ------------------------------------------------------------- the cursor --
 *
 * Where the cursor is, said four ways at once, because colour alone was not
 * enough. It used to be that the chip under the cursor and the merely-current
 * category were both cyan and differed only in whether the text on them was
 * black or blue — which on most terminals is barely a difference, and to
 * somebody colour-blind is none at all. You could not find your own cursor.
 *
 * So the thing under the cursor is filled, underlined, and has a band of
 * brighter colour sweeping along it about once a second; cards keep their
 * double rule as well. Motion is the channel that survives every kind of
 * colour blindness, and unlike colour every terminal renders it the same. The
 * double rule is the one that survives --ascii on a monochrome link.
 *
 * The band takes the same time to cross a narrow chip as a wide card, so the
 * screen pulses at one rate rather than at one rate per element size.
 *
 * `--no-blink` stops the motion for anybody who finds moving text worse than
 * the problem it solves. The fill and the underline stay.
 */
/* True for the two or three cells the bright band is passing over. It runs the
 * length of the element and then waits, so it reads as a sweep and not as a
 * flicker — nothing here ever blinks on and off. */
static int sweep_hot(int i, int w)
{
	if (!g_anim || w <= 0) return 0;
	int span = w + 8;                       /* the pause between passes */
	int ticks = SWEEP_MS / ANIM_MS;
	if (ticks < 1) ticks = 1;
	int head = (int)((g_phase % (unsigned)ticks) * (unsigned)span / (unsigned)ticks);
	int d = head - i;
	return d >= 0 && d < 3;
}

/* Lay the moving band over a run that has already been composed. */
static void cursor_sweep(int row, int col, int w, int base, int hot)
{
	for (int i = 0; i < w; i++)
		gtint(row, col + i, 1, sweep_hot(i, w) ? hot : base);
}

/* A scroll indicator: a track the height of the viewport with a thumb on it as
 * long a fraction of the track as the viewport is of the whole. A count says
 * where you are if you read it; a bar says it without being read, which is the
 * point of having both.
 *
 * Nothing is drawn when it all fits — a full-length thumb is a scrollbar
 * saying "there is nothing to scroll" in the most confusing way available. */
static void scrollbar(int row, int col, int h, int first, int shown, int total,
                      int thumb, int track)
{
	if (total <= shown || h < 2) return;
	int len = h * shown / total;
	if (len < 1) len = 1;
	if (len > h) len = h;
	int span = total - shown;
	int pos = span > 0 ? (h - len) * first / span : 0;
	if (pos < 0) pos = 0;
	if (pos > h - len) pos = h - len;
	for (int i = 0; i < h; i++) {
		int on = (i >= pos && i < pos + len);
		gput(row + i, col, on ? BAR_F : BAR_E, on ? thumb : track, 1);
	}
}

/* ------------------------------------------------------------ hit testing --
 *
 * Where the clickable things are. A screen registers a rectangle as it draws
 * it, which is the only arrangement that cannot drift: there is no second
 * description of the layout to keep in step, and a card that moved because the
 * window was resized takes its click target with it.
 *
 * Later entries win, so a button drawn on top of a panel is found first.
 */
enum { H_NONE = 0, H_BACK, H_LANG, H_CHIP, H_CARD, H_BTN, H_BODY, H_VIEW, H_FIND };

typedef struct { short r0, c0, r1, c1; short what, idx; } Hit;
static Hit g_hit[256];
static int g_nhit = 0;

static void hit_clear(void) { g_nhit = 0; }

static void hit_add(int what, int idx, int row, int col, int h, int w)
{
	if (g_nhit >= (int)(sizeof g_hit / sizeof g_hit[0]) || w <= 0 || h <= 0) return;
	Hit *z = &g_hit[g_nhit++];
	z->r0 = (short)row; z->c0 = (short)col;
	z->r1 = (short)(row + h - 1); z->c1 = (short)(col + w - 1);
	z->what = (short)what; z->idx = (short)idx;
}

static int hit_test(int row, int col, int *idx)
{
	for (int i = g_nhit - 1; i >= 0; i--) {
		Hit *z = &g_hit[i];
		if (row >= z->r0 && row <= z->r1 && col >= z->c0 && col <= z->c1) {
			if (idx) *idx = z->idx;
			return z->what;
		}
	}
	if (idx) *idx = 0;
	return H_NONE;
}

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

static void btn_draw(int row, int col, const char *label, int focused, int idx)
{
	int a = focused ? P_BTNACT : P_BTN;
	char t[128];
	snprintf(t, sizeof t, "<%s>", label);
	gput(row, col, t, a, btn_width(label));
	hit_add(H_BTN, idx, row, col, 1, btn_width(label));
	if (focused) cursor_sweep(row, col, btn_width(label), P_BTNACT, P_CURSORHOT);
}

static void help_line(const char *text)
{
	gfill(g_h - 1, 0, g_w, " ", P_HELP);
	gput(g_h - 1, 1, text, P_HELP, g_w - 2);
}

/* The help line names keys with arrow glyphs, which is the clearest way to say
 * "press this" right up until the terminal cannot draw them — and then it is
 * three bytes of mojibake in the one line whose entire job is telling somebody
 * which key to press. Spelling them out is done here rather than in a second
 * set of strings so that a translator only ever writes the line once. */
static void help_line_l(const L *l)
{
	if (g_utf8) { help_line(S(*l)); return; }

	static const struct { const char *u, *a; } sub[] = {
		{"↑↓←→", "arrows"}, {"↑↓", "up/down"}, {"←→", "left/right"},
		{"↑", "up"}, {"↓", "down"}, {"←", "left"}, {"→", "right"},
		{"…", "..."},
	};
	char out[512];
	size_t n = 0;
	for (const char *s = S(*l); *s && n + 12 < sizeof out; ) {
		size_t k = 0;
		for (; k < sizeof sub / sizeof sub[0]; k++) {
			size_t ul = strlen(sub[k].u);
			if (!strncmp(s, sub[k].u, ul)) {
				n += (size_t)snprintf(out + n, sizeof out - n, "%s", sub[k].a);
				s += ul;
				break;
			}
		}
		if (k == sizeof sub / sizeof sub[0]) out[n++] = *s++;
	}
	out[n] = '\0';
	help_line(out);
}

/* The blue root, with the program name and what this machine is. Drawn under
 * every screen, so a dialog always sits on the same background.
 *
 * The home screen also asks for the two buttons that live up here — the way
 * out and the way to the other language. They are set through globals rather
 * than an argument because every modal screen in this file calls draw_root()
 * and none of them wants them: the modals carry their own Back, on their own
 * top row, so that Back is in the top right corner of whatever is in front of
 * you and never somewhere behind it.
 */
static int g_showtop = 0;      /* draw the top-right buttons at all */
static int g_topsel  = -1;     /* which one has the cursor: 0 language, 1 back */

/* Which program's name goes on the blue bar. app-setup's own by default;
 * `helppage` points these at its own pair before it draws anything. */
static const L *g_rootname = &T_TITLE;
static const L *g_rootsub  = &T_SUBTITLE;

static void draw_root(void)
{
	grid_clear(P_ROOT);

	/* Right to left, because the right hand end is the part with a fixed
	 * claim on the row: the buttons are always the full width of their
	 * labels, and it is the title that gives way on a narrow terminal. */
	int rightedge = g_w - 1;
	if (g_showtop) {
		/* No language button on a terminal that cannot draw the language it
		 * would switch to — --ascii already pins this to English, and a
		 * button labelled in mojibake is worse than no button. */
		int offer_lang = g_utf8;
		char b[64];
		snprintf(b, sizeof b, " %s ", S(T_BACK));
		int bw = u8width(b);
		if (bw < g_w / 3) {
			rightedge -= bw;
			gput(0, rightedge, b, g_topsel == 1 ? P_CURSOR : P_RBTN, bw);
			if (g_topsel == 1) cursor_sweep(0, rightedge, bw, P_CURSOR, P_CURSORHOT);
			hit_add(H_BACK, 0, 0, rightedge, 1, bw);
		}
		snprintf(b, sizeof b, " %s ", lang_other());
		bw = u8width(b);
		if (offer_lang && bw < g_w / 3) {
			rightedge -= bw + 1;
			gput(0, rightedge, b, g_topsel == 0 ? P_CURSOR : P_RBTN, bw);
			if (g_topsel == 0) cursor_sweep(0, rightedge, bw, P_CURSOR, P_CURSORHOT);
			hit_add(H_LANG, 0, 0, rightedge, 1, bw);
		}
		rightedge -= 2;
	}

	char left[256];
	snprintf(left, sizeof left, "%s %s  %s", S(*g_rootname), APP_VERSION, S(*g_rootsub));
	gput(0, 1, left, P_ROOTTITLE, rightedge - 2);

	char right[128];
	const char *user = geteuid() == 0 ? "root" : (getenv("USER") ? getenv("USER") : "user");
	char host[64] = "";
	if (gethostname(host, sizeof host - 1) != 0) copy_str(host, sizeof host, "container");
	snprintf(right, sizeof right, "%s@%s", user, host);
	int rw = u8width(right);
	if (rw < rightedge - u8width(left) - 3) gput(0, rightedge - rw, right, P_ROOTDIM, rw);

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



/* The state word's colour, on the light grey every window and card is made
 * of. Green up, yellow down, grey absent, red broken. */
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

	/* Wrapped, not truncated. Every row used to be cut to the pane's width
	 * with an ellipsis and there is no sideways scroll, so anything past the
	 * edge was simply gone — in a window whose whole job is showing somebody
	 * text they cannot otherwise see. Rewrapped only when the width changes,
	 * because this also holds sixty kilobytes of log at eleven frames a
	 * second. */
	char **disp = NULL;
	int nd = 0, wrapped_at = -1;

	int scroll = 0;
	for (;;) {
		term_measure();
		grid_size(g_w, g_h);
		draw_root();
		hit_clear();

		/* Sized to what it holds. It used to be g_h - 4 tall and g_w - 8 wide
		 * whatever was in it, so eight lines about a running service got a
		 * box the height of the terminal with a field of grey under them. */
		int longest = 0;
		for (int i = 0; i < n; i++) {
			int lw = u8width(raw[i]);
			if (lw > longest) longest = lw;
		}
		int w = longest + 6;
		if (w > 96) w = 96;
		if (w < 34) w = 34;
		if (w > g_w - 2) w = g_w - 2;
		int inner = w - 4;

		/* Wrap before choosing the height, or a paragraph that needs three
		 * rows gets a box sized for the one line it was written as. */
		if (inner != wrapped_at) {
			static char wrap[64][512];
			for (int i = 0; i < nd; i++) free(disp[i]);
			free(disp);
			disp = NULL; nd = 0;
			int cap_d = 0;
			for (int i = 0; i < n; i++) {
				int k = u8wrap(raw[i], inner, wrap, 64);
				if (k < 1) k = 1;               /* a blank line is still a line */
				for (int j = 0; j < k; j++) {
					if (nd == cap_d) {
						cap_d = cap_d ? cap_d * 2 : 64;
						disp = realloc(disp, (size_t)cap_d * sizeof(char *));
						if (!disp) { nd = 0; break; }
					}
					const char *src = (k == 1 && !*raw[i]) ? "" : wrap[j];
					size_t len = strlen(src);
					disp[nd] = xmalloc(len + 1);
					memcpy(disp[nd], src, len + 1);
					nd++;
				}
			}
			wrapped_at = inner;
		}

		int h = nd + 3;
		if (h > g_h - 4) h = g_h - 4;
		if (h < 7) h = 7;
		if (h > g_h - 2) h = g_h - 2;
		int row = (g_h - h) / 2 - 1, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, title);
		int body = h - 3;

		if (scroll > nd - 1) scroll = nd - 1;
		if (scroll < 0) scroll = 0;
		for (int i = 0; i < body && scroll + i < nd; i++)
			gput(row + 1 + i, col + 2, disp[scroll + i], P_WIN, inner);
		scrollbar(row + 1, col + w - 2, body, scroll, body, nd,
		          P_SBTHUMBW, P_SBTRACKW);
		if (nd > body) {
			char sb[32];
			snprintf(sb, sizeof sb, " %d/%d ", scroll + 1, nd);
			int sw = u8width(sb);
			gput(row + h - 1, col + w - 3 - sw, sb, P_TITLE, sw);
		}
		btn_draw(row + h - 1, col + 2, S(T_CLOSE), 1, 0);
		help_line_l(&T_HELPPAGE);
		grid_flush();

		int k = read_key();
		if (k == K_CLICK) { if (hit_test(g_my, g_mx, NULL) == H_BTN) break; continue; }
		if (k == K_WHEELUP) { scroll--; continue; }
		if (k == K_WHEELDN) { scroll++; continue; }
		if (k == K_ENTER || k == K_ESC || k == ' ' || k == 'q' || k == K_LEFT) break;
		else if (k == K_DOWN) scroll++;
		else if (k == K_UP)   scroll--;
		else if (k == K_PGDN || k == K_RIGHT) scroll += body;
		else if (k == K_PGUP) scroll -= body;
		else if (k == K_HOME) scroll = 0;
		else if (k == K_END)  scroll = nd - 1;
	}
	for (int i = 0; i < nd; i++) free(disp[i]);
	free(disp);
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
		hit_clear();

		int w = u8width(msg) + 8;
		if (w > g_w - 6) w = g_w - 6;
		if (w > 76) w = 76;
		if (w < 34) w = 34;
		int inner = w - 4;
		char lines[6][512];
		int nl = u8wrap(msg, inner, lines, 6);
		int h = nl + 5;
		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, title);
		for (int i = 0; i < nl; i++) gput(row + 1 + i, col + 2, lines[i], P_WIN, inner);

		int bw = btn_width(S(T_OK)) + 2 + btn_width(S(T_CANCEL));
		int bx = col + (w - bw) / 2;
		btn_draw(row + h - 2, bx, S(T_OK), focus == 0, 0);
		btn_draw(row + h - 2, bx + btn_width(S(T_OK)) + 2, S(T_CANCEL), focus == 1, 1);
		help_line(S(T_CONFIRM));
		grid_flush();

		int k = read_key();
		if (k == K_CLICK) {
			int idx = 0;
			if (hit_test(g_my, g_mx, &idx) == H_BTN) return idx == 0;
			continue;
		}
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
		hit_clear();
		int w = u8width(msg) + 8;
		if (w > g_w - 6) w = g_w - 6;
		if (w > 76) w = 76;
		if (w < 30) w = 30;
		int inner = w - 4;
		char lines[8][512];
		int nl = u8wrap(msg, inner, lines, 8);
		int h = nl + 5;
		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, title);
		for (int i = 0; i < nl; i++) gput(row + 1 + i, col + 2, lines[i], P_WIN, inner);
		int bx = col + (w - btn_width(S(T_OK))) / 2;
		btn_draw(row + h - 2, bx, S(T_OK), 1, 0);
		help_line_l(&T_HELPDONE);
		grid_flush();
		int k = read_key();
		if (k == K_CLICK) { if (hit_test(g_my, g_mx, NULL) == H_BTN) return; continue; }
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

/* The last thing the recipe said before it stopped. common.sh's `err` and
 * `die` both print "  x  <sentence>", and runner_line_in has already stripped
 * the escapes and the indent, so the stored line begins with the x. Searching
 * backwards finds the `die` rather than an earlier `err` the script recovered
 * from.
 *
 * NULL when nothing in the ring has that shape — a recipe that fell over
 * inside apt says nothing in it, and the plain exit-code dialog is then the
 * honest thing to show. */
static const char *runner_last_error(const Runner *r)
{
	for (int i = r->nlog - 1; i >= 0; i--) {
		const char *l = runner_line(r, i);
		while (*l == ' ' || *l == '\t') l++;
		if (*l != 'x' || (l[1] != ' ' && l[1] != '\t')) continue;
		l++;
		while (*l == ' ' || *l == '\t') l++;
		if (*l) return l;
	}
	return NULL;
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
		/* Newlines survive. They did not, and the two callers that hand this
		 * whole files rather than single lines came out as one enormous line:
		 * `detail=demo-web 1.4.2, port 9090enabled=1` is two fields of a
		 * recipe's status output with the newline between them eaten. */
		if ((unsigned char)*p < 32 && *p != '\t' && *p != '\n') { p++; continue; }
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

/* Drawing the running screen, split from the loop that feeds it, so that
 * `screenshot --screen progress` can hand it a Runner filled in by hand rather
 * than by a child process. The alternative is a second drawing of this screen
 * living in the screenshot path, which is what the previous version had: a
 * mocked-up frame that proves nothing about the real one.
 *
 * `rows` and `first` come back out because the key handling needs to know how
 * tall the log pane turned out and where it is scrolled to, and only the code
 * that laid it out knows. */
static void progress_draw(Runner *r, const char *title, int log_scroll,
                          int esc_armed, int *rows_out, int *first_out)
{
	grid_size(g_w, g_h);
	g_showtop = 0;
	draw_root();
	hit_clear();

	int w = g_w - 8; if (w > 100) w = 100; if (w < 36) w = g_w - 2;
	int h = g_h - 4; if (h > 26) h = 26; if (h < 12) h = g_h - 2;
	int row = (g_h - h) / 2 - 1, col = (g_w - w) / 2;
	if (row < 1) row = 1;
	if (col < 0) col = 0;
	int inner = w - 4, x = col + 2;
	win_box(row, col, w, h, title);

	int y = row + 1;
	int pct = runner_percent(r);

	char head[128];
	if (r->done)          snprintf(head, sizeof head, "%s", r->rc == 0 ? S(T_DONE) : S(T_BROKEN));
	else if (r->total > 0) snprintf(head, sizeof head, S(T_STEPOF),
	                                r->step > r->total ? r->total : r->step, r->total);
	else                   snprintf(head, sizeof head, "%s", S(T_WORKING));

	/* Back sits in the corner it occupies everywhere else, and on this screen
	 * it is always grey: while the child is alive there is no leaving, and the
	 * moment it exits this screen is replaced by the dialog that says what
	 * happened. So it is here to say "there is a way out, not yet" — letting
	 * somebody leave half an install behind a screen that said Back is how a
	 * container comes to be believed to hold a package it does not. */
	char backl[64];
	snprintf(backl, sizeof backl, " %s ", S(T_BACK));
	int backw = u8width(backl);
	gput(y, x + inner - backw, backl, P_DIM, backw);

	gput(y, x, head, r->done && r->rc ? P_ERR : P_DIM, inner - backw - 2);
	y++;

	char pctstr[16];
	snprintf(pctstr, sizeof pctstr, " %3d%%", pct);
	draw_bar(y, x, inner - 5, pct);
	gput(y, x + inner - 5, pctstr, P_WIN, 5);
	y += 2;

	char phase[600];
	u8ellipsis(phase, sizeof phase, r->done
	           ? (r->rc == 0 ? S(T_DONE) : r->phase)
	           : r->phase, inner);
	gput(y, x, phase, r->done && r->rc ? P_ERR : P_WIN, inner);
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
	int first = log_scroll >= 0 ? log_scroll : (r->nlog > rows ? r->nlog - rows : 0);
	if (first > r->nlog - rows) first = r->nlog - rows;
	if (first < 0) first = 0;
	for (int i = 0; i < rows && first + i < r->nlog; i++) {
		char cut[600];
		u8ellipsis(cut, sizeof cut, runner_line(r, first + i), inner - 4);
		gput(y + 1 + i, x + 2, cut, P_DIM, inner - 4);
	}
	hit_add(H_BODY, 0, y + 1, x + 1, rows, inner - 2);

	if (r->done)
		help_line_l(&T_HELPDONE);
	else
		help_line(esc_armed
		          ? (g_zh ? "再按一次 Esc 强行中止" : "press Esc again to force a stop")
		          : S(T_HELPRUN));

	if (rows_out)  *rows_out = rows;
	if (first_out) *first_out = first;
}

/* title_override: NULL for every built-in verb (Install/Start/Stop/…) —
 * verb_title already knows what to call those. A `# action:` button
 * (docs/app-setup.edit.md §3.3) passes its own label here instead, because
 * verb_title falls back to "Installing %s" for any verb it does not
 * recognise by name, and growing that switch statement for every future
 * action verb is the wrong fix when the button already carries a label. */
static void screen_progress(Pkg *p, const char *verb, const char *title_override)
{
	Runner r;
	char title[256];
	if (title_override && *title_override) copy_str(title, sizeof title, title_override);
	else verb_title(title, sizeof title, verb, p);

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
		int rows = 0, first = 0;
		progress_draw(&r, title, log_scroll, esc_armed, &rows, &first);
		grid_flush();

		/* The moment the child has exited, stop and say so. Leaving somebody
		 * on a finished progress screen to work out for themselves that it
		 * ended, and which of the buttons ends it, is the state this screen
		 * used to sit in. */
		if (r.done) break;

		/* While it runs the screen has to keep moving, so the wait is short
		 * and a timeout is just another redraw. */
		int k = read_key_to(120);
		if (k == K_TIMEOUT || k == K_RESIZE || k == K_NONE) {
			if (k == K_TIMEOUT) g_phase++;
			else esc_armed = 0;
			continue;
		}

		/* Touching the log stops it following the tail, so what has already
		 * gone by can be read back; reaching the bottom picks the tail up. */
		if (k == K_WHEELUP) {
			log_scroll = first - 1; if (log_scroll < 0) log_scroll = 0;
			esc_armed = 0; continue;
		}
		if (k == K_WHEELDN) {
			log_scroll = first + 1; if (log_scroll > r.nlog - rows) log_scroll = -1;
			esc_armed = 0; continue;
		}
		if (k == K_CLICK) {
			esc_armed = 0;
			if (hit_test(g_my, g_mx, NULL) == H_BODY && log_scroll < 0)
				log_scroll = first;
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

	{
		char msg[900], logpath[600];
		snprintf(logpath, sizeof logpath, "%s/%s.log", log_dir(), p->id);
		if (r.rc != 0) {
			const char *why = runner_last_error(&r);
			if (why) {
				/* Trimmed to what the box can hold without pushing the log
				 * path off the bottom — message() wraps to eight lines. */
				char cut[400];
				u8ellipsis(cut, sizeof cut, why, 200);
				snprintf(msg, sizeof msg, S(T_FAILEDWHY), pkg_name(p), cut, r.rc, logpath);
			} else {
				snprintf(msg, sizeof msg, S(T_FAILED), pkg_name(p), r.rc, logpath);
			}
			message(S(T_BROKEN), msg);
		} else if (title_override && *title_override && r.nlog) {
			/* A `# action:` button is pressed to be *told* something —
			 * Test the origin, Refresh, Back up now. Its answer is what it
			 * printed, and this screen breaks the instant the child exits, so
			 * on a verb that takes half a second the output goes past in a
			 * flash and a box says it is in a file. That is the whole button
			 * wasted: somebody pressed "Test the origin" and got a path to go
			 * and read instead of an answer. Page what it said, the way
			 * `# button:` verbs have always been paged.
			 *
			 * Install and the service verbs keep the one-line box: their answer
			 * really is "it finished", and their output is five hundred lines
			 * of a package manager. */
			char out[16384];
			size_t n = 0, room = sizeof out - 200;
			int i = r.nlog;
			/* Backwards for the first line to keep, so a long scan is trimmed
			 * at the front rather than at the verdict. */
			while (i > 0) {
				size_t len = strlen(runner_line(&r, i - 1)) + 1;
				if (n + len > room) break;
				n += len; i--;
			}
			n = 0;
			for (; i < r.nlog; i++)
				n += (size_t)snprintf(out + n, sizeof out - n, "%s\n",
				                      runner_line(&r, i));
			snprintf(out + n, sizeof out - n, "\n%s\n", logpath);
			pager(title, out);
		} else {
			snprintf(msg, sizeof msg, S(T_FINISHED), title, logpath);
			message(S(T_DONE), msg);
		}
	}
	probe_pkg(p);
}

/* ----------------------------------------------------------- the settings --
 *
 * nmtui's form: a column of labels, a column of fields, OK and Cancel at the
 * bottom. Text fields take typing; a bool is a checkbox that Space flips; a
 * list is a chooser that Left and Right walk (or, past ENUM_POPUP_MIN
 * choices, Enter opens a popup instead of walking eight of them one at a
 * time — docs/app-setup.edit.md §3.2).
 *
 * Three kinds of row, not one field per row: a field itself (ROW_PARAM), a
 * `# group:` header that folds a run of fields together (ROW_GROUP), and a
 * `# action:` button belonging to the field above it (ROW_ACTION) —
 * docs/app-setup.edit.md §3.1/§3.3. build_param_rows lays that list out
 * fresh every frame, cheap enough that a fold toggle or a reloaded recipe
 * just falls out of calling it again rather than needing its own patch-up
 * path.
 */
enum { ROW_PARAM, ROW_GROUP, ROW_ACTION };
typedef struct { int kind; int idx; } VisRow;   /* idx: a param index, or (for ROW_GROUP) a group index */

/* At most one group header before a field and one action row after it, for
 * every field — generous headroom over what MAX_PARAMS/MAX_GROUPS actually
 * allow, not a real bound anything gets close to. */
#define MAX_VISROWS (MAX_PARAMS * 2 + MAX_GROUPS)

static int build_param_rows(const Pkg *p, VisRow *rows)
{
	int n = 0, lastgroup = -2;   /* -2: "no group seen yet", distinct from -1 "ungrouped" */
	for (int i = 0; i < p->nparams && n < MAX_VISROWS - 2; i++) {
		const Param *pm = &p->params[i];
		if (pm->group != lastgroup && pm->group >= 0)
			rows[n++] = (VisRow){ROW_GROUP, pm->group};
		lastgroup = pm->group;
		if (pm->group >= 0 && p->groups[pm->group].folded) continue;
		rows[n++] = (VisRow){ROW_PARAM, i};
		if (pm->action_verb[0] && n < MAX_VISROWS) rows[n++] = (VisRow){ROW_ACTION, i};
	}
	return n;
}

/* Past this many choices, cycling ◀/▶ one at a time is slower than picking
 * — xray.sh's eight-site camouflage field is the case this exists for. At
 * or below it, inline ◀ value ▶ stays exactly as it always has; apply_to's
 * three choices are faster to cycle than to pop a window over. */
#define ENUM_POPUP_MIN 5

/* A small selectable list, opened by Enter on a chooser field with more
 * choices than are comfortable to walk with ◀/▶ — nmtui's own popup for
 * exactly this. Same shape as message()/pager(): draw_root() first, this
 * dialog's own box on the plain background, looped until Enter commits or
 * Esc leaves the field unchanged. Returns 1 if the value changed. */
static int screen_enum_popup(Param *pm)
{
	int sel = 0;
	for (int i = 0; i < pm->nchoices; i++) if (!strcmp(pm->choices[i], pm->value)) sel = i;
	int start = sel;

	for (;;) {
		term_measure();
		grid_size(g_w, g_h);
		draw_root();
		hit_clear();

		int cw = 4;
		for (int i = 0; i < pm->nchoices; i++) {
			int lw = u8width(pm->choices[i]);
			if (lw > cw) cw = lw;
		}
		int w = cw + 6;
		if (w > g_w - 4) w = g_w - 4;
		if (w < 20) w = 20;
		int h = pm->nchoices + 2;
		if (h > g_h - 4) h = g_h - 4;
		if (h < 3) h = 3;
		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, param_label(pm));

		for (int i = 0; i < pm->nchoices && i < h - 2; i++) {
			int a = (i == sel) ? P_ENTRYACT : P_WIN;
			gfill(row + 1 + i, col + 1, w - 2, " ", a);
			gput(row + 1 + i, col + 2, pm->choices[i], a, w - 4);
			hit_add(H_BODY, i, row + 1 + i, col + 1, 1, w - 2);
		}
		help_line_l(&T_HELPFORM);
		grid_flush();

		int k = read_key();
		if (k == K_CLICK) {
			int idx = 0;
			if (hit_test(g_my, g_mx, &idx) == H_BODY) { sel = idx; k = K_ENTER; }
			else continue;
		}
		if (k == K_UP)   { sel = (sel - 1 + pm->nchoices) % pm->nchoices; continue; }
		if (k == K_DOWN) { sel = (sel + 1) % pm->nchoices; continue; }
		if (k == K_ESC)  return 0;
		if (k == K_ENTER) {
			copy_str(pm->value, sizeof pm->value, pm->choices[sel]);
			return sel != start;
		}
	}
}


/* ---- a field whose choices this machine works out ------------------------ */

#define LIST_MAX 32

/* The options for a `@…` field. `owner` is the package the field belongs to
 * and is left out of its own list: backup.sh defines do_backup because it is
 * the thing that runs everybody else's, and offering to back up the backup
 * card is nonsense.
 *
 * Installed first. What somebody wants to back up is nearly always something
 * they have, and a list that opens on ten things they do not is a list they
 * have to read past to reach the one they came for. The ones they do not have
 * are still offered, and still say so, because setting a machine up before
 * filling it is a normal order to do things in.
 */
static int list_options(const Pkg *owner, const char *source, const Pkg *opts[], int max)
{
	int n = 0;
	if (strcmp(source, "backup") != 0) return 0;
	for (int pass = 0; pass < 2; pass++)
		for (int i = 0; i < g_npkg && n < max; i++) {
			const Pkg *q = &g_pkg[i];
			if (!q->can_backup || q == owner) continue;
			int have = (q->status != ST_ABSENT && q->status != ST_UNKNOWN);
			if (have != (pass == 0)) continue;
			opts[n++] = q;
		}
	return n;
}

/* A PT_LIST value is the string the recipe already takes on its command line:
 * `mysql,wordpress`. These two are what keep that string and the ticks in the
 * popup saying the same thing. */
static int list_has(const char *csv, const char *id)
{
	size_t n = strlen(id);
	for (const char *p = csv; *p; ) {
		while (*p == ' ' || *p == ',') p++;
		if (!*p) break;
		const char *e = p;
		while (*e && *e != ',') e++;
		size_t len = (size_t)(e - p);
		while (len && p[len - 1] == ' ') len--;
		if (len == n && !strncmp(p, id, n)) return 1;
		p = e;
	}
	return 0;
}

static void list_toggle(char *csv, size_t cap, const char *id)
{
	if (!list_has(csv, id)) {
		size_t n = strlen(csv);
		if (n) snprintf(csv + n, cap - n, ",%s", id);
		else   copy_str(csv, cap, id);
		return;
	}
	/* Rebuilt rather than spliced: the string is short, and every attempt to
	 * cut one item out of a comma list in place gets the commas wrong at one
	 * end or the other. */
	char out[256] = "";
	size_t n = strlen(id);
	for (const char *p = csv; *p; ) {
		while (*p == ' ' || *p == ',') p++;
		if (!*p) break;
		const char *e = p;
		while (*e && *e != ',') e++;
		size_t len = (size_t)(e - p);
		while (len && p[len - 1] == ' ') len--;
		if (len && !(len == n && !strncmp(p, id, n))) {
			size_t have = strlen(out);
			snprintf(out + have, sizeof out - have, "%s%.*s",
			         have ? "," : "", (int)len, p);
		}
		p = e;
	}
	copy_str(csv, cap, out);
}

/* The same shape as screen_enum_popup and a different thing: this one is a
 * set, not a choice. Space ticks, Enter commits the lot, Esc puts back what
 * was there. Built from list_options every time it opens, so a database
 * installed five minutes ago is in the list with nothing edited anywhere. */
/* One frame of it, so `app-setup screenshot --screen pick` can take this
 * window the same way it takes every other one. */
static void list_popup_draw(const Param *pm, const Pkg *opts[], int n, int sel)
{
	{
		int idw = 4, stw = 0;
		for (int i = 0; i < n; i++) {
			int w = u8width(opts[i]->id);
			if (w > idw) idw = w;
			w = u8width(S(*status_label(opts[i])));
			if (w > stw) stw = w;
		}
		int w = 4 + 4 + idw + 3 + stw + 2;
		if (w > g_w - 4) w = g_w - 4;
		if (w < 24) w = 24;
		int h = n + 2;
		if (h > g_h - 4) h = g_h - 4;
		if (h < 3) h = 3;
		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, param_label(pm));

		for (int i = 0; i < n && i < h - 2; i++) {
			int y = row + 1 + i;
			int a = (i == sel) ? P_ENTRYACT : P_WIN;
			gfill(y, col + 1, w - 2, " ", a);
			char box[128];
			snprintf(box, sizeof box, "[%s] %s",
			         list_has(pm->value, opts[i]->id) ? MK_OK : " ", opts[i]->id);
			gput(y, col + 2, box, a, w - 4);
			/* The state word, in the colour the cards already use for it, and
			 * only when there is room for it to be read rather than clipped. */
			const char *st = S(*status_label(opts[i]));
			int sw = u8width(st);
			int sx = col + w - 2 - sw;
			if (sx > col + 3 + u8width(box))
				gput(y, sx, st, i == sel ? a : status_attr(opts[i]), sw);
			hit_add(H_BODY, i, y, col + 1, 1, w - 2);
		}
		help_line_l(&T_HELPPICK);
	}
}

static int screen_list_popup(const Pkg *owner, Param *pm)
{
	const Pkg *opts[LIST_MAX];
	int n = list_options(owner, pm->source, opts, LIST_MAX);
	if (n == 0) { message(param_label(pm), S(T_PICKNONE)); return 0; }

	char start[sizeof pm->value];
	copy_str(start, sizeof start, pm->value);
	int sel = 0;

	for (;;) {
		term_measure();
		grid_size(g_w, g_h);
		hit_clear();
		draw_root();
		list_popup_draw(pm, opts, n, sel);
		grid_flush();

		int k = read_key();
		if (k == K_NONE || k == K_RESIZE || k == K_TIMEOUT) continue;
		/* A click is the tick. Moving the cursor there first would be a second
		 * gesture for something already pointed at, which is the same call the
		 * cards on the home screen make. */
		if (k == K_CLICK) {
			int idx = 0;
			if (hit_test(g_my, g_mx, &idx) == H_BODY && idx >= 0 && idx < n) {
				sel = idx;
				list_toggle(pm->value, sizeof pm->value, opts[sel]->id);
			}
			continue;
		}
		if (k == K_WHEELUP) { if (sel > 0) sel--; continue; }
		if (k == K_WHEELDN) { if (sel < n - 1) sel++; continue; }
		if (k == K_UP)   { sel = (sel - 1 + n) % n; continue; }
		if (k == K_DOWN) { sel = (sel + 1) % n; continue; }
		if (k == ' ')    { list_toggle(pm->value, sizeof pm->value, opts[sel]->id); continue; }
		if (k == K_ESC)  { copy_str(pm->value, sizeof pm->value, start); return 0; }
		if (k == K_ENTER) return strcmp(start, pm->value) != 0;
	}
}

/* A field being edited is as tall as its value needs, up to this. Nine lines
 * of a thirty-column field is the whole 256 bytes a value can hold, so on any
 * terminal wide enough for the ordinary form nothing is ever hidden while
 * somebody is typing into it. */
#define PARAM_MAXH 9

/* One line per row, except the text field that has the cursor: that one is as
 * tall as its value. Everything else on this screen is one line and stays one
 * line — a chooser, a checkbox and a group header have nothing to expand. */
static int param_rowh(const Pkg *p, const VisRow *vr, int focused, int fieldw)
{
	if (!focused || vr->kind != ROW_PARAM) return 1;
	const Param *pm = &p->params[vr->idx];
	if (pm->type != PT_TEXT && pm->type != PT_NUMBER) return 1;
	int need = u8width(pm->value) + 1;        /* +1 so the caret has a cell */
	if (need <= fieldw) return 1;
	int n = (need + fieldw - 1) / fieldw;
	return n > PARAM_MAXH ? PARAM_MAXH : n;
}

/* The value, wrapped down the field column. Hard-wrapped at the column rather
 * than on spaces: these values are comma lists and paths, and a wrap that
 * moved a comma would move where somebody thinks their cursor is.
 *
 * `caret` is a byte offset into `val`. Its cell is drawn in the button colour
 * rather than replaced by an underscore — an underscore hides the character it
 * stands on, and that character is the one thing somebody editing is looking
 * at. Only at the very end of the value, where there is no character to hide,
 * is the caret an underscore.
 *
 * When the value still needs more lines than it has been given, the window
 * follows the caret rather than the start of the string. */
static void field_draw(int y, int fx, int fieldw, int rh, int attr,
                       const char *val, int caret, int show_caret)
{
	int line = 0, used = 0, cline = 0, ccol = 0;
	const char *cch = NULL;
	size_t cchlen = 0;

	for (const char *q = val; ; ) {
		int at_caret = ((int)(q - val) == caret);
		if (at_caret) { cline = line; ccol = used; cch = NULL; cchlen = 0; }
		if (!*q) break;
		unsigned int c;
		const char *nx = u8next(q, &c);
		int cw = cp_width(c);
		if (used + cw > fieldw) {
			line++; used = 0;
			if (at_caret) { cline = line; ccol = 0; }
		}
		if (at_caret) { cch = q; cchlen = (size_t)(nx - q); }
		used += cw;
		q = nx;
	}
	int nlines = line + 1;
	if (ccol >= fieldw) { cline++; ccol = 0; if (cline >= nlines) nlines = cline + 1; }

	int top = 0;
	if (nlines > rh) {
		top = cline - rh + 1;
		if (top > nlines - rh) top = nlines - rh;
		if (top < 0) top = 0;
	}

	for (int i = 0; i < rh; i++) gfill(y + i, fx, fieldw, " ", attr);

	line = 0; used = 0;
	for (const char *q = val; *q; ) {
		unsigned int c;
		const char *nx = u8next(q, &c);
		int cw = cp_width(c);
		if (used + cw > fieldw) { line++; used = 0; }
		if (line >= top + rh) break;
		if (line >= top) {
			char one[8];
			size_t len = (size_t)(nx - q);
			if (len < sizeof one) { memcpy(one, q, len); one[len] = '\0';
				gput(y + line - top, fx + used, one, attr, cw); }
		}
		used += cw;
		q = nx;
	}

	if (!show_caret) return;
	if (cline < top || cline >= top + rh) return;
	if (cch && cchlen < 8) {
		char one[8];
		memcpy(one, cch, cchlen); one[cchlen] = '\0';
		gput(y + cline - top, fx + ccol, one, P_BTNACT, 1);
	} else {
		gput(y + cline - top, fx + ccol, "_", attr, 1);
	}
}

/* The label, plus the star that says the recipe cannot run without it. LuCI
 * marks these; this form saved an empty one happily and let a shell script
 * discover it, which is app-setup.cdn.md §3 #6 from the other end. */
static const char *param_label_req(const Pkg *p, const Param *pm)
{
	static char buf[176];
	snprintf(buf, sizeof buf, "%s%s", param_label(pm),
	         list_has(p->require, pm->name) ? " *" : "");
	return buf;
}

static const char *param_help(const Param *pm)
{
	return (g_zh && pm->help_zh[0]) ? pm->help_zh : pm->help;
}

static int screen_params(Pkg *p)
{
	if (!p->nparams) { message(pkg_name(p), S(T_NOPARAM)); return 0; }

	Param before[MAX_PARAMS];
	memcpy(before, p->params, sizeof before);
	Group groups_before[MAX_GROUPS];
	memcpy(groups_before, p->groups, sizeof groups_before);

	VisRow rows[MAX_VISROWS];
	int nrows = build_param_rows(p, rows);

	int sel = 0, scroll = 0;
	/* The caret belongs to the field rather than to the form, so moving to
	 * another row puts it at the end of that row's value — which is where
	 * typing used to append before there was a caret to put anywhere else. */
	int caret = 0, lastsel = -1;
	/* A complaint from Save & Apply, shown where the field's own description
	 * goes, and cleared as soon as the cursor moves. want_param survives the
	 * frame that unfolds a group so the offending field can be pointed at
	 * even when it was hidden. */
	char formmsg[220] = "";
	int want_param = -1;
	char title[256];
	snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_PARAMS));

	for (;;) {
		term_measure();
		grid_size(g_w, g_h);
		draw_root();
		hit_clear();

		/* Rebuilt every frame: a fold toggle or a reloaded recipe (the
		 * Refresh button, §3.3) changes this out from under a running loop,
		 * and rebuilding is cheap enough that patching the old list in place
		 * is not worth a second code path for it. */
		nrows = build_param_rows(p, rows);
		int B_APPLY = nrows, B_SAVE = nrows + 1, B_CANCEL = nrows + 2;
		int nitems = nrows + 3;
		if (sel > B_CANCEL) sel = B_CANCEL;

		if (want_param >= 0) {
			for (int i = 0; i < nrows; i++)
				if (rows[i].kind == ROW_PARAM && rows[i].idx == want_param) { sel = i; break; }
			want_param = -1;
			/* lastsel, not -1: moving the cursor is what clears the complaint,
			 * and this move *is* the complaint pointing at its field. */
			lastsel = sel;
			caret = 0;
		}
		if (sel != lastsel) {
			lastsel = sel;
			formmsg[0] = '\0';
			caret = (sel < nrows && rows[sel].kind == ROW_PARAM)
			        ? (int)strlen(p->params[rows[sel].idx].value) : 0;
		}

		int labw = 12;
		for (int i = 0; i < nrows; i++)
			if (rows[i].kind == ROW_PARAM) {
				int lw = u8width(param_label_req(p, &p->params[rows[i].idx]));
				if (lw > labw) labw = lw;
			}
		if (labw > 28) labw = 28;
		int fieldw = 30;
		int w = labw + fieldw + 8;
		if (w > g_w - 6) { w = g_w - 6; fieldw = w - labw - 8; }
		if (fieldw < 10) fieldw = 10;
		/* Three buttons are wider than two, and in Chinese wider again. The
		 * box grows to hold them rather than letting them run off its edge —
		 * everything else in here is sized to its contents too. */
		int bw = btn_width(S(T_SAVEAPPLY)) + 2 + btn_width(S(T_SAVE)) + 2 + btn_width(S(T_CANCEL));
		if (w < bw + 4) { w = bw + 4; if (w > g_w - 2) w = g_w - 2; }

		/* One line a row, plus however many extra the field being edited
		 * needs — clamped to the screen, where a scrollbar (not a truncated
		 * list with nothing to say so) takes up the difference. */
		int total = 0;
		for (int i = 0; i < nrows; i++)
			total += param_rowh(p, &rows[i], i == sel, fieldw);
		/* Two rows and the rule above them, and only when there is something
		 * to put there. A form whose recipe wrote no `# help:` is exactly the
		 * form it was before this existed. */
		int helph = 0;
		for (int i = 0; i < p->nparams; i++)
			if (p->params[i].help[0] || p->params[i].help_zh[0]) { helph = 3; break; }
		if (p->require[0]) helph = 3;
		int h = total + 6 + helph;
		if (h > g_h - 2) h = g_h - 2;
		int visrows = h - 6 - helph;
		if (visrows < 1) visrows = 1;
		/* Rows are not all one line any more, so "is the cursor on screen"
		 * is a walk rather than a subtraction. Scrolling one row at a time
		 * until the whole of the focused row fits keeps an expanded field
		 * from being cut off at the bottom, which is the case this exists
		 * for. */
		if (sel < nrows) {
			if (sel < scroll) scroll = sel;
			while (scroll < sel) {
				int used = 0;
				for (int i = scroll; i <= sel; i++)
					used += param_rowh(p, &rows[i], i == sel, fieldw);
				if (used <= visrows) break;
				scroll++;
			}
		} else if (scroll > nrows - 1) scroll = nrows - 1;
		if (scroll < 0) scroll = 0;

		int row = (g_h - h) / 2, col = (g_w - w) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		win_box(row, col, w, h, title);

		int y = row + 1;
		for (int i = scroll; i < nrows && y < row + 1 + visrows; i++) {
			VisRow *vr = &rows[i];
			int focused = (sel == i);
			int rh = param_rowh(p, vr, focused, fieldw);
			if (y + rh > row + 1 + visrows) rh = row + 1 + visrows - y;

			if (vr->kind == ROW_GROUP) {
				Group *gr = &p->groups[vr->idx];
				const char *lbl = (g_zh && gr->label_zh[0]) ? gr->label_zh : gr->label;
				/* A rule across the box with the name in it, which is what a
				 * terminal's version of LuCI's tab looks like. It used to be
				 * "= Advanced" sitting in the label column, where it read as a
				 * field called Advanced whose value was <Hide>. */
				int a = focused ? P_ENTRYACT : P_BORDER;
				gput(y, col, BX_LT, P_BORDER, 1);
				gfill(y, col + 1, w - 2, BX_H, P_BORDER);
				gput(y, col + w - 1, BX_RT, P_BORDER, 1);
				char hdr[160];
				snprintf(hdr, sizeof hdr, " %s ", lbl);
				int hw = u8width(hdr);
				gput(y, col + 2, hdr, a, hw);
				char btxt[32];
				snprintf(btxt, sizeof btxt, " <%s> ", S(gr->folded ? T_SHOW : T_HIDE));
				int btw = u8width(btxt);
				gput(y, col + w - 2 - btw, btxt, focused ? P_BTNACT : P_BTN, btw);
				if (focused) cursor_sweep(y, col + 2, hw, P_ENTRYACT, P_CURSORHOT);
				hit_add(H_BODY, i, y, col + 1, 1, w - 2);
				y += rh;
				continue;
			}
			if (vr->kind == ROW_ACTION) {
				Param *apm = &p->params[vr->idx];
				const char *lbl = (g_zh && apm->action_label_zh[0])
				                  ? apm->action_label_zh : apm->action_label;
				/* A button, not a row of text with a tick in front of it.
				 * `✓ Test the origin` was indistinguishable from a label
				 * whose field happened to be empty. */
				char btxt[96];
				snprintf(btxt, sizeof btxt, "<%s>", lbl);
				int a = focused ? P_ENTRYACT : P_WIN;
				gfill(y, col + 1, w - 2, " ", a);
				gput(y, col + 4, btxt, focused ? P_BTNACT : P_BTN, w - 6);
				if (focused) cursor_sweep(y, col + 4, u8width(btxt), P_BTNACT, P_CURSORHOT);
				hit_add(H_BODY, i, y, col + 1, 1, w - 2);
				y += rh;
				continue;
			}

			Param *pm = &p->params[vr->idx];
			/* A field that belongs to a group reads as nested under its
			 * header — two columns in, same as the header's own "= " costs. */
			int indent = (pm->group >= 0) ? 2 : 0;
			gput(y, col + 2 + indent, param_label_req(p, pm), P_WIN, labw - indent);

			int fx = col + 3 + labw;
			int a = focused ? P_ENTRYACT : P_ENTRY;
			hit_add(H_BODY, i, y, col + 2, rh, labw + 1 + fieldw + 1);
			if (pm->type == PT_BOOL) {
				int on = !strcmp(pm->value, "on") || !strcmp(pm->value, "1") ||
				         !strcmp(pm->value, "yes") || !strcmp(pm->value, "true");
				char box[32];
				snprintf(box, sizeof box, "[%s] %s", on ? MK_OK : " ", on ? S(T_ON) : S(T_OFF));
				gput(y, fx, box, a, fieldw);
			} else if (pm->type == PT_LIST) {
				/* What is ticked, and a `›` saying there is a window behind
				 * this rather than a box to type in. */
				gfill(y, fx, fieldw, " ", a);
				char cut[256];
				u8ellipsis(cut, sizeof cut, *pm->value ? pm->value : S(T_PICKEMPTY),
				           fieldw - 3);
				gput(y, fx, cut, a, fieldw - 3);
				gput(y, fx + fieldw - 2, CH_MORE, a, 1);
			} else if (pm->type == PT_ENUM) {
				char ch[128];
				snprintf(ch, sizeof ch, "%s %s %s", AR_L, pm->value, AR_R);
				gfill(y, fx, fieldw, " ", a);
				gput(y, fx, ch, a, fieldw);
				/* the two arrows are their own targets, so a choice can be
				 * stepped with the mouse and not only with the keys — keyed
				 * by row slot now, not param index, since sel is too */
				hit_add(H_BTN, 1000 + i, y, fx, 1, 1);
				hit_add(H_BTN, 2000 + i, y, fx + u8width(ch) - 1, 1, 1);
			} else if (focused) {
				/* Whole, over as many lines as it takes. A field somebody is
				 * typing into is the one place on this screen where hiding
				 * half the value costs something. */
				int cr = caret;
				if (cr > (int)strlen(pm->value)) cr = (int)strlen(pm->value);
				field_draw(y, fx, fieldw, rh, a, pm->value, cr, 1);
			} else {
				/* Read rather than edited: the front of a value is what
				 * identifies it, and one line a row keeps the form scannable. */
				gfill(y, fx, fieldw, " ", a);
				char cut[512];
				u8ellipsis(cut, sizeof cut, pm->value, fieldw - 1);
				gput(y, fx, cut, a, fieldw - 1);
			}
			y += rh;
		}
		scrollbar(row + 1, col + w - 2, visrows, scroll, visrows, nrows,
		          P_SBTHUMBW, P_SBTRACKW);

		/* LuCI puts this under every field because a web page scrolls. Twelve
		 * fields times two rows is this whole terminal, so it lives in one
		 * fixed place and follows the cursor instead. */
		if (helph) {
			int hy = row + h - 3 - helph + 1;
			gput(hy - 1, col, BX_LT, P_BORDER, 1);
			gfill(hy - 1, col + 1, w - 2, BX_H, P_BORDER);
			gput(hy - 1, col + w - 1, BX_RT, P_BORDER, 1);
			const char *txt = formmsg;
			if (!*txt && sel < nrows && rows[sel].kind == ROW_PARAM)
				txt = param_help(&p->params[rows[sel].idx]);
			char hl[4][512];
			int hn = *txt ? u8wrap(txt, w - 4, hl, 2) : 0;
			for (int i = 0; i < 2; i++) {
				gfill(hy + i, col + 1, w - 2, " ", P_WIN);
				if (i < hn)
					gput(hy + i, col + 2, hl[i], *formmsg ? P_ERR : P_DIM, w - 4);
			}
		}

		int bx = col + (w - bw) / 2;
		if (bx < col + 1) bx = col + 1;
		btn_draw(row + h - 2, bx, S(T_SAVEAPPLY), sel == B_APPLY, B_APPLY);
		bx += btn_width(S(T_SAVEAPPLY)) + 2;
		btn_draw(row + h - 2, bx, S(T_SAVE), sel == B_SAVE, B_SAVE);
		bx += btn_width(S(T_SAVE)) + 2;
		btn_draw(row + h - 2, bx, S(T_CANCEL), sel == B_CANCEL, B_CANCEL);
		help_line_l(&T_HELPFORM);
		grid_flush();

		int k = read_key();
		if (k == K_CLICK) {
			int idx = 0;
			switch (hit_test(g_my, g_mx, &idx)) {
			case H_BODY:
				sel = idx;
				if (idx < nrows && rows[idx].kind == ROW_PARAM) {
					Param *cpm = &p->params[rows[idx].idx];
					/* a checkbox is a thing you click, not a thing you
					 * select and then press space on; a long chooser opens
					 * the same popup a click gets on ENTER for one */
					if (cpm->type == PT_BOOL) k = ' ';
					else if (cpm->type == PT_LIST) k = K_ENTER;
					else if (cpm->type == PT_ENUM && cpm->nchoices >= ENUM_POPUP_MIN) k = K_ENTER;
					else continue;
				} else if (idx < nrows) {
					k = K_ENTER;   /* a group header or an action button */
				} else continue;
				break;
			case H_BTN:
				if (idx >= 2000) { sel = idx - 2000; k = K_RIGHT; }
				else if (idx >= 1000) { sel = idx - 1000; k = K_LEFT; }
				else { sel = idx; k = K_ENTER; }
				break;
			default: continue;
			}
		}
		Param *pm = (sel < nrows && rows[sel].kind == ROW_PARAM)
		            ? &p->params[rows[sel].idx] : NULL;

		if (k == K_ESC) {
			memcpy(p->params, before, sizeof before);
			memcpy(p->groups, groups_before, sizeof groups_before);
			return 0;
		}
		if (k == K_UP || k == K_BTAB) { sel = (sel - 1 + nitems) % nitems; continue; }
		if (k == K_DOWN || k == K_TAB) { sel = (sel + 1) % nitems; continue; }
		if (k == K_ENTER) {
			if (sel == B_CANCEL) {
				memcpy(p->params, before, sizeof before);
				memcpy(p->groups, groups_before, sizeof groups_before);
				return 0;
			}
			if (sel == B_APPLY || sel == B_SAVE) {
				/* A form that can be saved into a state its own program refuses
				 * is a form with a rule missing, not a program with a bad error
				 * message. The cursor goes to the field — unfolding its group if
				 * that is where it was hiding — and nothing is written. */
				int bad = -1;
				for (int i = 0; i < p->nparams; i++)
					if (list_has(p->require, p->params[i].name) && !p->params[i].value[0]) { bad = i; break; }
				if (bad >= 0) {
					if (p->params[bad].group >= 0) p->groups[p->params[bad].group].folded = 0;
					want_param = bad;
					copy_str(formmsg, sizeof formmsg, S(T_REQFIELD));
					continue;
				}
				if (!params_save(p)) {
					message(title, g_zh ? "保存失败：写不了参数文件。"
					                    : "could not write the settings file");
					return 0;
				}
				return sel == B_APPLY ? 2 : 1;
			}
			if (sel < nrows && rows[sel].kind == ROW_GROUP) {
				Group *gr = &p->groups[rows[sel].idx];
				gr->folded = !gr->folded;
				continue;
			}
			if (sel < nrows && rows[sel].kind == ROW_ACTION) {
				Param *apm = &p->params[rows[sel].idx];
				const char *lbl = (g_zh && apm->action_label_zh[0])
				                  ? apm->action_label_zh : apm->action_label;
				screen_progress(p, apm->action_verb, lbl);
				/* The verb may have rewritten this recipe's own header
				 * (rewrite_choices/drop_candidate, docs/app-setup.edit.md
				 * §3.1) — reload and stay in Settings with fresh choices,
				 * rather than falling back to screen_app the way every
				 * other verb does. */
				char path[512];
				copy_str(path, sizeof path, p->path);
				Pkg reloaded;
				if (load_recipe(path, &reloaded)) {
					*p = reloaded;
					params_load(p);
				}
				memcpy(before, p->params, sizeof before);
				memcpy(groups_before, p->groups, sizeof groups_before);
				continue;
			}
			if (pm && pm->type == PT_LIST) {
				screen_list_popup(p, pm);
				continue;
			}
			if (pm && pm->type == PT_ENUM && pm->nchoices >= ENUM_POPUP_MIN) {
				screen_enum_popup(pm);
				continue;
			}
			sel = B_APPLY;         /* Enter in a field moves on to the primary */
			continue;
		}
		if (!pm) {
			if (sel >= nrows) {   /* one of the three bottom buttons */
				if (k == K_LEFT)  sel = (sel - 1 < B_APPLY) ? B_CANCEL : sel - 1;
				if (k == K_RIGHT) sel = (sel + 1 > B_CANCEL) ? B_APPLY : sel + 1;
			}
			continue;
		}
		if (pm->type == PT_LIST) {
			if (k == ' ' || k == K_LEFT || k == K_RIGHT) screen_list_popup(p, pm);
		} else if (pm->type == PT_BOOL) {
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
			/* A caret, at last. Everything below moves or edits at `caret`
			 * rather than at the end of the string, and the field draws
			 * itself around wherever that is. UTF-8 continuation bytes are
			 * stepped over rather than into: half a character is not a
			 * position, and leaving the caret inside one would put a Chinese
			 * label through a paper shredder on the next keypress. */
			int vlen = (int)strlen(pm->value);
			if (caret > vlen) caret = vlen;
			if (caret < 0) caret = 0;
			if (k == K_LEFT) {
				if (caret > 0) {
					caret--;
					while (caret > 0 && ((unsigned char)pm->value[caret] & 0xC0) == 0x80) caret--;
				}
			} else if (k == K_RIGHT) {
				if (caret < vlen) {
					caret++;
					while (caret < vlen && ((unsigned char)pm->value[caret] & 0xC0) == 0x80) caret++;
				}
			} else if (k == K_HOME) {
				caret = 0;
			} else if (k == K_END) {
				caret = vlen;
			} else if (k == K_BACK) {
				if (caret > 0) {
					int from = caret - 1;
					while (from > 0 && ((unsigned char)pm->value[from] & 0xC0) == 0x80) from--;
					memmove(pm->value + from, pm->value + caret, (size_t)(vlen - caret + 1));
					caret = from;
				}
			} else if (k == 21) {          /* ^U */
				/* Replacing a long default is the commonest edit these fields
				 * get, and without this it is a hundred presses of Backspace.
				 * readline's key, because it is the one fingers already know. */
				pm->value[0] = '\0';
				caret = 0;
			} else if (k == 23) {          /* ^W */
				/* The item before the caret. Two of these fields are comma
				 * lists that people prune rather than retype, so the word this
				 * deletes is delimited by a comma as well as by a space. */
				int n = caret;
				while (n && (pm->value[n-1] == ',' || pm->value[n-1] == ' ')) n--;
				while (n && pm->value[n-1] != ',' && pm->value[n-1] != ' ') n--;
				while (n && (pm->value[n-1] == ',' || pm->value[n-1] == ' ')) n--;
				memmove(pm->value + n, pm->value + caret, (size_t)(vlen - caret + 1));
				caret = n;
			} else if (k >= 32 && k < 256) {
				if (pm->type == PT_NUMBER && !isdigit(k) && k != '.') continue;
				if (vlen < (int)sizeof pm->value - 2) {
					memmove(pm->value + caret + 1, pm->value + caret, (size_t)(vlen - caret + 1));
					pm->value[caret] = (char)k;
					caret++;
				}
			}
		}
	}
}

/* ------------------------------------------------------------ the details --
 *
 * Both of these are label-and-value columns, and both pad the label with
 * u8pad rather than %-10s: printf counts bytes, and every label here is
 * fewer bytes per column in Chinese than in English, so %-10s lines the
 * column up in one language and not the other.
 */
#define DET_LAB 10

static void screen_details(Pkg *p)
{
	char t[4096], gut[64];
	size_t n = 0;
	char cats[192] = "";
	for (int i = 0; i < p->ncats; i++) {
		int ci = cat_index(p->cats[i]);
		snprintf(cats + strlen(cats), sizeof cats - strlen(cats), "%s%s",
		         i ? ", " : "", ci >= 0 ? S(g_cats[ci].label) : p->cats[i]);
	}

	n += (size_t)snprintf(t + n, sizeof t - n, "%s\n\n", pkg_summary(p));
	u8pad(gut, sizeof gut, g_zh ? "状态" : "State", DET_LAB);
	n += (size_t)snprintf(t + n, sizeof t - n, "%s %s %s\n", gut,
	                      S(*status_label(p)), p->detail[0] ? p->detail : "");
	if (pkg_includes(p)[0]) {
		u8pad(gut, sizeof gut, S(T_INCLUDES), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, pkg_includes(p));
	}
	u8pad(gut, sizeof gut, g_zh ? "分类" : "Category", DET_LAB);
	n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, cats);
	if (p->disk[0]) {
		u8pad(gut, sizeof gut, S(T_DISK), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, p->disk);
	}
	if (p->memory[0]) {
		u8pad(gut, sizeof gut, S(T_RAM), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, p->memory);
	}
	if (p->ports[0]) {
		u8pad(gut, sizeof gut, S(T_PORT), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, p->ports);
	}
	if (p->requires[0]) {
		u8pad(gut, sizeof gut, S(T_NEEDS), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, p->requires);
	}
	if (p->service[0]) {
		u8pad(gut, sizeof gut, S(T_SERVICE), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s (%s %s)\n", gut, p->service,
		                      S(T_BOOT),
		                      p->enabled == 1 ? S(T_YES) : p->enabled == 0 ? S(T_NO) : "?");
	}
	if (p->nparams) {
		n += (size_t)snprintf(t + n, sizeof t - n, "\n%s\n", S(T_PARAMS));
		for (int i = 0; i < p->nparams; i++) {
			u8pad(gut, sizeof gut, param_label(&p->params[i]), 16);
			n += (size_t)snprintf(t + n, sizeof t - n, "  %s %s\n",
			                      gut, p->params[i].value);
		}
	}
	u8pad(gut, sizeof gut, g_zh ? "脚本" : "Recipe", DET_LAB);
	n += (size_t)snprintf(t + n, sizeof t - n, "\n%s %s\n", gut, p->path);
	u8pad(gut, sizeof gut, S(T_LOG), DET_LAB);
	snprintf(t + n, sizeof t - n, "%s %s/%s.log\n", gut, log_dir(), p->id);

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

	char t[9000], gut[64];
	size_t n = 0;
	u8pad(gut, sizeof gut, g_zh ? "状态" : "State", DET_LAB);
	n += (size_t)snprintf(t + n, sizeof t - n, "%s %s %s\n", gut,
	                      status_mark(p), S(*status_label(p)));
	if (p->detail[0]) {
		u8pad(gut, sizeof gut, S(T_VERSION), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, p->detail);
	}
	if (p->service[0]) {
		u8pad(gut, sizeof gut, S(T_SERVICE), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, p->service);
		u8pad(gut, sizeof gut, S(T_BOOT), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut,
		                      p->enabled == 1 ? S(T_YES) : p->enabled == 0 ? S(T_NO) : "?");
	}
	if (p->ports[0]) {
		u8pad(gut, sizeof gut, S(T_PORT), DET_LAB);
		n += (size_t)snprintf(t + n, sizeof t - n, "%s %s\n", gut, p->ports);
	}

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

/* What actually happened, the last few times anything was run on this package.
 *
 * The detail page has always named this file and, until now, naming it was all
 * it did — the one thing on that page you could not get to without leaving the
 * program, which is backwards for the page somebody is on when an install has
 * just failed. Every package has the button; it is grey until there is a file
 * behind it.
 *
 * Only the tail is read. Installing a suite runs to tens of thousands of lines
 * and the end is the part that says how it went. */
static void screen_log(Pkg *p)
{
	char path[600], title[256];
	snprintf(path, sizeof path, "%s/%s.log", log_dir(), p->id);
	snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_LOG));

	int fd = open(path, O_RDONLY);
	if (fd < 0) {
		char msg[700];
		snprintf(msg, sizeof msg, S(T_NOLOG), path);
		message(title, msg);
		return;
	}

	off_t size = lseek(fd, 0, SEEK_END);
	off_t from = size > LOG_TAIL ? size - LOG_TAIL : 0;
	if (lseek(fd, from, SEEK_SET) < 0) from = 0;

	char *buf = xmalloc(LOG_TAIL + 2);
	ssize_t n = read(fd, buf, LOG_TAIL);
	close(fd);
	if (n < 0) n = 0;
	buf[n] = '\0';

	char *start = buf;
	if (from > 0) {                      /* never begin half way through a line */
		char *nl = strchr(buf, '\n');
		if (nl) start = nl + 1;
	}
	strip_ansi(start);

	if (!*start) {
		message(title, S(T_LOGEMPTY));
		free(buf);
		return;
	}

	if (from > 0) {
		/* say so, rather than let somebody scroll to the top and believe
		 * that is where the install began */
		char shown[16], total[16], head[200];
		human_size((long long)(n), shown, sizeof shown);
		human_size((long long)size, total, sizeof total);
		snprintf(head, sizeof head, S(T_LOGTAIL), shown, total);

		size_t len = strlen(start), hl = strlen(head);
		char *joined = xmalloc(hl + len + 3);
		snprintf(joined, hl + len + 3, "%s\n\n%s", head, start);
		pager(title, joined);
		free(joined);
	} else {
		pager(title, start);
	}
	free(buf);
}

/* Run `verb`, capture its stdout (20s, same deadline Docs always used),
 * page it. Docs itself is now the `help`-flavoured call of this — and it is
 * also what a `# button:` verb runs through (build_actions/add_button),
 * so a recipe with no service and no install can still hand back text
 * without going anywhere near /var/log/app-setup. */
static void screen_docs_verb(Pkg *p, const char *verb, const char *title)
{
	char out[32768];
	g_env_pkg = p;
	int rc = run_capture(p->path, verb, out, sizeof out, 20, 1);
	g_env_pkg = NULL;
	if (rc != 0 && !out[0]) snprintf(out, sizeof out, "%s", S(T_NODOC));
	strip_ansi(out);
	pager(title, out);
}

static void screen_docs(Pkg *p)
{
	char title[256];
	snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_DOCS));
	screen_docs_verb(p, "help", title);
}

/* ------------------------------------------------------------- the cover --
 *
 * A terminal has no pictures, so the thing a card shows where a thumbnail
 * would go is a block of shade in the category's colour with the package's own
 * id across it in capitals. The id is latin by construction — it is a filename
 * — so it can never be the thing that pushes a border out by a column, and
 * adding a package draws its cover without anybody drawing anything.
 */
static int cover_of(const Pkg *p)
{
	/* First category wins, and it is the recipe that decides the order, so a
	 * package that is both `web` and `stack` gets the colour of whichever it
	 * calls itself first. */
	if (p->ncats > 0) {
		int i = cat_index(p->cats[0]);
		if (i >= 0) return i % N_COVERS;
	}
	return N_COVERS - 1;
}

static void cover_wordmark(char *out, size_t cap, const Pkg *p)
{
	size_t n = 0;
	for (const char *s = p->id; *s && n + 1 < cap; s++)
		out[n++] = (char)toupper((unsigned char)*s);
	out[n] = '\0';
}

/* `rows` rows of shade at (row,col), the wordmark across the middle of it and
 * the size in the bottom right, which is where a video's duration sits. */
static void draw_cover(int row, int col, int w, int rows, const Pkg *p, const char *badge)
{
	int cv = cover_of(p);
	for (int r = 0; r < rows; r++) gfill(row + r, col, w, TH_COVER, P_COV0 + cv);
	/* the wordmark sits on a solid run of the same colour, so it reads as a
	 * label printed on the block rather than as more of the texture */

	char mark[96], lg[104];
	cover_wordmark(mark, sizeof mark, p);
	snprintf(lg, sizeof lg, " %s ", mark);
	int lw = u8width(lg);
	if (lw <= w) gput(row + (rows - 1) / 2, col + (w - lw) / 2, lg, P_LOGO0 + cv, lw);

	if (badge && badge[0] && rows >= 2) {
		char bd[40];
		snprintf(bd, sizeof bd, " %s ", badge);
		int bw = u8width(bd);
		if (bw + 2 <= w) gput(row + rows - 1, col + w - bw - 1, bd, P_LOGO0 + cv, bw);
	}
}

/* --------------------------------------------------------- the app screen --
 *
 * The one the whole redesign is for. You walk onto a card and press Enter, and
 * you get everything that can be done to that thing laid along the top —
 * install it, change its settings, read what it is — with Back at the right
 * hand end of the same row, in the same corner it occupies everywhere else.
 * Choosing what to do is the same gesture as choosing what to do it to.
 */
/* The tabs are places and never reorder; the verbs inside a tab are actions
 * and may. That split is the whole point of §6 — `build_actions` used to put
 * Install in slot 0 when a package was absent and Stop in slot 0 when it was
 * running, so the same two keystrokes did different things. */
enum { TAB_STATUS = 0, TAB_SETTINGS, TAB_LOG, TAB_DOCS, TAB_REMOVE };
#define MAX_TABS 6
#define MAX_ACTS 14
typedef struct { int kind; char label[64]; char aux[16]; } TabE;

enum { A_INSTALL = 1, A_REMOVE, A_START, A_STOP, A_RESTART, A_BOOT,
       A_STATUS, A_DETAILS, A_PARAMS, A_DOCS, A_LOG, A_BUTTON };

/* `verb` is only ever read when `act == A_BUTTON` — every other action's
 * verb is implied by `act` itself and dispatched by name in screen_app. */
typedef struct { int act; char label[64]; char aux[32]; int dim; char verb[32]; int mode; } Action;

/* Fill in the Log entry: grey until something has been run on this package,
 * carrying the file's size when there is one — which answers "is there
 * anything in it" without opening it. */
static void add_log_action(const Pkg *p, Action *a)
{
	char lp[600];
	struct stat st;
	snprintf(lp, sizeof lp, "%s/%s.log", log_dir(), p->id);
	a->act = A_LOG;
	copy_str(a->label, 64, S(T_LOG));
	a->aux[0] = '\0';
	a->dim = 1;
	if (stat(lp, &st) == 0 && S_ISREG(st.st_mode)) {
		a->dim = 0;
		if (st.st_size > 0) human_size((long long)st.st_size, a->aux, sizeof a->aux);
	}
}

/* The order is the order somebody needs them in, not the order they were
 * written in. The verb that changes the thing comes first — Install, or Stop
 * on something running — and **the log comes straight after it**, because "it
 * is not running" and "why is it not running" are the same moment and the
 * answer should not be at the far end of a wrapped row behind Details. */
/* The verbs of one tab. Status has the ones that change what the machine is
 * doing; Remove has the one; Settings, Log and How-to-use-it have none, because
 * they are places to look rather than things to do. */
static int build_actions(const Pkg *p, int tab, Action *a)
{
	int n = 0;

	if (tab == TAB_REMOVE) {
		a[0].act = A_REMOVE; copy_str(a[0].label, 64, S(T_REMOVE));
		a[0].aux[0] = '\0'; a[0].dim = 0;
		return 1;
	}
	if (tab != TAB_STATUS) return 0;

	/* A recipe that declares `# button:` has said the service state machine
	 * does not describe it. Its buttons are the Status tab's verbs. */
	if (p->nbuttons) {
		for (int i = 0; i < p->nbuttons && n < MAX_ACTS; i++) {
			const Btn *b = &p->buttons[i];
			a[n].act = A_BUTTON;
			copy_str(a[n].label, 64, (g_zh && b->label_zh[0]) ? b->label_zh : b->label);
			copy_str(a[n].verb, sizeof a[n].verb, b->verb);
			a[n].mode = b->mode;
			a[n].aux[0] = '\0';
			a[n].dim = 0;
			n++;
		}
		return n;
	}

	int inst = pkg_installed(p);
	if (!inst) {
		a[n].act = A_INSTALL; copy_str(a[n].label, 64, S(T_INSTALL)); a[n].aux[0] = 0; a[n].dim = 0; n++;
		return n;
	}
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
	return n;
}



/* Which tabs this package has. Settings only when it declares any, Log only
 * when there is one on disk, Remove only when there is something to remove —
 * a tab that opens on nothing is a tab somebody presses once and distrusts
 * afterwards. */
static int build_tabs(const Pkg *p, TabE *t)
{
	int n = 0, inst = pkg_installed(p);
	char lp[600];
	struct stat st;

	t[n].kind = TAB_STATUS;
	copy_str(t[n].label, 64, S(inst ? T_TSTATUS : T_TABSENT));
	t[n].aux[0] = '\0'; n++;

	if (p->nparams) {
		t[n].kind = TAB_SETTINGS;
		copy_str(t[n].label, 64, S(T_PARAMS));
		snprintf(t[n].aux, sizeof t[n].aux, "%d", p->nparams);
		n++;
	}
	snprintf(lp, sizeof lp, "%s/%s.log", log_dir(), p->id);
	if (stat(lp, &st) == 0 && S_ISREG(st.st_mode)) {
		t[n].kind = TAB_LOG;
		copy_str(t[n].label, 64, S(T_LOG));
		t[n].aux[0] = '\0';
		if (st.st_size > 0) human_size((long long)st.st_size, t[n].aux, sizeof t[n].aux);
		n++;
	}
	t[n].kind = TAB_DOCS;
	copy_str(t[n].label, 64, S(T_DOCS));
	t[n].aux[0] = '\0'; n++;

	if (inst) {
		t[n].kind = TAB_REMOVE;
		copy_str(t[n].label, 64, S(T_REMOVE));
		t[n].aux[0] = '\0'; n++;
	}
	return n;
}

static int act_width(const Action *a)
{
	int w = u8width(a->label) + 2;
	if (a->aux[0]) w += u8width(a->aux) + 1;
	return w;
}

/* One verb, drawn as a pill. Cyan under the cursor, grey when it cannot be
 * pressed, plain otherwise. Returns the columns it used. */
static int act_draw(int row, int col, const Action *a, int focused, int maxw)
{
	/* `<Label>`, which is newt's shape and LuCI's and the one btn_draw has
	 * always used for the form's three buttons. This row is the one somebody
	 * opened the screen to press, and it was the one drawn as bare words.
	 * Same width as the spaces it replaces, so nothing above needs to know. */
	char t[128];
	if (a->aux[0]) snprintf(t, sizeof t, "<%s %s>", a->label, a->aux);
	else           snprintf(t, sizeof t, "<%s>", a->label);
	int w = u8width(t);
	if (w > maxw) return 0;
	gput(row, col, t, focused ? P_CURSOR : (a->dim ? P_BTNDIM : P_WIN), w);
	if (focused) cursor_sweep(row, col, w, P_CURSOR, P_CURSORHOT);
	return w;
}

/* The label / value pairs shown beside the cover. Two to a line, three lines,
 * in the order somebody scanning for "will this fit and what will it open"
 * reads them. */
static int detail_facts(const Pkg *p, char lab[6][32], char val[6][64])
{
	int n = 0;
	int inst = pkg_installed(p);
	if (inst && p->detail[0]) {
		copy_str(lab[n], 32, S(T_VERSION)); copy_str(val[n], 64, p->detail); n++;
	}
	if (!inst && p->disk[0]) {
		copy_str(lab[n], 32, S(T_DISK)); copy_str(val[n], 64, p->disk); n++;
	}
	if (!inst && p->memory[0] && p->mem_bytes > 0 && n < 6) {
		copy_str(lab[n], 32, S(T_RAM)); copy_str(val[n], 64, p->memory); n++;
	}
	if (p->ports[0] && n < 6) {
		copy_str(lab[n], 32, S(T_PORT)); copy_str(val[n], 64, p->ports); n++;
	}
	if (p->service[0] && n < 6) {
		copy_str(lab[n], 32, S(T_SERVICE)); copy_str(val[n], 64, p->service); n++;
	}
	if (p->service[0] && n < 6) {
		copy_str(lab[n], 32, S(T_BOOT));
		copy_str(val[n], 64, p->enabled == 1 ? S(T_YES) : p->enabled == 0 ? S(T_NO) : MK_DOT);
		n++;
	}
	if (p->nparams && n < 6) {
		copy_str(lab[n], 32, S(T_PARAMS));
		snprintf(val[n], 64, S(T_NITEMS), p->nparams);
		n++;
	}
	if (p->requires[0] && n < 6) {
		copy_str(lab[n], 32, S(T_NEEDS)); copy_str(val[n], 64, p->requires); n++;
	}
	return n;
}

/* The prose under the cover: what it is, what comes with it, where the log
 * goes. Built as lines rather than drawn, because it is the part that scrolls
 * and the scroller only needs to know how many there are. */
#define DET_LINES 96
typedef struct { char t[512]; unsigned char a; } DetLine;

static int detail_body(const Pkg *p, int cols, DetLine *out)
{
	int n = 0;
	char wrap[24][512];

	int nw = u8wrap(pkg_summary(p), cols, wrap, 24);
	for (int i = 0; i < nw && n < DET_LINES; i++) {
		copy_str(out[n].t, sizeof out[n].t, wrap[i]); out[n].a = P_WIN; n++;
	}

	int labw = u8width(S(T_INCLUDES));
	if (u8width(S(T_LOG)) > labw) labw = u8width(S(T_LOG));
	labw += 3;

	char gutter[64];
	if (pkg_includes(p)[0] && n < DET_LINES) {
		out[n].t[0] = '\0'; out[n].a = P_WIN; n++;
		nw = u8wrap(pkg_includes(p), cols - labw, wrap, 8);
		for (int i = 0; i < nw && n < DET_LINES; i++) {
			u8pad(gutter, sizeof gutter, i == 0 ? S(T_INCLUDES) : "", labw);
			snprintf(out[n].t, sizeof out[n].t, "%s%s", gutter, wrap[i]);
			out[n].a = P_DIM; n++;
		}
	}
	if (n < DET_LINES) {
		out[n].t[0] = '\0'; out[n].a = P_WIN; n++;
		u8pad(gutter, sizeof gutter, S(T_LOG), labw);
		snprintf(out[n].t, sizeof out[n].t, "%s%s/%s.log", gutter, log_dir(), p->id);
		out[n].a = P_DIM; n++;
	}
	return n;
}

/* --- the body of each tab -------------------------------------------------
 *
 * Every one of them produces the same thing the detail pane always produced: a
 * list of styled lines the existing scroller already knows how to draw. That
 * is why four of the five tabs cost almost nothing — Log and How-to-use-it
 * were separate paged screens, and a paged screen is a list of lines with a
 * window drawn round it.
 *
 * Built when the tab changes rather than every frame: How-to-use-it forks a
 * shell to ask the recipe, and doing that sixty times a second would be a
 * cursor animation that runs a script.
 */
static int status_body(const Pkg *p, int cols, DetLine *out)
{
	int n = 0;
	char lab[6][32], val[6][64];
	int nf = detail_facts(p, lab, val);

	/* One label column, all the way down — LuCI's shape. The facts used to be
	 * an inline 2x3 grid above hanging-indent blocks, which is two layout
	 * languages on one screen and neither edge to track. */
	int labw = 0;
	for (int i = 0; i < nf; i++) {
		int w = u8width(lab[i]);
		if (w > labw) labw = w;
	}
	labw += 3;
	for (int i = 0; i < nf && n < DET_LINES - 4; i++) {
		char g[64];
		u8pad(g, sizeof g, lab[i], labw);
		snprintf(out[n].t, sizeof out[n].t, "%s%s", g, val[i]);
		out[n].a = P_WIN; n++;
	}
	if (nf && n < DET_LINES) { out[n].t[0] = '\0'; out[n].a = P_WIN; n++; }
	if (n < DET_LINES - 8) n += detail_body(p, cols, out + n);
	return n;
}

static int text_body(const char *txt, int cols, DetLine *out, int attr)
{
	int n = 0;
	const char *l = txt;
	while (*l && n < DET_LINES) {
		const char *e = strchr(l, '\n');
		size_t len = e ? (size_t)(e - l) : strlen(l);
		char one[1024];
		if (len >= sizeof one) len = sizeof one - 1;
		memcpy(one, l, len); one[len] = '\0';
		/* Wrapped rather than cut: a log line and a help line are both prose
		 * often enough that losing the right of them loses the point. */
		if (u8width(one) <= cols) {
			copy_str(out[n].t, sizeof out[n].t, one); out[n].a = attr; n++;
		} else {
			/* A recipe's help text and a log are both laid out with indents
			 * that carry meaning, and u8wrap eats leading spaces. Take the
			 * indent off first and put it back on every piece. */
			int ind = 0;
			while (one[ind] == ' ' && ind < cols / 2) ind++;
			char pad[64];
			int pn = ind < (int)sizeof pad - 1 ? ind : (int)sizeof pad - 1;
			memset(pad, ' ', (size_t)pn); pad[pn] = '\0';
			char wrap[8][512];
			int nw = u8wrap(one + ind, cols - pn, wrap, 8);
			for (int i = 0; i < nw && n < DET_LINES; i++) {
				snprintf(out[n].t, sizeof out[n].t, "%s%s", pad, wrap[i]);
				out[n].a = attr; n++;
			}
		}
		if (!e) break;
		l = e + 1;
	}
	return n;
}

static int log_body(const Pkg *p, int cols, DetLine *out)
{
	char path[600];
	snprintf(path, sizeof path, "%s/%s.log", log_dir(), p->id);
	int fd = open(path, O_RDONLY);
	if (fd < 0) return 0;
	off_t size = lseek(fd, 0, SEEK_END);
	off_t from = size > LOG_TAIL ? size - LOG_TAIL : 0;
	if (lseek(fd, from, SEEK_SET) < 0) from = 0;
	char *buf = xmalloc(LOG_TAIL + 2);
	ssize_t got = read(fd, buf, LOG_TAIL);
	close(fd);
	if (got < 0) got = 0;
	buf[got] = '\0';
	char *start = buf;
	/* a tail that begins mid-line begins at the next one instead */
	if (from > 0) { char *nl = strchr(buf, '\n'); if (nl) start = nl + 1; }
	strip_ansi(start);
	int n = text_body(start, cols, out, P_DIM);
	free(buf);
	return n;
}

static int docs_body(Pkg *p, int cols, DetLine *out)
{
	char txt[32768];
	g_env_pkg = p;
	int rc = run_capture(p->path, "help", txt, sizeof txt, 20, 1);
	g_env_pkg = NULL;
	if (rc != 0 && !txt[0]) snprintf(txt, sizeof txt, "%s", S(T_NODOC));
	strip_ansi(txt);
	return text_body(txt, cols, out, P_WIN);
}

static int settings_body(const Pkg *p, int cols, DetLine *out)
{
	int n = 0, labw = 0;
	for (int i = 0; i < p->nparams; i++) {
		int w = u8width(param_label_req(p, &p->params[i]));
		if (w > labw) labw = w;
	}
	if (labw > cols / 2) labw = cols / 2;
	labw += 2;
	for (int i = 0; i < p->nparams && n < DET_LINES - 3; i++) {
		const Param *pm = &p->params[i];
		char g[200], cut[256];
		u8pad(g, sizeof g, param_label_req(p, pm), labw);
		u8ellipsis(cut, sizeof cut, pm->value[0] ? pm->value : "—", cols - labw);
		snprintf(out[n].t, sizeof out[n].t, "%s%s", g, cut);
		out[n].a = pm->value[0] ? P_WIN : P_DIM;
		n++;
	}
	if (n < DET_LINES - 2) {
		out[n].t[0] = '\0'; out[n].a = P_WIN; n++;
		copy_str(out[n].t, sizeof out[n].t, S(T_EDITHINT)); out[n].a = P_DIM; n++;
	}
	return n;
}

static int body_for_tab(Pkg *p, int tab, int cols, DetLine *out)
{
	switch (tab) {
	case TAB_SETTINGS: return settings_body(p, cols, out);
	case TAB_LOG:      return log_body(p, cols, out);
	case TAB_DOCS:     return docs_body(p, cols, out);
	case TAB_REMOVE:   return text_body(S(T_REMOVEBODY), cols, out, P_WIN);
	default:           return status_body(p, cols, out);
	}
}


/* Two zones on this screen: the row of verbs, and the prose under it that
 * scrolls when there is more of it than fits. */
enum { Z_TAB = 0, Z_BTN, Z_BODY };

/* Everything the app screen needs to draw itself, and everything drawing it
 * works out on the way. The screen is split from its loop so that
 * `screenshot --screen app` renders the real thing rather than a second
 * drawing of it that is free to drift — the last version had two, and the
 * copy is what a layout test would have been testing. */

typedef struct {
	int sel;          /* 0..na-1 a verb, na is Back */
	int zone;         /* Z_TAB, Z_BTN or Z_BODY */
	/* which place this screen is showing, and the cursor's own position on
	 * the bar. tsel is separate from sel so walking down into the verbs and
	 * back up returns to the tab you came from. */
	int tab, tsel;
	int ntab;
	TabE tabs[MAX_TABS];
	int trow[MAX_TABS + 1], tcol[MAX_TABS + 1], twid[MAX_TABS + 1];
	int ntrows;
	int bscroll;      /* first line of prose drawn */
	/* filled in by app_draw */
	int na, brows, maxscroll;
	Action acts[MAX_ACTS];
	/* where each verb ended up, so Up and Down can move between the rows of
	 * them rather than only along one. Index na is Back. */
	int arow[MAX_ACTS + 1], acol[MAX_ACTS + 1], awid[MAX_ACTS + 1];
	int nbrows;
} AppView;

/* Lay the verbs out left to right, wrapping. Back is pinned to the right of
 * the first row and the verbs flow under it.
 *
 * They used to scroll sideways under a `›` instead, which meant a package with
 * a service — stop, restart, running state, update, start at boot, settings,
 * details, how to use it, uninstall — hid three of its own verbs off the right
 * hand edge, on a screen with a completely empty middle. Wrapping costs a row
 * or two of a panel that is sized to its contents anyway. */
static int act_layout(AppView *v, int inner, int backw)
{
	int first = inner - backw - 2;   /* the first row stops short of Back */
	if (first < 8) first = 8;
	int x = 0, row = 0;

	for (int i = 0; i < v->na; i++) {
		int w = act_width(&v->acts[i]);
		int limit = row ? inner : first;
		if (x && x + w > limit) { row++; x = 0; limit = inner; }
		v->arow[i] = row;
		v->acol[i] = x;
		v->awid[i] = w;
		x += w + 1;
	}
	v->arow[v->na] = 0;                            /* Back */
	v->acol[v->na] = inner - backw;
	v->awid[v->na] = backw;
	return row + 1;
}

/* The tab bar, laid out exactly like the verb row underneath it and with Back
 * pinned to the right the way it is on every other screen. Index ntab is Back. */
static int tab_layout(AppView *v, int inner, int backw)
{
	int first = inner - backw - 2;
	if (first < 8) first = 8;
	int x = 0, row = 0;
	for (int i = 0; i < v->ntab; i++) {
		int w = u8width(v->tabs[i].label) + 2;
		if (v->tabs[i].aux[0]) w += u8width(v->tabs[i].aux) + 1;
		int limit = row ? inner : first;
		if (x && x + w > limit) { row++; x = 0; }
		v->trow[i] = row; v->tcol[i] = x; v->twid[i] = w;
		x += w + 1;
	}
	v->trow[v->ntab] = 0;
	v->tcol[v->ntab] = inner - backw;
	v->twid[v->ntab] = backw;
	return row + 1;
}

static void app_draw(Pkg *p, AppView *v)
{
	static DetLine body[DET_LINES];
	static int nb = 0, body_tab = -1, body_cols = -1;
	static const Pkg *body_pkg = NULL;

	v->ntab = build_tabs(p, v->tabs);
	if (v->tab >= v->ntab) v->tab = 0;
	if (v->tsel > v->ntab) v->tsel = v->ntab;
	v->na = build_actions(p, v->tabs[v->tab].kind, v->acts);
	if (v->sel >= v->na) v->sel = v->na ? v->na - 1 : 0;
	if (v->sel < 0) v->sel = 0;
	if (v->zone == Z_BTN && !v->na) v->zone = Z_TAB;

	grid_size(g_w, g_h);
	g_showtop = 0;
	draw_root();
	hit_clear();

	/* Wide enough to read and no wider. A hundred columns of prose is already
	 * a long line to track back from. */
	int px = 1, pw = g_w - 2, room = g_h - 3;
	if (pw > 100) { pw = 100; px = (g_w - pw) / 2; }
	if (room < 10) { px = 0; pw = g_w > 100 ? 100 : g_w; room = g_h - 1; }
	int tx = px + 2, inner = pw - 4;

	char backl[64];
	snprintf(backl, sizeof backl, " %s ", S(T_BACK));
	int backw = u8width(backl);

	v->ntrows = tab_layout(v, inner, backw);
	v->nbrows = v->na ? act_layout(v, inner, 0) : 0;

	/* Built when the tab changes, not every frame: How-to-use-it forks a shell
	 * to ask the recipe what it says about itself. */
	if (body_tab != v->tabs[v->tab].kind || body_cols != inner || body_pkg != p) {
		nb = body_for_tab(p, v->tabs[v->tab].kind, inner, body);
		body_tab = v->tabs[v->tab].kind;
		body_cols = inner;
		body_pkg = p;
		v->bscroll = 0;
	}

	/* border, tabs, [verbs + a blank], the rule, the body, border */
	int ph = 2 + v->ntrows + (v->na ? v->nbrows + 1 : 0) + 1 + nb;
	if (ph > room) ph = room;
	if (ph < 8) ph = 8;

	int prow = 2 + (room - ph) / 2;
	if (prow + ph > g_h - 1) prow = g_h - 1 - ph;
	if (prow < 1) prow = 1;
	win_box(prow, px, pw, ph, pkg_name(p));

	/* The state belongs on the title bar, which is what a title bar is for. It
	 * used to float as an unlabelled line inside the panel while every other
	 * line had a label. */
	{
		char st[128];
		snprintf(st, sizeof st, " %s %s ", status_mark(p), S(*status_label(p)));
		int sw = u8width(st);
		if (sw < pw - u8width(pkg_name(p)) - 8)
			gput(prow, px + pw - 2 - sw, st, status_attr(p), sw);
	}

	/* ---- the tabs ------------------------------------------------------- */
	int y = prow + 1;
	for (int i = 0; i < v->ntab; i++) {
		char t[128];
		if (v->tabs[i].aux[0]) snprintf(t, sizeof t, " %s %s ", v->tabs[i].label, v->tabs[i].aux);
		else                   snprintf(t, sizeof t, " %s ", v->tabs[i].label);
		int by = y + v->trow[i], bx = tx + v->tcol[i], bw = v->twid[i];
		int cur = (v->zone == Z_TAB && v->tsel == i);
		gput(by, bx, t, cur ? P_CURSOR : (i == v->tab ? P_CHIPSEL : P_WIN), bw);
		if (cur) cursor_sweep(by, bx, bw, P_CURSOR, P_CURSORHOT);
		hit_add(H_CHIP, i, by, bx, 1, bw);
	}
	{
		int bcur = (v->zone == Z_TAB && v->tsel == v->ntab);
		int bx = tx + v->tcol[v->ntab];
		gput(y, bx, backl, bcur ? P_BACKCUR : P_BACK, backw);
		if (bcur) cursor_sweep(y, bx, backw, P_BACKCUR, P_BACKHOT);
		hit_add(H_BACK, 0, y, bx, 1, backw);
	}
	y += v->ntrows;

	/* ---- the verbs of this tab ------------------------------------------ */
	if (v->na) {
		for (int i = 0; i < v->na; i++) {
			int by = y + v->arow[i], bx = tx + v->acol[i];
			act_draw(by, bx, &v->acts[i], v->zone == Z_BTN && i == v->sel, v->awid[i]);
			hit_add(H_BTN, i, by, bx, 1, v->awid[i]);
		}
		y += v->nbrows;
	}

	gput(y, px, BX_LT, P_BORDER, 1);
	gfill(y, px + 1, pw - 2, BX_H, P_BORDER);
	gput(y, px + pw - 1, BX_RT, P_BORDER, 1);
	y++;

	g_clip_top = prow + 1; g_clip_bot = prow + ph - 2;

	int btop = y;
	v->brows = prow + ph - 1 - btop;
	if (v->brows < 1) v->brows = 1;
	v->maxscroll = nb - v->brows;
	if (v->maxscroll < 0) v->maxscroll = 0;
	if (v->bscroll > v->maxscroll) v->bscroll = v->maxscroll;
	if (v->bscroll < 0) v->bscroll = 0;
	if (v->zone == Z_BODY && !v->maxscroll) v->zone = v->na ? Z_BTN : Z_TAB;

	for (int i = 0; i < v->brows && v->bscroll + i < nb; i++)
		gput(btop + i, tx, body[v->bscroll + i].t, body[v->bscroll + i].a, inner);
	hit_add(H_BODY, 0, btop, tx, v->brows, inner);
	g_clip_top = g_clip_bot = -1;

	if (v->maxscroll) {
		scrollbar(btop, px + pw - 2, v->brows, v->bscroll, v->brows, nb,
		          v->zone == Z_BODY ? P_CURSOR : P_SBTHUMBW, P_SBTRACKW);
		char sb[32];
		snprintf(sb, sizeof sb, " %d%% ", (v->bscroll + v->brows) * 100 / nb);
		int sw = u8width(sb);
		gput(prow + ph - 1, px + pw - 3 - sw, sb,
		     v->zone == Z_BODY ? P_CURSOR : P_TITLE, sw);
	}

	help_line_l(&T_HELPDET);
}

/* Move the cursor a row up or down through the wrapped verbs, landing on
 * whichever one starts nearest the column it was already in — the same thing
 * the eye does. Returns 0 when there is no row that way. */
static int act_step(AppView *v, int dir)
{
	int row = v->arow[v->sel] + dir;
	if (row < 0 || row >= v->nbrows) return 0;
	int best = -1, bestd = 1 << 30;
	/* `< na`, not `<= na`: Back moved to the tab row, so index na is no
	 * longer a place the verb cursor may land. */
	for (int i = 0; i < v->na; i++) {
		if (v->arow[i] != row) continue;
		int d = v->acol[i] - v->acol[v->sel];
		if (d < 0) d = -d;
		if (d < bestd) { bestd = d; best = i; }
	}
	if (best < 0) return 0;
	v->sel = best;
	return 1;
}

/* Install, with the question about free space in front of it. Two callers:
 * the Install row, and Save & Apply in the settings form. */
static void action_install(Pkg *p)
{
	int ds = 0, ms = 0;
	if (resource_short(p, &ds, &ms)) {
		char have[16], q[500];
		human_size(ds ? g_sys.disk_free : g_sys.mem_total, have, sizeof have);
		snprintf(q, sizeof q, S(T_TIGHTQ), pkg_name(p), ds ? p->disk : p->memory, have);
		if (!confirm(pkg_name(p), q)) return;
	}
	screen_progress(p, "install", NULL);
}

static void screen_app(Pkg *p)
{
	AppView v;
	memset(&v, 0, sizeof v);
	/* Lands on Status, which is the tab that answers "what is this and what
	 * is it doing" — the question somebody had when they pressed Enter. */
	v.zone = Z_TAB;

	for (;;) {
		term_measure();
		app_draw(p, &v);
		grid_flush();

		int k = read_key();
		if (k == K_RESIZE || k == K_TIMEOUT || k == K_NONE) continue;
		if (k == K_ESC || k == 'q' || k == 3) return;
		if (k == 'L' || k == K_F2) { g_zh = !g_zh; continue; }

		if (k == K_CLICK) {
			int idx = 0;
			switch (hit_test(g_my, g_mx, &idx)) {
			case H_BACK: return;
			case H_BTN:  v.zone = Z_BTN; v.sel = idx; k = K_ENTER; break;
			case H_CHIP: v.zone = Z_TAB; v.tsel = idx;
			             if (v.tab != idx) { v.tab = idx; v.sel = 0; v.bscroll = 0; }
			             continue;
			case H_BODY: v.zone = v.maxscroll ? Z_BODY : Z_TAB; continue;
			default: continue;
			}
		}
		if (k == K_WHEELUP) { if (v.bscroll > 0) v.bscroll--; continue; }
		if (k == K_WHEELDN) { if (v.bscroll < v.maxscroll) v.bscroll++; continue; }

		if (v.zone == Z_BODY) {
			switch (k) {
			case K_UP:    if (v.bscroll > 0) v.bscroll--; else v.zone = Z_BTN; continue;
			case K_DOWN:  if (v.bscroll < v.maxscroll) v.bscroll++; continue;
			case K_PGUP:  v.bscroll -= v.brows; continue;
			case K_PGDN:  v.bscroll += v.brows; continue;
			case K_HOME:  v.bscroll = 0; continue;
			case K_END:   v.bscroll = v.maxscroll; continue;
			case K_ENTER: v.zone = v.na ? Z_BTN : Z_TAB; continue;
			default: continue;
			}
		}

		/* ---- the tab bar ------------------------------------------------
		 * Left and right change the tab and the body under it changes with
		 * them — no Enter, nothing opens. Enter is only for Back and for the
		 * one tab that has an editor behind it. */
		if (v.zone == Z_TAB) {
			int moved = 0;
			switch (k) {
			case K_LEFT:  if (v.tsel > 0) { v.tsel--; moved = 1; } break;
			case K_RIGHT: if (v.tsel < v.ntab) { v.tsel++; moved = 1; } break;
			case K_HOME:  v.tsel = 0; moved = 1; break;
			case K_END:   v.tsel = v.ntab; moved = 1; break;
			case K_TAB:   v.tsel = (v.tsel + 1) % (v.ntab + 1); moved = 1; break;
			case K_DOWN:
				if (v.na) v.zone = Z_BTN;
				else if (v.maxscroll) v.zone = Z_BODY;
				break;
			case K_UP: break;
			default: break;
			}
			if (moved && v.tsel < v.ntab && v.tab != v.tsel) {
				v.tab = v.tsel; v.sel = 0; v.bscroll = 0;
			}
			if (k == K_ENTER || k == ' ') {
				if (v.tsel == v.ntab) return;              /* Back */
				if (v.tabs[v.tsel].kind == TAB_SETTINGS) {
					/* The one tab with an editor rather than a view. Its
					 * body already shows every value; this opens the form
					 * that changes them, and Save & Apply is the install
					 * verb because for every recipe here it is also the
					 * reconfigure path. */
					switch (screen_params(p)) {
					case 2: action_install(p); break;
					case 1: message(S(T_PARAMS), S(T_PARAMSAVED)); break;
					}
					probe_pkg(p);
				} else if (v.na) v.zone = Z_BTN;
			}
			continue;
		}

		switch (k) {
		case K_LEFT:  if (v.na) v.sel = (v.sel - 1 + v.na) % v.na; continue;
		case K_RIGHT: if (v.na) v.sel = (v.sel + 1) % v.na; continue;
		case K_HOME:  v.sel = 0; continue;
		case K_END:   v.sel = v.na ? v.na - 1 : 0; continue;
		case K_DOWN:
			if (!act_step(&v, +1) && v.maxscroll) v.zone = Z_BODY;
			continue;
		case K_UP:    if (!act_step(&v, -1)) v.zone = Z_TAB; continue;
		case K_TAB:   v.zone = Z_TAB; continue;
		}
		if (k != K_ENTER && k != ' ') continue;
		if (!v.na) continue;
		if (v.acts[v.sel].dim) continue;

		switch (v.acts[v.sel].act) {
		case A_DETAILS: screen_details(p); break;
		case A_LOG:     screen_log(p); break;
		case A_DOCS:    screen_docs(p); break;
		case A_STATUS:  screen_status(p); break;
		/* Apply is the install verb, so it goes through the same free-space
		 * question: on a package that is not installed yet, "apply these
		 * settings" and "install this" are the same action. */
		case A_PARAMS:
			switch (screen_params(p)) {
			case 2: action_install(p); break;
			case 1: message(S(T_PARAMS), S(T_PARAMSAVED)); break;
			}
			break;
		case A_INSTALL: action_install(p); break;
		case A_REMOVE: {
			char q[400];
			snprintf(q, sizeof q, S(T_REMOVEQ), pkg_name(p));
			if (confirm(pkg_name(p), q)) screen_progress(p, "uninstall", NULL);
			break;
		}
		case A_START:   screen_progress(p, "start", NULL); break;
		case A_STOP:    screen_progress(p, "stop", NULL); break;
		case A_RESTART: screen_progress(p, "restart", NULL); break;
		case A_BOOT:    screen_progress(p, p->enabled == 1 ? "disable" : "enable", NULL); break;
		case A_BUTTON: {
			char title[256];
			snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, v.acts[v.sel].label);
			/* A verb that only prints goes through the pager on a 20s
			 * deadline, which is right for it and fatal for anything else: a
			 * mysqldump of a real database is killed a third of the way in,
			 * and what the pager then shows is a truncated log of a backup
			 * that did not happen. Anything declared `progress` streams
			 * through the same screen Install uses, with no deadline and a
			 * log behind it. */
			if (v.acts[v.sel].mode == B_CONFIRM) {
				char q[500];
				snprintf(q, sizeof q, S(T_BUTTONQ), v.acts[v.sel].label, pkg_name(p));
				if (confirm(pkg_name(p), q))
					screen_progress(p, v.acts[v.sel].verb, title);
			} else if (v.acts[v.sel].mode == B_PROG) {
				screen_progress(p, v.acts[v.sel].verb, title);
			} else {
				screen_docs_verb(p, v.acts[v.sel].verb, title);
			}
			break;
		}
		}
		v.bscroll = 0;
	}
}

/* --------------------------------------------------------- the home screen
 *
 * A grey toolbar along the top and a grid of cards under it, laid out the way
 * a video site lays out videos — which is the one arrangement anybody who has
 * used a browser can already drive, without being told.
 *
 * Everything you can reach that is not a card lives on that one bar: the
 * categories, the language switch, and the way out. The first version put the
 * last two on the blue root above it, in white on blue, and they were simply
 * not seen — a language switch nobody finds is a program that only has one
 * language. On the bar they are grey-backed controls among other grey-backed
 * controls, and Left and Right walk the whole row.
 *
 * Installed is the first chip rather than a pane of its own. Coming back to
 * see whether things are still up is the common visit, so it is the first
 * thing the cursor reaches; but it is the same kind of thing as every other
 * chip, which costs a whole column of screen less than making it special did.
 *
 * Two zones, and Up from the cards reaches the bar. Up again jumps to Back,
 * so holding Up still walks you out of the program without knowing that `q`
 * exists.
 */
enum { Z_STRIP = 0, Z_GRID };

static int g_zone = Z_GRID;
static int g_chip = 1;                /* the category being shown */
static int g_strip = 1;               /* the cursor's place along the bar */
static int g_card = 0, g_cardrow = 0;
static int g_cat = 0;                 /* the category the current chip names */
static int g_view[MAX_PKGS], g_nview = 0;
/* The search box. Every printable key on this screen lands here, which is
 * what cost `q`, `r` and `L` their shortcuts — F2 is the language now, F3 the
 * view, F5 the refresh, and Esc clears the box before it leaves. Fifty
 * recipes is more than anybody should have to walk past. */
static char g_filter[64] = "";
/* Which body is drawn under the bar. The bar — search, chips, switch — belongs
 * to neither of them, which is the whole reason the switch is cheap. */
enum { V_CARDS = 0, V_LIST };
static int g_vmode = V_CARDS;
static int g_inst[MAX_PKGS], g_ninst = 0;
static char g_msg[256] = "";

/* chip -> category, with two reserved values ahead of the real ones */
#define CHIP_INSTALLED (-2)
#define CHIP_ALL       (-1)
static int g_chipcat[MAX_CATS + 2];
static int g_nchip = 0;

/* The bar is chips, then the language switch, then Back — one cursor over all
 * of it, so there is no separate "now you are among the buttons" mode. */
#define S_LANG  (g_nchip)
#define S_BACK  (g_nchip + 1)
/* The view switch sits on the find row, one below the bar, and is part of
 * the same cursor: a control drawn as a chip that no arrow key can reach is
 * a control lying about what it is. */
#define S_LIST  (g_nchip + 2)
#define S_CARDS (g_nchip + 3)
#define S_LEN   (g_nchip + 4)

/* the bar and the grid, both recomputed every frame so a resize needs no
 * special case. The grid starts below whatever height the bar wrapped to. */
static int SB_row[MAX_CATS + 6], SB_col[MAX_CATS + 6], SB_wid[MAX_CATS + 6];
static int SB_rows = 1;
/* which row of the bar the search box is on, and how wide it may be */
static int SB_findrow = 0, SB_findw = 40;
static int G_cols, G_cardw, G_coverh, G_cardh, G_pitch, G_top, G_rows, G_chiprow;

/* Case-insensitive substring, byte-wise — which is also correct for the
 * Chinese fields, because a UTF-8 substring of a UTF-8 string is a substring
 * of its bytes. No fuzzy matching: fzf's subsequence match is lovely and is a
 * thing to get wrong quietly, and `ng` finding `mongodb` is a surprise on a
 * list somebody is about to install from. */
static int ci_find(const char *hay, const char *needle)
{
	if (!*needle) return 1;
	for (const char *h = hay; *h; h++) {
		const char *a = h, *b = needle;
		while (*a && *b && tolower((unsigned char)*a) == tolower((unsigned char)*b)) { a++; b++; }
		if (!*b) return 1;
	}
	return 0;
}

/* Both names and both summaries, not just the id: somebody reading the
 * Chinese cards should find nginx by typing 网页, and somebody who wants a
 * cache should find `cdn` by a word that appears only in its summary. */
static int pkg_matches(const Pkg *p, const char *needle)
{
	return ci_find(p->id, needle) || ci_find(p->name, needle) ||
	       ci_find(p->name_zh, needle) || ci_find(p->summary, needle) ||
	       ci_find(p->summary_zh, needle);
}

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

/* An empty category is not shown at all — a source that ships no databases
 * should not put an empty Databases on the bar. Which means the bar changes
 * shape as things are installed, so the cursor is kept on the category it was
 * on rather than on the index it was at. */
static void rebuild_chips(void)
{
	int keep = g_nchip ? g_chipcat[g_chip] : CHIP_ALL;
	g_nchip = 0;
	g_chipcat[g_nchip++] = CHIP_INSTALLED;
	g_chipcat[g_nchip++] = CHIP_ALL;
	for (int i = 0; i < g_ncat && g_nchip < MAX_CATS + 2; i++)
		if (cat_count(i)) g_chipcat[g_nchip++] = i;

	g_chip = 1;
	for (int i = 0; i < g_nchip; i++) if (g_chipcat[i] == keep) { g_chip = i; break; }
	if (g_chip >= g_nchip) g_chip = g_nchip - 1;
	if (g_chip < 0) g_chip = 0;
	if (g_chipcat[g_chip] >= 0) g_cat = g_chipcat[g_chip];
	if (g_strip >= S_LEN) g_strip = S_LEN - 1;
	if (g_strip < 0) g_strip = 0;
}

static void chip_label(int i, char *out, size_t cap)
{
	int c = g_chipcat[i];
	if (c == CHIP_INSTALLED) snprintf(out, cap, "%s %d", S(T_INSTALLP), g_ninst);
	else if (c == CHIP_ALL)  snprintf(out, cap, "%s", S(T_ALL));
	else                     snprintf(out, cap, "%s", S(g_cats[c].label));
}

static void rebuild_lists(void)
{
	g_ninst = 0;
	for (int i = 0; i < g_npkg; i++)
		if (pkg_installed(&g_pkg[i])) g_inst[g_ninst++] = i;

	rebuild_chips();

	int c = g_chipcat[g_chip];
	g_nview = 0;
	for (int i = 0; i < g_npkg; i++) {
		Pkg *p = &g_pkg[i];
		if (!pkg_matches(p, g_filter)) continue;
		if (c == CHIP_INSTALLED) { if (pkg_installed(p)) g_view[g_nview++] = i; }
		else if (c == CHIP_ALL)  g_view[g_nview++] = i;
		else if (pkg_in_cat(p, g_cats[c].id)) g_view[g_nview++] = i;
	}

	if (g_card >= g_nview) g_card = g_nview ? g_nview - 1 : 0;
	if (g_card < 0) g_card = 0;
}

/* Three columns while a card can still be 28 columns wide, then two, then one.
 * The card never shrinks below that: a narrow terminal shows fewer of them at
 * a time, it does not show unreadable ones. */
static void card_layout(void)
{
	/* A card is a window with a shadow two columns wide, and the shadow of
	 * the last card in a row has to land on screen — hence the 3 held back
	 * on the right, and the 3-column gap: two for the shadow, one of blue so
	 * two cards never look joined. */
	int avail = g_w - 4;
	G_cols = 3;
	while (G_cols > 1 && (avail - 3 * (G_cols - 1)) / G_cols < 28) G_cols--;
	G_cardw = (avail - 3 * (G_cols - 1)) / G_cols;
	if (G_cardw < 14) G_cardw = 14;
	if (G_cardw > avail) G_cardw = avail;

	G_chiprow = (g_h >= 18) ? 3 : 2;
	G_top = G_chiprow + SB_rows + 2;          /* the bar, its shadow, a blank */
	int space = (g_h - 1) - G_top;            /* the help line owns the last row */
	if (space < 5) { G_top = G_chiprow + SB_rows; space = (g_h - 1) - G_top; }
	if (space < 4) space = 4;

	/* The list is one column of one-row items, which is not a special case
	 * for anything below it: the cursor arithmetic, the viewport, PgUp and the
	 * wheel are all written in terms of G_cols and G_rows, so saying "one
	 * column" here is the whole of the navigation for the other view. */
	if (g_vmode == V_LIST) {
		G_cols = 1;
		G_cardw = g_w - 2;
		G_rows = space - 2;              /* the window's own two border rows */
		if (G_rows < 1) G_rows = 1;
		G_coverh = 0; G_cardh = 1; G_pitch = 1;
		return;
	}

	/* The cover is what gives when the window is short, because it is the
	 * part carrying no words. */
	G_coverh = 3;
	while (G_coverh > 1 && space < G_coverh + 6) G_coverh--;
	G_cardh = G_coverh + 6;
	G_pitch = G_cardh + 1;
	G_rows = (space + 1) / G_pitch;           /* the last row needs no gap */
	if (G_rows < 1) G_rows = 1;
}

/* The language switch shows both languages side by side with the one you are
 * in lit, rather than naming the one you would get. A button reading 中文 only
 * tells you what it does if you already know; EN | 中文 is a switch, and looks
 * like one whichever language you can read. It is also a fixed width, so the
 * bar does not reflow when you press it. */
static int lang_width(void) { return 2 + 2 + 3 + 4 + 1; }   /* " EN | 中文 " */

static void draw_lang(int row, int col, int focused)
{
	int base = focused ? P_CURSOR : P_CHIP;
	int on   = focused ? P_CURSOR : P_CHIPSEL;
	int off  = focused ? P_CURSOR : P_BTNDIM;
	int x = col;
	gput(row, x++, " ", base, 1);
	gput(row, x, "EN", g_zh ? off : on, 2);        x += 2;
	gput(row, x, " ", base, 1);                    x += 1;
	gput(row, x, MK_DOT, base, 1);                 x += 1;
	gput(row, x, " ", base, 1);                    x += 1;
	gput(row, x, "中文", g_zh ? on : off, 4);      x += 4;
	gput(row, x, " ", base, 1);
	if (focused) cursor_sweep(row, col, lang_width(), P_CURSOR, P_CURSORHOT);
	hit_add(H_LANG, 0, row, col, 1, lang_width());
}

/* Where everything on the bar ended up. The bar wraps rather than scrolling
 * sideways under a `›`: a category hidden off the right hand edge cannot be
 * clicked, and a control you can only reach by walking the keyboard onto it is
 * not a control on a toolbar. Rows are cheap; a hidden category is not. */
static void strip_layout(void)
{
	/* Row 0 is the machine's own controls and nothing else — Back in the
	 * corner it has always had, then the language, then the two views, then
	 * whatever is left over for the search box. Rows 1 and down are the
	 * categories, which is where the cursor starts and what somebody is
	 * usually here to change. Putting the globals together and the categories
	 * together is the whole of this layout. */
	char backl[64], lst[48], crd[48];
	snprintf(backl, sizeof backl, " %s ", S(T_BACK));
	snprintf(lst, sizeof lst, " %s %s ", GL_LIST,  S(T_VLIST));
	snprintf(crd, sizeof crd, " %s %s ", GL_CARDS, S(T_VCARDS));
	int backw = u8width(backl), langw = lang_width();
	int wl = u8width(lst), wc = u8width(crd);

	int x = g_w - backw;
	SB_row[S_BACK]  = 0; SB_col[S_BACK]  = x;  SB_wid[S_BACK]  = backw;
	x -= langw + 1;
	SB_row[S_LANG]  = 0; SB_col[S_LANG]  = x;  SB_wid[S_LANG]  = langw;
	x -= wc + 1;
	SB_row[S_CARDS] = 0; SB_col[S_CARDS] = x;  SB_wid[S_CARDS] = wc;
	x -= wl + 1;
	SB_row[S_LIST]  = 0; SB_col[S_LIST]  = x;  SB_wid[S_LIST]  = wl;

	/* Too narrow to put the search box beside them: it gets a row of its own
	 * rather than being dropped. A search box that is only there on a wide
	 * terminal is a search box nobody learns about. */
	SB_findw = x - 2;
	SB_findrow = (SB_findw >= 14) ? 0 : 1;
	if (SB_findrow) SB_findw = g_w - 2;

	int row = SB_findrow + 1;
	x = 1;
	for (int i = 0; i < g_nchip; i++) {
		char lab[160];
		chip_label(i, lab, sizeof lab);
		int w = u8width(lab) + 2;
		if (x > 1 && x + w > g_w - 1) { row++; x = 1; }
		SB_row[i] = row;
		SB_col[i] = x;
		SB_wid[i] = w;
		x += w + 1;
	}
	SB_rows = row + 1;
}

/* The bar: a grey strip the width of the screen, as many rows as it takes,
 * with a shadow under it — the same object as every other window here. */
/* The row under the bar: what has been typed, how many recipes it left, and
 * which of the two bodies is showing. One row, and always there — §5.1.
 *
 * The switch names both views with the current one lit, rather than naming the
 * one you are not in. A control that says "Cards" while you are looking at a
 * list is a coin flip every time somebody reads it: is that what this is, or
 * what I will get? Both, and the question does not arise. */
/* Which body somebody last chose, remembered where the other things nobody
 * edits are remembered. A person who prefers cards on an eighty-column
 * terminal should have to say so once, not once a session — and a person who
 * never touches the switch should never be shown a screen they did not ask
 * for, which is why the first answer comes from the terminal's own size. */
static void view_save(void)
{
	char path[600];
	snprintf(path, sizeof path, "%s/view", state_dir());
	mkdir_p(state_dir());
	FILE *f = fopen(path, "w");
	if (!f) return;                       /* a read-only /var is not an error here */
	fprintf(f, "%s\n", g_vmode == V_LIST ? "list" : "cards");
	fclose(f);
}

static void view_load(void)
{
	char path[600], buf[32];
	snprintf(path, sizeof path, "%s/view", state_dir());
	FILE *f = fopen(path, "r");
	if (f) {
		if (fgets(buf, sizeof buf, f)) {
			g_vmode = !strncmp(buf, "list", 4) ? V_LIST : V_CARDS;
			fclose(f);
			return;
		}
		fclose(f);
	}
	/* Never asked: pick by what the terminal can actually hold. A screen with
	 * room for twenty cards gets the grid it was designed for; a screen that
	 * would show two gets the list. */
	g_vmode = (g_w >= 100 && g_h >= 30) ? V_CARDS : V_LIST;
}

static void draw_find(void)
{
	/* Painted over the bar draw_strip has already filled, on whichever of its
	 * rows the layout gave the box. No fill of its own: two things filling the
	 * same row is how one of them ends up drawing over the other's cursor. */
	int y = G_chiprow + SB_findrow;
	char lst[48], crd[48], cnt[32];
	snprintf(lst, sizeof lst, " %s %s ", GL_LIST,  S(T_VLIST));
	snprintf(crd, sizeof crd, " %s %s ", GL_CARDS, S(T_VCARDS));
	snprintf(cnt, sizeof cnt, "%d / %d", g_nview, g_npkg);

	int curl = (g_zone == Z_STRIP && g_strip == S_LIST);
	int curc = (g_zone == Z_STRIP && g_strip == S_CARDS);
	int xl = SB_col[S_LIST], xc = SB_col[S_CARDS];
	gput(0 + G_chiprow, xl, lst, curl ? P_CURSOR : (g_vmode == V_LIST  ? P_CHIPSEL : P_CHIP), SB_wid[S_LIST]);
	gput(0 + G_chiprow, xc, crd, curc ? P_CURSOR : (g_vmode == V_CARDS ? P_CHIPSEL : P_CHIP), SB_wid[S_CARDS]);
	if (curl) cursor_sweep(G_chiprow, xl, SB_wid[S_LIST],  P_CURSOR, P_CURSORHOT);
	if (curc) cursor_sweep(G_chiprow, xc, SB_wid[S_CARDS], P_CURSOR, P_CURSORHOT);
	hit_add(H_VIEW, V_LIST,  G_chiprow, xl, 1, SB_wid[S_LIST]);
	hit_add(H_VIEW, V_CARDS, G_chiprow, xc, 1, SB_wid[S_CARDS]);

	int wn = u8width(cnt), right = SB_findrow ? g_w - 1 : xl;
	int xn = right - wn - 2;
	if (xn > 14) gput(y, xn, cnt, P_CHIP, wn);
	else xn = right;

	char left[220];
	if (g_filter[0]) snprintf(left, sizeof left, " %s  %s_", S(T_FIND), g_filter);
	else             snprintf(left, sizeof left, " %s  %s", S(T_FIND), S(T_FINDHINT));
	gput(y, 1, left, g_filter[0] ? P_CHIPSEL : P_ABSENT, xn - 2);
	hit_add(H_FIND, 0, y, 1, 1, xn - 2);
}

static void draw_strip(void)
{
	int y = G_chiprow;
	for (int r = 0; r < SB_rows; r++) gfill(y + r, 0, g_w, " ", P_CHIP);
	gfill(y + SB_rows, 2, g_w - 2, " ", P_SHADOW);

	for (int i = 0; i < g_nchip; i++) {
		char lab[160], pill[168];
		chip_label(i, lab, sizeof lab);
		snprintf(pill, sizeof pill, " %s ", lab);
		int cur = (g_zone == Z_STRIP && g_strip == i);
		int ry = y + SB_row[i], rx = SB_col[i], w = SB_wid[i];
		gput(ry, rx, pill, cur ? P_CURSOR : (i == g_chip ? P_CHIPSEL : P_CHIP), w);
		if (cur) cursor_sweep(ry, rx, w, P_CURSOR, P_CURSORHOT);
		hit_add(H_CHIP, i, ry, rx, 1, w);
	}

	draw_lang(y + SB_row[S_LANG], SB_col[S_LANG],
	          g_zone == Z_STRIP && g_strip == S_LANG);

	char backl[64];
	snprintf(backl, sizeof backl, " %s ", S(T_BACK));
	int bcur = (g_zone == Z_STRIP && g_strip == S_BACK);
	int bx = SB_col[S_BACK], bw = SB_wid[S_BACK];
	gput(y, bx, backl, bcur ? P_BACKCUR : P_BACK, bw);
	if (bcur) cursor_sweep(y, bx, bw, P_BACKCUR, P_BACKHOT);
	hit_add(H_BACK, 0, y, bx, 1, bw);
}

/* Move the cursor along the bar. Landing on a category selects it, because a
 * category is not a thing you do anything to — and the grid then goes back to
 * its first card, since landing on card 14 of a category you have only just
 * arrived in is disorienting and there is nothing there you were looking at. */
static void strip_to(int i)
{
	if (i < 0) i = 0;
	if (i >= S_LEN) i = S_LEN - 1;
	g_strip = i;
	if (i >= g_nchip || i == g_chip) return;
	g_chip = i;
	if (g_chipcat[i] >= 0) g_cat = g_chipcat[i];
	g_card = 0;
	g_cardrow = 0;
	rebuild_lists();
}

/* Up and down between the bar's rows, landing on whichever control starts
 * nearest the column already held. Returns 0 when there is no row that way. */
static int strip_step(int dir)
{
	int row = SB_row[g_strip] + dir;
	if (row < 0 || row >= SB_rows) return 0;
	int best = -1, bestd = 1 << 30;
	for (int i = 0; i < S_LEN; i++) {
		if (SB_row[i] != row) continue;
		int d = SB_col[i] - SB_col[g_strip];
		if (d < 0) d = -d;
		if (d < bestd) { bestd = d; best = i; }
	}
	if (best < 0) return 0;
	strip_to(best);
	return 1;
}

/* One card: a cover with the id across it and the disk footprint in the
 * corner, then the name, what it is for, and where it stands.
 *
 * A card is a window, not a region of the page — grey, bordered, with a black
 * shadow down and to the right, the same object the dialogs in here have
 * always been. The first version drew them straight onto the blue root, and
 * everything written on them was then light text on a mid blue: the summary
 * line in particular was barely there. Black on light grey is the strongest
 * pairing sixteen colours can make, and it is the reason this program looked
 * legible everywhere else and did not look legible here.
 *
 * Under the cursor the whole frame goes cyan and doubles its rule, because a
 * terminal showing this over a monochrome ssh session still has to say which
 * card is which.
 */
static void draw_card(int row, int col, Pkg *p, int focused)
{
	int inner = G_cardw - 2;
	int b = focused ? P_CARDBSEL : P_CARDB;
	const char *tl = focused ? B2_TL : BX_TL, *tr = focused ? B2_TR : BX_TR;
	const char *bl = focused ? B2_BL : BX_BL, *br = focused ? B2_BR : BX_BR;
	const char *hz = focused ? B2_H  : BX_H,  *vt = focused ? B2_V  : BX_V;
	const char *lt = focused ? B2_LT : BX_LT, *rt = focused ? B2_RT : BX_RT;

	/* the shadow first, so the card and its border land on top of it */
	for (int r = row + 1; r <= row + G_cardh; r++)
		gfill(r, col + G_cardw, 2, " ", P_SHADOW);
	gfill(row + G_cardh, col + 2, G_cardw - 2, " ", P_SHADOW);

	gput(row, col, tl, b, 1);
	gfill(row, col + 1, inner, hz, b);
	gput(row, col + inner + 1, tr, b, 1);

	for (int r = 1; r <= G_coverh; r++) {
		gput(row + r, col, vt, b, 1);
		gput(row + r, col + inner + 1, vt, b, 1);
	}
	draw_cover(row + 1, col + 1, inner, G_coverh, p, p->disk[0] ? p->disk : NULL);

	int sy = row + G_coverh + 1;
	gput(sy, col, lt, b, 1);
	gfill(sy, col + 1, inner, BX_H, b);
	gput(sy, col + inner + 1, rt, b, 1);

	for (int r = 1; r <= 3; r++) {
		gput(sy + r, col, vt, b, 1);
		gfill(sy + r, col + 1, inner, " ", P_WIN);
		gput(sy + r, col + inner + 1, vt, b, 1);
	}

	int tw = inner - 2, tcol = col + 2;
	char buf[700];
	u8ellipsis(buf, sizeof buf, pkg_name(p), tw);
	gput(sy + 1, tcol, buf, P_WIN, tw);
	u8ellipsis(buf, sizeof buf, pkg_summary(p), tw);
	gput(sy + 2, tcol, buf, P_DIM, tw);

	/* The last line answers the question being asked at that moment: while it
	 * is not installed, what it will cost; once it is, which version is
	 * actually there. The disk figure is not repeated — it is on the cover. */
	char facts[320], sep[8];
	size_t fn = 0;
	facts[0] = '\0';
	snprintf(sep, sizeof sep, " %s ", MK_DOT);
	if (pkg_installed(p) && p->detail[0])
		fn += (size_t)snprintf(facts + fn, sizeof facts - fn, "%s", p->detail);
	else if (p->memory[0] && p->mem_bytes > 0)
		fn += (size_t)snprintf(facts + fn, sizeof facts - fn, "%s %s", S(T_RAM), p->memory);
	if (p->ports[0] && fn < sizeof facts - 32)
		snprintf(facts + fn, sizeof facts - fn, "%s%s %s",
		         fn ? sep : "", S(T_PORT), p->ports);

	char meta[700];
	snprintf(meta, sizeof meta, "%s %s%s%s", status_mark(p), S(*status_label(p)),
	         facts[0] ? sep : "", facts);
	u8ellipsis(buf, sizeof buf, meta, tw);
	int ds = 0, ms = 0;
	gput(sy + 3, tcol, buf,
	     resource_short(p, &ds, &ms) ? P_WARN : status_attr(p), tw);

	int by = sy + 4;
	gput(by, col, bl, b, 1);
	gfill(by, col + 1, inner, hz, b);
	gput(by, col + inner + 1, br, b, 1);

	/* The band runs along the top and bottom rules of the card under the
	 * cursor. Sweeping the whole rectangle would mean chasing it round four
	 * sides to work out where it is; two parallel runs read as one card
	 * lighting up. */
	if (focused) {
		cursor_sweep(row, col, G_cardw, P_CARDBSEL, P_CARDBHOT);
		cursor_sweep(by, col, G_cardw, P_CARDBSEL, P_CARDBHOT);
	}
}

/* The dot in front of a row, and what colour it is. The words "running" and
 * "not installed" cost nine columns and twelve to say what one cell says. */
static const char *state_mark(const Pkg *p, int *attr)
{
	switch (p->status) {
	case ST_RUNNING:   *attr = P_RUN;     return MK_RUN;
	case ST_INSTALLED: *attr = P_RUN;     return MK_RUN;
	case ST_STOPPED:   *attr = P_STOPPED; return MK_STOP;
	case ST_BROKEN:    *attr = P_ERR;     return MK_ERR;
	default:           *attr = P_ABSENT;  return MK_ABSENT;
	}
}

/* The list body: every match on the left at one row apiece, and whichever the
 * cursor is on opened on the right. The bar above it is the same bar the grid
 * has — §5.1 — so the search, the category and the switch are not drawn here
 * and do not know which body they are above. */
static void draw_list(void)
{
	int top = G_top, h = (g_h - 1) - top;
	if (h < 4 || !g_nview) return;
	int w = g_w - 2;
	int lw = w * 2 / 5;
	if (lw < 18) lw = 18;
	if (lw > 34) lw = 34;
	int detail = (w - lw > 28);
	if (!detail) lw = w - 2;

	win_box(top, 0, w, h, NULL);
	if (detail)
		for (int r = 1; r < h - 1; r++) gput(top + r, 1 + lw, BX_V, P_BORDER, 1);

	for (int r = 0; r < G_rows && g_cardrow + r < g_nview; r++) {
		int i = g_cardrow + r, y = top + 1 + r;
		Pkg *p = &g_pkg[g_view[i]];
		int cur = (g_zone == Z_GRID && i == g_card);
		int a = cur ? P_CURSOR : P_WIN, sa;
		const char *mk = state_mark(p, &sa);
		gfill(y, 1, lw, " ", a);
		gput(y, 2, mk, cur ? P_CURSOR : sa, 1);

		/* The id rather than the name: it is what somebody just typed into the
		 * box, what the command line takes, and the one label that does not
		 * change when the language does. The name is on the right. */
		int dw = p->disk[0] ? u8width(p->disk) : 0;
		int room = lw - 4 - (dw ? dw + 2 : 0);
		char nm[128];
		u8ellipsis(nm, sizeof nm, p->id, room);
		gput(y, 4, nm, a, room);
		if (dw) gput(y, 1 + lw - dw - 1, p->disk, a, dw);
		if (cur) cursor_sweep(y, 1, lw, P_CURSOR, P_CURSORHOT);
		hit_add(H_CARD, i, y, 1, 1, lw);
	}
	scrollbar(top + 1, w - 1, h - 2, g_cardrow, G_rows, g_nview,
	          P_SBTHUMBW, P_SBTRACKW);

	if (!detail) return;

	Pkg *p = &g_pkg[g_view[g_card]];
	/* one column back from the frame, and one more for the scrollbar that is
	 * painted on it — text that touches a scrollbar reads as text that was cut */
	int x = lw + 3, dw2 = w - x - 2, y = top + 1, last = top + h - 2;
	if (dw2 < 4) return;

	char nm[160];
	u8ellipsis(nm, sizeof nm, pkg_name(p), dw2 - 14);
	gput(y, x, nm, P_TITLE, dw2);
	{
		int sa; const char *mk = state_mark(p, &sa);
		char st[64];
		snprintf(st, sizeof st, "%s %s", mk, S(*status_label(p)));
		int sw = u8width(st);
		if (sw < dw2 - u8width(nm) - 2) gput(y, x + dw2 - sw, st, sa, sw);
	}
	y += 2;

	char lab[6][32], val[6][64];
	int nf = detail_facts(p, lab, val);
	for (int i = 0; i < nf && y <= last; i++) {
		char one[128];
		snprintf(one, sizeof one, "%-9s %s", lab[i], val[i]);
		char cut[160];
		u8ellipsis(cut, sizeof cut, one, dw2);
		gput(y++, x, cut, P_WIN, dw2);
	}

	char lines[8][512];
	if (y < last) y++;
	int n = u8wrap(pkg_summary(p), dw2, lines, 4);
	for (int i = 0; i < n && y <= last; i++) gput(y++, x, lines[i], P_WIN, dw2);

	const char *inc = pkg_includes(p);
	if (inc[0] && y + 1 <= last) {
		y++;
		char head[600];
		snprintf(head, sizeof head, "%s  %s", S(T_INCLUDES), inc);
		n = u8wrap(head, dw2, lines, 4);
		for (int i = 0; i < n && y <= last; i++) gput(y++, x, lines[i], P_WIN, dw2);
	}
}

static void render_home(void)
{
	grid_size(g_w, g_h);
	hit_clear();
	draw_root();
	strip_layout();          /* the grid starts below however tall it came out */
	card_layout();

	if (g_npkg == 0) {
		gput(G_chiprow, 2, S(T_NORECIPE), P_WARNB, g_w - 4);
		help_line_l(&T_HELPHOME);
		return;
	}

	draw_strip();
	draw_find();

	/* Follow the cursor with the viewport, then pin the viewport inside the
	 * list — in that order, so a shrinking list cannot leave it past the end. */
	int nrows = (g_nview + G_cols - 1) / G_cols;
	int cur = g_card / G_cols;
	if (cur < g_cardrow) g_cardrow = cur;
	if (cur >= g_cardrow + G_rows) g_cardrow = cur - G_rows + 1;
	if (g_cardrow > nrows - G_rows) g_cardrow = nrows - G_rows;
	if (g_cardrow < 0) g_cardrow = 0;

	if (g_vmode == V_LIST) {
		draw_list();
		if (!g_nview) {
			const L *e = g_filter[0] ? &T_NOMATCH
			           : g_chipcat[g_chip] == CHIP_INSTALLED ? &T_NOINST : &T_EMPTY;
			gput(G_top, 2, S(*e), P_ABSENTB, g_w - 4);
		}
		help_line_l(&T_HELPHOME);
		if (g_msg[0]) {
			char m[300];
			snprintf(m, sizeof m, " %s ", g_msg);
			int mw = u8width(m);
			if (mw > g_w - 4) mw = g_w - 4;
			gput(g_h - 1, g_w - 1 - mw, m, P_HELP, mw);
		}
		return;
	}

	g_clip_top = G_top; g_clip_bot = g_h - 2;
	for (int r = 0; r < G_rows; r++) {
		for (int c = 0; c < G_cols; c++) {
			int i = (g_cardrow + r) * G_cols + c;
			if (i >= g_nview) break;
			int row = G_top + r * G_pitch, col = 1 + c * (G_cardw + 3);
			draw_card(row, col, &g_pkg[g_view[i]], g_zone == Z_GRID && i == g_card);
			hit_add(H_CARD, i, row, col, G_cardh, G_cardw);
		}
	}
	g_clip_top = g_clip_bot = -1;

	/* measured in rows of cards, which is what the wheel and the arrows move
	 * by — a thumb sized in screen rows would be a sliver against a pitch of
	 * ten and would say nothing */
	scrollbar(G_top, g_w - 1, G_rows * G_pitch - 1, g_cardrow, G_rows, nrows,
	          P_SBTHUMB, P_SBTRACK);

	if (!g_nview) {
		const L *e = g_filter[0] ? &T_NOMATCH
		           : g_chipcat[g_chip] == CHIP_INSTALLED ? &T_NOINST : &T_EMPTY;
		gput(G_top, 2, S(*e), P_ABSENTB, g_w - 4);
	}

	help_line_l(&T_HELPHOME);
	if (g_msg[0]) {          /* after the help line, which fills its row */
		char m[300];
		snprintf(m, sizeof m, " %s ", g_msg);
		int mw = u8width(m);
		if (mw > g_w - 4) mw = g_w - 4;
		gput(g_h - 1, g_w - 1 - mw, m, P_HELP, mw);
	}
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
	view_load();
	rebuild_lists();
	/* Something is already installed: that is what this visit is probably
	 * about, so start on that chip rather than on the whole catalogue. */
	if (g_ninst) strip_to(0);

	for (;;) {
		term_measure();
		rebuild_lists();
		render_home();
		grid_flush();

		int k = read_key();
		if (k == K_NONE || k == K_RESIZE || k == K_TIMEOUT) continue;

		/* The letters belong to the search box now, so the three things they
		 * used to do moved to keys a search box will never be given. */
		if (k == 3) { term_cooked(); return; }              /* ^C */
		if (k == K_F2) { g_zh = !g_zh; continue; }
		if (k == K_F3) { g_vmode = (g_vmode == V_CARDS) ? V_LIST : V_CARDS;
		                 view_save(); g_cardrow = 0; continue; }
		if (k == K_F5 || k == 18) {                          /* F5 or ^R */
			copy_str(g_msg, sizeof g_msg, g_zh ? "正在刷新…" : "refreshing…");
			render_home(); grid_flush();
			probe_all(1);
			g_msg[0] = '\0';
			continue;
		}

		/* Esc empties the box before it leaves, so the way out is the same
		 * key twice from anywhere rather than a key somebody has to know. */
		if (k == K_ESC) {
			if (g_filter[0]) { g_filter[0] = '\0'; g_card = 0; g_cardrow = 0; continue; }
			term_cooked(); return;
		}

		if (k == K_CLICK) {
			int idx = 0;
			switch (hit_test(g_my, g_mx, &idx)) {
			case H_BACK: term_cooked(); return;
			case H_LANG: g_zh = !g_zh; g_zone = Z_STRIP; g_strip = S_LANG; continue;
			case H_CHIP: g_zone = Z_STRIP; strip_to(idx); continue;
			case H_VIEW: g_vmode = idx; view_save(); g_cardrow = 0; continue;
			case H_FIND: continue;   /* the box is always live; nothing to focus */
			/* A card opens on a single click, anywhere on it, the way a
			 * thumbnail does. Moving the cursor there first would be a
			 * second gesture for something already pointed at. */
			case H_CARD:
				g_zone = Z_GRID; g_card = idx; g_msg[0] = '\0';
				screen_app(&g_pkg[g_view[idx]]);
				continue;
			default: continue;
			}
		}
		/* The wheel moves the cursor a row at a time, not the viewport on its
		 * own. The viewport is pinned to the cursor every frame — scrolling it
		 * by itself was undone before it could be drawn, which is why the
		 * wheel appeared to do nothing at all here. */
		if (k == K_WHEELUP) {
			g_zone = Z_GRID;
			if (g_card >= G_cols) g_card -= G_cols;
			else if (g_cardrow > 0) g_cardrow--;
			continue;
		}
		if (k == K_WHEELDN) {
			g_zone = Z_GRID;
			if (g_card + G_cols < g_nview) g_card += G_cols;
			else if (g_nview) g_card = g_nview - 1;
			continue;
		}

		/* Every printable byte goes in the box, wherever the cursor is —
		 * including the bytes of a Chinese character, which arrive one at a
		 * time and reassemble in the buffer. This is the whole design: the
		 * fastest way to find one of fifty is the one somebody falls into
		 * without being told it exists. */
		if (k >= 32 && k < 256 && k != 127) {
			size_t n = strlen(g_filter);
			if (n < sizeof g_filter - 2) { g_filter[n] = (char)k; g_filter[n+1] = '\0'; }
			g_card = 0; g_cardrow = 0; g_msg[0] = '\0';
			continue;
		}
		if (k == K_BACK) {
			size_t n = strlen(g_filter);
			while (n && ((unsigned char)g_filter[n-1] & 0xC0) == 0x80) n--;
			if (n) n--;
			g_filter[n] = '\0';
			g_card = 0; g_cardrow = 0;
			continue;
		}

		switch (g_zone) {
		case Z_STRIP:
			switch (k) {
			case K_LEFT:  strip_to(g_strip - 1); break;
			case K_RIGHT: strip_to(g_strip + 1); break;
			case K_HOME:  strip_to(0); break;
			case K_END:   strip_to(S_BACK); break;
			/* Up a row of the bar if there is one, and off the top of it to
			 * the way out — so holding Up from a card still walks out of the
			 * program however many rows the bar wrapped onto. */
			case K_UP:    if (!strip_step(-1)) strip_to(S_BACK); break;
			case K_TAB:   g_zone = Z_GRID; break;
			case K_DOWN:
				if (strip_step(+1)) break;
				if (g_nview) g_zone = Z_GRID;
				break;
			case K_ENTER:
				if (g_strip == S_BACK) { term_cooked(); return; }
				if (g_strip == S_LANG) { g_zh = !g_zh; break; }
				if (g_strip == S_LIST || g_strip == S_CARDS) {
					g_vmode = (g_strip == S_LIST) ? V_LIST : V_CARDS;
					view_save(); g_cardrow = 0; break;
				}
				if (g_nview) g_zone = Z_GRID;
				break;
			}
			break;

		default:
			switch (k) {
			case K_LEFT:  if (g_card > 0) g_card--; break;
			case K_RIGHT: if (g_card < g_nview - 1) g_card++; break;
			case K_UP:
				if (g_card >= G_cols) g_card -= G_cols;
				else { g_zone = Z_STRIP; g_strip = g_chip; }
				break;
			case K_DOWN:
				if (g_card + G_cols < g_nview) g_card += G_cols;
				else if (g_nview) g_card = g_nview - 1;
				break;
			case K_PGUP:
				g_card -= G_cols * G_rows;
				if (g_card < 0) g_card = 0;
				break;
			case K_PGDN:
				g_card += G_cols * G_rows;
				if (g_card >= g_nview) g_card = g_nview ? g_nview - 1 : 0;
				break;
			case K_HOME: g_card = 0; break;
			case K_END:  g_card = g_nview ? g_nview - 1 : 0; break;
			case K_TAB:  g_zone = Z_STRIP; g_strip = g_chip; break;
			case K_ENTER:
				g_msg[0] = '\0';
				if (g_nview) screen_app(&g_pkg[g_view[g_card]]);
				break;
			}
			break;
		}
		if (g_card < 0) g_card = 0;
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

/* Defined further down, after the domain socket plumbing (hqnode_sock_call,
 * domain_reply) it needs — cli_run is defined ahead of all of that, so this
 * is a forward declaration, not a second definition. */
static void offer_domain_prompt(void);

static int cli_run(const char *verb, int argc, char **argv)
{
	int rc = 0;
	int any_installed = 0;
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
		} else if (!strcmp(verb, "install")) {
			any_installed = 1;
		}
	}
	// One offer per `install` call, not one per package: a tenant installing
	// lnmp and wordpress together wants one domain pointed at the whole
	// stack, not to be asked three times. Only on a real terminal, so a
	// scripted `ssh host app-setup install nginx` never blocks on stdin
	// waiting for input that will never come.
	if (any_installed && isatty(STDIN_FILENO) && isatty(STDOUT_FILENO)) {
		offer_domain_prompt();
	}
	return rc;
}

/* `sshcmd` and `remote` exist to be captured — `SSH=$(app-setup sshcmd
 * store-rsync)` — so neither may go through run_stream, which tees into a log
 * and frames what it prints. Straight fork/exec with stdout inherited, exactly
 * one store, and an optional folder passed through to the recipe. */
static int cli_print_verb(const char *verb, int argc, char **argv)
{
	if (argc < 1) {
		fprintf(stderr, "app-setup: %s needs a store id, e.g. store-rsync\n", verb);
		return 2;
	}
	Pkg *p = find_pkg(argv[0]);
	if (!p) { fprintf(stderr, "app-setup: no such software: %s\n", argv[0]); return 1; }
	g_env_pkg = p;
	pid_t pid = fork();
	if (pid < 0) { perror("fork"); g_env_pkg = NULL; return 1; }
	if (pid == 0) {
		child_env();
		exec_recipe_arg(p->path, verb, argc > 1 ? argv[1] : NULL);
	}
	int status = 0;
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR) { }
	g_env_pkg = NULL;
	return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
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

/* Is /data a disk of its own, or just a directory on the root filesystem?
 *
 * A reinstall replaces the container's root filesystem and keeps /data — but
 * only a container that was given a data disk *has* one, and without it /data
 * is an ordinary directory that dies with everything else while looking
 * exactly the same from in here. That is the question the recipes ask before
 * deciding where to put a database, so `doctor` answers it too: it is the one
 * fact about this machine that decides whether anything installed survives.
 *
 * Field 5 of a mountinfo line is the mount point. Reading it rather than
 * stat()ing because a bind mount of the same filesystem shares st_dev with /,
 * and a bind is exactly what /data is. */
static const char *data_disk_line(void)
{
	FILE *f = fopen("/proc/self/mountinfo", "r");
	if (!f) return "unknown — no /proc/self/mountinfo to read";
	char line[4096];
	int found = 0;
	while (!found && fgets(line, sizeof line, f)) {
		char *p = line;
		for (int i = 0; i < 4 && p; i++) p = strchr(p + 1, ' ');
		if (!p) continue;
		p++;
		char *end = strchr(p, ' ');
		if (!end) continue;
		*end = '\0';
		if (!strcmp(p, "/data")) found = 1;
	}
	fclose(f);
	if (found) return "yes — /data survives a reinstall, and is where databases go";
	struct stat st;
	if (stat("/data", &st) == 0)
		return "NO — /data is a plain directory here; a reinstall takes it";
	return "no — this container has no /data; a reinstall takes everything";
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
	printf("data disk   %s\n", data_disk_line());
	printf("root        %s\n", geteuid() == 0 ? "yes" : (have_cmd("sudo") ? "no, sudo present" : "no, and no sudo"));
	printf("sources     %s\n", getenv("APP_SETUP_PATH") ? getenv("APP_SETUP_PATH") : DEFAULT_PATH);
	printf("settings    %s/params\n", conf_dir());
	printf("passwords   %s/secrets\n", conf_dir());
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
 * terminal: render at 130, 88 and 46 columns and look at what survived.
 *
 * Every screen below is drawn by the function the interactive program calls,
 * given a hand-made cursor position — so what this prints is what a terminal
 * would show. The settings form is the exception and is still drawn twice; it
 * is a plain stack of fields, with no geometry worth a second implementation
 * being wrong about.
 */
static int cli_screenshot(int n, char **rest)
{
	int w = 100, h = 30, sel = 0, zone = -1, want = 0, vset = 0;
	const char *cat = NULL, *screen = "home", *pick = NULL;
	for (int i = 1; i < n; i++) {
		if (!strcmp(rest[i], "--width") && i + 1 < n) w = atoi(rest[++i]);
		else if (!strcmp(rest[i], "--height") && i + 1 < n) h = atoi(rest[++i]);
		else if (!strcmp(rest[i], "--category") && i + 1 < n) cat = rest[++i];
		else if (!strcmp(rest[i], "--screen") && i + 1 < n) screen = rest[++i];
		else if (!strcmp(rest[i], "--id") && i + 1 < n) pick = rest[++i];
		else if (!strcmp(rest[i], "--select") && i + 1 < n) sel = atoi(rest[++i]);
		else if (!strcmp(rest[i], "--focus") && i + 1 < n) {
			const char *f = rest[++i];
			if (!strcmp(f, "back"))       { zone = Z_STRIP; want = -1; }
			else if (!strcmp(f, "lang"))  { zone = Z_STRIP; want = -2; }
			else if (!strcmp(f, "chips")) { zone = Z_STRIP; want = -3; }
			else                            zone = Z_GRID;
		}
		/* So a filtered home screen can be rendered without a terminal, which
		 * is the only way the search box is testable from a script. */
		else if (!strcmp(rest[i], "--find") && i + 1 < n)
			copy_str(g_filter, sizeof g_filter, rest[++i]);
		else if (!strcmp(rest[i], "--view") && i + 1 < n)
			{ g_vmode = !strcmp(rest[++i], "list") ? V_LIST : V_CARDS; vset = 1; }
		else if (!strcmp(rest[i], "--probe")) probe_all(1);
	}
	g_w = w > 24 ? w : 24;
	g_h = h > 10 ? h : 10;
	g_anim = 0;              /* a frame that moves is not a frame you can diff */

	if (!vset) view_load();
	rebuild_lists();
	if (cat) {
		int ci = cat_index(cat);
		for (int i = 0; i < g_nchip; i++) {
			int c = g_chipcat[i];
			if ((ci >= 0 && c == ci) ||
			    (c == CHIP_INSTALLED && !strcmp(cat, "installed")) ||
			    (c == CHIP_ALL && !strcmp(cat, "all"))) { strip_to(i); break; }
		}
	}
	if (zone >= 0) {
		g_zone = zone;
		if (want == -1) g_strip = S_BACK;
		else if (want == -2) g_strip = S_LANG;
		else if (want == -3) g_strip = g_chip;
	}
	if (sel > 0 && sel <= g_nview) g_card = sel - 1;

	Pkg *p = pick ? find_pkg(pick) : (g_nview ? &g_pkg[g_view[g_card]] : NULL);

	if (p && (!strcmp(screen, "app") || !strcmp(screen, "menu") ||
	          !strcmp(screen, "detail"))) {
		AppView v;
		memset(&v, 0, sizeof v);
		v.zone = Z_TAB;
		v.tab = v.tsel = sel;
		app_draw(p, &v);
		screen = "app";
	} else if (!strcmp(screen, "progress")) {
		/* A Runner that never had a child: the drawing cannot tell, which is
		 * the point of it taking one. */
		static Runner r;
		memset(&r, 0, sizeof r);
		r.fd = r.logfd = -1;
		r.step = 3; r.total = 6; r.lines_in_step = 4;
		copy_str(r.phase, sizeof r.phase,
		         g_zh ? "正在配置默认站点…" : "configuring the default site…");
		runner_push(&r, "Setting up nginx (1.26.3-1) ...");
		runner_push(&r, g_zh ? "==> 配置默认站点" : "==> configuring the default site");
		runner_push(&r, "nginx: configuration file /etc/nginx/nginx.conf test is ok");
		runner_push(&r, g_zh ? "==> 启动 nginx" : "==> starting nginx");
		char title[256];
		verb_title(title, sizeof title, "install", p);
		progress_draw(&r, title, -1, 0, NULL, NULL);
	} else if (!strcmp(screen, "pick") && p) {
		/* The chooser behind a `@…` field, over the plain root the way it is
		 * actually drawn. --select is which row has the cursor. */
		grid_size(g_w, g_h);
		draw_root();
		Param *pm = NULL;
		for (int i = 0; i < p->nparams; i++)
			if (p->params[i].type == PT_LIST) { pm = &p->params[i]; break; }
		if (!pm) { fprintf(stderr, "screenshot: %s has no @-list field\n", p->id); return 1; }
		const Pkg *opts[LIST_MAX];
		int n = list_options(p, pm->source, opts, LIST_MAX);
		if (!n) { fprintf(stderr, "screenshot: nothing to offer for @%s\n", pm->source); return 1; }
		list_popup_draw(pm, opts, n, sel > 0 && sel <= n ? sel - 1 : 0);
	} else if (!strcmp(screen, "params") && p) {
		render_home();
		/* Same VisRow list screen_params itself walks (build_param_rows) —
		 * two implementations of what a group fold or an action row looks
		 * like is exactly the drift this screenshot mode exists to catch,
		 * not something to reintroduce for it. */
		VisRow vrows[MAX_VISROWS];
		int nvr = build_param_rows(p, vrows);
		int labw = 12;
		for (int i = 0; i < nvr; i++)
			if (vrows[i].kind == ROW_PARAM) {
				int lw = u8width(param_label_req(p, &p->params[vrows[i].idx]));
				if (lw > labw) labw = lw;
			}
		if (labw > 28) labw = 28;
		int fieldw = 30, ww = labw + fieldw + 8;
		if (ww > g_w - 6) { ww = g_w - 6; fieldw = ww - labw - 8; }
		/* Same growth rule as the live form, or the screenshot would be a
		 * picture of a box the form never draws. */
		int bfit = btn_width(S(T_SAVEAPPLY)) + 2 + btn_width(S(T_SAVE)) + 2 +
		           btn_width(S(T_CANCEL)) + 4;
		if (ww < bfit) { ww = bfit; if (ww > g_w - 2) ww = g_w - 2; }
		int helph = 0;
		for (int i = 0; i < p->nparams; i++)
			if (p->params[i].help[0] || p->params[i].help_zh[0]) { helph = 3; break; }
		if (p->require[0]) helph = 3;
		int hh = nvr + 6 + helph; if (hh > g_h - 2) hh = g_h - 2;
		int visrows = hh - 6 - helph; if (visrows < 1) visrows = 1;
		int row = (g_h - hh) / 2, col = (g_w - ww) / 2;
		if (row < 1) row = 1;
		if (col < 0) col = 0;
		char title[256];
		snprintf(title, sizeof title, "%s %s %s", pkg_name(p), MK_DOT, S(T_PARAMS));
		win_box(row, col, ww, hh, title);
		for (int slot = 0; slot < visrows && slot < nvr; slot++) {
			VisRow *vr = &vrows[slot];
			int y = row + 1 + slot;
			int a0 = (slot == 0) ? P_ENTRYACT : P_ENTRY;
			if (vr->kind == ROW_GROUP) {
				Group *gr = &p->groups[vr->idx];
				const char *lbl = (g_zh && gr->label_zh[0]) ? gr->label_zh : gr->label;
				gput(y, col, BX_LT, P_BORDER, 1);
				gfill(y, col + 1, ww - 2, BX_H, P_BORDER);
				gput(y, col + ww - 1, BX_RT, P_BORDER, 1);
				char hdr[160];
				snprintf(hdr, sizeof hdr, " %s ", lbl);
				gput(y, col + 2, hdr, slot == 0 ? P_ENTRYACT : P_BORDER, u8width(hdr));
				char btxt[32];
				snprintf(btxt, sizeof btxt, " <%s> ", S(gr->folded ? T_SHOW : T_HIDE));
				gput(y, col + ww - 2 - u8width(btxt), btxt, P_BTN, u8width(btxt));
				continue;
			}
			if (vr->kind == ROW_ACTION) {
				Param *apm = &p->params[vr->idx];
				const char *lbl = (g_zh && apm->action_label_zh[0])
				                  ? apm->action_label_zh : apm->action_label;
				char btxt[96];
				snprintf(btxt, sizeof btxt, "<%s>", lbl);
				gput(y, col + 4, btxt, slot == 0 ? P_BTNACT : P_BTN, ww - 6);
				continue;
			}
			Param *pm = &p->params[vr->idx];
			int indent = (pm->group >= 0) ? 2 : 0;
			int fx = col + 3 + labw;
			gput(y, col + 2 + indent, param_label_req(p, pm), P_WIN, labw - indent);
			gfill(y, fx, fieldw, " ", a0);
			if (pm->type == PT_BOOL) {
				int on = !strcmp(pm->value, "on") || !strcmp(pm->value, "1");
				char box[32];
				snprintf(box, sizeof box, "[%s] %s", on ? MK_OK : " ", on ? S(T_ON) : S(T_OFF));
				gput(y, fx, box, a0, fieldw);
			} else if (pm->type == PT_LIST) {
				char cut[256];
				u8ellipsis(cut, sizeof cut, *pm->value ? pm->value : S(T_PICKEMPTY),
				           fieldw - 3);
				gput(y, fx, cut, a0, fieldw - 3);
				gput(y, fx + fieldw - 2, CH_MORE, a0, 1);
			} else if (pm->type == PT_ENUM) {
				char ch[128];
				snprintf(ch, sizeof ch, "%s %s %s", AR_L, pm->value, AR_R);
				gput(y, fx, ch, a0, fieldw);
			} else {
				/* The same rule the live form uses: the focused row shows the
				 * end of the value, because that is where the cursor is, and
				 * every other row shows the front, which is what identifies it.
				 * Drawn here rather than shared, like the rest of this renderer,
				 * but drawn the same way — a screenshot of a field the form
				 * never draws is worse than no screenshot. */
				char cut[512];
				if (slot == 0) u8tail(cut, sizeof cut, pm->value, fieldw - 1);
				else           u8ellipsis(cut, sizeof cut, pm->value, fieldw - 1);
				gput(y, fx, cut, a0, fieldw - 1);
			}
		}
		scrollbar(row + 1, col + ww - 2, visrows, 0, visrows, nvr, P_SBTHUMBW, P_SBTRACKW);
		if (helph) {
			int hy = row + hh - 3 - helph + 1;
			gput(hy - 1, col, BX_LT, P_BORDER, 1);
			gfill(hy - 1, col + 1, ww - 2, BX_H, P_BORDER);
			gput(hy - 1, col + ww - 1, BX_RT, P_BORDER, 1);
			const char *txt = "";
			for (int i = 0; i < nvr; i++)
				if (vrows[i].kind == ROW_PARAM) { txt = param_help(&p->params[vrows[i].idx]); break; }
			char hl[4][512];
			int hn = *txt ? u8wrap(txt, ww - 4, hl, 2) : 0;
			for (int i = 0; i < 2; i++) {
				gfill(hy + i, col + 1, ww - 2, " ", P_WIN);
				if (i < hn) gput(hy + i, col + 2, hl[i], P_DIM, ww - 4);
			}
		}
		int bw = btn_width(S(T_SAVEAPPLY)) + 2 + btn_width(S(T_SAVE)) + 2 + btn_width(S(T_CANCEL));
		int bx = col + (ww - bw) / 2;
		if (bx < col + 1) bx = col + 1;
		btn_draw(row + hh - 2, bx, S(T_SAVEAPPLY), 1, 0);
		bx += btn_width(S(T_SAVEAPPLY)) + 2;
		btn_draw(row + hh - 2, bx, S(T_SAVE), 0, 1);
		bx += btn_width(S(T_SAVE)) + 2;
		btn_draw(row + hh - 2, bx, S(T_CANCEL), 0, 2);
		help_line_l(&T_HELPFORM);
	} else {
		render_home();
		screen = "home";
	}

	grid_dump(stdout);
	printf("\n[screen=%s cols=%d card=%dx%d apps=%d/%d installed=%d %dx%d]\n",
	       screen, G_cols, G_cardw, G_cardh, g_nview, g_npkg, g_ninst, g_w, g_h);
	return 0;
}

static void usage(FILE *f)
{
	fprintf(f,
	  "app-setup %s — install software into this container\n"
	  "\n"
	  "  app-setup                    the full-screen picker (this is the one you want)\n"
	  "  app-setup list [category]    everything, or one of: stack web db backup\n"
	  "                               dev system\n"
	  "  app-setup info <id>          one package in detail\n"
	  "  app-setup status [id...]     state only. Exit: 0 running, 1 stopped,\n"
	  "                               2 not installed, 3 broken, 4 no such id\n"
	  "  app-setup install <id>...\n"
	  "  app-setup remove <id>...\n"
	  "  app-setup start|stop|restart <id>...\n"
	  "  app-setup enable|disable <id>...   start at boot, or stop doing that\n"
	  "  app-setup backup <id>...     pack it, and upload it if a bucket is set\n"
	  "  app-setup restore <id>...    put the newest archive back\n"
	  "  app-setup archives <id>      the archives this job has, here and there\n"
	  "  app-setup verify <id>        open the newest one and check it loads\n"
	  "  app-setup test <id>          a backup destination's five-step check\n"
	  "  app-setup sshcmd <store>     the ssh command that store uses, for a\n"
	  "                               script that drives rsync itself\n"
	  "  app-setup remote <store> [folder]\n"
	  "                               the user@host:/path a folder resolves to\n"
	  "  app-setup dump <id>...       one plain .sql (or .rdb) file you can read\n"
	  "  app-setup load <id>...       feed the newest one back in\n"
	  "  app-setup set <id> [k=v ...] show or change a recipe's settings\n"
	  "  app-setup docs <id>          what the recipe says about itself\n"
	  "  app-setup doctor             what this machine looks like to app-setup\n"
	  "  app-setup domain add|del|ls|help   point a domain at this container\n"
	  "                               without the panel's web UI — `domain help`\n"
	  "                               for the full syntax\n"
	  "  app-setup dashboard [section ...]  what this box is, is allowed and is\n"
	  "                               using. No section draws all of them:\n"
	  "                               box cpu mem disk net ports domains ssh\n"
	  "  app-setup reinstall [ls|<image>|ref <r>|archive <f>]\n"
	  "                               rebuild this container's root filesystem\n"
	  "                               from an image. No argument lists what it\n"
	  "                               can be rebuilt from — `reinstall help`\n"
	  "  app-setup helppage [page]    the guide, full-screen: ports and domains,\n"
	  "                               installing software, limits, reinstall.\n"
	  "                               `helppage --list` names the pages\n"
	  "  app-setup screenshot [--width N] [--height N] [--category C|installed|all]\n"
	  "                       [--screen home|app|params|progress] [--id ID]\n"
	  "                       [--select N] [--focus grid|chips|back] [--probe]\n"
	  "                               render one frame as plain text\n"
	  "\n"
	  "  --lang en|zh    English unless this or APP_SETUP_LANG says otherwise;\n"
	  "                  in the picker, the button in the top right corner\n"
	  "                  switches it, and so does L\n"
	  "  --no-mouse      do not ask the terminal to report clicks. Everything is\n"
	  "                  reachable from four arrow keys and Enter either way; use\n"
	  "                  this if your terminal will not Shift-drag to select text\n"
	  "  --no-blink      hold the cursor highlight still. It normally has a\n"
	  "                  band of light sweeping along it, because a fill and\n"
	  "                  an underline alone are hard to find on some terminals\n"
	  "  --no-color      no escape sequences in the CLI output\n"
	  "  --version\n"
	  "\n"
	  "Everything you might want to edit is under /etc/app-setup — the recipes\n"
	  "as *.sh, your own in local/ where they override ours by id, what the\n"
	  "Settings form saved in params/, generated passwords in secrets/.\n"
	  "APP_SETUP_PATH overrides where recipes are read from and APP_SETUP_CONF\n"
	  "where the rest lives. Action output is appended to %s/<id>.log.\n",
	  APP_VERSION, LOG_DIR);
}

/* --------------------------------------------------------------- passwd ---
 *
 * /usr/local/bin/passwd is a symlink to this binary (image build —
 * docs/passwd.md). The SSH gateway on the host never reads a container's own
 * /etc/shadow, so `passwd` changing it looked like it worked and changed
 * nothing about how the tenant logs back in. The real tool is untouched at
 * /usr/bin/passwd, and this only special-cases one shape of the call —
 * everything else falls straight through to it, untouched.
 *
 * /usr/local/bin, and not /usr/bin, because no package manager owns that
 * directory. The first shape of this shipped by renaming the real tool to
 * .passwd and taking over /usr/bin/passwd, which held for exactly as long as
 * nobody installed anything: Alpine's busybox trigger runs `bbsuid --install`
 * on *every* apk transaction, and that recreates /usr/bin/passwd as a symlink
 * to /bin/bbsuid whenever it finds a symlink there — silently restoring the
 * bug this file exists to fix, on the same `apk add` that app-setup's own
 * pkg_install runs. (It leaves a regular file alone, which is why the real
 * tool is safe sitting there and a symlink never was.) dpkg and rpm do the
 * same thing more slowly: upgrading the package that owns /usr/bin/passwd
 * writes its own binary back over anything else at that path. Winning on
 * PATH instead of owning the path takes us out of that fight — /usr/local/bin
 * precedes /usr/bin in the login PATH and in sudo's secure_path on every
 * image we publish, and it is the same trick this Dockerfile already uses for
 * sftp-server.
 *
 * The one shape handled here is root, changing a password, no flags: bare
 * `passwd` or `passwd NAME`. It is the only login shape an hqnode container's
 * SSH mapping produces (ContainerUser defaults to root — agent/internal/
 * store/sshusers.go), and it is the one case that never needs the old
 * password — which is what makes it possible to collect the new one here and
 * hand it to both sides in a controlled order, rather than trying to observe
 * it inside the real passwd's own interactive session. Nothing here ever
 * reads a password back out of it.
 */
#define PWSYNC_SOCK "/etc/hqnode/hqnode.sock"

static const char *prog_basename(const char *path)
{
	const char *slash = strrchr(path, '/');
	return slash ? slash + 1 : path;
}

/* Standard base64, no line wrapping. The daemon only ever decodes what this
 * writes, so the alphabet and padding just have to match Go's
 * encoding/base64 StdEncoding. */
static void b64_encode(const unsigned char *in, size_t n, char *out)
{
	static const char tbl[] =
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	size_t i, o = 0;
	for (i = 0; i + 3 <= n; i += 3) {
		unsigned v = ((unsigned)in[i] << 16) | ((unsigned)in[i + 1] << 8) | in[i + 2];
		out[o++] = tbl[(v >> 18) & 0x3f];
		out[o++] = tbl[(v >> 12) & 0x3f];
		out[o++] = tbl[(v >> 6) & 0x3f];
		out[o++] = tbl[v & 0x3f];
	}
	size_t rem = n - i;
	if (rem == 1) {
		unsigned v = (unsigned)in[i] << 16;
		out[o++] = tbl[(v >> 18) & 0x3f];
		out[o++] = tbl[(v >> 12) & 0x3f];
		out[o++] = '=';
		out[o++] = '=';
	} else if (rem == 2) {
		unsigned v = ((unsigned)in[i] << 16) | ((unsigned)in[i + 1] << 8);
		out[o++] = tbl[(v >> 18) & 0x3f];
		out[o++] = tbl[(v >> 12) & 0x3f];
		out[o++] = tbl[(v >> 6) & 0x3f];
		out[o++] = '=';
	}
	out[o] = '\0';
}

/* Echo off, canonical mode left on: the kernel's line discipline still
 * handles backspace and only ever hands back a whole line, which is all a
 * password prompt needs. term_raw()/term_cooked() do more than that (the
 * alternate screen, mouse reporting, character-at-a-time reads) and neither
 * has been touched yet when this runs. */
static int read_password_line(char *buf, size_t cap)
{
	struct termios saved, t;
	int have_tty = tcgetattr(STDIN_FILENO, &saved) == 0;
	if (have_tty) {
		t = saved;
		t.c_lflag &= (tcflag_t)~ECHO;
		tcsetattr(STDIN_FILENO, TCSAFLUSH, &t);
	}
	size_t n = 0;
	int got_input = 0;
	for (;;) {
		char c;
		ssize_t r = read(STDIN_FILENO, &c, 1);
		if (r <= 0) break;
		got_input = 1;
		if (c == '\n' || c == '\r') break;
		if (n + 1 < cap) buf[n++] = c;
	}
	buf[n] = '\0';
	if (have_tty) {
		tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved);
		fputc('\n', stdout); /* ECHO being off swallowed the Enter's own newline */
		fflush(stdout);
	}
	return got_input;
}

/* Set when the last reply did not fit in the buffer below. It used to be
 * neither reported nor possible to notice: the overflow was dropped a byte at
 * a time and the caller was handed a truncated line that still looked like a
 * whole one. That was harmless while the only answers were "OK" and a short
 * domain list, and stops being harmless the moment a reply is a document
 * (`dashboard`) — half of one parses into a screen missing rows nobody knows
 * are missing. Cheaper to say so than to grow the buffer and hope. */
static int g_sock_truncated = 0;

/* Connects to the local socket, writes one already-newline-terminated line,
 * reads one line back. NULL means the socket could not be reached at all —
 * nothing has happened yet — which every caller has to tell apart from
 * "ERR ...", where the daemon looked at the request and refused it. The
 * returned pointer is a static buffer valid until the next call. */
static const char *hqnode_sock_call(const char *line)
{
	static char resp[8192];
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) return NULL;

	struct sockaddr_un addr;
	memset(&addr, 0, sizeof addr);
	addr.sun_family = AF_UNIX;
	snprintf(addr.sun_path, sizeof addr.sun_path, "%s", PWSYNC_SOCK);
	if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
		close(fd);
		return NULL;
	}

	size_t n = strlen(line);
	if (write(fd, line, n) != (ssize_t)n) {
		close(fd);
		return NULL;
	}

	size_t got = 0;
	g_sock_truncated = 0;
	for (;;) {
		char c;
		ssize_t r = read(fd, &c, 1);
		if (r <= 0) break;
		if (c == '\n') break;
		if (got + 1 < sizeof resp) resp[got++] = c;
		else g_sock_truncated = 1;
	}
	close(fd);
	if (got == 0) return NULL;
	resp[got] = '\0';
	return resp;
}

/* `SETPW <account> <base64(password)>`; passwd_main makes exactly one call. */
static const char *pwsync_call(const char *account, const char *password)
{
	char b64[512];
	b64_encode((const unsigned char *)password, strlen(password), b64);
	char line[700];
	int n = snprintf(line, sizeof line, "SETPW %s %s\n", account, b64);
	if (n < 0 || (size_t)n >= sizeof line) return NULL;
	return hqnode_sock_call(line);
}

/* `STOP` — poweroff_main/halt_main's one call, before they fall through to
 * the real binary. See docs/passwd.md §11 for why this exists: both already
 * exit the container cleanly today (the kernel's namespaced-reboot(2)
 * redirect sends this pid-namespace's own init a signal, never the host),
 * the missing piece was telling the daemon not to restart it under
 * restart_policy=always once that exit is reported. */
static const char *stop_call(void)
{
	return hqnode_sock_call("STOP\n");
}

/* ---------------------------------------------------------------- domain --
 * `app-setup domain add/del/ls/help` — point a domain at this container
 * without going to the panel's web UI. Unlike passwd/poweroff/halt this is
 * not a system binary this file is standing in for; it is a plain app-setup
 * subcommand, dispatched in main()'s own argv chain next to `install`/
 * `start`/etc. See docs/domain-cli.md for the wire protocol and why it goes
 * through the same local socket passwd sync and STOP already use rather
 * than calling the panel directly: this container gets no network
 * credential of its own, only what pwsync_call/stop_call already have —
 * a connection to the daemon on this same host, which relays the request
 * over its own already-authenticated link to the panel.
 */

static void domain_usage(FILE *out)
{
	fprintf(out,
		"Usage: app-setup domain <command>\n"
		"\n"
		"Commands:\n"
		"  add <domain> <port> [self-hosted] [http-port]\n"
		"                    claim a domain and point it at this container\n"
		"  del <domain>      stop answering for a domain\n"
		"  ls                list this container's domains, as a table\n"
		"  help              this text\n"
		"\n"
		"Arguments to \"add\":\n"
		"  <domain>       required, string. The host name to route, e.g.\n"
		"                 example.com or *.example.com (wildcard first label\n"
		"                 only). No scheme, no port, no path — just the name.\n"
		"  <port>         required, integer 1-65535. The TCP port this\n"
		"                 container is listening on. With a managed\n"
		"                 certificate (the default) this is the plain-HTTP\n"
		"                 backend port; with \"self-hosted\" it is the TLS\n"
		"                 backend port instead.\n"
		"  self-hosted    optional, literal keyword (type it exactly as\n"
		"                 shown, or omit it). Leave it out to let this host\n"
		"                 get you a certificate and terminate TLS for you —\n"
		"                 the usual case. Include it to terminate TLS\n"
		"                 yourself inside this container; traffic reaches\n"
		"                 <port> still encrypted (SNI passthrough).\n"
		"  [http-port]    optional, integer 1-65535. Only meaningful\n"
		"                 together with \"self-hosted\": a second, plain-HTTP\n"
		"                 port this container also answers on, alongside\n"
		"                 its own TLS port. Skip it if this container only\n"
		"                 speaks HTTPS.\n"
		"\n"
		"Examples:\n"
		"  app-setup domain add example.com 8080\n"
		"      Managed certificate. example.com:443 (HTTPS, cert handled by\n"
		"      this host) and example.com:80 both forward to this\n"
		"      container's port 8080.\n"
		"\n"
		"  app-setup domain add *.example.com 3000\n"
		"      Same, but for a wildcard: any-name.example.com forwards to\n"
		"      port 3000.\n"
		"\n"
		"  app-setup domain add example.com 8443 self-hosted\n"
		"      This container terminates its own TLS on port 8443.\n"
		"      example.com:443 is passed through untouched; nothing on :80.\n"
		"\n"
		"  app-setup domain add example.com 8443 self-hosted 8080\n"
		"      Same as above, and example.com:80 also forwards to this\n"
		"      container's port 8080 in plain HTTP.\n"
		"\n"
		"  app-setup domain del example.com\n"
		"      Stop answering for example.com. Other domains on this\n"
		"      container are unaffected.\n"
		"\n"
		"  app-setup domain ls\n"
		"      List every domain this container currently answers for, as\n"
		"      a table, with how many of your allowance are in use.\n");
}

/* Very small, deliberately not a JSON parser: every successful reply this
 * command ever gets back is exactly {"domains":[{"domain":"a"},…],"max":N}
 * (server/internal/api/domains.go's domainResult) and nothing else, so
 * pulling every "domain":"…" substring out by hand is exact for the one
 * shape this ever has to read. The cap is the real one: the reply buffer is
 * large enough now (8KB, for `dashboard`) that it is this array rather than
 * the line length that runs out first, so it is set well past any allowance
 * an admin would hand one container (MaxDomains defaults to 10).
 */
#define DOMAIN_LIST_CAP 128

static int domain_parse_list(const char *json, char rows[][254], int cap)
{
	const char *p = json;
	int n = 0;
	while (n < cap && (p = strstr(p, "\"domain\":\"")) != NULL) {
		p += 10; /* strlen("\"domain\":\"") */
		const char *end = strchr(p, '"');
		if (!end) break;
		size_t len = (size_t)(end - p);
		if (len > 253) len = 253;
		memcpy(rows[n], p, len);
		rows[n][len] = '\0';
		n++;
		p = end;
	}
	return n;
}

/* -1 if "max" is missing, which domain_print_table treats as "don't know
 * the allowance" rather than zero. */
static int domain_parse_max(const char *json)
{
	const char *p = strstr(json, "\"max\":");
	if (!p) return -1;
	return atoi(p + 6); /* strlen("\"max\":") */
}

static void domain_print_table(const char *json)
{
	static char rows[DOMAIN_LIST_CAP][254];
	int n = domain_parse_list(json, rows, DOMAIN_LIST_CAP);
	int max = domain_parse_max(json);

	if (max >= 0) printf("Your domains (%d of %d used):\n\n", n, max);
	else printf("Your domains:\n\n");

	if (n == 0) {
		printf("  (none yet — see \"app-setup domain help\" to add one)\n");
		return;
	}

	size_t width = strlen("DOMAIN");
	for (int i = 0; i < n; i++) {
		size_t len = strlen(rows[i]);
		if (len > width) width = len;
	}
	int idx_width = 1;
	for (int t = n; t >= 10; t /= 10) idx_width++;

	printf("  %-*s  %-*s\n", idx_width, "#", (int)width, "DOMAIN");
	for (int i = 0; i < n; i++)
		printf("  %-*d  %-*s\n", idx_width, i + 1, (int)width, rows[i]);
}

/* hqnode_sock_call's answer is one line: NULL if the socket could not be
 * reached at all (the daemon is not running, or this image predates the
 * bind — nothing has happened yet), "ERR <message>" if the daemon or the
 * panel refused the request, or "OK" / "OK <json>". */
static int domain_reply(const char *resp)
{
	if (!resp) {
		fprintf(stderr, "app-setup: could not reach the hqnode daemon\n");
		return 1;
	}
	if (!strncmp(resp, "ERR ", 4)) {
		fprintf(stderr, "app-setup: %s\n", resp + 4);
		return 1;
	}
	if (strncmp(resp, "OK", 2) != 0) {
		fprintf(stderr, "app-setup: unexpected answer from the hqnode daemon\n");
		return 1;
	}
	const char *json = resp[2] == ' ' ? resp + 3 : resp + 2;
	if (*json) domain_print_table(json);
	return 0;
}

static int cli_domain(int argc, char **argv)
{
	if (argc == 0) {
		domain_usage(stderr);
		return 2;
	}
	const char *verb = argv[0];

	if (!strcmp(verb, "help") || !strcmp(verb, "-h") || !strcmp(verb, "--help")) {
		domain_usage(stdout);
		return 0;
	}
	if (!strcmp(verb, "ls")) {
		return domain_reply(hqnode_sock_call("DOMAIN LS\n"));
	}
	if (!strcmp(verb, "del")) {
		if (argc < 2) {
			fprintf(stderr, "app-setup: domain del needs a domain\n");
			return 2;
		}
		char line[600];
		int n = snprintf(line, sizeof line, "DOMAIN DEL %s\n", argv[1]);
		if (n < 0 || (size_t)n >= sizeof line) {
			fprintf(stderr, "app-setup: that domain name is too long\n");
			return 1;
		}
		return domain_reply(hqnode_sock_call(line));
	}
	if (!strcmp(verb, "add")) {
		if (argc < 3) {
			fprintf(stderr, "app-setup: domain add needs a domain and a port\n\n");
			domain_usage(stderr);
			return 2;
		}
		const char *domain = argv[1], *port = argv[2];
		int self_hosted = 0;
		const char *http_port = NULL;
		for (int i = 3; i < argc; i++) {
			if (!strcmp(argv[i], "self-hosted")) self_hosted = 1;
			else http_port = argv[i];
		}
		char line[700];
		int n;
		if (self_hosted && http_port)
			n = snprintf(line, sizeof line, "DOMAIN ADD %s %s self-hosted %s\n", domain, port, http_port);
		else if (self_hosted)
			n = snprintf(line, sizeof line, "DOMAIN ADD %s %s self-hosted\n", domain, port);
		else
			n = snprintf(line, sizeof line, "DOMAIN ADD %s %s\n", domain, port);
		if (n < 0 || (size_t)n >= sizeof line) {
			fprintf(stderr, "app-setup: that request is too long\n");
			return 1;
		}
		return domain_reply(hqnode_sock_call(line));
	}

	fprintf(stderr, "app-setup: domain: unknown command: %s\n\n", verb);
	domain_usage(stderr);
	return 2;
}

/* ------------------------------------------------------------- dashboard --
 * `app-setup dashboard [section ...]` — what this box is, what it is allowed,
 * and what it is using, on the same socket `domain` rides
 * (docs/dashboard-cli.md). With no arguments it draws everything, which is
 * the whole point of typing one word; a section name filters, and the daemon
 * refuses one it does not know rather than quietly drawing the lot.
 *
 * This end knows the *layout* and nothing about the content. The daemon sends
 * rows that are already worded — kind, label, value — and all that happens
 * here is one column being lined up under another. That is not laziness about
 * where to put the strings: the agent upgrades itself online while this binary
 * is baked into twenty published images, so a field added on the far side has
 * to appear here without a rebuild, and it does. It is also what keeps a JSON
 * parser out of a program that has no business having one.
 */
#define DASH_MAX_ROWS 128
#define DASH_RS       '\x1e'    /* between rows   */
#define DASH_US       '\x1f'    /* between fields */

static void dashboard_usage(FILE *out)
{
	fprintf(out,
		"Usage: app-setup dashboard [section ...]\n"
		"\n"
		"Everything this host and the panel know about the container you\n"
		"are sitting in: what it was sold, what it is using, where it\n"
		"answers, and when it expires.\n"
		"\n"
		"With no section, all of them are drawn. Naming one or more draws\n"
		"only those, always in the order below rather than the order typed:\n"
		"\n"
		"  box        name, image, state, uptime, expiry\n"
		"  cpu        cores allowed, and how busy they are\n"
		"  mem        memory and swap allowed, and how much is in use\n"
		"  disk       disk allowed, in use, and /data if there is one\n"
		"  net        traffic allowance, what this window has used, what is left\n"
		"  ports      public ports an admin opened onto this container\n"
		"  domains    the names this container answers for\n"
		"  ssh        how to log back in\n"
		"\n"
		"  --brief    the six-line version printed on every SSH login\n"
		"             (/etc/profile.d/app-setup.sh). Silent if this host's\n"
		"             daemon does not answer, so a login never waits on it.\n"
		"\n"
		"Examples:\n"
		"  dashboard\n"
		"      The whole screen.\n"
		"\n"
		"  dashboard net\n"
		"      Just the traffic meter — how much of this window's allowance\n"
		"      is gone, and how much is left.\n"
		"\n"
		"  dashboard cpu mem disk\n"
		"      The three resource sections, nothing else.\n");
}

/* Splits s on sep, in place, into at most cap pieces. Unlike strtok this
 * keeps empty pieces, which carry meaning here: a row with an empty label is
 * a continuation line under the row above it. */
static int dash_split(char *s, char sep, char **out, int cap)
{
	int n = 0;
	if (cap <= 0) return 0;
	out[n++] = s;
	for (char *p = s; *p; p++) {
		if (*p != sep) continue;
		*p = '\0';
		if (n >= cap) break;
		out[n++] = p + 1;
	}
	return n;
}

/* A section name is one word of ASCII. Anything else is refused here rather
 * than sent: the socket's framing is one line, so a newline in an argument
 * would end the request early and the daemon would answer a different
 * question than the one that was asked. */
static int dash_word_ok(const char *s)
{
	if (!*s) return 0;
	for (const unsigned char *p = (const unsigned char *)s; *p; p++)
		if (!isalnum(*p) && *p != '-' && *p != '_') return 0;
	return 1;
}

/* first_label/first_value, when given, are one extra field drawn above
 * everything else and counted in the same column width — the login banner's
 * "System" row. It is the one line on that banner this side has to supply:
 * the daemon knows what the container was sold and what it is using, and has
 * no idea which distribution is inside it. */
static int dashboard_print(const char *payload, const char *first_label, const char *first_value)
{
	static char buf[8192];
	snprintf(buf, sizeof buf, "%s", payload);

	static char *items[DASH_MAX_ROWS];
	int n = dash_split(buf, DASH_RS, items, DASH_MAX_ROWS);

	static char *kind[DASH_MAX_ROWS], *label[DASH_MAX_ROWS], *value[DASH_MAX_ROWS];
	int width = first_label ? (int)strlen(first_label) : 0;
	for (int i = 0; i < n; i++) {
		char *f[3] = { (char *)"", (char *)"", (char *)"" };
		dash_split(items[i], DASH_US, f, 3);
		kind[i] = f[0]; label[i] = f[1]; value[i] = f[2];
		if (kind[i][0] == 'F') {
			int len = (int)strlen(label[i]);
			if (len > width) width = len;
		}
	}

	int drawn = 0;
	if (first_label) {
		printf("  %-*s  %s\n", width, first_label, first_value ? first_value : "");
		drawn = 1;
	}
	for (int i = 0; i < n; i++) {
		if (kind[i][0] == 'H') {
			if (drawn) printf("\n");
			printf("%s", label[i]);
			if (value[i][0]) printf("  %s", value[i]);
			printf("\n");
		} else if (!label[i][0]) {
			/* A continuation line — one of a list, under the heading it
			 * belongs to. It sits at the label column rather than the value
			 * one, because there is no label beside it for it to line up
			 * with, and a lone value indented under nothing reads as lost. */
			printf("  %s\n", value[i]);
		} else {
			printf("  %-*s  %s\n", width, label[i], value[i]);
		}
		drawn = 1;
	}
	return 0;
}

static int cli_dashboard(int argc, char **argv)
{
	if (argc > 0 && (!strcmp(argv[0], "help") || !strcmp(argv[0], "-h") ||
	                 !strcmp(argv[0], "--help"))) {
		dashboard_usage(stdout);
		return 0;
	}

	/* --brief is the login banner (/etc/profile.d/app-setup.sh): six rows,
	 * no headings, printed above the shell prompt on every interactive
	 * login. It is quiet on every failure — a container whose daemon is not
	 * answering must still give somebody a prompt, without an error on it
	 * they can do nothing about. */
	int brief = 0;
	if (argc > 0 && !strcmp(argv[0], "--brief")) { brief = 1; argc--; argv++; }

	char line[512];
	size_t used = 0;
	int n = snprintf(line, sizeof line, "DASHBOARD%s", brief ? " --brief" : "");
	if (n < 0) return 1;
	used = (size_t)n;
	for (int i = 0; i < argc; i++) {
		if (!dash_word_ok(argv[i])) {
			fprintf(stderr, "app-setup: not a section name: %s\n\n", argv[i]);
			dashboard_usage(stderr);
			return 2;
		}
		n = snprintf(line + used, sizeof line - used, " %s", argv[i]);
		if (n < 0 || (size_t)n >= sizeof line - used) {
			fprintf(stderr, "app-setup: too many sections at once\n");
			return 2;
		}
		used += (size_t)n;
	}
	if (used + 2 > sizeof line) {
		fprintf(stderr, "app-setup: too many sections at once\n");
		return 2;
	}
	line[used] = '\n';
	line[used + 1] = '\0';

	const char *resp = hqnode_sock_call(line);
	if (brief && (!resp || strncmp(resp, "OK", 2) != 0 || g_sock_truncated)) {
		return 1;   /* silent: see the comment on `brief` above */
	}
	if (!resp) {
		fprintf(stderr, "app-setup: could not reach the hqnode daemon\n");
		return 1;
	}
	if (!strncmp(resp, "ERR ", 4)) {
		fprintf(stderr, "app-setup: %s\n", resp + 4);
		return 1;
	}
	if (strncmp(resp, "OK", 2) != 0) {
		fprintf(stderr, "app-setup: unexpected answer from the hqnode daemon\n");
		return 1;
	}
	if (g_sock_truncated) {
		/* Better than drawing most of a dashboard: a screen quietly missing
		 * its last two sections is one somebody makes a decision on. */
		fprintf(stderr, "app-setup: the answer was too long to read whole; "
		                "try one section at a time, e.g. `dashboard net`\n");
		return 1;
	}
	const char *rows = resp[2] == ' ' ? resp + 3 : resp + 2;
	if (!*rows) {
		if (!brief) fprintf(stderr, "app-setup: the hqnode daemon sent an empty dashboard\n");
		return 1;
	}
	if (!brief) return dashboard_print(rows, NULL, NULL);

	/* The banner's own first row. read_os_release rather than probe_system:
	 * the bare-word path reaches here before main() has probed anything, and
	 * the distribution's name is the only part of that this needs. */
	if (!g_sys.pretty[0]) read_os_release();
	int rc = dashboard_print(rows, "System", g_sys.pretty[0] ? g_sys.pretty : "this container");
	printf("\n");
	return rc;
}


/* -------------------------------------------------------------- reinstall --
 * `reinstall` — rebuild this container's root filesystem from an image, from
 * inside the container that is about to lose it (docs/reinstall-cli.md). Same
 * socket as `domain` and `dashboard`, same reason: this container has no
 * credential of its own, only a connection to the daemon on its host, which
 * relays the request over its own already-authenticated link to the panel.
 *
 * It is the only thing on that socket that destroys anything, and the whole
 * shape of this command follows from one fact — **the shell that types it
 * does not survive it.** Part-way through, the container is stopped; this
 * process is killed with it, and so is the SSH session it was typed into. So:
 *
 *   1. ASK   the daemon what the typed word resolves to. Nothing is touched.
 *            A word naming no image is refused here, before anybody has been
 *            made to retype their container's name for nothing.
 *   2. the confirmation prompt, worded by the daemon and printed by this.
 *   3. GO    and say so before waiting, because the last thing this terminal
 *            ever prints is whatever was flushed before the rebuild began.
 *
 * As everywhere else on this socket, the wording is the daemon's and the
 * drawing is this program's: the daemon is upgraded in place from the panel,
 * while this binary is baked into twenty published images where a changed
 * sentence costs a rebuild and a republish of all of them.
 */
#define REINSTALL_MAX_ROWS 256

static void reinstall_usage(FILE *out)
{
	fprintf(out,
		"Usage: reinstall [ls | <image> | ref <reference> | archive <file>]\n"
		"\n"
		"Replace this container's root filesystem with a fresh image, and\n"
		"start it again. Everything in the root filesystem is erased. A\n"
		"/data disk, where this container has one, is not touched.\n"
		"\n"
		"Commands:\n"
		"  ls                 what this container can be rebuilt from: the\n"
		"                     images this machine offers, the archives on it,\n"
		"                     and whether it takes an image of your own.\n"
		"                     This is also what bare `reinstall` prints.\n"
		"  <image>            one of the images from \"ls\". Part of the name\n"
		"                     is enough, as long as it names only one of them\n"
		"                     — \"reinstall ubuntu-24.04\".\n"
		"  ref <reference>    an image of your own, from any registry this\n"
		"                     machine can reach. It is fetched for this\n"
		"                     container alone and the download counts against\n"
		"                     this container's traffic allowance. Only where\n"
		"                     the machine allows it and this container has a\n"
		"                     disk of its own.\n"
		"  archive <file>     one of the archive files from \"ls\", which\n"
		"                     whoever runs the machine put there.\n"
		"  help               this text\n"
		"\n"
		"Options:\n"
		"  --confirm <name>   answer the confirmation prompt up front, with\n"
		"                     this container's own name. For a script; typing\n"
		"                     it at a prompt is the ordinary way.\n"
		"\n"
		"Examples:\n"
		"  reinstall\n"
		"      What this container can be rebuilt from.\n"
		"\n"
		"  reinstall debian-13\n"
		"      Rebuild from the machine's Debian 13 image, after confirming.\n"
		"\n"
		"  reinstall ref ghcr.io/me/mine:v2\n"
		"      Rebuild from an image of your own.\n");
}

/* The value travels base64 for the reason the password in SETPW does: a
 * registry reference and an operator's own file name are not this protocol's
 * to put rules on, and the request is one line. */
static int reinstall_encode(const char *value, char *out, size_t cap)
{
	size_t n = strlen(value);
	if (n * 4 / 3 + 8 > cap) return 0;
	b64_encode((const unsigned char *)value, n, out);
	return 1;
}

/* Draws the rows the daemon sent — the same three-field framing `dashboard`
 * reads, with one row kind of its own: 'P' is the prompt to print before
 * reading an answer, and is handed back rather than drawn. Its label is the
 * one word that answers it, which is this container's own name. */
static void reinstall_print(const char *payload, char *prompt, size_t prompt_cap,
                            char *expect, size_t expect_cap)
{
	static char buf[8192];
	snprintf(buf, sizeof buf, "%s", payload);
	if (prompt && prompt_cap) prompt[0] = '\0';
	if (expect && expect_cap) expect[0] = '\0';

	static char *items[REINSTALL_MAX_ROWS];
	int n = dash_split(buf, DASH_RS, items, REINSTALL_MAX_ROWS);

	static char *kind[REINSTALL_MAX_ROWS], *label[REINSTALL_MAX_ROWS], *value[REINSTALL_MAX_ROWS];
	int width = 0;
	for (int i = 0; i < n; i++) {
		char *f[3] = { (char *)"", (char *)"", (char *)"" };
		dash_split(items[i], DASH_US, f, 3);
		kind[i] = f[0]; label[i] = f[1]; value[i] = f[2];
		if (kind[i][0] == 'F') {
			int len = (int)strlen(label[i]);
			if (len > width) width = len;
		}
	}

	int drawn = 0;
	for (int i = 0; i < n; i++) {
		if (kind[i][0] == 'P') {
			if (prompt && prompt_cap) snprintf(prompt, prompt_cap, "%s", value[i]);
			if (expect && expect_cap) snprintf(expect, expect_cap, "%s", label[i]);
			continue;
		}
		if (kind[i][0] == 'H') {
			if (drawn) printf("\n");
			printf("%s", label[i]);
			if (value[i][0]) printf("  %s", value[i]);
			printf("\n");
		} else if (!label[i][0]) {
			printf("  %s\n", value[i]);
		} else {
			printf("  %-*s  %s\n", width, label[i], value[i]);
		}
		drawn = 1;
	}
}

/* One line of typed answer, echo left on — this is a container's own name
 * being retyped, not a secret. NULL on end of input, which is what a script
 * that piped nothing in gets, and is a cancel rather than a confirmation. */
static char *reinstall_read_line(char *buf, size_t cap)
{
	if (!fgets(buf, (int)cap, stdin)) return NULL;
	size_t n = strlen(buf);
	while (n && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = '\0';
	return buf;
}

/* hqnode_sock_call's answer, checked the way domain_reply checks it, but
 * handing the payload back instead of printing it: the three verbs here each
 * do something different with theirs. NULL means it has already been
 * reported. */
static const char *reinstall_payload(const char *resp)
{
	if (!resp) {
		fprintf(stderr, "reinstall: could not reach the hqnode daemon\n");
		return NULL;
	}
	if (!strncmp(resp, "ERR ", 4)) {
		fprintf(stderr, "reinstall: %s\n", resp + 4);
		return NULL;
	}
	if (strncmp(resp, "OK", 2) != 0) {
		fprintf(stderr, "reinstall: unexpected answer from the hqnode daemon\n");
		return NULL;
	}
	if (g_sock_truncated) {
		fprintf(stderr, "reinstall: the answer was too long to read whole; "
		                "nothing was done\n");
		return NULL;
	}
	return resp[2] == ' ' ? resp + 3 : resp + 2;
}

static int reinstall_ls(void)
{
	const char *rows = reinstall_payload(hqnode_sock_call("REINSTALL LS\n"));
	if (!rows) return 1;
	reinstall_print(rows, NULL, 0, NULL, 0);
	return 0;
}

static int cli_reinstall(int argc, char **argv)
{
	const char *confirm = NULL;
	char *rest[8];
	int n = 0;
	for (int i = 0; i < argc; i++) {
		if (!strcmp(argv[i], "--confirm") && i + 1 < argc) { confirm = argv[++i]; continue; }
		if (n < 7) rest[n++] = argv[i];
	}

	if (n == 0) return reinstall_ls();
	const char *verb = rest[0];
	if (!strcmp(verb, "help") || !strcmp(verb, "-h") || !strcmp(verb, "--help")) {
		reinstall_usage(stdout);
		return 0;
	}
	if (!strcmp(verb, "ls") || !strcmp(verb, "list")) return reinstall_ls();

	/* Three sources, and the bare form is the one people type: `reinstall
	 * debian-13` means the machine's own image list, because that is where
	 * nearly every reinstall comes from. An image whose name happens to be
	 * one of the words above can still be named as `reinstall image ls`. */
	const char *kind = "image", *value = NULL;
	if (!strcmp(verb, "ref") || !strcmp(verb, "reference") ||
	    !strcmp(verb, "archive") || !strcmp(verb, "image")) {
		if (n < 2) {
			fprintf(stderr, "reinstall: %s needs something after it\n\n", verb);
			reinstall_usage(stderr);
			return 2;
		}
		kind = !strcmp(verb, "reference") ? "ref" : verb;
		value = rest[1];
	} else {
		value = rest[0];
	}

	char encoded[1400];
	if (!reinstall_encode(value, encoded, sizeof encoded)) {
		fprintf(stderr, "reinstall: that is too long to name here\n");
		return 1;
	}

	/* 1. What would this be? Nothing is touched by asking. */
	char line[2048];
	int len = snprintf(line, sizeof line, "REINSTALL ASK %s %s\n", kind, encoded);
	if (len < 0 || (size_t)len >= sizeof line) {
		fprintf(stderr, "reinstall: that is too long to name here\n");
		return 1;
	}
	const char *rows = reinstall_payload(hqnode_sock_call(line));
	if (!rows) return 1;

	char prompt[256], expect[128];
	reinstall_print(rows, prompt, sizeof prompt, expect, sizeof expect);

	/* 2. The confirmation, which is this container's own name. */
	char typed[128];
	if (confirm) {
		snprintf(typed, sizeof typed, "%s", confirm);
		/* The screen above is on stdout and the refusal below is on stderr,
		 * and the branch that prompts flushes between them by having to. This
		 * one does not prompt, so nothing flushes: to a terminal that costs
		 * nothing (stdout is line-buffered there), but redirected to a file or
		 * a pipe — which is what --confirm is for — stdout is block-buffered
		 * and the refusal lands in the middle of the screen it is refusing. */
		fflush(stdout);
	} else {
		printf("\n%s", prompt[0] ? prompt : "Type this container's name to confirm: ");
		fflush(stdout);
		if (!reinstall_read_line(typed, sizeof typed) || typed[0] == '\0') {
			printf("Nothing was done.\n");
			return 1;
		}
	}
	/* Checked here as well as by the panel, and only so that the line below
	 * — which says this session is about to end — is never printed over an
	 * answer that was never going to be accepted. The panel checks it again
	 * and is the thing that decides; this is about what the terminal says. */
	if (expect[0] ? strcmp(typed, expect) != 0 : strpbrk(typed, " \t") != NULL) {
		/* The fallback, for an answer this end cannot check against a name:
		 * a container name cannot hold whitespace (the panel's own rule) and
		 * the request is one line, so an answer that could not be one is a
		 * mismatch rather than something to send and let the line break on. */
		fprintf(stderr, "reinstall: that is not this container's name. Nothing was done.\n");
		return 1;
	}

	/* 3. Say it before doing it: the rebuild stops this container, which
	 * kills this process and the SSH session it is running in. Whatever is
	 * still in the output buffer at that moment is never seen. */
	len = snprintf(line, sizeof line, "REINSTALL GO %s %s %s\n", kind, typed, encoded);
	if (len < 0 || (size_t)len >= sizeof line) {
		fprintf(stderr, "reinstall: that is too long to name here\n");
		return 1;
	}
	printf("\nRebuilding. This session ends here — log back in a minute or two "
	       "from now, with the same address and the same password.\n");
	fflush(stdout);

	/* The answer to this arrives only where there is still somebody to read
	 * it, which means only where it was refused: on success this process is
	 * long dead by the time the daemon writes back. */
	const char *done = hqnode_sock_call(line);
	if (!done) {
		fprintf(stderr, "reinstall: the connection to the hqnode daemon ended "
		                "without an answer. If this container is still up in a "
		                "few minutes, nothing was rebuilt.\n");
		return 1;
	}
	if (!strncmp(done, "ERR ", 4)) {
		fprintf(stderr, "reinstall: %s\n", done + 4);
		return 1;
	}
	printf("%s\n", done[2] == ' ' ? done + 3 : done + 2);
	return 0;
}

/* -------------------------------------------------------------- helppage --
 *
 * `helppage` — the guide somebody reads before they break something, in the
 * same window furniture as the picker, driven the same four ways.
 *
 * It knows nothing about what is in the guide. Pages are plain .txt files in
 * /etc/helppage, one per topic per language, and the program scans that
 * directory the way app-setup scans /etc/app-setup: a host who wants a page
 * of their own — their own support address, their own backup policy — drops
 * a file in and it is a chapter, indistinguishable from the ones we ship.
 * There is no table in the C to update and no rebuild.
 *
 *     NN-id.LANG.txt        10-ports.en.txt, 10-ports.zh.txt
 *
 * NN orders the contents, id ties the two languages together, and LANG picks
 * which one is shown. The top of each file is `key: value` lines — title and
 * summary — stopping at the first line that is not one, so a file that opens
 * with prose keeps its prose.
 *
 * In the body: `== A heading ==` is a heading, a line indented four spaces is
 * something to type and is never wrapped, and everything else is a paragraph
 * wrapped to the pane. That is the whole markup, on purpose: it has to read
 * as well through `cat` as it does in here, because on a container with no
 * terminal `cat` is what somebody has.
 */
#define HELP_DIR_DEFAULT "/etc/helppage:/usr/local/etc/helppage"
#define HELP_MAXTOPIC    24
#define HELP_MAXBYTES    (96 * 1024)

typedef struct {
	int  order;
	char id[40];
	char title[2][96];      /* [0] English, [1] 中文 */
	char summary[2][200];
	char path[2][600];
} Topic;

static Topic g_topics[HELP_MAXTOPIC];
static int   g_ntopics = 0;

static const char *help_title(const Topic *t)
{
	const char *s = t->title[g_zh ? 1 : 0];
	if (!*s) s = t->title[g_zh ? 0 : 1];
	return *s ? s : t->id;
}

/* Which file to show: this language if there is one, the other if there is
 * not. A page nobody has translated yet is better read in English than not
 * read at all. */
static const char *help_path(const Topic *t)
{
	const char *p = t->path[g_zh ? 1 : 0];
	return *p ? p : t->path[g_zh ? 0 : 1];
}

static int topic_cmp(const void *a, const void *b)
{
	const Topic *x = a, *y = b;
	if (x->order != y->order) return x->order - y->order;
	return strcmp(x->id, y->id);
}

static Topic *topic_find(const char *id)
{
	for (int i = 0; i < g_ntopics; i++)
		if (!strcmp(g_topics[i].id, id)) return &g_topics[i];
	return NULL;
}

/* One `key: value` header line, if that is what this is. Returns 0 for
 * anything else, which ends the header block. */
static int help_meta(Topic *t, int lang, const char *line)
{
	const char *colon = strchr(line, ':');
	if (!colon || colon == line) return 0;
	for (const char *p = line; p < colon; p++)
		if (!islower((unsigned char)*p) && *p != '_') return 0;
	if (colon[1] != ' ' && colon[1] != '\0') return 0;

	char key[32];
	size_t klen = (size_t)(colon - line);
	if (klen >= sizeof key) return 0;
	memcpy(key, line, klen);
	key[klen] = '\0';
	const char *val = colon + 1;
	while (*val == ' ') val++;

	if (!strcmp(key, "title"))        copy_str(t->title[lang], sizeof t->title[lang], val);
	else if (!strcmp(key, "summary")) copy_str(t->summary[lang], sizeof t->summary[lang], val);
	return 1;
}

/* `10-ports.en.txt` → order 10, id "ports", lang en. A file with no NN- goes
 * to the end rather than to the front, so somebody's own page does not land
 * above the one about ports without them asking for it. */
static void help_scan_file(const char *dir, const char *name)
{
	size_t len = strlen(name);
	if (len < 8 || strcmp(name + len - 4, ".txt") != 0) return;

	char base[128];
	if (len - 4 >= sizeof base) return;
	memcpy(base, name, len - 4);
	base[len - 4] = '\0';

	char *dot = strrchr(base, '.');
	if (!dot) return;
	int lang;
	if (!strcmp(dot + 1, "en"))      lang = 0;
	else if (!strcmp(dot + 1, "zh")) lang = 1;
	else return;
	*dot = '\0';

	int order = 500;
	char *id = base;
	if (isdigit((unsigned char)base[0])) {
		char *dash = strchr(base, '-');
		if (dash) { order = atoi(base); id = dash + 1; }
	}
	if (!*id) return;

	Topic *t = topic_find(id);
	if (!t) {
		if (g_ntopics >= HELP_MAXTOPIC) return;
		t = &g_topics[g_ntopics++];
		memset(t, 0, sizeof *t);
		copy_str(t->id, sizeof t->id, id);
		t->order = order;
	}
	if (order < t->order) t->order = order;
	snprintf(t->path[lang], sizeof t->path[lang], "%s/%s", dir, name);

	FILE *f = fopen(t->path[lang], "r");
	if (!f) return;
	char line[512];
	while (fgets(line, sizeof line, f)) {
		line[strcspn(line, "\r\n")] = '\0';
		if (!help_meta(t, lang, line)) break;
	}
	fclose(f);
}

static void help_scan(void)
{
	g_ntopics = 0;
	const char *env = getenv("HELPPAGE_PATH");
	char path[1024];
	copy_str(path, sizeof path, env && *env ? env : HELP_DIR_DEFAULT);

	for (char *dir = strtok(path, ":"); dir; dir = strtok(NULL, ":")) {
		DIR *d = opendir(dir);
		if (!d) continue;
		struct dirent *e;
		while ((e = readdir(d))) {
			if (e->d_name[0] == '.') continue;
			help_scan_file(dir, e->d_name);
		}
		closedir(d);
	}
	qsort(g_topics, (size_t)g_ntopics, sizeof g_topics[0], topic_cmp);
}

/* ---- the body, wrapped once per (topic, language, width) ---------------- */

static char         **g_hl = NULL;      /* wrapped display lines */
static unsigned char *g_ha = NULL;      /* the attribute for each */
static int g_nhl = 0, g_hlcap = 0;
static int g_hl_topic = -1, g_hl_lang = -1, g_hl_cols = -1;

static void help_free(void)
{
	for (int i = 0; i < g_nhl; i++) free(g_hl[i]);
	free(g_hl); free(g_ha);
	g_hl = NULL; g_ha = NULL; g_nhl = g_hlcap = 0;
	g_hl_topic = g_hl_lang = g_hl_cols = -1;
}

static void help_push(const char *text, int attr)
{
	if (g_nhl == g_hlcap) {
		int cap = g_hlcap ? g_hlcap * 2 : 256;
		char **lines = realloc(g_hl, (size_t)cap * sizeof *lines);
		unsigned char *attrs = realloc(g_ha, (size_t)cap);
		if (!lines || !attrs) { free(lines); free(attrs); return; }
		g_hl = lines; g_ha = attrs; g_hlcap = cap;
	}
	size_t n = strlen(text);
	char *copy = xmalloc(n + 1);
	memcpy(copy, text, n + 1);
	g_hl[g_nhl] = copy;
	g_ha[g_nhl] = (unsigned char)attr;
	g_nhl++;
}

/* A blank row, unless the last one already is. The files have a blank line
 * around every heading and the parser adds its own, and two blank rows in a
 * row read as something missing rather than as spacing. */
static void help_blank(void)
{
	if (g_nhl && !*g_hl[g_nhl - 1]) return;
	help_push("", P_WIN);
}

/* A paragraph, reflowed to the pane rather than re-wrapped line by line.
 *
 * The files are hard-wrapped at about 76 columns so that `cat` and an editor
 * both show them properly, and a pane is almost never 76 columns wide. Taking
 * each source line as its own paragraph produced exactly what you would
 * expect and nobody wants: every line broken into a long one and a stub. So
 * the lines of a paragraph are joined back into one string and wrapped once,
 * at whatever width the pane turned out to be.
 *
 * `lead` is a bullet's or a numbered item's marker, and the continuation rows
 * are indented by its width so they line up under its first word instead of
 * under the dash.
 */
static void help_para(const char *text, const char *lead, int cols, int attr)
{
	static char wrap[128][512];
	char indent[16];
	size_t leadw = strlen(lead);
	if (leadw >= sizeof indent) leadw = sizeof indent - 1;
	memset(indent, ' ', leadw);
	indent[leadw] = '\0';

	int inner = cols - (int)leadw;
	if (inner < 8) inner = 8;
	int n = u8wrap(text, inner, wrap, 128);
	if (n < 1) { help_push("", attr); return; }
	for (int i = 0; i < n; i++) {
		char out[640];
		/* The precision is what tells the compiler this cannot overrun: a
		 * wrapped row is one row of `wrap`, and nothing longer. */
		snprintf(out, sizeof out, "%s%.*s", i == 0 ? lead : indent,
		         (int)sizeof wrap[0] - 1, wrap[i]);
		help_push(out, attr);
	}
}

/* An indented line: something to type, or a two-column table of commands and
 * what they do. It keeps its own indentation and is never reflowed with the
 * prose around it — but when it is wider than the pane it is *wrapped*, at
 * its own indent plus two, rather than cut off with an ellipsis. Cutting one
 * of these loses the half that says what the command is for, in a window
 * whose whole job is explaining that.
 */
static void help_literal(const char *line, int cols)
{
	static char wrap[64][512];
	if (u8width(line) <= cols) { help_push(line, P_RUN); return; }

	int ind = 0;
	while (line[ind] == ' ') ind++;
	if (ind > 24) ind = 24;
	char pad[32];
	memset(pad, ' ', (size_t)ind + 2);
	pad[ind + 2] = '\0';

	int inner = cols - ind - 2;
	if (inner < 12) inner = 12;
	int n = u8wrap(line + ind, inner, wrap, 64);
	for (int i = 0; i < n; i++) {
		char out[640];
		snprintf(out, sizeof out, "%.*s%.*s", i == 0 ? ind : ind + 2, pad,
		         (int)sizeof wrap[0] - 1, wrap[i]);
		help_push(out, P_RUN);
	}
}

/* How a source line opens: "- " for a bullet, "1. " for a numbered item, and
 * the width of that marker is the hanging indent its continuations get. */
static int help_marker(const char *line, char *out, size_t cap)
{
	if (!strncmp(line, "- ", 2)) { copy_str(out, cap, "- "); return 2; }
	if (isdigit((unsigned char)line[0])) {
		const char *p = line;
		while (isdigit((unsigned char)*p)) p++;
		if (p[0] == '.' && p[1] == ' ') {
			size_t n = (size_t)(p - line) + 2;
			if (n < cap) { memcpy(out, line, n); out[n] = '\0'; return (int)n; }
		}
	}
	out[0] = '\0';
	return 0;
}

static void help_build(int topic, int cols)
{
	int lang = g_zh ? 1 : 0;
	if (topic == g_hl_topic && lang == g_hl_lang && cols == g_hl_cols) return;
	help_free();
	g_hl_topic = topic; g_hl_lang = lang; g_hl_cols = cols;
	if (topic < 0 || topic >= g_ntopics) return;

	FILE *f = fopen(help_path(&g_topics[topic]), "r");
	if (!f) { help_push(S(T_NOGUIDE), P_WARN); return; }

	char line[1024];
	int inheader = 1, bytes = 0;
	char para[4096] = "", lead[16] = "";

	/* One paragraph's worth of source lines have accumulated; wrap them as
	 * one thing and start the next. */
	#define HELP_FLUSH() do { \
		if (*para) { help_para(para, lead, cols, P_WIN); para[0] = '\0'; lead[0] = '\0'; } \
	} while (0)

	while (fgets(line, sizeof line, f)) {
		bytes += (int)strlen(line);
		if (bytes > HELP_MAXBYTES) break;
		line[strcspn(line, "\r\n")] = '\0';

		if (inheader) {
			Topic scratch;
			memset(&scratch, 0, sizeof scratch);
			if (help_meta(&scratch, lang, line)) continue;
			inheader = 0;
			if (!*line) continue;          /* the blank line under the header */
		}

		size_t n = strlen(line);
		if (n > 4 && !strncmp(line, "== ", 3) && !strcmp(line + n - 3, " ==")) {
			HELP_FLUSH();
			char head[256];
			copy_str(head, sizeof head, line + 3);
			head[strlen(head) - 3] = '\0';
			trim(head);
			help_blank();
			help_push(head, P_TITLE);
			help_push("", P_WIN);
			continue;
		}
		if (!strncmp(line, "    ", 4)) {   /* something to type, or a table */
			HELP_FLUSH();
			help_literal(line, cols);
			continue;
		}
		if (!*line) { HELP_FLUSH(); help_blank(); continue; }

		/* A marker starts a paragraph of its own; one to three leading
		 * spaces are a continuation of the one being built, which is how a
		 * bullet's second line is written in the file. */
		char mark[16];
		int mw = help_marker(line, mark, sizeof mark);
		const char *rest = line;
		if (mw) {
			HELP_FLUSH();
			copy_str(lead, sizeof lead, mark);
			rest = line + mw;
		} else {
			while (*rest == ' ') rest++;
		}
		if (*para) {
			size_t have = strlen(para);
			/* Joining two source lines usually wants a space between them —
			 * they were one sentence before the file was hard-wrapped. Not
			 * in Chinese: there are no spaces between characters there, and
			 * one inserted at every line break of the file put a gap in the
			 * middle of a word on every third line. Either side being
			 * multibyte is enough to know this is that case. */
			int cjk = (unsigned char)para[have - 1] >= 0x80 ||
			          (unsigned char)rest[0] >= 0x80;
			snprintf(para + have, sizeof para - have, "%s%s", cjk ? "" : " ", rest);
		} else {
			copy_str(para, sizeof para, rest);
		}
	}
	HELP_FLUSH();
	#undef HELP_FLUSH
	fclose(f);
	/* Two blank rows at the end, so the last line of a page can sit at the
	 * top of the pane instead of being pinned to the bottom of it. */
	help_push("", P_WIN);
	help_push("", P_WIN);
}

/* ---- one frame ---------------------------------------------------------- */

/* Two places the cursor can be, and left and right are how it crosses between
 * them: the contents pane on one side, the text on the other. That is the
 * whole navigation model, and it is the one every two-pane reader has, from a
 * mail client to a file manager — the arrows move within a pane, and the pair
 * pointing at the other pane go to it.
 *
 * The language switch is the first thing in the contents pane and the first
 * thing the cursor is on when the program opens. It used to be up on the blue
 * bar with Back, which is the right place for a control nobody is looking for
 * and the wrong one for the control a reader who cannot read this page opens
 * the program already wanting.
 */
enum { GZ_NAV = 0, GZ_BODY };
#define NAV_LANG (-1)

/* The top of the contents pane: the language switch when the terminal can draw
 * it, and the first chapter when it cannot. Everything that walks the cursor
 * up the pane stops here. */
static int nav_top(void) { return g_utf8 ? NAV_LANG : 0; }

/* Draws the whole screen and reports back what the key handler cannot work out
 * for itself — how tall the body pane turned out, how many lines are in it,
 * and whether the contents pane is showing at all. scroll and cur are clamped
 * here, which is why they are passed by address: the geometry is what decides
 * how far down it is possible to be. */
static void help_draw(int topic, int zone, int nav, int *scroll, int *cur,
                      int *body_h, int *total, int *has_nav)
{
	term_measure();
	grid_size(g_w, g_h);
	/* Before draw_root, not after. The bar registers Back and its own
	 * language button as it draws them, and clearing afterwards threw both
	 * away — which is why the language up there could be seen and not
	 * clicked. Every other screen in this file clears first. */
	hit_clear();
	g_showtop = 1;
	draw_root();

	int top = g_h >= 18 ? 3 : 2;
	int h = g_h - top - 1;
	if (h < 5) h = 5;

	int widest = u8width(S(T_CONTENTS));
	for (int i = 0; i < g_ntopics; i++) {
		int w = u8width(help_title(&g_topics[i])) + 2;
		if (w > widest) widest = w;
	}
	/* The switch is in this pane now, so the pane is at least as wide as it
	 * is. A control cut in half is worse than a wider pane. */
	if (widest < lang_width()) widest = lang_width();
	int cw = widest + 4;
	if (cw > 30) cw = 30;
	if (cw < 18) cw = 18;
	/* The contents pane costs its own width plus a border, and what it costs
	 * is the width of the tables of commands in the pages. On an 80-column
	 * terminal — still the most common one — the body is better off with the
	 * whole screen and the reader with one pane. What the pane holds is still
	 * reachable without it: n and p turn the chapters, L switches the
	 * language, and the bar's own button does too. */
	int show_contents = (g_w >= cw + 56);
	if (has_nav) *has_nav = show_contents;
	if (!show_contents) zone = GZ_BODY;

	int bcol = show_contents ? 1 + cw + 1 : 1;
	int bw = g_w - bcol - 1;
	if (bw < 20) bw = 20;

	if (show_contents) {
		win_box(top, 1, cw, h, S(T_CONTENTS));

		/* No switch on a terminal that cannot draw the language it would
		 * switch to. The bar's own button has always been held to this, and a
		 * control labelled in mojibake is worse than no control — so on such
		 * a terminal the pane is the chapters and nothing else. */
		int offer_lang = g_utf8;
		if (offer_lang) {
			draw_lang(top + 1, 1 + (cw - lang_width()) / 2,
			          zone == GZ_NAV && nav == NAV_LANG);
			/* A rule under it, joined to the box on both sides. The switch is
			 * not a chapter, and walking the cursor past it should feel like
			 * leaving one thing for a list of others. */
			gput(top + 2, 1, BX_LT, P_BORDER, 1);
			gfill(top + 2, 2, cw - 2, BX_H, P_BORDER);
			gput(top + 2, cw, BX_RT, P_BORDER, 1);
		}

		int first = top + (offer_lang ? 3 : 1);
		int rows  = h - (offer_lang ? 4 : 2);
		for (int i = 0; i < g_ntopics && i < rows; i++) {
			int row = first + i;
			int open = (i == topic);
			int foc  = (zone == GZ_NAV && nav == i);
			char label[128];
			snprintf(label, sizeof label, "%s %s", open ? AR_R : " ",
			         help_title(&g_topics[i]));
			/* Which chapter is open and where the cursor is are two different
			 * facts, and while the cursor is in the text they are on two
			 * different sides of the screen. The open one keeps the arrow and
			 * the selection colour; only the focused one gets the cursor. */
			gput(row, 2, label, foc ? P_CURSOR : (open ? P_SEL : P_WIN), cw - 2);
			if (foc) cursor_sweep(row, 2, cw - 2, P_CURSOR, P_CURSORHOT);
			hit_add(H_CHIP, i, row, 1, 1, cw);
		}
	}

	const char *title = topic >= 0 && topic < g_ntopics ? help_title(&g_topics[topic]) : S(T_GTITLE);
	win_box(top, bcol, bw, h, title);
	/* One column narrower than the pane allows, so a line that wraps to the
	 * full width still has air between its last letter and the scroll bar. */
	int inner = bw - 5;
	int body = h - 2;
	help_build(topic, inner);

	/* The cursor is a line of the document, and the viewport is whatever has
	 * to be true for it to be on the screen — but only while the text has the
	 * focus. With the cursor in the contents the viewport is its own: the
	 * wheel and the page keys move it, and the line cursor is dragged along
	 * behind so it is where the eye left it when the focus comes back. */
	if (*cur > g_nhl - 1) *cur = g_nhl - 1;
	if (*cur < 0) *cur = 0;
	if (zone == GZ_BODY) {
		if (*scroll > *cur) *scroll = *cur;
		if (*scroll < *cur - body + 1) *scroll = *cur - body + 1;
	}
	if (*scroll > g_nhl - body) *scroll = g_nhl - body;
	if (*scroll < 0) *scroll = 0;
	if (*cur < *scroll) *cur = *scroll;
	if (*cur > *scroll + body - 1) *cur = *scroll + body - 1;
	if (*cur > g_nhl - 1) *cur = g_nhl - 1;
	if (*cur < 0) *cur = 0;

	for (int i = 0; i < body && *scroll + i < g_nhl; i++) {
		int line = *scroll + i;
		gput(top + 1 + i, bcol + 2, g_hl[line], g_ha[line], inner);
		/* One hit target per row rather than one for the pane, so a click
		 * lands the cursor on the line under the pointer. */
		hit_add(H_BODY, line, top + 1 + i, bcol + 1, 1, bw - 2);
		/* The cursor is a mark in the gutter, not the line repainted: these
		 * pages colour their headings and the commands in them, and a cursor
		 * that ate those colours would cost more than it told you. */
		if (zone == GZ_BODY && line == *cur) {
			gput(top + 1 + i, bcol + 1, AR_R, P_CURSOR, 1);
			cursor_sweep(top + 1 + i, bcol + 1, 1, P_CURSOR, P_CURSORHOT);
		}
	}
	scrollbar(top + 1, bcol + bw - 2, body, *scroll, body, g_nhl,
	          zone == GZ_BODY ? P_CURSOR : P_SBTHUMBW, P_SBTRACKW);

	if (g_nhl > body) {
		char sb[32];
		snprintf(sb, sizeof sb, " %d%% ", (*scroll + body >= g_nhl) ? 100
		                                  : (*scroll * 100) / (g_nhl - body));
		int sw = u8width(sb);
		gput(top + h - 1, bcol + bw - 3 - sw, sb,
		     zone == GZ_BODY ? P_CURSOR : P_TITLE, sw);
	}
	help_line_l(!show_contents ? &T_GKEYSONE
	            : zone == GZ_BODY ? &T_GKEYSBODY : &T_GKEYSNAV);

	if (body_h) *body_h = body;
	if (total) *total = g_nhl;
}

static void screen_help(void)
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

	term_raw();
	atexit(term_cooked);

	/* Per chapter, so walking the contents and coming back to one lands where
	 * it was left rather than at its top. */
	static int scroll[HELP_MAXTOPIC], curline[HELP_MAXTOPIC];
	int topic = 0, zone = GZ_NAV, nav = nav_top();

	for (;;) {
		int body = 1, total = 1, has_nav = 1;
		help_draw(topic, zone, nav, &scroll[topic], &curline[topic],
		          &body, &total, &has_nav);
		grid_flush();

		int k = read_key();
		if (k == K_NONE || k == K_RESIZE || k == K_TIMEOUT) continue;

		/* A terminal too narrow for the contents pane has one pane, and the
		 * cursor cannot be in the one that is not on the screen. */
		if (!has_nav) zone = GZ_BODY;

		if (k == 'q' || k == 'Q' || k == K_ESC) { term_cooked(); return; }
		/* The shortcut, held to the same rule as the switch itself: a
		 * terminal that cannot draw 中文 must not be put into it. */
		if (k == 'L') { if (g_utf8) g_zh = !g_zh; continue; }
		/* The chapters, from either pane and without moving the cursor out of
		 * the text. Turning forward past the end of one is what turning a page
		 * means, so the next starts at its own top. */
		if (k == 'n' && topic + 1 < g_ntopics) {
			topic++; scroll[topic] = 0; curline[topic] = 0;
			if (zone == GZ_NAV) nav = topic;
			continue;
		}
		if (k == 'p' && topic > 0) {
			topic--; scroll[topic] = 0; curline[topic] = 0;
			if (zone == GZ_NAV) nav = topic;
			continue;
		}

		if (k == K_CLICK) {
			int idx = 0;
			switch (hit_test(g_my, g_mx, &idx)) {
			case H_BACK: term_cooked(); return;
			/* Either switch — the pane's or the bar's — and the cursor comes
			 * to the pane's, so the keyboard carries on from where the hand
			 * was rather than from wherever it had been left. */
			case H_LANG:
				if (!g_utf8) break;
				g_zh = !g_zh;
				if (has_nav) { zone = GZ_NAV; nav = NAV_LANG; }
				break;
			case H_CHIP:
				if (idx >= 0 && idx < g_ntopics) { topic = idx; zone = GZ_NAV; nav = idx; }
				break;
			/* A click in the text is where the reading is: the cursor goes to
			 * the line under the pointer, and the focus goes with it. */
			case H_BODY:
				zone = GZ_BODY;
				curline[topic] = idx;
				break;
			default: break;
			}
			continue;
		}

		/* The wheel acts on the pane it is over, whichever one has the cursor.
		 * Pointing at something and turning the wheel is one gesture and it
		 * should not need a click in front of it. A notch is three lines,
		 * which is what every terminal program does and what a hand expects
		 * from one flick. */
		if (k == K_WHEELUP || k == K_WHEELDN) {
			int down = (k == K_WHEELDN);
			int idx = 0;
			if (has_nav && hit_test(g_my, g_mx, &idx) == H_CHIP) {
				zone = GZ_NAV;
				nav += down ? 1 : -1;
				if (nav < nav_top()) nav = nav_top();
				if (nav > g_ntopics - 1) nav = g_ntopics - 1;
				if (nav >= 0) topic = nav;
			} else {
				zone = GZ_BODY;
				scroll[topic]  += down ? 3 : -3;
				curline[topic] += down ? 3 : -3;
			}
			continue;
		}

		if (zone == GZ_NAV) {
			switch (k) {
			/* Down walks the pane — the switch, then the chapters, and off
			 * the end of the last one into the text. That is the order the
			 * screen is read in by somebody who has just arrived. */
			case K_DOWN: case 'j':
				if (nav + 1 < g_ntopics) { nav++; topic = nav; }
				else zone = GZ_BODY;
				break;
			case K_UP: case 'k':
				if (nav > nav_top()) { nav--; if (nav >= 0) topic = nav; }
				break;
			case K_RIGHT: case K_TAB: zone = GZ_BODY; break;
			case K_HOME: nav = nav_top(); break;
			case K_END:
				if (g_ntopics) { nav = g_ntopics - 1; topic = nav; }
				break;
			case K_ENTER: case ' ':
				if (nav == NAV_LANG) g_zh = !g_zh;
				else zone = GZ_BODY;
				break;
			default: break;
			}
			continue;
		}

		switch (k) {
		case K_UP:   case 'k':
			if (curline[topic] > 0) curline[topic]--;
			/* Off the top of the text and back to the list, which is the only
			 * thing Up from the first line can mean. */
			else if (has_nav) { zone = GZ_NAV; nav = topic; }
			break;
		case K_DOWN: case 'j': curline[topic]++; break;
		/* Left and right are the two panes. Without a contents pane to be in
		 * there is nothing to cross to, and they turn the chapters instead —
		 * on a narrow terminal that is the only way to. */
		case K_LEFT: case K_BTAB:
			if (has_nav) { zone = GZ_NAV; nav = topic; }
			else if (topic > 0) { topic--; scroll[topic] = 0; curline[topic] = 0; }
			break;
		case K_RIGHT: case K_TAB:
			if (!has_nav && topic + 1 < g_ntopics) {
				topic++; scroll[topic] = 0; curline[topic] = 0;
			}
			break;
		/* ^F and ^B, because this is a document and that is what pages a
		 * document everywhere else. Space and PgDn do it too. */
		case 6: case K_PGDN: case ' ': case K_ENTER:
			scroll[topic] += body - 1; curline[topic] += body - 1; break;
		case 2: case K_PGUP: case K_BACK:
			scroll[topic] -= body - 1; curline[topic] -= body - 1; break;
		case K_HOME: case 'g': scroll[topic] = 0;     curline[topic] = 0;     break;
		case K_END:  case 'G': scroll[topic] = total; curline[topic] = total; break;
		default: break;
		}
	}
}

/* One frame as plain text, the same way `app-setup screenshot` does it and
 * for the same reason: this is how the layout is checked at 130, 88 and 46
 * columns without a terminal to hold it in. */
static int help_screenshot(int argc, char **argv)
{
	int w = 100, h = 30, scroll = 0, topic = 0, cur = -1;
	int zone = GZ_NAV, nav = NAV_LANG;
	for (int i = 0; i < argc; i++) {
		if (!strcmp(argv[i], "--width") && i + 1 < argc) w = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--height") && i + 1 < argc) h = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--scroll") && i + 1 < argc) scroll = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--cursor") && i + 1 < argc) cur = atoi(argv[++i]);
		/* Which pane has the cursor, so the three states this screen has are
		 * three frames a rig can take rather than three things to describe. */
		else if (!strcmp(argv[i], "--focus") && i + 1 < argc) {
			const char *f = argv[++i];
			if (!strcmp(f, "lang"))       { zone = GZ_NAV;  nav = NAV_LANG; }
			else if (!strcmp(f, "nav"))   { zone = GZ_NAV;  nav = 0; }
			else                            zone = GZ_BODY;
		}
		else if (!strcmp(argv[i], "--topic") && i + 1 < argc) {
			const char *id = argv[++i];
			for (int t = 0; t < g_ntopics; t++)
				if (!strcmp(g_topics[t].id, id)) topic = t;
		}
	}
	/* --topic is allowed to come after --focus, so the list cursor is put on
	 * the chapter that is open once both have been read. */
	if (zone == GZ_NAV && nav != NAV_LANG) nav = topic;
	if (nav < nav_top()) nav = nav_top();
	/* No --cursor given: the top of what is on the screen, which is where it
	 * would be if somebody had just walked into the text. */
	if (cur < 0) cur = scroll;

	g_w = w > 24 ? w : 24;
	g_h = h > 10 ? h : 10;
	g_anim = 0;
	g_color = 0;

	int body = 0, total = 0, has_nav = 0;
	help_draw(topic, zone, nav, &scroll, &cur, &body, &total, &has_nav);
	grid_dump(stdout);
	printf("\n[topic=%s cols=%d lines=%d scroll=%d cur=%d body=%d "
	       "focus=%s contents=%s %dx%d]\n",
	       g_ntopics ? g_topics[topic].id : "-", g_hl_cols, total, scroll, cur, body,
	       zone == GZ_BODY ? "body" : (nav == NAV_LANG ? "lang" : "nav"),
	       has_nav ? "on" : "off", g_w, g_h);
	return 0;
}

static void helppage_usage(FILE *out)
{
	fprintf(out,
		"Usage: helppage [page]\n"
		"\n"
		"The guide to this container, in a full-screen reader: what ports\n"
		"and domains are for, how to install software, what your limits\n"
		"mean, what a reinstall keeps, and how to get back in.\n"
		"\n"
		"  ↑↓ or j/k     move, scroll  ←→        contents pane / the text\n"
		"  ^F / ^B       page          Home/End  top / bottom\n"
		"  n / p         next / previous chapter, from either side\n"
		"  wheel, click  the mouse works        L  switch language\n"
		"  q or Esc      quit\n"
		"\n"
		"  helppage            open at the first page\n"
		"  helppage ports      open at one, by name\n"
		"  helppage --list     the pages, as a table\n"
		"  helppage --text     one page as plain text, for a pipe\n"
		"\n"
		"Pages are .txt files in /etc/helppage (HELPPAGE_PATH overrides it),\n"
		"named NN-id.en.txt / NN-id.zh.txt. Dropping one in adds a chapter.\n");
}

static int helppage_list(void)
{
	printf("%-14s %-34s %s\n", "PAGE", "TITLE", "SUMMARY");
	for (int i = 0; i < g_ntopics; i++) {
		Topic *t = &g_topics[i];
		const char *sum = t->summary[g_zh ? 1 : 0];
		if (!*sum) sum = t->summary[g_zh ? 0 : 1];
		printf("%-14s %-34s %s\n", t->id, help_title(t), sum);
	}
	return g_ntopics ? 0 : 1;
}

/* The page, unwrapped, for a pipe or a terminal that cannot hold a TUI —
 * `helppage --text ports | less`. The files are meant to read this way. */
static int helppage_text(const char *id)
{
	Topic *t = id ? topic_find(id) : (g_ntopics ? &g_topics[0] : NULL);
	if (!t) { fprintf(stderr, "helppage: no such page: %s\n", id ? id : ""); return 1; }
	FILE *f = fopen(help_path(t), "r");
	if (!f) { fprintf(stderr, "helppage: cannot read %s\n", help_path(t)); return 1; }
	char line[1024];
	int inheader = 1;
	while (fgets(line, sizeof line, f)) {
		if (inheader) {
			Topic scratch;
			memset(&scratch, 0, sizeof scratch);
			char probe[1024];
			copy_str(probe, sizeof probe, line);
			probe[strcspn(probe, "\r\n")] = '\0';
			if (help_meta(&scratch, 0, probe)) continue;
			inheader = 0;
		}
		fputs(line, stdout);
	}
	fclose(f);
	return 0;
}

static int cli_helppage(int argc, char **argv)
{
	/* The bare-word form reaches here before main() has looked at the
	 * environment, so the language is picked up here rather than there. */
	const char *lang = getenv("APP_SETUP_LANG");
	if (lang && (strstr(lang, "zh") || strstr(lang, "ZH"))) g_zh = 1;
	const char *enc = getenv("LC_ALL");
	if (!enc) enc = getenv("LANG");
	g_utf8 = !enc || strstr(enc, "UTF-8") || strstr(enc, "utf8") ||
	         strstr(enc, "UTF8") || strstr(enc, "utf-8");
	if (!g_utf8) g_zh = 0;
	if (getenv("NO_COLOR")) g_color = 0;

	const char *open_id = NULL;
	int want_list = 0, want_text = 0, want_shot = 0;
	for (int i = 0; i < argc; i++) {
		const char *a = argv[i];
		if (!strcmp(a, "--lang") && i + 1 < argc) g_zh = !strncmp(argv[++i], "zh", 2);
		else if (!strcmp(a, "--no-mouse")) g_mouse = 0;
		else if (!strcmp(a, "--no-blink")) g_anim = 0;
		else if (!strcmp(a, "--no-color")) g_color = 0;
		else if (!strcmp(a, "--ascii")) { g_utf8 = 0; g_zh = 0; }
		else if (!strcmp(a, "--list")) want_list = 1;
		else if (!strcmp(a, "--text")) want_text = 1;
		else if (!strcmp(a, "--screenshot")) want_shot = 1;
		else if (!strcmp(a, "--version")) { printf("helppage %s\n", APP_VERSION); return 0; }
		else if (!strcmp(a, "help") || !strcmp(a, "-h") || !strcmp(a, "--help")) {
			helppage_usage(stdout);
			return 0;
		}
		else if (a[0] == '-') continue;          /* a flag for the screenshot */
		else if (!open_id) open_id = a;
	}
	pick_glyphs();
	help_scan();
	/* Every path below that draws anything draws the blue bar, screenshot
	 * included, so the name on it is set before any of them run. */
	g_rootname = &T_GTITLE;
	g_rootsub  = &T_GSUBTITLE;

	if (g_ntopics == 0) {
		fprintf(stderr, "helppage: no pages found in %s\n",
		        getenv("HELPPAGE_PATH") ? getenv("HELPPAGE_PATH") : HELP_DIR_DEFAULT);
		return 1;
	}
	if (want_list) return helppage_list();
	if (want_text) return helppage_text(open_id);

	/* Both remaining paths draw the blue bar, and the bar carries what this
	 * machine is. main() probes before it dispatches, but the bare word
	 * `helppage` never reaches that — found on a real container, where the
	 * facts line read " · · · 0 CPU · RAM 0B". Nothing else here needs it,
	 * so it is probed at the one moment it is about to be shown. */
	probe_system();
	if (want_shot) return help_screenshot(argc, argv);

	if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) {
		/* No terminal to draw in, and somebody still asked for the guide:
		 * give them the page rather than an error about ttys. */
		return helppage_text(open_id);
	}

	g_rootname = &T_GTITLE;
	g_rootsub  = &T_GSUBTITLE;
	if (open_id) {
		Topic *t = topic_find(open_id);
		if (!t) {
			fprintf(stderr, "helppage: no such page: %s\n\n", open_id);
			helppage_list();
			return 1;
		}
	}
	/* screen_help starts on the first page; opening by name is a jump to
	 * that one before the first frame is drawn. */
	if (open_id) {
		Topic *t = topic_find(open_id);
		Topic tmp = *t;                     /* move it to the front, once */
		for (int i = 0; i < g_ntopics; i++) {
			if (&g_topics[i] == t) {
				memmove(&g_topics[1], &g_topics[0], (size_t)i * sizeof(Topic));
				g_topics[0] = tmp;
				break;
			}
		}
	}
	screen_help();
	help_free();
	return 0;
}

/* cli_run's hook, after a successful `install`: the same DOMAIN ADD path
 * `app-setup domain add` uses, just walked by hand instead of typed out —
 * skippable at either question, and the whole thing is skipped already
 * (cli_run's own isatty check) for anything not run at a real terminal. */
static void offer_domain_prompt(void)
{
	printf("\nDomain to point at this container? [Enter to skip] ");
	fflush(stdout);
	char line[256];
	if (!fgets(line, sizeof line, stdin)) return;
	line[strcspn(line, "\r\n")] = '\0';
	char *domain = line;
	while (*domain == ' ' || *domain == '\t') domain++;
	if (*domain == '\0') return;

	printf("Port this container answers on? [80] ");
	fflush(stdout);
	char portline[32];
	const char *port = "80";
	if (fgets(portline, sizeof portline, stdin)) {
		portline[strcspn(portline, "\r\n")] = '\0';
		char *p = portline;
		while (*p == ' ' || *p == '\t') p++;
		if (*p != '\0') port = p;
	}

	char req[700];
	int n = snprintf(req, sizeof req, "DOMAIN ADD %s %s\n", domain, port);
	if (n < 0 || (size_t)n >= sizeof req) {
		fprintf(stderr, "app-setup: that request is too long\n");
		return;
	}
	domain_reply(hqnode_sock_call(req));
}

/* argv[1] if there is one — root naming another local account — otherwise
 * root's own name, whatever this system actually calls uid 0 rather than an
 * assumed "root". */
static const char *passwd_target_account(int argc, char **argv, char *self, size_t selfcap)
{
	if (argc > 1) return argv[1];
	struct passwd *pw = getpwuid(geteuid());
	snprintf(self, selfcap, "%s", (pw && pw->pw_name[0]) ? pw->pw_name : "root");
	return self;
}

/* The one shape this file handles itself: no flags, at most one positional
 * argument. Everything else — passwd -l, -S, -d, any other flag — falls
 * through to the real tool unmodified in passwd_main, further down. */
static int passwd_is_plain(int argc, char **argv)
{
	if (argc <= 1) return 1;
	if (argc == 2 && argv[1][0] != '-') return 1;
	return 0;
}

/* Hand off to the distribution's own passwd, by absolute path rather than by
 * PATH lookup — a PATH search would find this binary again at
 * /usr/local/bin/passwd and fork-bomb the tenant's session. Both names are
 * tried because /bin is only a symlink to /usr/bin on a usrmerged image, and
 * the catalog still carries two that are not (CentOS 7, Ubuntu 16.04).
 * Returns only on failure; on success this process *becomes* the real tool. */
static void passwd_exec_real(char **argv)
{
	execv("/usr/bin/passwd", argv);
	execv("/bin/passwd", argv);
}

/* Unlike passwd, poweroff/halt do not live under /usr/bin or /bin on any
 * base in the catalog — confirmed live across all three families
 * (openrc-alpine, systemd-deb, systemd-rpm): /usr/sbin/poweroff on a
 * usrmerged systemd image (a symlink to systemctl there), /sbin/poweroff on
 * Alpine (busybox), where usrmerge does not reach sbin. Two names for the
 * same reason passwd_exec_real tries two — which one exists varies by base. */
static void shutdown_exec_real(char **argv, const char *name)
{
	char path[64];
	snprintf(path, sizeof path, "/usr/sbin/%s", name);
	execv(path, argv);
	snprintf(path, sizeof path, "/sbin/%s", name);
	execv(path, argv);
}

/* poweroff/halt: tell the daemon first, then become the real tool
 * unconditionally, argv untouched — every flag the real binary understands
 * still behaves exactly as it always has, because this never inspects argv,
 * only forwards it. Unlike passwd this fails *open*: a control-socket hiccup
 * still has to let a tenant power off their own container, an occasional
 * un-suppressed restart is the far smaller failure. reboot is deliberately
 * not shimmed — it already restarts correctly via the kernel's SIGHUP path,
 * with nothing here to add. */
static int shutdown_main(char **argv, const char *name)
{
	stop_call();
	shutdown_exec_real(argv, name);
	fprintf(stderr, "%s: could not run /usr/sbin/%s: %s\n", name, name, strerror(errno));
	return 1;
}

static int passwd_main(int argc, char **argv)
{
	if (geteuid() != 0 || !passwd_is_plain(argc, argv)) {
		/* Not root, or a shape this does not special-case: run the real tool,
		 * inheriting this process's own stdin/stdout/stderr — already the
		 * tenant's real terminal, so its own prompts (a non-root user's
		 * old-password check among them) behave exactly as if the real passwd
		 * had been typed directly. */
		passwd_exec_real(argv);
		fprintf(stderr, "passwd: could not run /usr/bin/passwd: %s\n", strerror(errno));
		return 1;
	}

	char self[64];
	const char *account = passwd_target_account(argc, argv, self, sizeof self);

	printf("New password: ");
	fflush(stdout);
	char pw1[257], pw2[257];
	if (!read_password_line(pw1, sizeof pw1) || pw1[0] == '\0') {
		fprintf(stderr, "passwd: no password entered, nothing changed\n");
		return 1;
	}
	printf("Retype new password: ");
	fflush(stdout);
	read_password_line(pw2, sizeof pw2);
	if (strcmp(pw1, pw2) != 0) {
		fprintf(stderr, "Sorry, passwords do not match.\n");
		return 1;
	}

	/* The gateway is asked before anything local changes, on purpose: a
	 * password its policy refuses must never end up set locally and not on
	 * the login that actually gates the internet. */
	const char *resp = pwsync_call(account, pw1);
	if (!resp) {
		fprintf(stderr,
		        "passwd: could not reach the SSH gateway — %s's password was "
		        "NOT changed. Ask whoever runs this machine if this keeps "
		        "happening.\n", account);
		return 1;
	}
	if (!strncmp(resp, "ERR ", 4)) {
		fprintf(stderr, "passwd: %s\n", resp + 4);
		return 1;
	}
	if (strcmp(resp, "OK") != 0 && strcmp(resp, "OK-NOOP") != 0) {
		fprintf(stderr, "passwd: unexpected answer from the SSH gateway\n");
		return 1;
	}

	/* Accepted — or OK-NOOP, meaning this account has no SSH login on this
	 * container at all, so there was nothing to have disagreed with locally
	 * in the first place. Either way the local account is set the way
	 * scripts already do it: chpasswd takes plaintext on stdin and needs no
	 * controlling terminal, unlike passwd itself. */
	int pfd[2];
	if (pipe(pfd) != 0) {
		fprintf(stderr, "passwd: password changed for the SSH login, but the "
		                "local account could not be updated: %s\n", strerror(errno));
		return 1;
	}
	pid_t pid = fork();
	if (pid < 0) {
		close(pfd[0]);
		close(pfd[1]);
		fprintf(stderr, "passwd: password changed for the SSH login, but the "
		                "local account could not be updated: %s\n", strerror(errno));
		return 1;
	}
	if (pid == 0) {
		close(pfd[1]);
		dup2(pfd[0], STDIN_FILENO);
		close(pfd[0]);
		execlp("chpasswd", "chpasswd", (char *)NULL);
		_exit(127);
	}
	close(pfd[0]);
	char line[600];
	int n = snprintf(line, sizeof line, "%s:%s\n", account, pw1);
	if (n > 0) {
		if (write(pfd[1], line, (size_t)n) < 0) { /* reaped below regardless */ }
	}
	close(pfd[1]);
	int status = 0;
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR) { }
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		fprintf(stderr, "passwd: password changed for the SSH login, but the "
		                "local account could not be updated (chpasswd exit %d)\n",
		                WIFEXITED(status) ? WEXITSTATUS(status) : -1);
		return 1;
	}

	printf("hqnode passwd: password updated successfully\n");
	return 0;
}

/* ------------------------------------------------------------------ main ---*/
int main(int argc, char **argv)
{
	if (argc > 0 && !strcmp(prog_basename(argv[0]), "passwd"))
		return passwd_main(argc, argv);
	if (argc > 0 && !strcmp(prog_basename(argv[0]), "poweroff"))
		return shutdown_main(argv, "poweroff");
	if (argc > 0 && !strcmp(prog_basename(argv[0]), "halt"))
		return shutdown_main(argv, "halt");
	// `domain` on its own, not only `app-setup domain` — the same multicall
	// trick passwd/poweroff/halt already answer to, just with no real system
	// binary standing behind this one to fall through to: argv[1:] is
	// cli_domain's own sub-verb (add/del/ls/help), unlike shutdown_main's
	// argv, which is forwarded whole because a real poweroff/halt is exec'd
	// with it.
	if (argc > 0 && !strcmp(prog_basename(argv[0]), "domain"))
		return cli_domain(argc - 1, argv + 1);
	// And `dashboard` the same way, for the same reason: somebody who has
	// just been handed a box types the word for the thing they want, not the
	// name of the program that happens to provide it.
	if (argc > 0 && !strcmp(prog_basename(argv[0]), "dashboard"))
		return cli_dashboard(argc - 1, argv + 1);
	// And `reinstall`, which is the one of these that is very nearly a system
	// binary: it is what somebody types when they want the box back the way
	// it came, and there is nothing else on the machine by that name.
	if (argc > 0 && !strcmp(prog_basename(argv[0]), "reinstall"))
		return cli_reinstall(argc - 1, argv + 1);
	if (argc > 0 && !strcmp(prog_basename(argv[0]), "helppage"))
		return cli_helppage(argc - 1, argv + 1);

	/* English unless somebody says otherwise, and only APP_SETUP_LANG or
	 * --lang says otherwise. LANG is not consulted: it describes the locale
	 * the terminal was started in, which on a shared box is whatever the
	 * image happened to set, and a picker that comes up in a language the
	 * holder cannot read has hidden its own way out. Switching is one press
	 * of the button in the top right corner, or of L. */
	const char *lang = getenv("APP_SETUP_LANG");
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
		else if (!strcmp(argv[i], "--no-mouse")) g_mouse = 0;
		else if (!strcmp(argv[i], "--no-blink")) g_anim = 0;
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
	else if (!strcmp(cmd, "backup"))  rc = na ? cli_run("backup", na, aa) : (usage(stderr), 2);
	/* Restore takes ids, not filenames — cli_run treats every argument as a
	 * package. Naming one archive out of several is `sh /etc/app-setup/<id>.sh
	 * restore <file>`, which the recipe's own help says. */
	else if (!strcmp(cmd, "restore")) rc = na ? cli_run("restore", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "dump"))    rc = na ? cli_run("dump", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "load"))    rc = na ? cli_run("load", na, aa) : (usage(stderr), 2);
	/* The Backup tab's other three buttons. Without these, a store configured
	 * from a shell — which is how anybody provisioning a container does it —
	 * can never be blessed: every job refuses with "has never passed a
	 * connection test", and the only thing that writes that stamp is a button
	 * on a full-screen picker. `verify` and `archives` are the same argument
	 * one step later: a backup nobody has looked at is a hope, and looking at
	 * it must not require a terminal that can draw. */
	else if (!strcmp(cmd, "test"))    rc = na ? cli_run("test", na, aa) : (usage(stderr), 2);
	else if (!strcmp(cmd, "verify"))  rc = na ? cli_run("verify", na, aa) : (usage(stderr), 2);
	/* Named `archives` because `list` is already this program's catalogue,
	 * and `app-setup list backup` — a category and a recipe with one id
	 * between them — has to keep meaning the tab. */
	else if (!strcmp(cmd, "archives")) rc = na ? cli_run("list", na, aa) : (usage(stderr), 2);
	/* For scripting against an SSH store. The `files` job packs a full tarball
	 * every run, so anybody with a large tree drives rsync themselves — and
	 * rebuilding the store's ssh invocation by hand is where that goes wrong,
	 * because the host key `test` pinned lives in the store's own known_hosts
	 * and not in ~/.ssh. These print what the store itself uses, so a script
	 * does not have to know. */
	else if (!strcmp(cmd, "sshcmd")) rc = cli_print_verb("sshcmd", na, aa);
	else if (!strcmp(cmd, "remote")) rc = cli_print_verb("remote", na, aa);
	else if (!strcmp(cmd, "domain")) rc = cli_domain(na, aa);
	else if (!strcmp(cmd, "dashboard")) rc = cli_dashboard(na, aa);
	else if (!strcmp(cmd, "reinstall")) rc = cli_reinstall(na, aa);
	else if (!strcmp(cmd, "helppage") || !strcmp(cmd, "guide")) rc = cli_helppage(na, aa);
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
