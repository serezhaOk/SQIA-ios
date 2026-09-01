# App Store Connect — what to paste where

Everything a submission asks for that is a piece of writing rather than a
click. Fill the account details in from your own records; nothing secret is
written down here.

---

## ASO strategy, in short

Apple's search index weighs three fields, in this order: **App Name**,
**Subtitle**, then the **Keywords** field. It builds its own index out of
every individual word across all three — it does not need a word repeated,
and a repeat just burns space that could carry a new word instead. So the
three are written to cover different ground rather than restate each other:

- **Name** carries the two highest-intent terms a music-sequencer app is
  found by: *sequencer* and *synth*.
- **Subtitle** carries the next tier: *drum machine* and *groovebox* — the
  other names people search this category by.
- **Keywords** picks up everything else: genre and technique terms
  (*ambient*, *generative*, *lofi*, *techno*), and the words people search
  next to those (*beatmaker*, *midi*, *jam*, *loop*, *arpeggiator*, *fm*,
  *bass*, *chill*, *groove*, *pad*, *keys*) — one word each, singular,
  un-plural, so Apple's own recombination does the work of matching
  "beat maker", "beats", "midi grid" and so on without spending characters
  on every variant.

This trades a little of the pure `SQIA` mark for search surface — the app
still opens with `SQIA` before the colon on every listing, and the
one-word description below still leads with the plain sequencer story
before any of this vocabulary shows up. If the trade isn't wanted, the
previous name (`SQIA`) and subtitle (`Built for sound accidents`) are a
straight drop-in; move their words into the Keywords field first so the
budget isn't spent twice.

## Name and subtitle

**Name** (30 characters, this one is 29): `SQIA: Music Sequencer & Synth`
**Subtitle** (30 characters, this one is 24): `Drum Machine & Groovebox`

## Promotional text (170 characters, changeable without review)

> Draw on the grid and it plays. Two tracks, five voices, a key and a tempo —
> nothing to set up, nothing to name, no wrong notes to avoid.

## Description

The first three lines show before "more" is tapped, so they carry the pitch
and the category words on their own; the rest is unchanged from before.

> A sequencer you draw on. Touch the grid and it plays — a generative music
> maker, drum machine and synth in one, built for sound accidents rather
> than right answers.
>
> There is a grid of dots. Touch one and it lights, and from then on it plays
> every time the pattern comes round. Drag across the grid and you have drawn
> a phrase — the notes nearest your finger come up brightest, the ones it
> passed through more faintly, so a gesture becomes a shape rather than a row
> of switches.
>
> Nothing here is quantised to a right answer. The grid is already in a key,
> so the notes belong together whichever ones you choose; every hit is rolled
> fresh, so a repeated pattern is never quite the same twice; and the patch
> itself wanders once a bar. It is built to be played with rather than
> programmed.
>
> FIVE VOICES
> • REVERIE — a drifting pad
> • KALIMBA — a plucked string
> • RHODES — an FM electric piano with a slow stereo tremolo
> • ACID — a 303-style bassline whose filter opens on every note
> • MACHINE — a drum kit laid out across the grid, one instrument per column
>
> Two tracks play at once. Open the mixer and the one you are playing flies
> into its own panel with the other beside it, each with its name and a mute
> button — tap either to go back to it full screen.
>
> Projects are saved as you draw them, and they are the same projects as on
> sqia.serezhaok.com. Start something on a phone and finish it in a browser,
> or the other way round.
>
> No accounts to configure beyond signing in, no subscriptions, no adverts,
> no analytics, and nothing collected but the email you sign in with and the
> patterns you make.

## Keywords (100 characters)

```
beatmaker,midi,jam,loop,ambient,generative,arpeggiator,lofi,techno,bass,chill,groove,pad,fm,keys
```

`sequencer`, `synth`, `music`, `drum`, `machine` and `groovebox` are already
carried by the Name and Subtitle above — repeating them here would spend
characters Apple's index already has for free.

## What's New (first submission)

App Store Connect requires this field on every version, including 1.0; it
just won't be shown until the first update. Worth having ready:

> First release. Draw a pattern on the grid and it plays — two tracks, five
> synthesised voices (REVERIE, KALIMBA, RHODES, ACID, MACHINE), a key and a
> tempo. Sign in with Apple or Google; projects sync with
> sqia.serezhaok.com.

