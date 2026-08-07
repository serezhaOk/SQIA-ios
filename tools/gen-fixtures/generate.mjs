// Golden fixtures for the iOS port.
//
// Runs the *real* web sources (funny-steps/src) and writes what they produce
// to JSON. The Swift tests replay the same inputs and compare, so "1:1 with
// the web" is a thing the test suite proves rather than a thing we hope for.
//
//   node --run gen            # writes Core/Tests/SQIACoreTests/Fixtures
//   WEB_SRC=/path/to/src node --run gen
//
// Anything random in the web code goes through Math.random, so the generator
// swaps in a seeded PRNG (mulberry32) for the duration of each case. The
// Swift side implements the same PRNG bit-for-bit — prng.json is what proves
// that, and every other fixture rests on it.

import { existsSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve as resolvePath } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { installDocumentStub, makeRecorder } from './recorder.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolvePath(HERE, '../..');
const OUT = resolvePath(REPO, 'Core/Tests/SQIACoreTests/Fixtures');

// Point WEB_SRC at the web app's src/, or keep a funny-steps checkout beside
// this one and it will be found.
const CANDIDATES = [
  process.env.WEB_SRC,
  resolvePath(REPO, '../funny-steps/src'),
  resolvePath(REPO, '../../workspace/serezhaok/funny-steps/src'),
  '/workspace/serezhaok/funny-steps/src',
].filter(Boolean);

const WEB_SRC = CANDIDATES.find((p) => existsSync(resolvePath(p, 'scales.ts')));
if (!WEB_SRC) {
  console.error(
    'Cannot find the web sources. Clone serezhaOk/funny-steps next to this\n' +
      'repository, or set WEB_SRC to its src/ directory. Looked in:\n' +
      CANDIDATES.map((p) => `  ${p}`).join('\n')
  );
  process.exit(1);
}
console.log(`web sources: ${WEB_SRC}\n`);

const load = (name) => import(pathToFileURL(resolvePath(WEB_SRC, name)).href);

const { COLS, NOTE_NAMES, SCALES, columnMidi, columnRate, rateTable } =
  await load('scales.ts');
const { Grid, ROWS } = await load('grid.ts');
const { randomName } = await load('projects.ts');

