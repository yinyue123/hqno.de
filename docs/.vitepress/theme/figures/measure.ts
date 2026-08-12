/**
 * How wide a string will be, in px, without a browser to ask.
 *
 * SVG has no text layout: a `<text>` is placed at a point and whatever it is
 * wide, it is wide. Every box drawn around a label therefore has to be sized
 * from an estimate, and an estimate that is wrong the *small* way clips real
 * words. So this errs high, and every box built on it adds padding on top.
 *
 * The one distinction that actually matters here is wide versus narrow. A
 * Chinese character is one em; Latin averages about half of one, and the
 * difference between those two is the whole reason the plain-text figures this
 * replaces came out ragged in a browser. Within Latin the per-character table
 * is a rounding of the site's own face — it does not have to be right, it has
 * to be close and never under.
 */

const FULLWIDTH: [number, number][] = [
  [0x1100, 0x115f], [0x2e80, 0x303e], [0x3041, 0x33ff],
  [0x3400, 0x4dbf], [0x4e00, 0x9fff], [0xa000, 0xa4cf],
  [0xac00, 0xd7a3], [0xf900, 0xfaff], [0xfe30, 0xfe6f],
  [0xff00, 0xff60], [0xffe0, 0xffe6], [0x20000, 0x3fffd],
];

function isWide(cp: number): boolean {
  return FULLWIDTH.some(([lo, hi]) => cp >= lo && cp <= hi);
}

/**
 * Width of one narrow character, in em.
 *
 * This was a per-character table once — i for a third of an em, W for most of
 * one — and it was worse than useless: measured against the real face it was
 * out by up to 9% in both directions, so it clipped labels *and* padded them.
 * A flat, deliberately high advance is out by a predictable amount in one
 * direction only, and one direction only is the whole requirement. The widest
 * per-character average measured across the site's own strings was 0.591, so:
 *
 *   0.60 em, flat, for anything the UI face draws.
 *
 * The marks below are the exception, because they really are about an em and
 * flattening them to 0.6 would clip a row of arrows. The em dash is 1.5: beside
 * Chinese it is not drawn by the face drawing the Latin around it.
 */
function narrow(ch: string): number {
  if (ch === '—') return 1.5;
  if ('↑↓←→⟳✓✕●▸◂■□≈🔒⚠🌐⚙'.includes(ch)) return 1.15;
  return 0.6;
}

export const FS = { base: 13, small: 11.5, mono: 12, title: 13 } as const;

export type Face = keyof typeof FS;

/**
 * Width of `s` in px, set in `face`. Monospace is a flat advance, and `bold`
 * costs a few percent in every face that has a bold at all.
 */
export function w(s: string, face: Face = 'base', bold = false): number {
  const size = FS[face];
  let n = 0;
  for (const ch of s) {
    const cp = ch.codePointAt(0)!;
    n += isWide(cp) ? 1 : face === 'mono' ? 0.62 : narrow(ch);
  }
  // Two percent of air on every figure, so a face this file has never seen
  // cannot clip a label by a hair.
  return n * size * 1.02 * (bold ? 1.07 : 1);
}

/** The widest of several strings, in px. */
export function wmax(list: string[], face: Face = 'base'): number {
  return list.reduce((m, s) => Math.max(m, w(s, face)), 0);
}
