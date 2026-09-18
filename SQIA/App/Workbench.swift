// Who gets the tuning panels.
//
// The field is still being decided and can only be decided by looking at it
// on a phone — not in the simulator, and not on a screenshot. So the panel
// has to exist in a build that goes through TestFlight, and it must not be
// something a stranger can find in the sound sheet.
//
// The signed-in address settles it, and it settles it in every build. A
// debug build used to carry the panel outright, which put it in front of
// whichever account happened to be signed in on the simulator — so the one
// question now is who is signed in, on a phone or on a desk.
//
// This is not a permission and it is not security: the code ships in the
// binary either way, and anyone who can sign in as the owner can reach it.
// It is a door that is only marked for the person who uses it.

import SQIACore
import SwiftUI

enum Workbench {
    /// The account the tuning is done from.
    static let owner = "serezhaok@gmail.com"

    static func isOpen(to email: String?) -> Bool {
        guard let email else { return false }
        return email.trimmingCharacters(in: .whitespaces).lowercased() == owner
    }
}

private struct AccountEmailKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The signed-in address, set once at the root. Nothing on screen is
    /// drawn from it — it is here so a screen deep in the sequencer can ask
    /// `Workbench` whether the workbench is open without every view between
    /// here and there carrying an address it has no use for.
    var accountEmail: String? {
        get { self[AccountEmailKey.self] }
        set { self[AccountEmailKey.self] = newValue }
    }
}
