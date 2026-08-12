<script setup lang="ts">
/**
 * One cell, drawn at (`x`, `cy`) — `cy` being the line's centre, so text and
 * boxes on the same line sit on the same axis whatever their heights are.
 */
import { computed } from 'vue';
import { w } from './measure';
import type { Cell } from './cells';

const props = defineProps<{ c: Cell; x: number; cy: number }>();

const s = computed(() => (typeof props.c === 'string' ? { t: props.c } : props.c) as any);
const tone = computed(() => (s.value?.tone ? ` f-${s.value.tone}` : ''));
const face = computed(() => (s.value?.face === 'small' ? ' f-sm' : s.value?.face === 'mono' ? ' f-mono' : ''));
const fieldW = computed(() => Math.max(s.value.fw ?? 0, w(s.value.f, 'mono') + 22, 56));
const btnW = computed(() => w(s.value.b) + 24);
const tagW = computed(() => w(s.value.tag) + 20);
// A command with one part picked out: three runs, so the highlight cannot
// shift the characters around it the way a separate cell would.
const mono = computed(() => {
  const all: string = s.value.m ?? '';
  const hi: string = s.value.hi ?? '';
  const at = hi ? all.indexOf(hi) : -1;
  return at < 0 ? [{ s: all, hi: false }] : [
    { s: all.slice(0, at), hi: false },
    { s: hi, hi: true },
    { s: all.slice(at + hi.length), hi: false },
  ].filter((r) => r.s !== '');
});
</script>

<template>
  <template v-if="c == null" />

  <text v-else-if="s.m !== undefined" :x="x" :y="cy + 4.5" class="f-t f-mono" xml:space="preserve"><tspan
      v-for="(r, i) in mono" :key="i" :class="r.hi ? 'f-accent' : ''">{{ r.s }}</tspan></text>

  <!-- Runs of spaces are how a caption line spaces its own columns, and SVG
       collapses them unless it is told not to. -->
  <text v-else-if="s.t !== undefined" :x="x" :y="cy + 4.5" :class="'f-t' + tone + face" xml:space="preserve">{{ s.t }}</text>

  <g v-else-if="s.f !== undefined">
    <rect class="f-field" :x="x" :y="cy - 11" :width="fieldW" height="22" rx="5" />
    <text class="f-t f-mono" :x="x + 10" :y="cy + 4">{{ s.f }}</text>
    <text v-if="s.note" class="f-t f-sm f-mute" :x="x + fieldW + 10" :y="cy + 4">{{ s.note }}</text>
  </g>

  <g v-else-if="s.b !== undefined">
    <rect class="f-btn" :x="x" :y="cy - 11" :width="btnW" height="22" rx="6" />
    <text class="f-t f-mid" :x="x + btnW / 2" :y="cy + 4">{{ s.b }}</text>
  </g>

  <g v-else-if="s.r !== undefined">
    <circle class="f-ring" :cx="x + 6" :cy="cy" r="6" />
    <circle v-if="s.on" class="f-dot" :cx="x + 6" :cy="cy" r="3" />
    <text class="f-t" :x="x + 18" :y="cy + 4.5">{{ s.r }}</text>
  </g>

  <g v-else-if="s.k !== undefined">
    <rect class="f-ring" :x="x" :y="cy - 6" width="12" height="12" rx="3" />
    <path v-if="s.on" class="f-tick" :d="`M${x + 3},${cy} l2.4,2.6 l4.2,-5.4`" />
    <text class="f-t" :x="x + 18" :y="cy + 4.5">{{ s.k }}</text>
  </g>

  <g v-else-if="s.bar !== undefined">
    <rect class="f-track" :x="x" :y="cy - 5" width="160" height="10" rx="5" />
    <rect class="f-fill" :x="x" :y="cy - 5" :width="160 * s.bar" height="10" rx="5" />
    <text v-if="s.label" class="f-t f-sm f-mute" :x="x + 168" :y="cy + 4">{{ s.label }}</text>
  </g>

  <g v-else-if="s.tag !== undefined">
    <rect class="f-tag" :x="x" :y="cy - 11" :width="tagW" height="22" rx="11" />
    <text class="f-t f-sm f-mid" :x="x + tagW / 2" :y="cy + 4">{{ s.tag }}</text>
  </g>
</template>
