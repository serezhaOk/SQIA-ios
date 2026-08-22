# Notices

SQIA for iOS is copyright (c) 2026 Sergei Diuzhev. All rights reserved.

The following third-party components are used under their own licences. None
of them is covered by SQIA's licence, and nothing in SQIA's licence restricts
your rights to them.

## Bundled into the application

| Component | Licence | Used for |
| --- | --- | --- |
| [Manrope](https://github.com/sharanda/manrope) | SIL Open Font License 1.1 | Every piece of text in the app |

Four static instances ship — Regular, Medium, SemiBold, Bold — cut from the
variable font by `tools/make-fonts.py`. The licence text travels with them as
`SQIA/Resources/Fonts/Manrope-OFL.txt`.

That is the whole list, which is worth saying out loud. The web version
bundles Tone.js for its sound and supabase-js for its backend; this app has
neither. Every voice, filter, envelope and reverb is written out in
`Core/Sources/SQIACore`, and the two things it asks of Supabase — rows and
sign-ins — are plain HTTPS requests. Icons are SF Symbols, which are Apple's
and stay Apple's: they are drawn by the system rather than shipped, and the
licence permits exactly that use.

## Used to build and test, not shipped

| Component | Licence |
| --- | --- |
| [swift-testing](https://github.com/swiftlang/swift-testing) | Apache License 2.0 |
| [Swift toolchain](https://github.com/swiftlang/swift) | Apache License 2.0 |

## Reference material

The synthesis is a port, not a copy: it reproduces the behaviour of
[Tone.js](https://github.com/Tonejs/Tone.js) (MIT) and of the Web Audio
implementations in [Chromium](https://www.chromium.org/) (BSD-3-Clause), both
read from their published sources to get the arithmetic right. No code from
either is present here.
