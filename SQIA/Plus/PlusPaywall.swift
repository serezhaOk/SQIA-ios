// The paywall: what Plus opens, and the system's own subscribe button.
//
// The buying is StoreKit's `SubscriptionStoreView` rather than a button of
// ours. It prints the price, the period and the renewal terms in the
// storefront's own currency and wording, carries Restore and the policy
// links, and handles Ask to Buy and a failed card — everything App Review
// checks a subscription screen for, done the way the reviewer expects to
// see it. What is ours is the part above it, set like the rest of the app.
//
// The same deliberate departure as the sheets: modals follow the platform.

import SQIACore
import StoreKit
import SwiftUI

struct PlusPaywall: View {
    let plus: PlusStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: PlusStore.productIDs) {
            pitch
        }
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .storeButton(.visible, for: .policies)
        .subscriptionStorePolicyDestination(url: Links.terms, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: Links.privacy, for: .privacyPolicy)
        .containerBackground(Palette.sheet, for: .subscriptionStoreFullHeight)
        .tint(Palette.ui)
        .onInAppPurchaseCompletion { _, result in
            // Pending (Ask to Buy) and cancelled both leave the paywall up:
            // the first arrives later through `Transaction.updates`, the
            // second is somebody changing their mind.
            guard case .success(.success(let verification)) = result else { return }
            await plus.handle(verification)
            if plus.access.hasPlus { dismiss() }
        }
        .onChange(of: plus.access.hasPlus) { _, hasPlus in
            // A restore, or a purchase finished on another device while
            // this was open.
            if hasPlus { dismiss() }
        }
    }

    private var pitch: some View {
        VStack(spacing: 0) {
            SQIALogo()
                .frame(width: 88, height: 88)
            Text("SQIA Plus")
                .manrope(.bold, 30, tracking: -0.03)
                .foregroundStyle(Palette.ui)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
            Text("Open the second track.")
                .manrope(.medium, TextStyle.promptSize, tracking: -0.01)
                .foregroundStyle(Palette.ui.opacity(0.7))
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 16) {
                point(
                    "square.split.2x1",
                    "Two parts on one field",
                    "A pulse under a melody, drums under a pad — each drawn on its own track.")
                point(
                    "slider.horizontal.3",
                    "Its own sound, its own mute",
                    "Pick a voice for each track and mix them in the mixer.")
                point(
                    "sparkles",
                    "Everything that comes next",
                    "New tools join Plus as they are made, at no extra cost.")
            }
            .padding(.top, 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 12)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.ui)
                .frame(width: 28, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .manrope(.semibold, 16, tracking: -0.01)
                    .foregroundStyle(Palette.ui)
                Text(detail)
                    .manrope(.regular, 14, tracking: 0)
                    .foregroundStyle(Palette.ui.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            PlusPaywall(plus: PlusStore())
        }
}