## Support and marketing URLs

- Support URL: `https://sqia.serezhaok.com`
- Marketing URL: `https://sqia.serezhaok.com`
- Privacy Policy URL: `https://sqia.serezhaok.com/privacy.html`

## Category

Primary: **Music**. Secondary: **Entertainment**.

## Age rating

Everything "None". The app has no user-generated content that other people
can see, no web browsing, no chat, no purchases. Expected rating: 4+.

---

## App privacy questionnaire

The answers here have to agree with `SQIA/Resources/PrivacyInfo.xcprivacy`,
which is the machine-readable version of the same thing.

**Do you or your third-party partners collect data from this app?** Yes.

| Data type | Linked to identity | Used for tracking | Purpose |
| --- | --- | --- | --- |
| Contact info → Email address | Yes | No | App Functionality |
| User content → Other user content (the saved patterns) | Yes | No | App Functionality |

Nothing else. No identifiers, no usage data, no diagnostics, no location, no
contacts. There are no third-party SDKs in the app at all — the only bundled
component is a font.

**Tracking:** no. The app does not use `AppTrackingTransparency` because it
has nothing to ask about.

---

## Notes for the review team

> **Signing in.** The app needs an account because the work is the account.
> Touching the grid does not open a document that is later saved — it
> creates a project, on the first touch, and every edit after that is
> written to it as it happens. There is no save button and nothing to
> export: the project is a row in the database, it opens in a browser at
> sqia.serezhaok.com against the same account, and without one there would
> be nowhere to put the first note and nothing to come back to. There are
> two ways in and both work on a device: Sign in with Apple, or Google. A
> test account is attached below.
>
> **Sign in with Apple** is offered first and is no less prominent than
> Google, as Guideline 4.8 requires. It is a native sign-in — no browser is
> opened.
>
> **Deleting an account.** From the library screen, tap the face icon at the
> top right → Delete account. It removes the account and every project with
> it, immediately and without contacting support (Guideline 5.1.1(v)).
>
> **Sound.** SQIA is a music app, so it plays through the silent switch —
> the audio session uses the `.playback` category. Please try it with the
> volume up: the screen alone does not show what the app is.
>
> The sign-in screen is the exception. Its film loop is muted and the quiet
> bed under it is `.ambient`, so it goes silent with the ring switch and
> never interrupts whatever the phone was already playing.
>
> **How to see it working in about a minute.** Sign in → tap
> "+ Create first project" → drag a finger across the grid of dots. It starts
> playing at once. The two dots at the top of the screen open the mixer,
> where "Back to projects" returns to the library.

**Test account:** _fill in the account to sign in with before submitting._

**Attachment:** a short screen recording helps here, because a still
screenshot of a grid of dots does not convey that it makes sound.

---

## Screenshots

Required sizes: 6.9" (1320 × 2868) and 6.5" (1242 × 2688). No iPad set is
needed: `TARGETED_DEVICE_FAMILY` is `1`, so 1.0 is listed as an iPhone app
and installs on an iPad in compatibility mode.

Five that tell the story in order:

1. The sign-in screen — the film, the wordmark, the two buttons.
2. The library with three or four projects in it.
3. The sequencer with a full pattern lit, mid-bloom.
4. The mixer open, both panels showing, names and mute chips visible.
5. The sound sheet open over a pattern.

The app is portrait-only, so every shot is portrait. Take them on a device
rather than the simulator: the field's glow is drawn in Metal and the
simulator's compositing is not identical.

---

## Version and build

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in the project's build
settings, currently `0.1.0` and `1`. Set the marketing version to `1.0` for
the first submission; the build number has to increase on every upload, so
bump it for each TestFlight build rather than reusing one.

## Before uploading

- [ ] Supabase: `sqia://auth` and the bridge page are in the redirect
      allowlist, the Apple provider is on with `com.serezhaok.sqia` in its
      authorized client IDs, and `delete-account` is deployed.
- [ ] Archive is a Release build — the tuning panel and the load meter are
      `#if DEBUG` and must not appear.
- [ ] Both sign-in routes tried on a real device, and account deletion
      tried once on an account you do not mind losing.
