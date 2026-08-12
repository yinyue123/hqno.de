<script setup lang="ts">
/**
 * The language switch that stands at the top of the sidebar.
 *
 * VitePress already grows one in the nav bar from the `locales` block, and it
 * stays. This is a second one, in the rail, for the same reason the panel has
 * one there (`web/components/lang-switch.tsx`): the nav bar is where somebody
 * looks *once*, on the way in, and a reader who is three pages deep and wants
 * the other language is looking at the sidebar. It is the panel's control, in
 * the panel's shape, so the two halves of the product read as one.
 *
 * Two locales, so this is a link rather than a menu — it always names the
 * language you are *not* reading, in that language's own words. A third one
 * makes that sentence false: this becomes a list, the way the panel's already
 * is, and the nav bar's menu is the shape to copy.
 *
 * The Chinese locale is deliberately partial (README.md), so a straight prefix
 * swap would send half the English pages at a URL that does not exist.
 * `themeConfig.translated` is the list of pages that do, written by
 * `config.ts` from the directory itself, so it cannot drift from what is on
 * disk. Anything not on it falls back to the Chinese front page and says so
 * rather than promising a translation it does not have.
 */
import { computed } from 'vue';
import { useData, withBase } from 'vitepress';

const { page, theme, localeIndex } = useData();

const other = computed(() => {
  // 'zh/how-it-works.md' → 'zh/how-it-works' · 'index.md' → '' · 'zh/index.md' → 'zh'
  const rel = page.value.relativePath
    .replace(/\.md$/, '')
    .replace(/(^|\/)index$/, '');

  if (localeIndex.value === 'zh') {
    const name = rel.replace(/^zh\/?/, '');
    return { link: `/${name}`, label: 'English', lang: 'en', title: 'Read this in English', partial: false };
  }

  const translated: string[] = theme.value.translated ?? [];
  const has = rel !== '' && translated.includes(rel);
  return {
    link: has ? `/zh/${rel}` : '/zh/',
    label: '中文',
    lang: 'zh-Hans',
    title: rel === '' || has ? '用中文读这一页' : '这一页还没有中文 —— 去中文首页',
    partial: !(rel === '' || has),
  };
});
</script>

<template>
  <a
    class="langsw"
    :href="withBase(other.link)"
    :title="other.title"
    :data-partial="String(other.partial)"
  >
    <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" aria-hidden="true">
      <circle cx="12" cy="12" r="9" />
      <path d="M3.2 9.5h17.6M3.2 14.5h17.6" />
      <path d="M12 3a15 15 0 0 1 0 18a15 15 0 0 1 0-18" />
    </svg>
    <span class="langsw-name" :lang="other.lang">{{ other.label }}</span>
  </a>
</template>
