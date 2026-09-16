# SQIA for iOS — the 1:1 porting plan

A port of the **SQIA** web app (https://sqia.serezhaok.com, repository
`serezhaOk/funny-steps`) to a native iOS app in Swift. The goal is a complete
copy: the same screens, the same mechanics, the same sound, the same backend.
A project saved in a browser opens on an iPhone and the other way round — the
account and the library are shared.

This document is both the plan of work and the parity specification: section 2
pins down what the web version actually does (read from the code, not the
README — the README is out of date in places), sections 4–6 are how that
carries over, section 7 is the milestones and the estimates.

---

## 1. Key decisions

| Area | Web | iOS | Why |
| --- | --- | --- | --- |
| Language / UI | TypeScript + DOM | Swift 5.10+, SwiftUI (the shell, every screen but the scene) | The platform's default |
| The scene (the field of dots) | Canvas 2D, additive blending | **Metal (MTKView)**: instanced quads, an atlas of glow sprites, additive blending | An exact match for the `lighter` composite and a guaranteed 60/120 fps on ProMotion; CoreGraphics over ~400 sprites with glow is on the edge |
| Audio graph | Web Audio API | **AVAudioEngine = one `AVAudioSourceNode`**, the whole path inside it — in `SQIACore` (see below) | Sample-accurate scheduling, and all the DSP testable off a device |
| Synthesis (5 presets) | Tone.js | Our own DSP voices in the same renderer | Precise control over the envelopes and over randomisation "the way Tone does it" |
| Effects | Tone.Filter/Chorus/PingPongDelay/Reverb/Distortion | Our own DSP in the same place; the reverb — see risk R3 | No external dependencies |
| Transport | setTimeout lookahead, 25 ms / 120 ms | The same lookahead pattern: a `DispatchSourceTimer` against the engine's render time, triggers carrying sample timestamps | A direct port of the architecture; the jitter only goes down |
| Backend | Supabase (auth + PostgREST + RLS) | **The same Supabase project**, the official `supabase-swift` | No backend work at all; cross-platform projects |
| Auth | Google OAuth, a magic link by email | The same, through ASWebAuthenticationSession and a deep link; **plus Sign in with Apple** (required, see §6) | |
| Session storage | localStorage (`sqia-auth`) | Keychain | |
| Fonts | Manrope, Material Symbols (Google Fonts, at runtime) | Manrope bundled (OFL 1.1), four static instances. Material Symbols **not bundled**: the icons are SF Symbols | See below |
| Minimum iOS | — | **iOS 17** (portrait, iPhone; the iPad adaptation is the web's ≥768 layout) | Observation, and a mature SwiftUI |
| Dependencies | supabase-js, tone | **None at all.** The sound is ours, Supabase is plain HTTPS requests | See below |

### Two corrections to the table, made after the fact (M9)

**The icons are SF Symbols, not Material Symbols.** The plan promised a
bundled subset with the `more_vert`, `volume_off`, `check` and `emoticon`
glyphs. What happened instead is that after the owner's decision of 20.08
(native modals and buttons) every icon became a system one: `ellipsis` for
`more_vert`, `speaker.slash.fill` for `volume_off`, `face.smiling` for
`emoticon`, and `List` draws its own ticks. SF Symbols do not ship with the
app — the system draws them, and Apple's licence permits exactly that use.
One font instead of two, and one licence fewer in NOTICE.

**There are no dependencies.** `supabase-swift` was not needed in M8:
PostgREST is five stateless endpoints, and auth turned out to be easier to
write over `ASWebAuthenticationSession` and `AuthenticationServices` than to
pull in a client with a realtime socket and a storage layer for it. The
result: a `Package.swift` without a single `.package(url:)`, and an app SBOM
that reads "Manrope".

### Why the renderer is ours rather than a rack of AVAudioNodes

A correction to the plan, made in M2 after measuring. The web creates a Web
Audio node per note and throws it away after the tail — with two dense tracks
that is ~30 nodes a second, and it costs a browser nothing. AVAudioEngine's
nodes do not work that way: attach/detach rebuilds the graph and is not safe
during playback. So the graph on iOS is **one source node**, and everything
inside it — the voices, the slap delay, the limiter, the summing — lives in
`SQIACore`.

The gain is double: the five presets from M5, with their synth-per-note, fit
this scheme exactly, and DSP written as ordinary code is checked by tests off
a device — which is already happening (filter response, echo spacing, the
limiter's knee, the shape of an envelope).

The price: the atomic queue between the transport thread and the render
thread is written on our own acquire/release out of a tiny C target —
`Synchronization.Atomic` needs iOS 18, and raising the minimum version for
one queue is not worth it.

Defaults (each changeable in one line, if a different answer is wanted):
background playback — as on the web, it pauses when the app goes away;
haptics — not added (the web has none, "1:1"); orientation — portrait only
(as in manifest.webmanifest).

---

## 2. An inventory of the web version (the parity specification)

Taken from the sources of `funny-steps@main` (src/*.ts, index.html,
style.css, supabase/schema.sql). The numbers are normative: the port's unit
tests are checked against them.

### 2.1 Screens and transitions

1. **Landing (sign-in)** — shown only when there is no session: the logo (a
   grid of dots in a rounded square), the "SQIA" wordmark, the tagline "Built
   for sound accidents", a "Continue with Google" button (a white pill with
   the G mark), "Continue with email" → unfolds a form (validation
   `\S+@\S+\.\S+`, the magic link sent, the status "Check … for your sign-in
   link", errors in red `#e08a80`, statuses in green `#9ad3a6`), Terms /
   Privacy links (we open the site's hosted pages), a "What is SQIA?" link
   (an Instagram reel), the copyright. Plus the note saying why a session
   ended (see 2.6).
2. **Projects (the library)** — straight after signing in (and instantly for
   a returning user, off the cached session, without waiting for the
   network): the header (the four-dot logo, a profile button — a 52×39 pill
   with the `emoticon` glyph), the "Projects" title (44 pt, centred), a grid
   of cards two columns wide, square, corner radius 20, background `#383838`,
   the name bottom left (15 pt, two lines at most), `more_vert` top right →
   a context menu of Rename (prompt) / Delete (confirm, red `#ff6b6b`); the
   empty state is a single 602 pt card, "+ Create first project"; a fixed
   "+ Create new" button (a white pill, hidden while the list is empty); the
   account menu: the email and "Log out". Sorted by `updated_at` descending.
   At widths ≥768 the tiles are fixed at 200×200 from the centre.
3. **Sequencer** — opening a project is the gesture that unlocks audio, and
   the transport starts at once:
   - the header: `120 BPM` (drag horizontally, ±0.4 BPM/px, range 40–240; a
     tap without movement: +10, and from ≥200 back to 60), the track
     indicator (two dots, the active one bright; a tap opens the mixer), the
     key: the root (a tap steps up a semitone, wrapping) and the scale (a tap
     cycles MINOR / MAJOR / DORIAN / PENTA / PHRYGIAN);
   - the stage: the canvas field (see 2.3), drawing with a finger, erasing;
   - the footer: `ERASE` (a toggle, white when on), the voice label (a tap
     opens the Sound sheet; the loading state is opacity 0.4), `RNDM`
     (randomises the active track's pattern).
4. **The mixer** (inside the sequencer): a 0.35 s animation (cubic
   ease-in-out) — the active track flies out of full screen into its own
   panel while the second fades up in its own; the panels: 10 outside, a
   17-wide gutter, the proportion 270:168.75 (1:1.6), the top at 10.8 % of
   the stage's height, 100 pt at the bottom left for the button; a 1 px white
   stroke at alpha 0.7·t; the chips on a panel: the voice name (a white
   plate, a tap opens the track) and mute (30×30, `volume_off`, white
   background when on), and the chips are visible only where the track has
   notes; a muted track is drawn at alpha 0.35; inactive panels get detail
   0.4 (no streaks, no glow); a tap on a panel opens that track; at the
   bottom, a "Back to projects" tile (height 126, white at 20 %, radius 32) —
   it flushes the save and returns to the library. The footer and the
   indicator dots are hidden in mixer mode.
5. **The Sound sheet** — from the bottom, 76 % of the height at most, a grip,
   the "Sound" title, the list of voices: a name and a hint, a tick against
   the current one; choosing: instant for a synth, a buffer load with an
   indicator for a sample; dismissed by tapping the scrim (black at 55 %). At
   ≥768 it is 375 wide.

### 2.2 The data model and the musical arithmetic

- The grid: **12 columns × 16 steps** (the README says "10" — out of date,
  the code says `COLS = 12`). A cell is an intensity, 0…1
  (`Float32Array`).
- **2** tracks, defaulting to the `reverie` and `machine` voices.
- The scales: minor `[0,2,3,5,7,8,10]`, major `[0,2,4,5,7,9,11]`, dorian
  `[0,2,3,5,7,9,10]`, penta `[0,3,5,7,10]`, phrygian `[0,1,3,5,7,8,10]`. The
  notes C…B; the defaults: root A (pc 9), minor, 120 BPM.
- `columnMidi(col) = 48 + rootPc + 12·⌊col/L⌋ + steps[col mod L]`; a
  sample's rate `= 2^((midi−baseMidi)/12)`, clamped to 0.25…4, with
  baseMidi defaulting to 60 (C4).
- The brush: the cell under the finger is 1; a neighbour along X/Y/diagonal
  bleeds `w·0.9` by the finger's fractional offset (a directional trail).
  The randomiser's stamp: 1 at the centre, 0.45 on the cross. The eraser: a
  2×2 block clamped to the edges. RNDM: clear, then for each row with p=0.42
  stamp in a random column, and with p=0.25 a second one.
- The project snapshot (JSON in `projects.tracks`, **the values exactly as
  the web writes them** — otherwise cross-platform breaks):
  `{bpm, root_pc, scale, tracks:[{voiceIdx, muted, cells[192]}]}`, cells
  rounded to two decimal places. Compare the values rather than the bytes:
  Postgres stores this as `jsonb` and normalises the text anyway.
- Project names: 37 microbial creatures and 15 modifiers, a modifier with
  p=0.45 ("Wild Amoeba").

### 2.3 Rendering the field (a literal port of grid.ts)

The constants: LENS_K 0.19 (the barrel "dome", the edges staying put), PUSH
0.62, PUSH_RADIUS 2.4 cells, DECAY 3.1/s; the colour waves: radius 4 cells,
0.05 s per ring, 0.09 s per colour, hard steps from yellow `(255,214,0)` to
green `(80,255,130)` to violet `(176,107,255)` with a strobe (1.0 for 62 % of
the beat, 0.4 for the rest), 48 waves at most; a note's flash: energy
`0.55+0.45·vel`, an exponential decay, the neighbours pushed outward
("jelly"), a radial streak from the centre, a 64×64 glow sprite (a radial
gradient, cached by colour quantised to /32); the field's "breathing"
`0.86+0.14·sin(t·1.5 + r·0.9 + c·0.6)`; the playhead's row lit (empty dots at
alpha 0.5 against 0.2); the inverse of the dome by Newton, six iterations;
the cell size found in three passes around the perimeter with 0.3 cells of
padding; dt clamped at 50 ms; alpha and detail are parameters, for the mixer.
The web caps its backing store at 8 Mpx — not relevant on Metal, but worth
remembering as a precedent (large iPad screens).

### 2.4 The sequencer and its triggers

- A step is a 1/16 of a bar; the lookahead: a 25 ms tick, a 0.12 s horizon.
- On a step: an accent (v=1) always plays; a soft cell (v<1) plays with
  probability `0.35+0.65·v`; the velocity is `v·rnd(0.72,0.98)`; a sample is
  additionally detuned ±15 cents and gets a random relScale of 0.1–0.9. The
  dots' flashes and the playhead's change of row are delayed to when the
  sound actually lands (`time − now`).
- A preset's `tick()` runs once a bar (step 0) for each synth voice in use,
  with no duplicates when both tracks are on the same preset.

### 2.5 The sound (a port of audio.ts + synths.ts)

**The master bus:** gain 0.9 → the limiter (a compressor: threshold −8 dB,
ratio 12:1, attack 3 ms, release 180 ms) → out. **The samples' slap delay:**
send 0.16 → delay 0.17 s → LPF 2400 Hz → feedback 0.28, into the master. The
samples: one-shots under an envelope (attack 6 ms, an exponential release of
`clamp(0.08, 1.5, duration/rate)·relScale`), 16 WAVs (≈12 MB) to go into the
bundle; the voice list is "synths-first" at the moment and the samples are
parked behind a comment — we carry over both the parking and the working
playback path.

**Five synths** (randomness inside a frame: pitches from the scale, the
timbre re-rolled on every note, the patch drifting once a bar; every voice is
one-shot, disposed after its tail, on a shared budget of **40 voices**):

| Preset | What it is | The per-note parameters |
| --- | --- | --- |
| REVERIE | a drifting pad | an oscillator out of 8 types (sine, triangle, fatsaw, fattriangle, fmsine, fmtriangle, amsine, square), release 10–90 % of 3.2 s, the attack long 30 % of the time at 0.04–0.35, detune ±14 c, a ghost octave at p=0.22, a sub at p=0.10, −12 dB |
| KALIMBA | Karplus-Strong | resonance 0.55–0.94, dampening 900–4500, attackNoise 0.4–1.8, a per-note LPF at 1200–5200 ramping to 500–1600 over 0.3–1.1 s, an octave "ghost" at p=0.18, velocity through the gain (the dB formula) |
| RHODES | an FM piano | harmonicity {1,2,3,3.01,4}, modIndex 3–11, tremolo 2.5–7 Hz / depth 0.15–0.55 / stereo spread, a fifth or an octave at p=0.16 |
| ACID | a 303 bass | saw or square → a resonant LPF at −24 dB/oct with its own envelope (base 90–260 Hz, 1.6–4.6 octaves, exponent 2, Q 4–15, an accent at vel>0.7 driving both the filter and the amp), played two octaves down, −18 dB, drive 0.08 in the chain |
| MACHINE | drum synthesis by register | `midi mod 12`: <3 a kick (a membrane, freq/4), <6 a tom (freq/2), <9 a snare (noise + a bandpass at 1200–3600 plus a body), <11 a clap (2–4 slaps 8–20 ms apart), otherwise metal and hats (an FM stack, open at p=0.25) |

**The preset chain:** LPF (Q 1.2) → [Distortion 0.08, acid only] → chorus
(0.45 Hz, 6 ms, depth 0.55, wet per preset) → ping-pong delay (0.32 s, fb
0.38, wet per preset) → the dry output plus a send into the **shared reverb**
(decay 7 s, preDelay 20 ms). The cutoff and reverbWet ranges per preset come
from `TONE_SETTINGS` (carry the table over literally).

**The drift, once a bar:** cutoff → a random point in its range, ramped over
0.4–2.5 s; feedback → 0.2–0.55 over 0.5 s; the reverb send → its range over
1 s; the chorus depth ±0.09 (clamped 0.2–0.8, and not ramped — ramping
clicks); the echo thrown onto a new division {2,3,4,6}×step at p=0.25 — with
the wet ducked to zero across the change of delayTime (otherwise the tail
pitch-warps and burbles); every ramp anchored to the bar's scheduled time
rather than to "now".

### 2.6 Auth and holding on to a session (a port of auth.ts)

- The Supabase URL and publishable key are baked into the client (which is
  normal — RLS is what protects the rows).
- `peekSession()`: the library opens instantly off the cached session,
  before the network confirms anything (Keychain rather than localStorage).
- Why a session ended: the response from `/auth/v1/token` is intercepted (the
  server's own refusal text), written down with a timestamp (TTL 24 h), and
  shown on the landing screen as "Session ended N min ago: …".
- Offline: a refresh that failed for want of a network is not a sign-out — we
  keep the session and retry when connectivity returns (NWPathMonitor rather
  than the `online` event), plus after 5 s and 20 s.
- Signing out is strictly local (it does not kill the other devices).
- A provider's OAuth errors are shown on the landing screen rather than
  swallowed.

### 2.7 The backend (unchanged)

`supabase/schema.sql` is already in production: `profiles` (created by a
trigger), `projects` (RLS "yours only", an index on `user_id, updated_at
desc`, an `updated_at` trigger). iOS goes to the same tables through
PostgREST. Autosave: a 1.2 s debounce, coalescing, and a queue of no more
than one
request in flight, and network errors swallowed quietly (the next edit will
repeat the save).

---

## 3. The architecture and the shape of the repository

```
SQIA-ios/
├─ PLAN.md                      ← this document
├─ SQIA.xcodeproj
├─ SQIA/
│  ├─ App/                      SQIAApp, AppState (the landing/projects/sequencer route)
│  ├─ Core/
│  │  ├─ Music/                 Scales, GridModel, RandomNames, ProjectSnapshot (Codable)
│  │  ├─ Audio/
│  │  │  ├─ EngineCore          the graph, the master, the limiter, the slap delay
│  │  │  ├─ StepTransport       the lookahead clock
│  │  │  ├─ Voices/             Reverie, Kalimba, Rhodes, Acid, Machine, SamplePlayer
│  │  │  └─ Chains/             PresetChain, ReverbBus, BarDrift
│  │  └─ Support/               RandomSource (seedable), Debouncer
│  ├─ Services/                 SupabaseClient, AuthService, ProjectsService
│  ├─ Features/
│  │  ├─ Landing/
│  │  ├─ Projects/
│  │  └─ Sequencer/             SequencerView, MixerOverlay, VoiceSheet,
│  │                            StageView (the MTKView wrapper), GridRenderer
│  ├─ Shaders/                  Grid.metal (instances: the dot, the glow, the streak)
│  └─ Resources/                Samples/ (16 wav), Fonts/, Assets.xcassets (icons from public/)
├─ SQIATests/                   + Fixtures/ (golden JSON from the web)
├─ SQIAUITests/
├─ tools/gen-fixtures/          a node script: runs the web's functions, dumps the references
└─ supabase/functions/delete-account/   (see §6)
```

The principles: all the "musical arithmetic" is pure functions with no UI and
no `Math.random` inside them (the RNG is injected → deterministic tests); the
audio allocates nothing and locks nothing on the render thread (events go
through a lock-free queue, voices come from a pool); the UI state is an
Observable model, one source of truth, the way `main.ts` is.

---

## 4. Proving parity: golden fixtures

The `tools/gen-fixtures` script runs the **real web code** (imported from
`funny-steps`) and dumps the references:

- the `columnMidi` / `rateTable` tables for all 12 roots × 5 scales;
- the results of `brush/stamp/erase/random` (with the RNG pinned);
- warp/unwarp/fitCell over a set of points and viewports;
- a sample project snapshot (compared by value);
- the corpus of random names.

The Swift tests read the same files. It is the only reliable way to prove
"1:1" on the arithmetic without comparing by eye.

The detail without which none of it works: the web randomises through
`Math.random`, so the generator replaces it with a seedable **Mulberry32**,
and `SQIACore` carries the same PRNG bit for bit (all the arithmetic in
UInt32 — JS's `^`, `>>>`, `|` and `Math.imul` compute mod 2³² anyway). The
`prng.json` fixture checks that first; everything else stands on it.

Sound parity is separate (the web already has a method in
`scripts/balance.mjs`): an offline render of each preset on both platforms
over one pattern with one seed → a comparison of RMS and spectrum, plus a
blind A/B by ear. The criterion: levels within ±1.5 dB, and a character that
is "indistinguishable in the mix".

---

## 5. The UI details that are easy to lose

- Manrope, letter-spacing −0.01em throughout and 0.14em on the sequencer's
  labels; the palette `--ui #f5f3f3`, `--card #383838`, `--ink #d4cccc`, the
  background pure black; a black status bar, the safe area as the CSS has it.
- The dot labels are not system buttons: a press is opacity 0.55.
- The mixer's name chips sit **over the lower rows of dots** (the panel is
  given over entirely to the grid).
- The sheet: a 0.22 s animation on cubic-bezier(0.22,1,0.36,1), the scrim
  0.18 s.
- A card's menu is positioned at the point of the tap, clamped to the screen
  edges.
- The empty-state card is clickable across the whole of it.
- A failure to start is shown on screen (the web has `#boot-err`; iOS gets an
  equivalent plate — a log is just as unreachable to a phone's user).

---

## 6. The required departures from the web (App Store)

Exactly three, all of them forced — everything else is 1:1:

1. **Sign in with Apple** (Guideline 4.8: once Google sign-in is offered,
   Apple's is required). Supabase supports the native `signInWithIdToken`.
   The button on the landing screen follows Apple's guidelines (a black or
   white pill — it fits the style).
2. **Deleting an account from inside the app** (Guideline 5.1.1(v)). The web
   has none. The minimum: a `delete-account` Edge Function (service role,
   `admin.deleteUser` by JWT; the cascade takes profiles/projects with it)
   and a "Delete account" item with a confirmation in the account menu. Worth
   adding to the web afterwards too.
3. **A privacy manifest and the privacy questionnaire** (the email you sign
   in with, and the user content that is the projects; no tracking).

**The sixth, by the owner's decision (22.08):** **the drums do not follow the
key, and only in the app.** MACHINE picks an instrument by the note's pitch
class, so transposing shifts the whole kit across the columns — the kicks you
drew become toms. In the app a column is always the same instrument
(`Music.drumTable`); on the web we leave it as it is.

The price is named plainly: **a project with MACHINE in it, made on the web,
will sound different on an iPhone.** That is an accepted divergence rather
than a bug, and it goes through the M9 checklist as "known". The notes, the
grid, the tempo and the key all agree — the only thing that differs is which
drum plays in which column. If it is ever to be reconciled, the fix belongs
on the web, because the right behaviour is the one here.

**The fifth, by the owner's decision (21.08):** the sound is tuned by ear and
differs from the web's. `Tuning.web` is the web's numbers and stays the
reference, under test; `Tuning.tuned` is what the app opens on. The tuning
panel (the sound sheet → Tuning) gives sliders over 29 parameters and can go
back either to the build's defaults or to the web's numbers, to hear what was
moved away from. **Since 22.08 it is in Debug builds only** (the owner's
decision): it is the workbench the sound was made on, not a feature — 29
unexplained sliders are not what you show somebody who has just opened a
music app. The numbers it produced live in `Tuning.tuned` and travel to the
release; the panel does not.

What was moved, and why: RHODES had its modulation cut almost in half and its
bell slowed (it was too "digital"); MACHINE's kick starts lower and louder
(it needs weight, not pitch); ACID's resonance was opened from zero to
14.5 dB (the squelch became an event rather than a background) and its sweep
slowed. The full list is in `Tuning.tuned`.

**What was written here about the room was wrong, and was corrected in M9.**
It said "half as long and brighter", which was read off the web asking for
`decay: 7` where 2.92 had been found by ear. But Tone does not read `decay`
as seconds: it turns the number into the time constant
`ln(decay+1)/ln(200)`, and the web's room rings for **2.71 seconds**. So the
length found by ear diverged from the web by eight per cent — and that
without knowing the reference — while the real difference is exactly one, and
the opposite of what was written: damping. The web has none at all (the
impulse is white noise under an envelope, bright to the end), we have
6870 Hz, so our room is **darker**, not brighter.

For M9 this means the A/B against the web is done on `Tuning.web` rather than
on the build's defaults.

**The fourth, by the owner's decision (20.08):** the modals and the buttons
are native iOS rather than ports of the web's. That applies to what is
already built as much as to everything after it.

- Choosing the sound, the key and the note happens in system sheets
  (`NavigationStack` + `List`, detents, Done in the toolbar) rather than in
  styled panels.
- The key and the scale are now **chosen** rather than cycled by tapping: on
  the web a tap on the label steps one note forward, and reaching the twelfth
  takes eleven taps. On a phone that is not the gesture.
  `SequencerState.setRoot/setScale` sit beside `cycleRoot/cycleScale` — the
  cycling stayed in the core, and the parity test uses it.
- The buttons inside modals are system ones (`.bordered`, `.plain`, the
  toolbar).
- The sequencer itself is still a literal port of the web: the field, the BPM
  drag, ERASE/RNDM, the labels. "Native" applies to the modals and the
  buttons, not to the scene.

What that buys beyond the look: VoiceOver, Dynamic Type, scrolling behaviour
and the dismissal gesture — all of it from the system, and all of it free.

An infrastructural detail: a magic link from an email needs a bridge into the
app. The recommendation is a static page at `sqia.serezhaok.com/ios` (GitHub
Pages is already there) that forwards the token to `sqia://auth`, with
`emailRedirectTo` pointing at it when the mail is sent from iOS. It is more
dependable than AASA/Universal Links on Pages and needs no new
infrastructure. Google OAuth: `ASWebAuthenticationSession` with a
`sqia://auth` redirect (a system browser — Google permits that). In the
Supabase dashboard, add those redirect URLs to the allowlist and switch the
Apple provider on.

---

## 7. Milestones, tasks, estimates

The estimates are pure development days (the range: confident — with room for
debugging). The order is chosen so that a **playable vertical slice** (you
draw, it sounds, it looks right) exists after M4, before full parity.

### M0 — Bootstrap ✅ done
The Xcode project (Xcode 16+, synchronised groups — new files need no project
edits), an iOS 17 target, portrait only, dark; the icon rendered out of
`icon.svg` at 1024 (`tools/make-icon.py`); Manrope cut into four static
instances (`tools/make-fonts.py` — the variable file's default instance is
ExtraLight, which the design does not use); the palette and the typography
from `style.css`; CI on GitHub Actions (the core in
a Linux Swift container, the app on a macos-runner).
**Acceptance:** the skeleton shows the field of dots through the real dome
geometry, in the real palette and the real font. The samples (12 MB) move to
M2, supabase-swift to M7.

### M1 — The music core and the fixtures ✅ done
`Core/` is the `SQIACore` SwiftPM package with no Apple frameworks: `Music`
(scales/MIDI/rate), `NoteGrid` (the model without the rendering — renamed,
because `Grid` collides with SwiftUI's container), `Field` (the dome's
geometry), `ProjectNames`, `ProjectSnapshot`/`Project` (Codable with the
database's keys), `Mulberry32`. The `tools/gen-fixtures` generator imports the
**live web sources** (an extension resolver plus an `auth` stub), 6 fixtures.
**Acceptance:** 20 tests green. The layout, the warp and every grid edit
match **bit for bit**; only `exp2` (1.6e-16) and the inverse Newton (1.2e-13)
diverge, and the tolerances are set to the measured facts rather than "with
room to spare".

### M2 — The audio foundation ✅ the code is done, acceptance on a device is yours
The `AudioMixer` renderer in the core: a voice pool, the slap delay (170 ms,
LPF 2400 Hz, fb 0.28, send 0.16), master 0.9, the limiter (−8 dB, 12:1, a
30 dB knee, 6 ms lookahead), stereo throughout — all 16 samples are stereo.
`StepVoicing` is the "randomness inside a frame" rule with the same order of
rolls as the web's. A wait-free event queue (checked with real threads). The
app layer: `AudioEngine`, `AudioSessionController` (a call, headphones, a
route change at a different rate, a media services reset), `SampleLibrary`
(decoded once, and the memory never released — the same as the web's cache),
`Sequencer` (a 25 ms timer against the renderer's frame counter).
**Acceptance (needs a device):** the bench inside the app — press PLAY and
let it run for ten minutes without drift; take a call; plug the headphones in
and pull them out. It compiles in CI on macOS; 81 core tests green.

### M3 — The scene on Metal ✅ done
`FieldAnimator` in the core: the energy of the flashes, the neighbours pushed
out, the colour waves with their per-ring delay and their strobe, the
breathing — it emits a list of primitives. `FieldRenderer` plus
`FieldShaders.metal`: instanced quads, the shape set by the fragment shader,
additive blending.
**Acceptance:** instead of comparing screenshots, a recording canvas context
takes the primitives themselves off the web (8 scenarios) and Swift checks
against them primitive by primitive, diverging by less than 1e-9. What is
left: fps on a device.

### M4 — The sequencer screen and the gestures ✅ done
`SequencerState` in the core (the tracks, the key, the tempo, snapshot/apply
— useful in M7 and already under test). `SequencerModel` ties the state, the
engine and the field together. `SequencerView` follows the CSS metrics: the
BPM drag and tap, the track dots, the root and the scale, ERASE, the voice
label, RNDM, the Sound sheet. The flashes arrive exactly when the sound does.
**Acceptance:** "you draw, it sounds". The voices are still samples (the
synths are M5), the mixer is M6.

### M5 — The voices and the effects ✅ done
The generators (Tone's 8 shapes plus a clean saw for the 303, saw/square
band-limited through PolyBLEP), an ADSR and a pitch envelope, white and pink
noise, Karplus-Strong, two-operator FM with its own modulator envelope, a
stereo tremolo, a resonant −24 dB/oct cascade with a filter envelope, a
chorus, a ping-pong delay, an overdrive on Tone's curve, the reverb (an FDN),
a high-pass on the reverb send, and the preset chain with its per-bar drift
and the echo ducked when it is thrown.

All five voices roll in the exact order, including the values Tone takes off
the stream and never uses (`octaves` on the metal, `release` on PluckSynth).
The samples were removed by the owner's decision: the voice list is synths
only now, and `voiceIdx` matches the web (0…4).

The preset buses became stereo — Tone's tremolo is spread 180° apart, and in
mono it would subtract to exactly nothing.

**Acceptance on a device is yours:** an A/B of each preset against the web.

**What rendering costs.** A crackle is a missed deadline, so it is measured
rather than guessed at: `RenderCostTests` prints the realtime factor (a
second of work per second of audio) and holds release under 0.25×. Two full
tracks come to about 0.08×, and idle to 0.002×.

What was done about the "heavy glitching and crackle" report:
- Xcode's Run button builds Debug, and unoptimised Swift is several times
  slower. Debug is now `-O` at the project level, with the app target taking
  `-Onone` back — only the package counts samples.
- Idle cost 21 % of a core: all five chains ground through a filter, a chorus
  and two delay lines every sample, and all 40 voice slots were scanned. Now
  a chain with no signal and no tail is skipped, the voices run up to a
  watermark, and complete silence exits the loop early.
- `pow`/`log10`/`sin` are gone from the per-sample path: the envelopes became
  multiplicative, the limiter's gain computer runs once every 8 samples, and
  the chorus LFO is a unit vector being rotated.
- The master output is clamped to ±1, and a non-finite sample (should some
  filter blow up after all) mutes the effects and is counted — there should
  be no roar until the app is restarted.
- In a Debug build the factor is on screen, next to a count of dropped notes.
  It is `#if DEBUG` and goes before the release.

The original scope:
One task per preset: REVERIE → KALIMBA → RHODES → ACID → MACHINE (the order
is the default voices and the most-used first); the preset chains and the
shared reverb; BarDrift with anchored ramps and the ducked echo throw; the
40-voice budget, the pool, disposal after the tail; the sample path (the
parked list); balancing by the method in §4.
**Acceptance:** an A/B per preset; RMS within ±1.5 dB; an hour of playing
with no degradation (voice leaks, an overloaded render thread).

### M6 — The mixer ✅ done
The panels' geometry is in the core and under test: 10 outside, a 17-wide
gutter, the proportion 270/168.75, starting at 0.108 of the height, 100
points at the bottom for the tile. The active track flies out of full screen
into its own slot over 0.35 s on a cubic ease — on the same display link as
the field, or two timers drift apart over a third of a second. The other
tracks wait in their slots and fade up; the slot outlines are a new primitive
in the shader (`kindOutline`), drawn as a hairline around the quad's contour.
The name and mute chips fade in on their own 0.18 s curve — exactly like the
CSS transition on the web, where the canvas flies and the controls simply
appear. The track dots in the header open the mixer; while it is open, they
and the whole bottom toolbar are hidden.

One trap the web does not have: a drag reports continuously, and choosing a
panel closes the mixer — without a latch the same tap would pick a track and
immediately draw a dot on it. On the web this is `pointerdown`.

The "Back to projects" tile, from M7, flushes the autosave and leaves for the
library.

### M6 — the original scope (2–3 days)
The full-screen↔panel animation (0.35 s, the same ease), the outlines, the
name and mute chips, tap-on-panel, "Back to projects", dimming a muted track,
detail on an inactive panel.
**Acceptance:** a frame-by-frame comparison of the transition against the
web; mute instant and persisted.

### M7 — The project library ✅ the code is done, acceptance waits on a session from M8
The screen follows the metrics in 2.1.2: the four-dot mark and the account
pill at 35 points, the title at 44 on a 60 line, cards in two columns with a
7-wide gutter and 20-point margins, the "+ Create new" pill 40 above the home
indicator, and one breakpoint at 768 where the cards stop stretching and
become fixed 200×200 tiles. The grid and its breakpoint are in the core,
under test.

The modals are not the web's but the system's: a `Menu` instead of a
positioned div, an alert with a text field instead of `prompt()`, a
`confirmationDialog` instead of `confirm()`. That follows your rule about
native windows and buttons.

Autosave is a port of `makeAutosave` with one deliberate difference. In a
browser `clearTimeout` cannot reach a request that has already left, while
cancelling a task in Swift reaches everything under it: the first version
held the write inside the timer's task, and the next edit cancelled the very
request it was waiting on — the save was lost in flight. The waiting and the
writing are two tasks now: the timer is cancellable, the writer is not. There
is a test for this, and it fails on the old shape.

Edits go through `publishVoicing` — the same `updateRates(); touch();` pair
the web has at every call site, but in one place instead of eight. The
snapshot is assembled when it is written rather than when the edit happens:
the difference between copying five hundred cells once a second and doing it
on every frame of a drag.

The rows live in a file on the phone. The web has no local copy at all, and a
phone cannot work that way; after M8 the file stays as what Supabase falls
back to. The Supabase store is written and under test (the columns, their
order, the write filter, the insert body, and the difference between "deleted
a row" and "found no row"), but it has nothing to talk to production with:
there is no session until M8. So the M7 acceptance — CRUD against production
Supabase and "a web project opens on an iPhone" — moves into M8.

Two deliberate departures from the web: a rename or a delete that failed puts
the row back (the web leaves the lie on screen until the next load), and a
list reload that failed keeps the cards already drawn instead of wiping the
library.

### M7 — the original scope (3–4 days)
The Projects screen to the metrics in 2.1.2, the context menus, rename and
delete, the empty state, the iPad layout; autosave (a 1.2 s debounce plus an
in-flight queue), creating with a random name, offline behaviour as on the
web.
**Acceptance:** CRUD against production Supabase; a project made on the web
opens and sounds identical, and edits from an iPhone are visible on the web.

### M8 — The landing screen and auth ✅ the code is done, acceptance on a device is yours
The sign-in screen to the web's metrics: the mark at 132, the wordmark at
2.6rem, buttons 54 tall and fully rounded, 38 points of air above the first
and 12 between the rest,
and the column capped at 340. One button the web does not have: Guideline 4.8
requires Apple wherever Google is offered, and requires it be no less
prominent — so it goes first, in Apple's own button, at the same size.

All the logic is in the core under test, and it rests on one distinction that
`AuthError` carries: **rejected** — the server looked and refused, the session
is over; **unreachable** — nobody looked, and nothing new is known about the
token on disk. A phone is on the network and then it is not, and treating the
second case as a sign-out is exactly what throws somebody onto the sign-in
screen in the underground, having lost nothing but their composure. A refusal
kills the session and writes down the reason in the server's own words
("Already Used" is two refreshes racing, "session expired" is policy, and the
words have to differ). An unreachable server keeps the session and retries
after 5 s, after 20 s, and when the network returns (`NWPathMonitor`). There
is a test named after the tunnel.

A returning user never sees this screen: the Keychain is read before anything
touches the network, the library opens off the cache, and the token is
confirmed behind it. `AfterFirstUnlock` — so a phone in a pocket can refresh
its token; the note about why a session ended lives in UserDefaults, because
Keychain items survive a reinstall and "Session ended 4 min ago" on a fresh
install would be a small lie.

SHA-256 is written out here rather than taken from CryptoKit: the whole
package is tested on Linux, and CryptoKit is not there. What is hashed is a
value that goes out in the clear a moment later, so there is nothing for a
timing attack to leak. It is checked against the FIPS vectors, against the
block boundaries (55/56/64 bytes — where padding breaks), and against the
worked example in RFC 7636 §4.4, which checks the digest, the encoding and
the challenge together.

Account deletion is Guideline 5.1.1(v): the function in
`supabase/functions/delete-account`, and the only thing standing between a
caller and somebody else's account is that it deletes the owner of exactly
the JWT it was called with. There is no request body, on purpose.

**What is missing:** an offline cache of the projects. A read-only cache
would show rows that can be opened and edited while every save failed
silently: the person believes they saved. Real offline means a queue of
deferred writes and conflict resolution — a feature of its own, not a line in
a milestone. An honestly empty library offline is exactly what the web does.

The file store for it was written and then removed in M9: nothing used it,
and dead code in a release is a liability with no upside. It is in the
history if it is ever wanted.

**Acceptance (needs a device and dashboard access):** all three ways in;
turn the network off and the app does not sign you out; an expired refresh
shows the reason on the landing screen; CRUD against production Supabase and
"a web project opens on an iPhone" (carried over from M7).

### M8 — the original scope (4–5 days)
The sign-in screen 1:1 (the logo as a vector, the Google button, the email
form, the statuses and errors); Google through ASWebAuthenticationSession;
the magic link through the bridge page; **Sign in with Apple**; the Keychain
session cache and the instant entry; the notes about why a session ended plus
the offline retries; a local sign-out; account deletion (the Edge Function
and the UI).
**Acceptance:** all three ways in, on a device; turn the network off and the
app does not sign you out; an expired refresh shows the reason on the landing
screen.

### M9 — Parity QA ✅ done, bar the device matrix
The A/B against the web's sound was done on `Tuning.web`, and it found three
things — all three in our favour, because all three were errors in the
reference or in the port rather than quibbles.

**The reverb (risk R3, closed).** Tone reads `decay` not as seconds but as
`ln(decay+1)/ln(200)` — a time constant for `setTargetAtTime`. So the web's
`decay: 7` is a 2.71 s room, and the rest of the seven-second buffer is
silence at −139 dB. `Tuning.web` held the seven and the network read it as
seven seconds of RT60: the reference everything else is measured against was
ringing two and a half times longer than the original. Plus 4500 Hz of
damping where the web has none at all. With the reference corrected the
network holds (the seconds asked for, to within 20 %) and no convolution is
needed.

**The limiter (risk R8, closed).** It turned out to be not "close" but
wrong. A textbook soft knee is centred on the threshold; Blink's runs upward
from it: at −8 dB with a 30 dB knee that is a divergence across everything
from −23 to +22 dBFS. The master was compressing what the web passes. The
static curve is now a port of `DynamicsCompressor::Saturate`, checked against
an independent second transcription of the same Chromium source. You can hear
it: the mix is louder and has its transients. The envelope stayed ours — the
difference is in how fast the same reduction arrives, not in how much of it
there is.

**Clipping.** Now that the limiter no longer squashes, a dense pattern
touches the ceiling. Measured: one sample in four thousand on the web's
numbers, one in six hundred on the tuned ones, and Web Audio clamps at ±1 in
exactly the same way. The test guards the proportion rather than the fact.

Also in M9: the flash delayed by the route's latency (the picture was running
ahead of the sound — on Bluetooth it would have been a fifth of a second);
VoiceOver for the field and the tempo (the field was an unnamed rectangle,
and the tempo could be read but not changed); the `NOTICE.md` that did not
exist; `PrivacyInfo.xcprivacy`; the unused file store removed; the sliders
taken out of the release; and the `SQIAUITests` smoke test that walks the
screens — the one thing the core cannot check.

**What is missing, and why.** Snapshot tests of the screens are deliberately
not done: their reference images are recorded on a machine with a simulator,
and this session lives in a Linux container. Adding them from here means
putting a failing step into CI until you record the references locally and
commit them. If they are wanted, say so and the target and the instructions
will follow, but the first run is yours. The device matrix (SE, ProMotion,
iPad) and Instruments are yours by definition.

### M9 — the original scope (4–6 days)
A pass through the §2 checklist, screen by screen, beside the web; the device
matrix (SE — the small stage and fitCell, ProMotion, iPad); Instruments (fps,
the audio thread, memory, energy); the behaviour under the silent switch (the
decision: play — this is a music app and the .playback category allows it);
VoiceOver labels on the controls (the web has aria-labels); snapshot tests of
the screens (swift-snapshot-testing); an XCUITest smoke test with test seams
like the web's (launching with fixture projects and no network — the
equivalent of `__setRows`).
**Acceptance:** the checklist closed, and the only known divergences are §6's.

### M10 — Release: the materials are ready, the store is yours
Written and in the repository: `PrivacyInfo.xcprivacy` (two data types, both
linked, both App Functionality, no tracking), `NOTICE.md`, the Sign in with
Apple entitlement, and `Support/AppStore.md` — the name, the subtitle, the
description, the keywords, the privacy questionnaire word for word against
the manifest, the notes for the reviewers and the checklist before uploading.

The review notes were worth writing carefully: a screenshot of a grid of dots
does not convey that the app makes sound, so they say how to hear it in a
minute, where account deletion lives, and that the Apple sign-in is native
and first.

The test account in the file is deliberately empty: it is the one thing that
does not belong in a repository.

Yours: App Store Connect, the screenshots (from a device — the glow is drawn
in Metal and the simulator composites differently), TestFlight, the age
rating, and `MARKETING_VERSION` at 1.0.

### M10 — the original scope (2–3 days + Apple's review)
The bundle id, signing, App Store Connect, PrivacyInfo.xcprivacy, the privacy
questionnaire, the screenshots, TestFlight, the notes for the reviewers (the
test account!), the age rating, the metadata. A buffer for one round of
review notes.

### Summary

| Milestone | Estimate, days |
| --- | --- |
| M0 bootstrap | 1–2 |
| M1 core + fixtures | 2–3 |
| M2 audio foundation | 3–4 |
| M3 the scene on Metal | 5–7 |
| M4 sequencer + gestures | 4–6 |
| M5 voices and effects | 10–14 |
| M6 mixer | 2–3 |
| M7 library | 3–4 |
| M8 landing + auth | 4–5 |
| M9 parity QA | 4–6 |
| M10 release | 2–3 |
| **Total** | **40–57** |

The vertical slice (M0–M4 with one voice) is roughly 2.5–3 weeks from the
start; after that the main risk and the main time is the sound (M5).

---

## 8. Risks

| # | Risk | Mitigation |
| --- | --- | --- |
| R1 | The timbres will not match Tone.js by ear | Port the formulas rather than "similar nodes"; an offline A/B from the first preset (the method in §4); a week of slack inside M5 |
| R2 | Tone's "fat"/FM/AM oscillators and envelopes have their own quirks (curves, the detune stack) | Take the exact behaviour from Tone's sources (MIT) and reproduce it in the DSP voices; fixtures over the envelope shapes |
| R3 | The reverb: the web convolves with a generated IR | **Closed in M9.** The A/B was done on decay time: the web's RT60 is 2.71 s (not 7 — Tone reads `decay` as a time constant), the network gives the seconds asked for to within 20 %, and on the web's numbers they agree. No convolution was needed. The tests are `ReverbParityTests` |
| R8 | The limiter is not a port of the Web Audio algorithm but a standard soft knee with the same numbers; it is on the master, so it colours everything | **Closed in M9 — and it turned out to be not "close" but wrong.** A textbook knee is centred on the threshold, Blink's runs upward from it: at −8 dB with a 30 dB knee that is a divergence across everything from −23 to +22 dBFS, which is to say across all the music. The static curve is now a port of `DynamicsCompressor::Saturate` (including the bisection over `k` and the makeup `(1/Saturate(1,k))^0.6`), checked against an independent transcription — `LimiterParityTests`. The envelope (the adaptive release) stayed ours: the difference is how fast the same reduction arrives, not how much of it there is |
| R4 | The magic link: the email opens a browser, not the app | The `/ios` bridge page (§6); the fallback is that link sign-in keeps working on the web |
| R5 | Apple's review: 4.8 / 5.1.1(v) | Closed as planned in M8; a test account and a video preview for the reviewers |
| R6 | The scene's performance on older devices | Metal from the start; the detail parameter is already in the design; profiling in M3 rather than at the end |
| R7 | A divergence in the snapshot format breaks cross-platform | Byte-level tests in M1 plus the M7 integration test, "a web project opens on iOS" |

---

## 9. What is needed from the project's owner

1. **The Apple Developer Program** ($99/year) and a Mac with Xcode — this
   Linux session writes the code and the tests, but only macOS can build and
   sign an iOS binary (the alternative, Xcode Cloud / a GitHub Actions
   macos-runner, is already in M0).
2. Access to the **Supabase dashboard**: under Authentication → URL
   Configuration, add `sqia://auth` and `https://sqia.serezhaok.com/ios` to
   the allowlist; switch the Apple provider on (a Service ID and a key);
   deploy the function — `supabase functions deploy delete-account`, the code
   is in `supabase/functions/delete-account`. Without this the sign-in
   buttons reach the server and are refused.
3. Copy `web/ios/` into `funny-steps/public/ios/` — the bridge page for the
   link in the email (a mail client will not follow `sqia://`). It reads
   nothing and stores nothing, it only forwards.
4. In Apple Developer: enable Sign in with Apple on the App ID
   `com.serezhaok.sqia` (the entitlement is already in
   `Support/SQIA.entitlements`).
5. Confirm the defaults in §1 (background/haptics/portrait) — otherwise they
   are taken as they stand.

---

## Appendix A. Known divergences between the README and the web's code

Written down so the port follows the code:

- The README says "10 × 16 grid" — the code says `COLS = 12`.
- The README describes choosing a sample as the main path ("KALIMBOX" in the
  footer of index.html is an old label too) — in the code the synth voices
  are primary, the sample list is parked, and the defaults are
  REVERIE/MACHINE.
- The README does not mention the mixer, the tracks or the projects — they
  exist, and they are being ported.
