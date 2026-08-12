import { w, type Face } from './measure';

/**
 * The vocabulary every figure is built from.
 *
 * A cell is one thing that appears on one line: a word, a form field, a button,
 * a radio, a progress bar. Both figure components lay cells out on a grid and
 * neither knows how to draw one — `Cell.vue` does — so a new kind of thing is
 * added here and appears in every figure at once, in both languages.
 *
 * A bare string is text, because that is nine cells in ten and the pages are
 * meant to stay readable as source.
 */

export type Tone = 'mute' | 'ok' | 'bad' | 'accent' | 'strong';

export type Cell =
  | string
  | null
  /** text: `t` with an optional tone and face */
  | { t: string; tone?: Tone; face?: Face }
  /** something you would type, with `hi` picked out in the accent colour */
  | { m: string; hi?: string }
  /** a form field with `f` typed into it; `fw` forces the box wider */
  | { f: string; fw?: number; note?: string }
  /** a button */
  | { b: string }
  /** a radio, `on` when it is the chosen one */
  | { r: string; on?: boolean }
  /** a checkbox */
  | { k: string; on?: boolean }
  /** a progress bar, 0–1 */
  | { bar: number; label?: string }
  /** a rounded chip, as the install menu uses for a package */
  | { tag: string };

export const ROW = 24;      // one line of a figure
export const PAD = 16;      // inside a screen's frame
export const GAP = 18;      // between two cells on one line

export function cellW(c: Cell): number {
  if (c == null) return 0;
  if (typeof c === 'string') return w(c);
  if ('t' in c) return w(c.t, c.face ?? 'base', c.tone === 'strong');
  if ('m' in c) return w(c.m, 'mono');
  if ('f' in c) {
    const box = Math.max(c.fw ?? 0, w(c.f, 'mono') + 22, 56);
    return box + (c.note ? 10 + w(c.note, 'small') : 0);
  }
  if ('b' in c) return w(c.b) + 24;
  if ('r' in c) return 18 + w(c.r);
  if ('k' in c) return 18 + w(c.k);
  if ('bar' in c) return 168 + (c.label ? 8 + w(c.label, 'small') : 0);
  if ('tag' in c) return w(c.tag) + 20;
  return 0;
}

/** The widest each column gets, across every row that has one. */
export function grid(rows: Cell[][], gap = GAP): number[] {
  const n = rows.reduce((m, r) => Math.max(m, r.length), 0);
  const wide: number[] = [];
  for (let i = 0; i < n; i++) wide[i] = rows.reduce((m, r) => Math.max(m, cellW(r[i] ?? null)), 0);
  const x: number[] = [];
  let at = 0;
  for (let i = 0; i < n; i++) {
    x[i] = at;
    at += wide[i] + gap;
  }
  return x;
}

export function rowsWidth(rows: Cell[][], gap = GAP): number {
  const x = grid(rows, gap);
  return rows.reduce((m, r) => {
    const last = r.length - 1;
    return Math.max(m, last < 0 ? 0 : x[last] + cellW(r[last]));
  }, 0);
}
