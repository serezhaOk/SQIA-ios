# SQIA for iOS

A native Swift port of [SQIA](https://sqia.serezhaok.com) — the note-matrix
sequencer built for sound accidents. The goal is a 1:1 copy of the web app
(`serezhaOk/funny-steps`): same screens, same feel, same sound, same backend.
Projects are stored in the same Supabase database, so a pattern made in a
browser opens on a phone and the other way round.

[PLAN.md](PLAN.md) is the full plan of work and the parity specification —
what the web app does, taken from its sources rather than its README, and how
each part maps onto iOS.

## Status

| Milestone | State |
| --- | --- |
| M0 — project bootstrap | done |
| M1 — music core + golden fixtures | done |
| M2 — audio foundation | done |
| M3 — the field on Metal | done |
| M4 — the sequencer screen | done |
| M5 — the five synths | done |
| M6 — the mixer | done |
| M7 — the project library | done |
| M8 — sign-in | done, waiting on the Supabase dashboard |
| M9 — parity QA | done bar the device matrix |
| M10 — release | materials written; the store side is manual |

What runs today: all of it. Sign in with Apple or Google;
the library lists what you have made and creates new ones with a name out of
the microbial world; opening a project starts it playing. Draw on the field
with a finger and it sounds; drag the tempo, choose the key, erase, scatter a
pattern, pick a sound. Edits save themselves, into the same Supabase rows the
browser reads. The dots bloom exactly when their note lands — allowing for
the buffer and the route, so the picture does not run ahead of the sound on
Bluetooth. Tapping the track dots opens the mixer — the track being played
flies into its panel while the other fades up beside it, each with a name and
a mute button.

The sounds are synthesised, not sampled — the sample set is gone. All five
presets are written: reverie the drifting pad, plucked a plucked string,
rhodes an FM electric piano with a stereo tremolo, acid a 303 whose filter
an envelope sweeps on every note, and machine the drums whose instrument is
chosen by the column's register. Every rolled value comes off the random
stream in the order the web takes it, including the ones Tone asks for and
never uses.

Modals and buttons are native iOS rather than ports of the web's — system
sheets for the sound and the key, with the platform's scrolling, Dynamic
Type and VoiceOver behaviour. The sequencer itself is still the web's,
gesture for gesture. One consequence worth naming: the key is chosen from a
list instead of cycled a semitone per tap.

The audio graph is one `AVAudioSourceNode`; everything that shapes the sound
lives in `SQIACore`, where it can be tested off a device.

Beside the five, the picker offers the sounds made in
[SQIA Lab](../SQIA-Lab), the Mac bench for designing them, played by
`SQIASound`: eight Plaits voices, a sampler and a Rings reverb in C++
behind a C header, which the Lab uses too, so a sound plays in the app
exactly as it did on the bench.

New sounds do not need a release. The Lab's **Publish** writes a row to
the `sounds` table and uploads any recordings to the public `sounds`
bucket (`supabase/migrations/20261001100000_sounds.sql`). The app reads the
table at launch, keeps the last copy for offline use, and downloads a
sound's recordings the first time it is picked or found in a project. While
they download, the track keeps playing what it had. After 1.5 seconds the
picker shows a progress bar, and the track switches once everything is on
the phone. A row can also mark a sound as Plus (it gets the diamond and the
paywall), hide it from the picker without breaking the projects that use it,
or re-label and re-order one of the five that ship in the bundle
(`Core/Sources/SQIACore/Sounds/`). A sound's number is the voice index
projects store, so it is never reused. The handpan, #10, is the first sound
served this way, and it is Plus. [PLAN.md](PLAN.md)
explains why, and what it costs.

## Two fields, and which one ships

The sequencer draws the **heat field**: notes are sources in a scalar field,
the sum is accumulated into a texture, and a second pass draws a contour
through the total. Two notes close together come out as one shape with one
outline, which is the whole reason it exists — nothing you do to two
separately drawn circles will do that. It is the target look, and it is what
`FieldStyle.heat` selects.

The **dot field** it replaced is still here, whole: a dot, a halo and a
streak per note, on the web's dome. It is not dead code and not a fallback.
It is what the parity fixtures were generated against — `warpField`,
`hitTesting` and the rest measure `FieldStyle.classic`, which is pinned to
the web's own numbers by `FieldTuning.web` and cannot be moved by anything
in the tuning panel. Deleting it would delete the answer to the question
this port exists to keep answering.

Debug builds can switch between them: the field panel's first row, or
`FieldScene.style` if you would rather do it in code. The style reaches
hit-testing as well as drawing, so the dome comes back under a finger at the
same moment it comes back on screen.

## What the render thread costs

A crackle is a missed deadline, so the cost of rendering is measured rather
than guessed at, in two places.

`RenderCostTests` reports the audio thread's realtime factor — seconds of
work per second of audio — and holds a release build to 0.25×; two full
tracks come to about 0.08×. `FieldCostTests` reports what one frame of the
field costs the main thread; a saturated field comes to about 0.26 ms
against a 16.7 ms frame.

`SQIACore` compiles at `-O` in Debug as well as Release, set in
`Package.swift` so it does not depend on whether Xcode's project settings
reach a package target. Unoptimised, the same passage costs five times as
much, and the audio thread's deadline does not care which configuration is
being built. A Run build is therefore a fair test of the sound.

The renderer still measures itself — what a frame costs the main thread and
how many are actually being delivered — but nothing shows those numbers now.
A meter floated over the field while the sound was being tuned; it sat on top
of the picture, which is what is being worked on, so it came off. The
measurement stays where it was, so putting a readout back is a small view
rather than a hunt: `FieldRenderer.onScreen` is the way to reach it, and the
mixer carries its own load, sounding voices and dropped-note counts.

## Layout

```
Core/          SQIACore — pitch mapping, the note matrix, dome geometry,
               the lookahead clock, the whole signal path, the project
               snapshot format. Pure Swift, no Apple frameworks, so it
               builds and tests on any platform.
  CSQIAAtomics  Acquire/release for one lock-free queue. Swift's own
                atomics need iOS 18 and SQIA targets 17.
SQIA/          The app: the AVFoundation shell around SQIACore, the design
               system, the screens. Xcode syncs this folder, so new files
               need no project edits.
Support/       Info.plist, the entitlements, and the App Store copy
tools/         gen-fixtures (golden data from the web sources),
               make-icon.py, make-fonts.py
```

## Building

Needs Xcode 16 or newer (the project uses synchronised folder groups).

```sh
open SQIA.xcodeproj
```

Set your team under Signing & Capabilities the first time; the bundle
identifier is `com.serezhaok.sqia`.

## Testing

The core suite proves parity with the web app rather than merely exercising
the Swift code. Every fixture under `Core/Tests/SQIACoreTests/Fixtures` is
produced by running the web app's own sources, and the tests replay the same
inputs:

```sh
swift test --package-path Core
```

Most comparisons are exact, including cell fitting and the dome warp — those
land on identical bits in JavaScript and Swift. Two cannot be: playback rates
differ by one ulp (`exp2` against V8's `Math.pow`) and the Newton inverse by
about 1.2e-13, and both are pinned to the divergence actually measured.

### Regenerating the fixtures

Clone the web app beside this repository and run the generator. Anything the
web app decides at random goes through `Math.random`, which the generator
replaces with a seeded Mulberry32 — the same PRNG `SQIACore` ships, bit for
bit, which is what makes a seeded comparison meaningful.

```sh
git clone https://github.com/serezhaOk/funny-steps ../funny-steps
cd tools/gen-fixtures && node --run gen      # or WEB_SRC=/path/to/src node --run gen
```

## Assets

`tools/make-icon.py` renders the app icon from the web app's `icon.svg`
geometry. `tools/make-fonts.py` cuts the four Manrope weights the design uses
out of the variable font — the variable file's default instance is ExtraLight,
which is not a weight SQIA uses anywhere.

Manrope is under the SIL Open Font License 1.1; the licence ships beside the
fonts in `SQIA/Resources/Fonts/`. It is also on the third-party
list, along with the Mutable Instruments DSP behind the Lab sounds — see
[NOTICE.md](NOTICE.md). There are no package dependencies: the code is
vendored in `Core`, and Supabase is reached over plain HTTPS.

## Copyright

Copyright © 2026 Sergei Diuzhev. All rights reserved. Like the web app, SQIA
for iOS is not open source — see the web repository's
[LICENSE](https://github.com/serezhaOk/funny-steps/blob/main/LICENSE).
