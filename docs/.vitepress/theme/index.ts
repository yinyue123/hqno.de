import { h } from 'vue';
import DefaultTheme from 'vitepress/theme';
import LangSwitch from './LangSwitch.vue';
import './custom.css';

/**
 * The default theme, plus one control: a language switch at the top of the
 * sidebar, in the shape the panel's rail uses. `sidebar-nav-before` is the same
 * slot on desktop and inside the drawer a phone opens, so it is reachable from
 * both without a second breakpoint to keep true.
 */
export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'sidebar-nav-before': () => h(LangSwitch),
    });
  },
};
