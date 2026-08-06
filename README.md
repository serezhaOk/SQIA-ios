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
| M2 — audio foundation | clock done; the engine is next |
| M3–M10 | see [PLAN.md](PLAN.md) |

What runs today: an app shell that draws the dot field through the real dome
geometry, in the real palette and typeface. No audio and no touch yet — those
arrive with the sequencer.

## Layout

```
Core/          SQIACore — pitch mapping, the note matrix, dome geometry,
               the lookahead clock, the project snapshot format. Pure Swift,
               no Apple frameworks, so it builds and tests on any platform.
SQIA/          The app. Xcode syncs this folder, so new files need no
               project edits.
Support/       Info.plist
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
fonts in `SQIA/Resources/Fonts/`.

## Copyright

Copyright © 2026 Sergei Diuzhev. All rights reserved. Like the web app, SQIA
for iOS is not open source — see the web repository's
[LICENSE](https://github.com/serezhaOk/funny-steps/blob/main/LICENSE).
