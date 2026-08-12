<script setup lang="ts">
/**
 * A screen: the panel, or the installer, drawn as a titled frame with lines in
 * it. This replaces the `┌ Title ─────┐` boxes the pages used to draw in text,
 * which had to be a fixed number of columns wide and so could not hold a
 * Chinese label without coming out ragged.
 *
 * Every line is an array of cells and the cells are laid out on one grid shared
 * by the whole screen, so labels line up down the left the way they do in a
 * real form without anybody counting spaces. A line can opt out with
 * `align: 'right'` — that is the row of buttons at the bottom of a dialog.
 */
import { computed } from 'vue';
import Cell from './Cell.vue';
import { w, wmax } from './measure';
import { cellW, grid, rowsWidth, type Cell as C, ROW, PAD } from './cells';

const props = withDefaults(
  defineProps<{
    title?: string;
    /** right-hand end of the title bar, e.g. `2 of 10` */
    right?: string;
    /** a tab strip instead of a plain title; the first is the open one */
    tabs?: string[];
    /**
     * A line is an array of cells on the screen's shared column grid — which is
     * what makes a form's labels line up without anybody counting spaces.
     * `pack` opts out and butts the cells together instead: a row of buttons
     * wants to be a row of buttons, not column four of a table.
     */
    lines: (C[] | { cols?: C[]; align?: 'right'; pack?: boolean })[];
    /** widen the frame past its contents, to sit beside another screen */
    min?: number;
  }>(),
  { min: 0 },
);

const norm = computed(() =>
  props.lines.map((l) =>
    Array.isArray(l)
      ? { cols: l, align: undefined as 'right' | undefined, pack: false }
      : { cols: l.cols ?? [], align: l.align, pack: !!l.pack },
  // A line with one cell has nothing to line up with, and letting it set a
  // column width is how a caption at the foot of a screen shoves the whole
  // form sideways. So it packs, which for a single cell means: start at PAD.
  ).map((l) => ({ ...l, pack: l.align !== 'right' && (l.pack || l.cols.length < 2) })),
);
const gridded = computed(() => norm.value.filter((l) => l.align !== 'right' && !l.pack).map((l) => l.cols));
const packW = computed(() =>
  norm.value.filter((l) => l.pack).reduce((m, l) => Math.max(m, l.cols.reduce((a, c) => a + cellW(c) + 10, -10)), 0),
);
const xs = computed(() => grid(gridded.value));

const head = computed(() => {
  if (props.tabs?.length) return props.tabs.join('   ');
  return props.title ?? '';
});
// The title is drawn at 600 weight and the tab strip's gaps are a `dx`, not
// spaces — measure what is actually drawn, or the frame ends inside its name.
const headW = computed(() =>
  props.tabs?.length
    ? props.tabs.reduce((a, s) => a + w(s, 'title', true), 0) + 12 * (props.tabs.length - 1)
    : w(head.value, 'title', true),
);

const bodyW = computed(() => rowsWidth(gridded.value));
const rightW = computed(() =>
  norm.value.filter((l) => l.align === 'right').reduce((m, l) => {
    const inner = l.cols.reduce((a, c) => a + cellW(c) + 14, -14);
    return Math.max(m, inner);
  }, 0),
);

const W = computed(() =>
  Math.max(props.min, bodyW.value + PAD * 2, rightW.value + PAD * 2, packW.value + PAD * 2, headW.value + 54, 260),
);
const H = computed(() => 22 + norm.value.length * ROW + 14);

/** x of each line's first cell, and the per-line offsets for a right-aligned one. */
function lineX(i: number, j: number): number {
  const l = norm.value[i];
  if (l.pack) {
    let at = PAD;
    for (let k = 0; k < j; k++) at += cellW(l.cols[k]) + 10;
    return at;
  }
  if (l.align !== 'right') return PAD + xs.value[j];
  let at = W.value - PAD;
  for (let k = l.cols.length - 1; k > j; k--) at -= cellW(l.cols[k]) + 14;
  return at - cellW(l.cols[j]);
}
const cy = (i: number) => 30 + i * ROW + ROW / 2;
</script>

<template>
  <svg class="fig fig-fit" :width="W" :height="H" :viewBox="`0 0 ${W} ${H}`" role="img" :aria-label="head">
    <rect class="f-frame" x="0.5" y="10.5" :width="W - 1" :height="H - 11" rx="8" />
    <rect class="f-legend" x="12" y="3" :width="headW + 16" height="15" />
    <text v-if="tabs?.length" class="f-t f-title" x="20" y="15"><tspan
        v-for="(t, i) in tabs" :key="t" :dx="i ? 12 : 0" :class="i === 0 ? 'f-on' : 'f-mute'">{{ t }}</tspan></text>
    <text v-else class="f-t f-title" x="20" y="15">{{ title }}</text>
    <template v-if="right">
      <rect class="f-legend" :x="W - 28 - w(right, 'small')" y="3" :width="w(right, 'small') + 16" height="15" />
      <text class="f-t f-sm f-mute" :x="W - 20 - w(right, 'small')" y="15">{{ right }}</text>
    </template>
    <template v-for="(l, i) in norm" :key="i">
      <Cell v-for="(c, j) in l.cols" :key="j" :c="c" :x="lineX(i, j)" :cy="cy(i)" />
    </template>
  </svg>
</template>
