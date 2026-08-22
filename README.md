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

What runs today: all of it. Sign in with Apple, Google or an email link;
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
presets are written: REVERIE the drifting pad, KALIMBA a plucked string,
RHODES an FM electric piano with a stereo tremolo, ACID a 303 whose filter
an envelope sweeps on every note, and MACHINE the drums whose instrument is
chosen by the column's register. Every rolled value comes off the random
stream in the order the web takes it, including the ones Tone asks for and
never uses.

Modals and buttons are native iOS rather than ports of the web's — system
sheets for the sound and the key, with the platform's scrolling, Dynamic
Type and VoiceOver behaviour. The sequencer itself is still the web's,
gesture for gesture. One consequence worth naming: the key is chosen from a
list instead of cycled a semitone per tap.

The audio graph is one `AVAudioSourceNode`; everything that shapes the sound
lives in `SQIACore`, where it can be tested off a device. [PLAN.md](PLAN.md)
explains why, and what it costs.

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

On the device, a Debug build floats a meter over the field: the audio load,
the voices sounding, what a frame costs the main thread, and the frame rate
actually being delivered, with dropped notes beside them when there are any.
It is `#if DEBUG` only and comes out before release.

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
fonts in `SQIA/Resources/Fonts/`. It is also the whole of the third-party
list — see [NOTICE.md](NOTICE.md). There are no package dependencies: the
sound is written out in `SQIACore` and Supabase is reached over plain HTTPS.

## Copyright

Copyright © 2026 Sergei Diuzhev. All rights reserved. Like the web app, SQIA
for iOS is not open source — see the web repository's
[LICENSE](https://github.com/serezhaOk/funny-steps/blob/main/LICENSE).
