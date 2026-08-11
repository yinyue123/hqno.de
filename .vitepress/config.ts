import baseConfig from '../docs/.vitepress/config';

/**
 * The same site, built from the repository root.
 *
 * VitePress takes its root from the argument it is given, and `docs/` is the
 * one this site is written for — `npx vitepress build docs`, which loads
 * `docs/.vitepress/config.ts` next door to the pages. That is still the
 * documented command and still what `npm run docs:build` runs.
 *
 * This exists because the argument is easy to lose. Without it VitePress takes
 * the repository root instead, finds no config at all, and treats every
 * markdown file in the tree as a page — including `images/README.md`, whose
 * link to the `app-setup/` source directory is correct on GitHub and is not a
 * page anywhere. Three Cloudflare Pages deploys died on exactly that, and the
 * build command lives in a dashboard rather than in this repository, so the
 * repository is the wrong place to keep being right about it.
 *
 * So the rootless build is made to mean the same thing as the other one rather
 * than a different, worse thing: same pages, same theme, same output
 * directory. There is no second copy of the configuration — only `srcDir` and
 * `outDir`, which are the two settings that depend on where the build started.
 */
export default {
  ...baseConfig,
  srcDir: 'docs',
  outDir: 'docs/.vitepress/dist',
  cacheDir: 'docs/.vitepress/cache',
};
