<script setup lang="ts">
/**
 * The one figure on this site that moves.
 *
 * "Deploying a website and CDN" opens by asking somebody to believe that two
 * identical machines in one rack answer at wildly different speeds, and then
 * spends five sections on why. That is a lot of reading before the first
 * surprise. This runs the surprise first: the same page, leaving two machines
 * at the same instant, arriving very differently.
 *
 * What it actually simulates, because a decorative animation would be worse
 * than none:
 *
 *   - a page is a fixed number of pieces, and the sender emits them steadily.
 *   - both lines cross the same gateway. The optimised one has a share held
 *     for it, so a piece passes the moment it arrives.
 *   - the ordinary one gets whatever is spare, modelled as one piece every
 *     GATE_MS. The sender is faster than that, so a queue forms — which is
 *     oversubscription, drawn.
 *   - when the queue is full, an arriving piece is dropped. That is tail drop,
 *     and it is what the page's "5–30% loss" line describes.
 *   - a dropped piece is sent again RTO later. This is the part people do not
 *     expect, and the reason the lower line is not merely slower: loss costs a
 *     timeout, not a retry.
 *
 * The numbers on the right are read out of that simulation rather than typed
 * in, so the figure cannot drift away from what it is drawing.
 *
 * Drawing writes attributes on a fixed pool of circles instead of going
 * through Vue's renderer: forty nodes re-diffed sixty times a second is real
 * work on a phone and none of it would change what anybody sees. Everything
 * else in the frame is static markup, and every colour is a theme variable, so
 * this follows the dark-mode switch like the drawn figures do.
 *
 * It costs nothing while nobody is looking at it: an IntersectionObserver
 * stops the loop when the figure scrolls away, and so does a hidden tab.
 * `prefers-reduced-motion` gets a still frame that makes the same point —
 * four pieces flowing, seven jammed, one falling — with the button offering to
 * run it anyway.
 */
import { onBeforeUnmount, onMounted, ref } from 'vue';

const props = withDefaults(
  defineProps<{
    title?: string;
    gate?: string;
    machine?: string;
    fast?: string;
    slow?: string;
    /** what the readout says when nothing was dropped */
    clean?: string;
    /** and when something was — `{n}` is the count */
    lost?: string;
    sec?: string;
    /** the outcome, in what a visitor would actually notice */
    verdict?: string;
    note?: string;
    replay?: string;
    alt?: string;
  }>(),
  {
    title: 'one page, two lines, both starting now',
    gate: 'the gateway',
    machine: 'your machine',
    fast: 'optimised',
    slow: 'ordinary',
    clean: 'nothing lost',
    lost: '{n} pieces lost',
    sec: 's',
    verdict: 'the upper line streams 4K without pausing; the lower one cannot open a page at 9pm',
    note: 'a lost piece has to be sent again — which is why the lower one is not merely slower',
    replay: 'play again',
    alt: 'Two lines carrying the same page. On the optimised line the pieces pass straight through the gateway and the page finishes in about two and a half seconds. On the ordinary line they pile up behind the gateway, some are dropped and have to be sent again, and the page takes more than twice as long.',
  },
);

/* ── the frame ────────────────────────────────────────────────────────── */

const W = 660;
const H = 248;
const X0 = 166; // where a piece leaves the machine
const GATE = 300;
const X1 = 436; // where it reaches the visitor
const BAR = 170;
const CYA = 88; // the optimised lane
const CYB = 178; // the ordinary one
const POOL = 22; // circles per lane, reused

/* ── the simulation ───────────────────────────────────────────────────── */

const SPEED = 0.33; // px per ms
const PIECES = 20; // how many the page is made of
const SEND_EVERY = 90; // ms between two pieces leaving the machine
const GATE_MS = 230; // ms between two pieces getting through the shared gateway
const QUEUE_MAX = 7; // how many may wait before the next one is dropped
const RTO = 700; // ms before a dropped piece is sent again
const SLOT = 13; // px between two waiting pieces
const HOLD = 1700; // ms the finished frame is held before it replays
const CAP = 11000; // ms after which the run ends whatever happened

type Piece = { x: number; drop: number; queued: boolean; through: boolean };

type Lane = {
  slow: boolean;
  toSend: number;
  again: number[]; // when each dropped piece is sent again
  live: Piece[];
  arrived: number;
  lostN: number;
  nextSend: number;
  nextGate: number;
  doneAt: number;
};

function makeLane(slow: boolean): Lane {
  const L = { slow } as Lane;
  reset(L, 0);
  return L;
}