// --------------------------------------------------------------------- rng --
// The exact sequence the Swift port has to reproduce. Every step is forced
// to 32 bits so the Swift version can use UInt32 wrapping arithmetic and
// land on the same bits: JS `^`, `>>>`, `|` and Math.imul all operate mod
// 2^32 already, and `>>> 0` pins the accumulator there too.
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), a | 1);
    t = (t + Math.imul(t ^ (t >>> 7), t | 61)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Run `body` with Math.random replaced by a seeded stream. */
function seeded(seed, body) {
  const real = Math.random;
  Math.random = mulberry32(seed);
  try {
    return body();
  } finally {
    Math.random = real;
  }
}

// ------------------------------------------------------------------ helpers --
const cellsOf = (grid) => Array.from(grid.cells);

/**
 * The layout `render()` installs, without a canvas. `fitCell` is private to
 * TypeScript only — at runtime it is an ordinary method, and calling it here
 * keeps the fixtures tied to the shipping implementation instead of a copy.
 */
function installLayout(grid, vx, vy, vw, vh) {
  const cell = grid.fitCell(vw, vh);
  const gw = cell * COLS;
  const gh = cell * ROWS;
  grid.layout = {
    cell,
    ox: vx + (vw - gw) / 2,
    oy: vy + (vh - gh) / 2,
    cx: vx + vw / 2,
    cy: vy + vh / 2,
    R: Math.hypot(gw, gh) / 2,
  };
  return grid.layout;
}

// -------------------------------------------------------------- 1. the prng --
const prng = {
  note: 'Swift must reproduce these exactly; everything else depends on it.',
  streams: [1, 12345, 0xdecafbad, 0].map((seed) => ({
    seed,
    values: Array.from({ length: 16 }, mulberry32(seed)),
  })),
};

// ------------------------------------------------------- 2. scales & pitch --
const scales = {
  cols: COLS,
  rows: ROWS,
  noteNames: NOTE_NAMES,
  scales: SCALES.map((s) => ({ name: s.name, steps: s.steps })),
  // Every root against every scale: the whole pitch map in one table.
  midi: SCALES.flatMap((scale) =>
    NOTE_NAMES.map((_, rootPc) => ({
      scale: scale.name,
      rootPc,
      midi: Array.from({ length: COLS }, (_, c) => columnMidi(c, rootPc, scale)),
    }))
  ),
  // Playback rates, including a sample pitched away from the C4 default.
  rates: SCALES.flatMap((scale) =>
    [0, 5, 9, 11].map((rootPc) => ({
      scale: scale.name,
      rootPc,
      base60: rateTable(rootPc, scale),
      base48: rateTable(rootPc, scale, 48),
      base72: rateTable(rootPc, scale, 72),
    }))
  ),
  // The clamp only bites at the extremes, so sample it deliberately.
  clamped: [
    { col: 0, rootPc: 0, scale: 'minor', base: 96, rate: columnRate(0, 0, SCALES[0], 96) },
    { col: 11, rootPc: 11, scale: 'major', base: 24, rate: columnRate(11, 11, SCALES[1], 24) },
  ],
};

// ---------------------------------------------------------- 3. grid editing --
const gridCases = [];

function gridCase(name, seed, ops) {
  const grid = new Grid();
  seeded(seed, () => {
    for (const op of ops) {
      if (op.op === 'brush') grid.brush(op.gx, op.gy);
      else if (op.op === 'erase') grid.erase(op.r, op.c);
      else if (op.op === 'random') grid.random();
      else if (op.op === 'clear') grid.clear();
      else throw new Error(`unknown op ${op.op}`);
    }
  });
  gridCases.push({ name, seed, ops, cells: cellsOf(grid), hasNotes: grid.hasNotes });
}

// A single tap dead centre of a cell: no bleed anywhere.
gridCase('brush-centre', 1, [{ op: 'brush', gx: 3.5, gy: 5.5 }]);
// Off centre in both axes: the directional trail the brush is built for.
gridCase('brush-corner', 1, [{ op: 'brush', gx: 3.92, gy: 5.08 }]);
// Hard against the grid edges, where the neighbour writes fall off the field.
gridCase('brush-edges', 1, [
  { op: 'brush', gx: 0.02, gy: 0.02 },
  { op: 'brush', gx: 11.98, gy: 15.98 },
]);
// A drag: successive fractional positions, each bleeding into the last.
gridCase(
  'brush-drag',
  1,
  Array.from({ length: 24 }, (_, i) => ({
    op: 'brush',
    gx: 1.3 + i * 0.37,
    gy: 2.1 + i * 0.53,
  }))
);
// The eraser clamps its 2x2 block so it never runs off the grid.
gridCase('erase-clamped', 1, [
  { op: 'brush', gx: 11.5, gy: 15.5 },
  { op: 'brush', gx: 10.5, gy: 14.5 },
  { op: 'erase', r: 15, c: 11 },
]);
gridCase('erase-middle', 1, [
  ...Array.from({ length: 12 }, (_, c) => ({ op: 'brush', gx: c + 0.5, gy: 7.5 })),
  { op: 'erase', r: 7, c: 4 },
]);
// The randomiser, on three seeds — this is the case that pins the PRNG to
// the exact call order inside Grid.random().
for (const seed of [1, 12345, 0xdecafbad]) {
  gridCase(`random-${seed}`, seed, [{ op: 'random' }]);
}
gridCase('clear', 1, [{ op: 'random' }, { op: 'clear' }]);

// ------------------------------------------------------------- 4. geometry --
// The dome: cell fitting, warp, its Newton inverse, and hit testing. Sizes
// cover a full-screen phone stage, an SE, a mixer panel and an iPad.
const VIEWPORTS = [
  { name: 'iphone-stage', vx: 0, vy: 0, vw: 375, vh: 600 },
  { name: 'se-stage', vx: 0, vy: 0, vw: 320, vh: 454 },
  { name: 'mixer-panel', vx: 10, vy: 64.8, vw: 168.75, vh: 270 },
  { name: 'ipad-stage', vx: 0, vy: 0, vw: 834, vh: 1000 },
  { name: 'wide-stage', vx: 0, vy: 0, vw: 900, vh: 400 },
];

const geometry = VIEWPORTS.map((v) => {
  const grid = new Grid();
  const layout = installLayout(grid, v.vx, v.vy, v.vw, v.vh);

  // Warp every cell centre: this is the whole field, not a sample of it.
  const centres = [];
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const x = layout.ox + (c + 0.5) * layout.cell;
      const y = layout.oy + (r + 0.5) * layout.cell;
      const [sx, sy] = grid.warp(x, y);
      centres.push({ r, c, x, y, sx, sy, scale: grid.warpScale(x, y) });
    }
  }

  // Taps: inside the field, the exact centre (the Newton solver's singular
  // point), and outside it.
  const taps = [
    [v.vx + v.vw / 2, v.vy + v.vh / 2],
    [v.vx + 4, v.vy + 4],
    [v.vx + v.vw - 4, v.vy + v.vh - 4],
    [v.vx + v.vw * 0.31, v.vy + v.vh * 0.72],
    [v.vx + v.vw * 0.83, v.vy + v.vh * 0.18],
    [v.vx - 40, v.vy + v.vh / 2],
  ].map(([x, y]) => {
    const [ux, uy] = grid.unwarp(x, y);
    const p = grid.pos(x, y);
    const h = grid.hit(x, y);
    return { x, y, ux, uy, pos: p, hit: h };
  });

  return { ...v, layout, centres, taps };
});

