# Before the first submission — what is left

`AppStore.md` is what to paste into App Store Connect. This is the other
half: what has to be true before there is anything to paste it against.
Written from the state of the repository at `cc700e9` and the four open pull
requests.

---

## The one thing a reviewer can refuse over

**Guideline 5.1.1(i) — nothing works without an account.** `RootView` shows
`LandingView` and goes no further until there is a session, so the library,
the sequencer and the sound are all behind a sign-in. Apple allows required
registration only where the function of the app does not exist without an
account. Syncing with sqia.serezhaok.com genuinely is account-based, and
that argument holds; drawing on a grid and hearing it is not, and a reviewer
sees that in under a minute.

Three ways out, cheapest first:

- Supabase anonymous sign-in behind a "Try it" button; the anonymous user
  links to Apple or Google on the first real sign-in, and the rows are the
  same rows.
- A local guest project with no store behind it, offering the sign-in at the
  moment there is something worth saving.
- Neither, and an explanation in the review notes. It works some of the time.

---

## Blockers — none of them are code

- [ ] **The branches are not merged, and there is no `main`.** The trunk is
      `claude/ios-swift-port-gqpqmz`. PR #3 redesigns the sign-in screen and
      **removes the email route** (and adds ~8 MB of film and audio to the
      bundle); PR #5 rewrites the store metadata for search. Both edit
      `Support/AppStore.md` and conflict, and #5's "What's New" promises the
      email sign-in that #3 deletes. Decide whether the redesign ships in
      1.0, merge #3 then #5, then cut a `main` from the result. PR #1 is an
      old field experiment and PR #4 is editor settings.
- [ ] **Supabase.** `sqia://auth` and `https://sqia.serezhaok.com/ios` in the
      redirect allowlist; the Apple provider on with `com.serezhaok.sqia` in
      its authorized client IDs; `supabase functions deploy delete-account`.
      Until then every sign-in button reaches the server and is refused, and
      "Delete account" fails — which is 5.1.1(v), not a nicety.
- [ ] **Sign in with Apple on the App ID.** The entitlement is in
      `Support/SQIA.entitlements`; the capability still has to be enabled on
      `com.serezhaok.sqia` or the archive will not sign.
- [ ] **The site's URLs are live.** `sqia.serezhaok.com` (support and
      marketing), `/privacy.html` (a required field), `/terms.html` (the
      sign-in screen links to it). A dead privacy URL is an automatic
      rejection. `/ios` matters only if the email route survives — copy
      `web/ios/` into `funny-steps/public/ios/`.
- [ ] **A test account in the review notes.** The field in `AppStore.md` is
      deliberately empty and has to be filled. If #3 lands, Apple and Google
      are the only routes: the reviewer brings their own Apple ID, so what
      you must prepare is a working Google account with a few projects in it.
- [ ] **The device matrix.** The one part of M9 still open, and the part a
      Linux container cannot close: iPhone SE (the small stage and
      `fitCell`), ProMotion, iPad, a call arriving mid-playback, headphones
      pulled, the Bluetooth bloom delay. Archive in Release and confirm by
      eye that the tuning panel and the load meter are absent.

---

## iPad, which is one line of build settings

`TARGETED_DEVICE_FAMILY = "1,2"` claims a universal app, and there is not one
`horizontalSizeClass` or idiom branch anywhere in `SQIA/` — the screens are
vertical stacks that will simply stretch. It also costs a 13" screenshot set
in Connect, and from iPadOS 26 the system gives windows arbitrary sizes
regardless of `UISupportedInterfaceOrientations`.

Setting it to `1` ships 1.0 as an iPhone app: no iPad screenshots, no iPad
layout, and it still installs on an iPad in compatibility mode. Keeping "1,2"
means shooting it on a real iPad first.

---

## Not blockers, but they will come back as reviews

- **There is no offline.** `SupabaseProjectStore` is the only store; the file
  one was removed in M9. With no network the library is empty behind an error
  banner. Worse is the quiet case in `AppModel.createNew()`: when the row
  fails to write, the field still draws and sounds, and edits are silently
  not saved. Make that failure loud for 1.0; cache the projects in 1.1.
- **Nothing reports back.** No analytics and no crash reporting is a good
  line in the privacy questionnaire and a blind spot after release. Check
  that Xcode Organizer → Crashes opens for the account, and watch it for the
  first week.
- **"What is SQIA?" points at an Instagram reel.** When the reel goes, the
  link goes. A page you control outlives it.
- **The icon has no dark or tinted iOS 18 variants.** Optional, and cheap.
- **English only.** A Russian metadata locale in Connect buys more reach than
  anything else on this list.
- **VoiceOver.** Labelled on the sequencer, the tempo, the sheets and the
  library. The sign-in screen needs re-checking once #3 turns the wordmark
  into an image.

---

## Already done

Version `1.0` and build `1`, bundle id and team; the privacy manifest and the
questionnaire that agrees with it word for word; account deletion in the app
and the function behind it; Sign in with Apple first and no smaller than
Google; `ITSAppUsesNonExemptEncryption`; a 1024 icon with no alpha; portrait,
dark, the launch screen, four weights of Manrope with the OFL beside them;
the `.playback` session and everything that interrupts it; one third-party
component in the bundle and a `NOTICE.md` that says so; green CI across the
parity suite in both configurations, the app build and the simulator smoke
test; and not one TODO or stub in eighty-seven Swift files.

---

## The order

1. Decide 5.1.1(i) — it may change code, so it goes first.
2. Turn on the outside: Supabase, the App ID capability, the site's URLs.
3. Merge the branches, resolve `AppStore.md`, cut `main`.
4. Decide iPad.
5. Release archive; both sign-in routes and a real account deletion on a
   device; no debug panels.
6. Screenshots from a device — 6.9" (1320 × 2868), 6.5" (1242 × 2688), and
   13" (2064 × 2752) if iPad stays. Metal draws the glow; the simulator
   composites it differently.
7. A 15–30 second screen recording with sound, attached to the submission.
8. App Store Connect: the listing, Music / Entertainment, 4+, the privacy
   questionnaire, the test account.
9. TestFlight, on somebody else's phone. Bump the build number every upload.
10. Submit, and leave room for one round of notes.
