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

The first line carries the whole pitch on its own: not a musician's tool,
a tool for anyone. The rest builds toward the other half of the
positioning, that this is built to be lost in rather than gotten right.
The closing line is not part of that pitch — it is the Terms of Use and
Privacy Policy links App Review looks for, especially on an app that asks
for a sign-in. Apple only requires this in-description for apps selling
auto-renewable subscriptions (Guideline 3.1.2), which SQIA doesn't do, but
reviewers ask for it often enough on account-based free apps that it is
worth having rather than defending its absence.

> SQIA is a sequencer you draw on, and you don't need to know music to use
> it.
>
> There is a grid of dots. Touch one and it lights, and from then on it
> plays every time the pattern comes round. Drag across the grid and
> you've drawn a phrase: the notes nearest your finger come up brightest,
> the ones it passed through more faintly, so a gesture becomes a shape
> instead of a row of switches.
>
> Nothing here needs the right notes. The grid is already in a key, so
> whatever you touch belongs together in it. Once a pattern is running, it
> keeps evolving on its own: every hit rolls fresh, the patch wanders once
> a bar, and a replay never sounds quite the same twice.
>
> FIVE VOICES
> • REVERIE: a drifting pad
> • PLUCKED: a muted wooden pluck
> • RHODES: an electric piano with a slow stereo tremolo
> • ACID: a bassline whose filter opens on every note
> • MACHINE: a drum kit laid out across the grid, one instrument per column
>
> Switch voices mid-pattern and the same drawing turns into a different
> soundscape.
>
> Two tracks play at once. Mute one to redraw it while the other keeps
> going, then bring it back and hear how the two sit together.
>
> Every soundscape you shape is saved as you play, and it's the same
> project as on sqia.serezhaok.com: start it on your phone, keep going in
> a browser, or come back to it in an hour, or next week, exactly how you
> left it.
>
> SQIA doesn't need accounts beyond signing in, subscriptions, adverts, or
> analytics. It collects only the email you sign in with and the patterns
> you make.
>
> Terms of Use (EULA): sqia.serezhaok.com/terms.html
> Privacy Policy: sqia.serezhaok.com/privacy.html

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
> synthesised voices (REVERIE, PLUCKED, RHODES, ACID, MACHINE), a key and a
> tempo. Sign in with Apple or Google; projects sync with
> sqia.serezhaok.com.

## Support and marketing URLs

- Support URL: `https://sqia.serezhaok.com`
- Marketing URL: `https://sqia.serezhaok.com`
- Privacy Policy URL: `https://sqia.serezhaok.com/privacy.html`
- License Agreement (EULA): `https://sqia.serezhaok.com/terms.html` — this is
  SQIA's own terms, the same ones the sign-in screen links to, not Apple's
  Standard EULA. Set it under App Store Connect → App Information → License
  Agreement, in the **Custom License Agreement** field, or App Review sees
  no license on file and the description's link below points nowhere
  Apple recognises.

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

The app is portrait-only, so every shot is portrait. Take the in-app shots
on a device rather than the simulator: the field's glow is drawn in Metal
and the simulator's compositing is not identical.

### The template

The five store frames are laid out in Figma, in the `SQIA` page of the
Prototyping file, in the section **App Store — screenshots — SQIA
(sequencer)** — the same format as the granular app's set, one section
below it. The copy is set in each frame; the one thing left empty is the
slot the device screenshot goes in, labelled with which screen belongs
there. Drop the shot in as an image fill on the slot and the frame is
done.

Frame geometry, per screen — all five are identical bar the layout flip on
04:

| Part | Value |
| --- | --- |
| Canvas | 1284 × 2778, ground `#050505` |
| Copy block | x 95.38, y 149.03, width 1090.93 |
| Eyebrow → headline gap | 23.85 (25.83 on 01) |
| Headline → subtext gap | 45.70 |
| Screenshot slot | x 95.38, y 779.95, 1090.93 × 2370.64 |
| Slot corner / border | radius 143.07, 9.94px `rgba(255,255,255,0.2)` |