function reset(L: Lane, now: number) {
  L.toSend = PIECES;
  L.again = [];
  L.live = [];
  L.arrived = 0;
  L.lostN = 0;
  L.nextSend = now;
  L.nextGate = now;
  L.doneAt = 0;
}

function step(L: Lane, now: number, dt: number) {
  // A piece whose timeout has expired joins the back of the send queue.
  for (let i = L.again.length - 1; i >= 0; i--) {
    if (L.again[i] <= now) {
      L.again.splice(i, 1);
      L.toSend++;
    }
  }

  if (now >= L.nextSend && L.toSend > 0) {
    L.toSend--;
    L.live.push({ x: X0, drop: 0, queued: false, through: false });
    L.nextSend = now + SEND_EVERY;
  }

  // The shared gateway lets the head of the queue through, one at a time.
  if (L.slow && now >= L.nextGate) {
    const head = L.live.find((p) => p.queued);
    if (head) {
      head.queued = false;
      head.through = true;
      L.nextGate = now + GATE_MS;
    }
  }

  for (const p of L.live) {
    if (p.drop || p.queued) continue;
    p.x += dt * SPEED;
    if (p.through || p.x < GATE) continue;
    if (!L.slow) {
      // A share is held for this line, so there is nothing to wait behind.
      p.through = true;
    } else if (L.live.reduce((n, o) => n + (o.queued ? 1 : 0), 0) >= QUEUE_MAX) {
      p.drop = now;
      p.x = GATE;
      L.lostN++;
      L.again.push(now + RTO);
    } else {
      p.queued = true;
    }
  }

  // Lay the queue out behind the gate, nearest first.
  let k = 0;
  for (const p of L.live) if (p.queued) p.x = GATE - 8 - k++ * SLOT;

  for (let i = L.live.length - 1; i >= 0; i--) {
    const p = L.live[i];
    if (p.drop) {
      if (now - p.drop > 480) L.live.splice(i, 1);
    } else if (p.x >= X1) {
      L.arrived++;
      L.live.splice(i, 1);
    }
  }

  if (!L.doneAt && L.arrived >= PIECES) L.doneAt = now;
}

/* ── drawing ──────────────────────────────────────────────────────────── */

const root = ref<SVGSVGElement>();
const dotsA = ref<SVGGElement>();
const dotsB = ref<SVGGElement>();
const barA = ref<SVGRectElement>();
const barB = ref<SVGRectElement>();
const outA = ref<SVGTextElement>();
const outB = ref<SVGTextElement>();

const A = makeLane(false);
const B = makeLane(true);
let started = 0;
let last = 0;
let raf = 0;
let io: IntersectionObserver | null = null;
let onScreen = true;

function say(L: Lane, el: SVGTextElement | undefined, now: number) {
  if (!el) return;
  const t = ((L.doneAt || now) - started) / 1000;
  const tail = L.lostN ? props.lost.replace('{n}', String(L.lostN)) : props.clean;
  el.textContent = `${t.toFixed(1)} ${props.sec} · ${tail}`;
  el.setAttribute('class', L.doneAt ? 's ok' : 's');
}

function paint(L: Lane, g: SVGGElement | undefined, bar: SVGRectElement | undefined, cy: number, now: number) {
  bar?.setAttribute('width', ((BAR * Math.min(L.arrived, PIECES)) / PIECES).toFixed(1));
  if (!g) return;
  const kids = g.children;
  let i = 0;
  for (const p of L.live) {
    if (i >= POOL) break;
    const c = kids[i++] as SVGCircleElement;
    c.setAttribute('cx', p.x.toFixed(1));
    if (p.drop) {
      const age = (now - p.drop) / 480;
      c.setAttribute('cy', (cy + age * 20).toFixed(1));
      c.setAttribute('class', 'f-bad');
      c.setAttribute('opacity', Math.max(0, 1 - age).toFixed(2));
    } else {
      c.setAttribute('cy', String(cy));
      c.setAttribute('class', L.slow ? 'ink' : 'f-dot');
      c.setAttribute('opacity', '1');
    }
  }
  for (; i < POOL; i++) (kids[i] as SVGCircleElement).setAttribute('opacity', '0');
}

/**
 * One moment of the same story, held still, for a reader who asked not to be
 * moved.
 *
 * It is a real frame rather than a hand-placed arrangement: the simulation is
 * run with the clock turned up until the fast lane is nearly done — which is
 * where the two lanes look least alike and both still have something on them —
 * and then that frame is drawn once. So the still picture cannot say anything
 * the moving one would not.
 */
