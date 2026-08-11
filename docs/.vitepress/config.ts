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
 */
export default defineConfig({
  title: 'hqno.de',
  description: 'Help for people who hold a container.',
  lang: 'en',

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

  themeConfig: {
    nav: [
      { text: 'Your container', link: '/using-your-container' },
      { text: 'Your own software', link: '/app-setup-sources' },
      { text: 'Panel', link: 'https://hqno.de' },
    ],

    // One flat group while there are four pages. It grows into sections when
    // there is enough to have sections about, and not before: a sidebar with
    // one item under each heading is a table of contents pretending to be a
    // structure.
    sidebar: [
      {
        text: 'Holding a container',
        items: [
          { text: 'Using your container', link: '/using-your-container' },
          { text: 'Adding your own software', link: '/app-setup-sources' },
          { text: 'Building your own image', link: '/building-your-own-image' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/yinyue123/hqno.de' },
    ],

    outline: [2, 3],

    editLink: {
      pattern: 'https://github.com/yinyue123/hqno.de/edit/main/docs/:path',
      text: 'Edit this page on GitHub',
    },

    search: { provider: 'local' },

    footer: {
      message:
        'Running the machines instead? <a href="https://github.com/yinyue123/hqnode/blob/main/docs/operating-the-panel.md">Operating the panel</a>.',
      copyright: 'hqnode',
    },
  },
});
