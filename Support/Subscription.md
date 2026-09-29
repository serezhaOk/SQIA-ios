# SQIA Plus — the subscription

One auto-renewable subscription, $1.99 a month. For now it opens the
mixer's second track and background playback; later features join it through `PlusFeature` in
`Core/Sources/SQIACore/Plus/Access.swift`, which is the one place that says
what Plus opens.

## How it works in the app

- `PlusStore` (SQIA/Plus) asks StoreKit 2 for the entitlement at launch and
  listens to `Transaction.updates` for the life of the app. Nothing goes to
  Supabase: the subscription belongs to the Apple ID, not the SQIA account,
  so signing out or into another account does not change it.
- The owner's account, `serezhaok@gmail.com` (`PlusStore.complimentary`),
  always has Plus without buying it; the profile's row says "Active".
  It is a check on the phone against the signed-in address, not a server
  grant, and it does not touch StoreKit.
- Without Plus the second track keeps its notes but is silent and locked.
  A project drawn with two tracks in the browser, or before a lapse, opens
  intact and plays both again the moment Plus comes back.
- Background playback: the profile's switch reads off without Plus and
  offers the paywall when pressed; subscribing from there turns it on. A
  switch left on when Plus lapses is ignored, so the app goes quiet when
  left, as it does on the free app.
- The paywall is the system's sheet with our content, from the Figma frame
  "Paywall" (Prototyping, node 426:7695): green ground and glows, vines at
  the bottom corners, the app icon in a wreath, Restore in the navigation
  bar and no close button. It
  shows the storefront's price and period, Restore, Privacy and Terms, and
  buys through `PlusStore.purchase()`. It opens from the locked panel in the
  mixer, the background playback switch, and Profile → SQIA Plus → Subscribe. Once
  subscribed, that row says Active and leads nowhere: cancelling is done in
  the system's Settings, not from the app.

## Testing locally

`SQIAUITests/SQIA.storekit` is the local App Store: SQIA Plus at 1.99 a
month. The scheme's Run action points at it, so a Run from Xcode sells from
it with no sandbox account. Debug → StoreKit → Manage Transactions refunds,
expires or deletes a purchase to see the track lock again.

The UI tests load the same file through `SKTestSession`, start every test
on the free app, and buy Plus once in `testSubscribingOpensTheSecondTrack`.

## App Store Connect, click by click

1. My Apps → SQIA → Monetization → Subscriptions → **Create** a group named
   `SQIA Plus`.
2. In it, create a subscription:
   - Reference name: `SQIA Plus Monthly`
   - Product ID: `com.serezhaok.sqia.plus.monthly` — exactly this; the app
     looks it up by this string.
   - Duration: 1 month. Price: $1.99 (tier for USD 1.99), then let Apple
     fill the other storefronts.
   - Family Sharing: off (matches the StoreKit file).
3. Localization (English): display name `SQIA Plus`, description
   `The second track, and everything Plus adds next.`
4. Group localization: display name `SQIA Plus`.
5. Review information: a screenshot of the paywall (the UI test
   `testTheSecondTrackAsksForPlus` attaches one) and a line of review notes.
6. The first subscription has to go to review **with an app version**: on
   the version page, under In-App Purchases and Subscriptions, add it before
   submitting.
7. Agreements, Tax, and Banking: the Paid Apps agreement must be active, or
   the product never loads outside Xcode.

## Before it ships

- [ ] Product created in App Store Connect with the ID above, status
      "Ready to Submit".
- [ ] Bought, restored and cancelled once on a real device with a sandbox
      account (Settings → Developer → Sandbox Apple Account).
- [ ] App Store description carries the SQIA PLUS paragraph with price,
      period and renewal terms (Support/AppStore.md).
- [ ] Review notes mention where the paywall is.