function freeze() {
  let now = 0;
  started = 0;
  reset(A, 0);
  reset(B, 0);
  while (A.arrived < PIECES - 5 && now < CAP) {
    now += 16;
    step(A, now, 16);
    step(B, now, 16);
  }
  paint(A, dotsA.value, barA.value, CYA, now);
  paint(B, dotsB.value, barB.value, CYB, now);
  say(A, outA.value, now);
  say(B, outB.value, now);
}

function frame(now: number) {
  const dt = Math.min(now - last, 48);
  last = now;

  step(A, now, dt);
  step(B, now, dt);
  paint(A, dotsA.value, barA.value, CYA, now);
  paint(B, dotsB.value, barB.value, CYB, now);
  say(A, outA.value, now);
  say(B, outB.value, now);

  const ended = A.doneAt && B.doneAt ? now - Math.max(A.doneAt, B.doneAt) > HOLD : now - started > CAP + HOLD;
  if (ended) {
    started = now;
    reset(A, now);
    reset(B, now);
  }
  raf = requestAnimationFrame(frame);
}

function run() {
  if (raf) return;
  last = performance.now();
  started = last;
  reset(A, last);
  reset(B, last);
  raf = requestAnimationFrame(frame);
}

function stop() {
  if (raf) cancelAnimationFrame(raf);
  raf = 0;
}

/** The button starts it, or starts it over. */
function replayNow() {
  stop();
  run();
}

function onVisibility() {
  if (document.hidden) stop();
  else if (onScreen) run();
}

onMounted(() => {
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
    freeze();
    return;
  }
  io = new IntersectionObserver(
    (entries) => {
      onScreen = entries[0].isIntersecting;
      if (onScreen && !document.hidden) run();
      else stop();
    },
    { threshold: 0.15 },
  );
  if (root.value) io.observe(root.value);
  document.addEventListener('visibilitychange', onVisibility);
});

onBeforeUnmount(() => {
  stop();
  io?.disconnect();
  document.removeEventListener('visibilitychange', onVisibility);
});
</script>

<template>
  <div class="race">
    <svg ref="root" class="fig" :viewBox="`0 0 ${W} ${H}`" role="img" :aria-label="alt">
      <text class="t" x="14" y="18">{{ title }}</text>
      <path class="rule" :d="`M${GATE},40 V206`" />
      <text class="s c" :x="GATE" y="32">{{ gate }}</text>

      <!-- the optimised lane -->
      <text class="s a" x="14" :y="CYA + 4">{{ fast }}</text>
      <rect class="box" x="76" :y="CYA - 18" width="86" height="36" rx="4" />
      <text class="s c" x="119" :y="CYA + 4">{{ machine }}</text>
      <path class="rule" :d="`M${X0},${CYA} H${X1}`" />
      <path class="ln" :d="`M${GATE},${CYA - 21} V${CYA - 10} M${GATE},${CYA + 10} V${CYA + 21}`" />
      <rect class="box" x="448" :y="CYA - 24" width="198" height="48" rx="5" />
      <rect class="f-track" x="462" :y="CYA - 12" :width="BAR" height="9" rx="4.5" />
      <rect ref="barA" class="f-fill" x="462" :y="CYA - 12" width="0" height="9" rx="4.5" />
      <text ref="outA" class="s" x="462" :y="CYA + 18" />

      <!-- the ordinary one -->
      <text class="s" x="14" :y="CYB + 4">{{ slow }}</text>
      <rect class="box" x="76" :y="CYB - 18" width="86" height="36" rx="4" />
      <text class="s c" x="119" :y="CYB + 4">{{ machine }}</text>
      <path class="rule" :d="`M${X0},${CYB} H${X1}`" />
      <path class="ln" :d="`M${GATE},${CYB - 21} V${CYB - 10} M${GATE},${CYB + 10} V${CYB + 21}`" />
      <rect class="box" x="448" :y="CYB - 24" width="198" height="48" rx="5" />
      <rect class="f-track" x="462" :y="CYB - 12" :width="BAR" height="9" rx="4.5" />
      <rect ref="barB" class="f-fill" x="462" :y="CYB - 12" width="0" height="9" rx="4.5" />
      <text ref="outB" class="s" x="462" :y="CYB + 18" />

      <g ref="dotsA">
        <circle v-for="n in POOL" :key="n" class="f-dot" cx="-20" :cy="CYA" r="4.5" opacity="0" />
      </g>
      <g ref="dotsB">
        <circle v-for="n in POOL" :key="n" class="ink" cx="-20" :cy="CYB" r="4.5" opacity="0" />
      </g>

      <text class="t" x="14" y="220">{{ verdict }}</text>
      <text class="s" x="14" y="238">{{ note }}</text>
    </svg>
    <button class="race-btn" type="button" @click="replayNow">{{ replay }}</button>
  </div>
</template>