Type is Manrope throughout, matching the app's own:

| Role | Style | Size | Tracking | Leading |
| --- | --- | --- | --- | --- |
| Eyebrow | SemiBold, uppercase | 43.72 | +6.12 | 43.72 |
| Headline | ExtraBold | 117.24 (127.18 on 01) | −3.52 (−3.82) | 113.27 (121.22) |
| Subtext | Medium, white 60% | 43.72 | — | 59.61 |

Each screen carries one accent, used for the eyebrow and for the glow
behind it. They are not invented: they are lifted from the heat gradient
the field actually renders with, in `FieldTuning.current` — so the
marketing colour and the colour in the screenshot beneath it are the same
colour.

| Screen | Accent | From |
| --- | --- | --- |
| 01 hook | white 50%, no glow | — |
| 02 the field | `#FF70E2` | the gradient's hottest stop |
| 03 voices | `#FCCC33` | the gold stop |
| 04 mixer | `#F5851F` | the orange stop |
| 05 library | `#5C85DB` | the coolest stop |

### The five, in order

Order follows the story rather than the app's navigation: what it is, why
it can't go wrong, what it sounds like, what else is playing, where the
work lives.

**01 · hook** — no subtext, no glow; the neutral opener.
> TOUCH SEQUENCER
> **Touch the grid / and it starts / playing**
> *Slot: the sign-in screen — the film, the wordmark, the two buttons.*

**02 · the field**
> NO WRONG NOTES
> **The grid is / already in a key**
> Every hit rolled fresh. Never the same twice.
> *Slot: the sequencer, a full pattern lit, mid-bloom.*

**03 · voices**
> FIVE VOICES
> **A pad, a pluck, / a Rhodes, a 303, / a drum kit**
> Synthesised, not sampled. Nothing to download.
> *Slot: the sound sheet open over a pattern.*

**04 · mixer** — the layout flips: the screenshot bleeds off the top of the
frame and the copy sits under it, which breaks the rhythm of five identical
frames in the store's carousel.
> TWO TRACKS
> **Open the mixer, / both keep / playing**
> One flies into its panel, the other fades up beside it.
> *Slot: the mixer, both panels, names and mute chips.*

**05 · library**
> PHONE AND BROWSER
> **Start it here, / finish it in / a browser**
> The same project, saved as you draw it.
> *Slot: the library with three or four projects in it.*

### Exporting

The frames are drawn at 1284 × 2778 — the 6.7" device resolution, and the
same aspect ratio (0.4622) the 6.5" requirement wants, so the 6.5" upload
is a straight scale to 1242 × 2688 with nothing recomposed. The 6.9"
requirement (1320 × 2868, ratio 0.4603) is a hair narrower: scale to width
and let the extra height fall into the ground at the bottom, where the slot
already runs off the frame, rather than squashing the type.

---

## Version and build

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in the project's build
settings, currently `1.0` and `1`, which is what the first submission wants.
The build number has to increase on every upload, so bump it for each
TestFlight build rather than reusing one. Both numbers also ride along in
every feedback mail the account menu opens, so a build nobody bumped is a
report you cannot place.

## Before uploading

- [ ] Supabase: `sqia://auth` and the bridge page are in the redirect
      allowlist, the Apple provider is on with `com.serezhaok.sqia` in its
      authorized client IDs, and `delete-account` is deployed.
- [ ] Archive is a Release build. The load meter is `#if DEBUG` and must not
      appear. The field's tuning panel does ship now, by design: `Workbench`
      opens it to the signed-in owner and to nobody else, so check it is
      absent under the account you attach for review.
- [ ] Both sign-in routes tried on a real device, and account deletion
      tried once on an account you do not mind losing.
- [ ] The account menu's Leave feedback item opens mail with the subject and
      the build filled in. It goes to `serezhaok@gmail.com`, which is in the
      shipped binary and so is public: expect it to be scraped eventually,
      and move it to an address on the domain if that starts to matter.