// ---------------------------------------------------------------- 5. names --
const names = [1, 12345, 0xdecafbad].map((seed) => ({
  seed,
  names: seeded(seed, () => Array.from({ length: 24 }, randomName)),
}));

// ------------------------------------------------------------- 6. snapshot --
// The row body the web app writes to Supabase. The iOS port has to produce
// the same values for the same state or projects stop crossing platforms.
// (Postgres stores this as jsonb and normalises the text, so what has to
// match is the values, not the byte layout.)
const snapshots = [12345, 0xdecafbad].map((seed) => {
  const tracks = [0, 1].map((i) => {
    const grid = new Grid();
    seeded(seed + i, () => grid.random());
    return {
      voiceIdx: i === 0 ? 0 : 4,
      muted: i === 1,
      // Exactly the web's rounding: two decimals, straight off the float32s.
      cells: Array.from(grid.cells, (v) => Math.round(v * 100) / 100),
    };
  });
  return { seed, snapshot: { bpm: 120, root_pc: 9, scale: 'minor', tracks } };
});

// ------------------------------------------------------------- 7. the field --
// What the live field actually draws, primitive by primitive: the dome, the
// decay of a flash, the jelly push on a dot's neighbours, the colour ripple
// spreading ring by ring, the breath under all of it.
//
// Each case runs the real `render` for a number of frames and keeps the last
// one, so the state the frame is drawn from is state the web built.
installDocumentStub();

function fieldCase({ name, seed, viewport, frames, dt, playhead, detail, alpha, flashes }) {
  const grid = new Grid();
  seeded(seed, () => grid.random());

  // Flashes are given as [row, column, velocity, frameToFireOn].
  const schedule = new Map();
  for (const [r, c, vel, frame = 0] of flashes ?? []) {
    if (!schedule.has(frame)) schedule.set(frame, []);
    schedule.get(frame).push([r, c, vel]);
  }

  const { ctx, ops, reset } = makeRecorder();
  const { vx, vy, vw, vh } = viewport;

  for (let frame = 0; frame < frames; frame++) {
    for (const [r, c, vel] of schedule.get(frame) ?? []) grid.flash(r, c, vel);
    reset(); // only the final frame is compared
    grid.render(ctx, vx, vy, vw, vh, playhead, dt, detail, alpha);
  }

  return {
    name,
    seed,
    viewport,
    frames,
    dt,
    playhead,
    detail,
    alpha,
    flashes: flashes ?? [],
    cells: cellsOf(grid),
    ops,
  };
}

