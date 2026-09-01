# Before the first submission — what is left

`AppStore.md` is what to paste into App Store Connect. This is the other
half: what has to be true before there is anything to paste it against.

Four questions this file used to ask have been answered by the owner, and
their answers are recorded under "Decisions taken" at the end. What is left
above is work.

---

## The blockers

Everything here is done in somebody else's dashboard, on a device, or with a
card in hand. None of it is code.

- [ ] **Supabase** — three switches, step by step below.
- [ ] **Sign in with Apple on the App ID** — Apple Developer, below.
- [ ] **The site's URLs answer** — below.
- [ ] **A test account for the reviewer.** The field in `AppStore.md` is
      deliberately empty. Apple and Google are the only two ways in, so the
      reviewer brings their own Apple ID and what you must prepare is a
      **Google account with two or three projects already in it**, signed in
      once on a device to prove it works. Write it into the "Test account"
      line before submitting.
- [ ] **The device matrix.** The one part of M9 still open, and the part a
      Linux container cannot close: an iPhone SE (the small stage and
      `fitCell`), a ProMotion phone, a call arriving mid-playback, headphones
      pulled out, the bloom delay over Bluetooth.
- [ ] **A Release archive, checked by eye.** The tuning panel and the load
      meter are behind `#if DEBUG`. Confirm they are absent from the archive
      rather than trusting that they are.

---

## Supabase, click by click

Open the dashboard for the project `iayngkirvbjlsmgtymnl` — the id in
`SupabaseProjectStore.projectURL`, so it is the right one by definition.

**1. The redirect allowlist.** Authentication → URL Configuration → Redirect
URLs → Add URL. Add, exactly:

```
sqia://auth
https://sqia.serezhaok.com/ios
```

The first is where Google's browser hands the app its code; without it
Google's sign-in ends on an error page. The second is the bridge for the
email link, and it matters only while the email route exists — harmless to
add either way.

**2. The Apple provider.** Authentication → Providers → Apple → Enable.
It asks for two things:

- **Client IDs** — put `com.serezhaok.sqia` in. This is the whole check for
  a native sign-in: GoTrue verifies that the identity token Apple signed was
  issued for this bundle id. Nothing else in this section is used by the app.
- **Secret Key**, built from a Service ID plus a `.p8` key from Apple
  Developer → Keys. Supabase's own form on that screen generates it from the
  four fields (Team ID `U6DN6CYY76`, Key ID, Service ID, the key's contents).
  Only the web app needs it; a native `signInWithIdToken` does not. Fill it
  in anyway so the web and the phone are the same account system.

**3. The delete-account function.** From the repository root, with the
Supabase CLI logged in:

```sh
supabase link --project-ref iayngkirvbjlsmgtymnl
supabase functions deploy delete-account
```

It needs no secrets: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are
already in the function environment. Verify it afterwards — sign in on a
device with an account you do not mind losing, tap the face icon → Delete
account, and confirm the row is gone from `auth.users`. Guideline 5.1.1(v)
is checked by a reviewer who will do exactly this.

---

## Apple Developer, click by click

Certificates, Identifiers & Profiles → Identifiers → `com.serezhaok.sqia` →
Capabilities → tick **Sign in with Apple** → Save. The entitlement is already
in `Support/SQIA.entitlements`; without the capability on the identifier the
archive fails to sign, and it fails at the end of a fifteen-minute build.

While there: Keys → + → tick Sign in with Apple → download the `.p8` once
(Apple will not offer it twice) — that is the key Supabase's Apple provider
asks for above.

---

## The site's URLs

Open each one in a browser and confirm it answers with a page, not a 404:

- `https://sqia.serezhaok.com` — the Support URL and the Marketing URL.
- `https://sqia.serezhaok.com/privacy.html` — a required field on the
  listing, and a dead one is an automatic rejection.
- `https://sqia.serezhaok.com/terms.html` — the sign-in screen links to it.
- `https://sqia.serezhaok.com/ios` — only while the email route exists. Copy
  `web/ios/` into `funny-steps/public/ios/` to serve it.

---

## Decisions taken

**Signing in is required, and stays required.** Touching the grid does not
open a document that is saved later — it creates a project on the first
touch, and every edit after that is written to it as it happens. There is no
save button and nothing to export, so without an account there would be
nowhere to put the first note. The review notes in `AppStore.md` say this in
those words, which is the mitigation: Guideline 5.1.1(i) allows required
registration where the function is account-based, and here the work *is* the
account.

**iPhone only for 1.0.** `TARGETED_DEVICE_FAMILY` is `1`. No iPad layout, no
iPad screenshots, and an iPad still runs it in compatibility mode. The
`~ipad` orientation key is gone from `Info.plist` with it.

**Online only.** No offline cache and no deferred writes. With no network the
library is empty behind an error banner, which is what the web does too.

**One trunk.** `main` is the branch to cut releases from; the sign-in
redesign, the store metadata and the editor settings are merged into it, and
the branches they came from can be deleted.

---

## Already done

Version `1.0` and build `1`, bundle id and team; the privacy manifest and the
questionnaire that agrees with it word for word; account deletion in the app
and the function behind it; Sign in with Apple first and no smaller than
Google; `ITSAppUsesNonExemptEncryption`; a 1024 icon with no alpha; portrait,
dark, the launch screen, four weights of Manrope with the OFL beside them;
the `.playback` session and everything that interrupts it, and the `.ambient`
bed under the sign-in film that goes quiet with the ring switch; one
third-party component in the bundle and a `NOTICE.md` that says so; green CI
across the parity suite in both configurations, the app build and the
simulator smoke test; and not one TODO or stub in the Swift sources.

---

## The order

1. Supabase, the App ID capability, the site's URLs — the three above.
2. Prepare the reviewer's Google account and put it in `AppStore.md`.
3. A Release archive; both sign-in routes and a real account deletion on a
   device; no debug panels.
4. Screenshots from a device — 6.9" (1320 × 2868) and 6.5" (1242 × 2688).
   Metal draws the glow; the simulator composites it differently.
5. A 15–30 second screen recording with sound, attached to the submission.
6. App Store Connect: the listing, Music / Entertainment, 4+, the privacy
   questionnaire, the test account.
7. TestFlight, on somebody else's phone. Bump the build number every upload.
8. Submit, and leave room for one round of notes.
