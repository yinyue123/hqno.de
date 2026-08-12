<script setup lang="ts">
/**
 * Rows of cells on a shared grid, with an arrow in one of the gaps: the shape
 * behind most of the small figures on this site — *this* leads to *that*, three
 * or four times over.
 *
 * `arrow` is which gap gets it (0 is between the first and second column), and
 * a row can suppress its own with a `null` where the arrow would be, which is
 * how a continuation line hangs under the row above it.
 *
 * `head` is an optional column-title row with a rule under it, for the figures
 * that are really small tables — what a visitor types against where it lands.
 */
import { computed } from 'vue';
import Cell from './Cell.vue';
import { cellW, grid, rowsWidth, type Cell as C, ROW } from './cells';

const props = withDefaults(
  defineProps<{
    rows: (C[] | { cols: C[]; arrow?: false })[];
    head?: string[];
    /** index of the gap the arrow sits in; -1 for none */
    arrow?: number;
    gap?: number;
  }>(),
  { arrow: -1, gap: 18 },
);

const ARROW = 36;
const norm = computed(() =>
  props.rows.map((r) => (Array.isArray(r) ? { cols: r, arrow: true } : { cols: r.cols, arrow: r.arrow !== false })),
);

/** The arrow lives in a gap, so that gap has to be wide enough to hold it. */
const gaps = computed(() => props.gap + (props.arrow >= 0 ? ARROW + 14 : 0));
const bodies = computed(() => norm.value.map((r) => r.cols));
const headRow = computed(() => (props.head ? [props.head as C[]] : []));
const all = computed(() => [...headRow.value, ...bodies.value]);

const xs = computed(() => {
  // One grid for every row including the head, but only the arrow's gap is wide.
  const n = all.value.reduce((m, r) => Math.max(m, r.length), 0);
  const wide: number[] = [];
  for (let i = 0; i < n; i++) wide[i] = all.value.reduce((m, r) => Math.max(m, cellW(r[i] ?? null)), 0);
  const x: number[] = [];
  let at = 14;
  for (let i = 0; i < n; i++) {
    x[i] = at;
    at += wide[i] + (i === props.arrow ? gaps.value : props.gap);
  }
  return x;
});
const colW = computed(() => {
  const n = all.value.reduce((m, r) => Math.max(m, r.length), 0);
  const wide: number[] = [];
  for (let i = 0; i < n; i++) wide[i] = all.value.reduce((m, r) => Math.max(m, cellW(r[i] ?? null)), 0);
  return wide;
});

const top = computed(() => (props.head ? ROW + 10 : 6));
const W = computed(() => {
  const n = colW.value.length;
  return Math.ceil(xs.value[n - 1] + colW.value[n - 1] + 18);
});
const H = computed(() => top.value + norm.value.length * ROW + 6);
const cy = (i: number) => top.value + i * ROW + ROW / 2;
const arrowX = computed(() => (props.arrow < 0 ? 0 : xs.value[props.arrow] + colW.value[props.arrow] + 16));

const label = computed(() =>
  norm.value.map((r) => r.cols.filter((c) => typeof c === 'string').join(' ')).join('; '),
);
</script>

<template>
  <svg class="fig fig-fit" :width="W" :height="H" :viewBox="`0 0 ${W} ${H}`" role="img" :aria-label="label">
    <defs>
      <marker id="fr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
        <path class="f-head" d="M0,0 L10,5 L0,10 z" />
      </marker>
    </defs>
    <template v-if="head">
      <text v-for="(h, j) in head" :key="j" class="f-t f-sm f-mute" :x="xs[j]" :y="16">{{ h }}</text>
      <path class="f-rule" :d="`M14,${ROW + 1} H${W - 14}`" />
    </template>
    <template v-for="(r, i) in norm" :key="i">
      <Cell v-for="(c, j) in r.cols" :key="j" :c="c" :x="xs[j]" :cy="cy(i)" />
      <!-- A row whose left-hand cell is empty is a continuation of the one
           above it, and a second arrow pointing at the same thing reads as a
           second claim. -->
      <path v-if="arrow >= 0 && r.arrow && r.cols.length > arrow + 1 && r.cols[arrow] != null && r.cols[arrow + 1] != null"
        class="f-ln" :d="`M${arrowX},${cy(i)} h${ARROW - 8}`" marker-end="url(#fr)" />
    </template>
  </svg>
</template>