const PHONE = { vx: 0, vy: 0, vw: 375, vh: 600 };
const PANEL = { vx: 10, vy: 64.8, vw: 168.75, vh: 270 };

const field = [
  // The field at rest: dome, breath and the playhead row, nothing else.
  fieldCase({
    name: 'at-rest',
    seed: 12345,
    viewport: PHONE,
    frames: 1,
    dt: 1 / 60,
    playhead: -1,
    detail: 1,
    alpha: 1,
  }),
  fieldCase({
    name: 'playhead',
    seed: 12345,
    viewport: PHONE,
    frames: 1,
    dt: 1 / 60,
    playhead: 7,
    detail: 1,
    alpha: 1,
  }),
  // Breath is a function of accumulated time, so this only differs from
  // 'at-rest' if the clock is being kept the same way.
  fieldCase({
    name: 'breathing',
    seed: 12345,
    viewport: PHONE,
    frames: 40,
    dt: 1 / 60,
    playhead: 3,
    detail: 1,
    alpha: 1,
  }),
  // One flash, two frames old: the bloom is near its peak, the push is
  // shoving its neighbours outward and the first colour ring has moved on.
  fieldCase({
    name: 'fresh-flash',
    seed: 12345,
    viewport: PHONE,
    frames: 3,
    dt: 1 / 60,
    playhead: 5,
    detail: 1,
    alpha: 1,
    flashes: [[5, 6, 1]],
  }),
  // A whole row lit, then left to decay for a third of a second — the
  // ripples have spread several rings and started to overlap.
  fieldCase({
    name: 'decaying-row',
    seed: 12345,
    viewport: PHONE,
    frames: 20,
    dt: 1 / 60,
    playhead: 9,
    detail: 1,
    alpha: 1,
    flashes: [
      [4, 1, 1],
      [4, 4, 0.6],
      [4, 7, 0.85],
      [4, 10, 0.4],
    ],
  }),
  // Overlapping ripples from three different moments.
  fieldCase({
    name: 'overlapping-waves',
    seed: 0xdecafbad,
    viewport: PHONE,
    frames: 14,
    dt: 1 / 60,
    playhead: 2,
    detail: 1,
    alpha: 1,
    flashes: [
      [2, 2, 1, 0],
      [6, 5, 0.9, 4],
      [3, 8, 0.7, 8],
    ],
  }),
  // A mixer panel: small, dimmed, and with the expensive extras turned off.
  fieldCase({
    name: 'mixer-panel',
    seed: 12345,
    viewport: PANEL,
    frames: 6,
    dt: 1 / 60,
    playhead: 11,
    detail: 0.4,
    alpha: 0.45,
    flashes: [[11, 3, 1]],
  }),
  // Mid-transition: the active track on its way out to its slot.
  fieldCase({
    name: 'mid-transition',
    seed: 12345,
    viewport: { vx: 40, vy: 60, vw: 260, vh: 430 },
    frames: 4,
    dt: 1 / 60,
    playhead: 0,
    detail: 0.7,
    alpha: 0.8,
    flashes: [[0, 0, 1]],
  }),
];

// ----------------------------------------------------------------- write it --
const files = {
  'prng.json': prng,
  'scales.json': scales,
  'grid-ops.json': { cases: gridCases },
  'geometry.json': { viewports: geometry },
  'names.json': { streams: names },
  'snapshot.json': { cases: snapshots },
  'field.json': { cases: field },
};

await mkdir(OUT, { recursive: true });
for (const [name, body] of Object.entries(files)) {
  await writeFile(resolvePath(OUT, name), `${JSON.stringify(body, null, 2)}\n`);
  console.log(`wrote ${name}`);
}
console.log(`\n${Object.keys(files).length} fixtures -> ${OUT}`);
