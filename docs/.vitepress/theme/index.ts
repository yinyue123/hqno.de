import { h } from 'vue';
import DefaultTheme from 'vitepress/theme';
import LangSwitch from './LangSwitch.vue';
import FigScreen from './figures/FigScreen.vue';
import FigRows from './figures/FigRows.vue';
import './custom.css';

/**
 * The default theme, plus one control and two figure components.
 *
 * The control is a language switch at the top of the sidebar, in the shape the
 * panel's rail uses. `sidebar-nav-before` is the same slot on desktop and
 * inside the drawer a phone opens, so it is reachable from both without a
 * second breakpoint to keep true.
 *
 * The figures are registered globally because they are used by name in markdown
 * on both language's copies of three pages, and an import line at the top of
 * every one of those files is six more things that can be wrong. What they are
 * for is in `figures/cells.ts`.
 */
export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'sidebar-nav-before': () => h(LangSwitch),
    });
  },
  enhanceApp({ app }) {
    app.component('FigScreen', FigScreen);
    app.component('FigRows', FigRows);
  },
};
