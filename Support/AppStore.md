# App Store Connect — what to paste where

Everything a submission asks for that is a piece of writing rather than a
click. Fill the account details in from your own records; nothing secret is
written down here.

---

## Name and subtitle

**Name:** `SQIA`
**Subtitle** (30 characters, and this one is 26): `Built for sound accidents`

The subtitle is the web app's tagline, unchanged. It fits, and it is the one
line that already describes the thing.

## Promotional text (170 characters, changeable without review)

> Draw on the grid and it plays. Two tracks, five voices, a key and a tempo —
> nothing to set up, nothing to name, no wrong notes to avoid.

## Description

> SQIA is a sequencer you draw on.
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
> Five voices. REVERIE is a pad that drifts. KALIMBA is a plucked string.
> RHODES is an electric piano with a slow stereo tremolo. ACID is a bassline
> whose filter opens on every note. MACHINE is a drum kit laid out across the
> grid, one instrument per column.
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
sequencer,synth,drum machine,beat,music maker,groovebox,ambient,generative,midi grid,jam
```

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

> **Signing in.** The app needs an account, because a project is stored
> against one and the same project opens in the browser at
> sqia.serezhaok.com. There are three ways in and all three work on a device:
> Sign in with Apple, Google, or an email link. A test account is attached
> below.
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
> **How to see it working in about a minute.** Sign in → tap
> "+ Create first project" → drag a finger across the grid of dots. It starts
> playing at once. The two dots at the top of the screen open the mixer,
> where "Back to projects" returns to the library.

**Test account:** _fill in the email and password (or the address the sign-in
link should go to) before submitting._

**Attachment:** a short screen recording helps here, because a still
screenshot of a grid of dots does not convey that it makes sound.

---

## Screenshots

Required sizes: 6.9" (1320 × 2868) and 6.5" (1242 × 2688). iPad is optional
unless the app is listed as iPad-compatible — it is, so 13" (2064 × 2752)
is needed too.

Five that tell the story in order:

1. The sign-in screen — the mark, the wordmark, the tagline.
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
- [ ] `sqia.serezhaok.com/ios` is live, or the email sign-in link goes
      nowhere.
- [ ] Archive is a Release build — the tuning panel and the load meter are
      `#if DEBUG` and must not appear.
- [ ] All three sign-in routes tried on a real device, and account deletion
      tried once on an account you do not mind losing.
