import { defineConfig } from 'vitepress';

/**
 * hqno.de — the site for someone who has been given a container.
 *
 * `docs/` is the source root because that is what Cloudflare Pages' VitePress
 * preset builds (`npx vitepress build docs` → `docs/.vitepress/dist`), so the
 * project needs no build settings typed in by hand and none to remember when
 * it is set up again.
 *
 * Two things in this repository are deliberately *not* pages, and both are
 * excluded below rather than left to be discovered:
 *
 *   images/     the image build pipeline. `images/catalog.json` is fetched by
 *               every panel at its default PANEL_CATALOG_URL, from
 *               raw.githubusercontent.com/…/main/images/catalog.json — so the
 *               directory cannot move and its README is not a page.
 *   README.md   about the repository, for whoever opens it on GitHub. The site
 *               has its own front page.
 *
 * # Languages
 *
 * English is the root locale, so its addresses are unprefixed and every link
 * anyone has already sent still answers. Chinese lives under `/zh/`, one file
 * per translated page in `docs/zh/`, and the theme grows a language menu on its
 * own from the `locales` below.
 *
 * A locale does not have to be complete. Only the pages a beginner needs are
 * translated so far, and the Chinese sidebar links straight at the English
 * copies of the rest, labelled `（英文）`, rather than either hiding them or
 * pointing at files that do not exist. That is also why the Chinese pages link
 * to `/using-your-container` with an absolute path: a relative link there would
 * resolve to `/zh/using-your-container`, which is nothing.
 */
export default defineConfig({
  title: 'hqno.de',
  description: 'Help for people who hold a container.',

  // Out to `<repo>/.vitepress/dist`, which is where the root config sends a
  // rootless build too. One output directory for every way of starting the
  // build: Cloudflare Pages is given one path and it has to be true whichever
  // command runs, and a deploy already failed on it being true for only one.
  outDir: '../.vitepress/dist',
  cacheDir: '../.vitepress/cache',

  // A page per file, addressed by its own name: /using-your-container rather
  // than /using-your-container.html. Cloudflare Pages serves the directory
  // form without a redirect, so the address someone pastes into a message is
  // the address that answers.
  cleanUrls: true,

  // Nothing outside docs/ is scanned, but the two directories that would be
  // picked up if that ever changes are named here anyway — the cost of being
  // wrong is a published page nobody meant to publish.
  srcExclude: ['**/README.md', 'images/**', 'node_modules/**'],

  // The tab title carries the site name; the page's own <title> is its H1.
  titleTemplate: ':title · hqno.de',

  head: [
    ['meta', { name: 'theme-color', content: '#d97757' }],
    ['link', { rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml' }],
  ],

  locales: {
    root: {
      label: 'English',
      lang: 'en',
      themeConfig: {
        nav: [
          { text: 'Quick start', link: '/quick-start' },
          { text: 'Your container', link: '/using-your-container' },
          { text: 'Hosting', link: '/running-a-machine' },
          { text: 'Panel', link: 'https://hqno.de' },
        ],

        // Three groups, in the order somebody arrives in them: understand it,
        // do it, then — separately — run a machine of your own. Two pages under
        // a heading is the least that earns one; a sidebar with a single item
        // under each is a table of contents pretending to be a structure.
        sidebar: [
          {
            text: 'Start here',
            items: [
              { text: 'How this works', link: '/how-it-works' },
              { text: 'Quick start', link: '/quick-start' },
            ],
          },
          {
            text: 'Holding a container',
            items: [
              { text: 'Using your container', link: '/using-your-container' },
              { text: 'Adding your own software', link: '/app-setup-sources' },
              { text: 'Building your own image', link: '/building-your-own-image' },
            ],
          },
          {
            text: 'Running a machine',
            items: [
              { text: 'Running a machine of your own', link: '/running-a-machine' },
            ],
          },
        ],

        editLink: {
          pattern: 'https://github.com/yinyue123/hqno.de/edit/main/docs/:path',
          text: 'Edit this page on GitHub',
        },

        footer: {
          message:
            'Running the machines instead? <a href="/running-a-machine">Running a machine of your own</a>.',
          copyright: 'hqnode',
        },
      },
    },

    zh: {
      label: '中文',
      lang: 'zh-Hans',
      link: '/zh/',
      title: 'hqno.de',
      description: '给拿到容器的人看的说明。',
      titleTemplate: ':title · hqno.de',

      themeConfig: {
        nav: [
          { text: '快速上手', link: '/zh/quick-start' },
          { text: '它是怎么分开的', link: '/zh/how-it-works' },
          { text: '自己跑一台机器', link: '/zh/running-a-machine' },
          { text: '面板', link: 'https://hqno.de' },
        ],

        sidebar: [
          {
            text: '从这里开始',
            items: [
              { text: '它是怎么分开的', link: '/zh/how-it-works' },
              { text: '快速上手', link: '/zh/quick-start' },
            ],
          },
          {
            text: '你是主机方',
            items: [
              { text: '自己跑一台机器', link: '/zh/running-a-machine' },
            ],
          },
          {
            // Not yet translated, and said so rather than hidden: somebody
            // hunting for the limits page should find it in the language it
            // exists in instead of concluding it does not exist.
            text: '还没翻译的页面',
            items: [
              { text: '使用你的容器（英文）', link: '/using-your-container' },
              { text: '添加你自己的软件（英文）', link: '/app-setup-sources' },
              { text: '自己做镜像（英文）', link: '/building-your-own-image' },
            ],
          },
        ],

        outlineTitle: '本页目录',
        returnToTopLabel: '回到顶部',
        sidebarMenuLabel: '目录',
        darkModeSwitchLabel: '深色模式',
        lightModeSwitchTitle: '切换到浅色',
        darkModeSwitchTitle: '切换到深色',
        langMenuLabel: '切换语言',
        docFooter: { prev: '上一页', next: '下一页' },
        lastUpdatedText: '最后更新',

        editLink: {
          pattern: 'https://github.com/yinyue123/hqno.de/edit/main/docs/:path',
          text: '在 GitHub 上修改这一页',
        },

        footer: {
          message:
            '你是跑机器的那一边？看 <a href="/zh/running-a-machine">自己跑一台机器</a>。',
          copyright: 'hqnode',
        },
      },
    },
  },

  themeConfig: {
    socialLinks: [
      { icon: 'github', link: 'https://github.com/yinyue123/hqno.de' },
    ],

    outline: [2, 3],

    // One index, both languages: VitePress builds a separate one per locale and
    // the Chinese half needs its own words for the empty and shortcut states.
    search: {
      provider: 'local',
      options: {
        locales: {
          zh: {
            translations: {
              button: { buttonText: '搜索', buttonAriaLabel: '搜索' },
              modal: {
                displayDetails: '显示详情',
                resetButtonTitle: '清空',
                backButtonTitle: '返回',
                noResultsText: '没有找到',
                footer: {
                  selectText: '选择',
                  navigateText: '切换',
                  closeText: '关闭',
                },
              },
            },
          },
        },
      },
    },
  },
});
