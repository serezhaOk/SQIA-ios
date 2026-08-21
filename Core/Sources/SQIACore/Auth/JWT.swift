// Reading the app's own token, and checking an address before mailing it.
//
// Two small things that were living in the view layer where nothing could
// test them. Both are about formats rather than about screens, so they are
// here instead.

import Foundation

public enum JWT {
    /// The `sub` claim — who the token is for.
    ///
    /// The signature is not checked and does not need to be. This is the
    /// app reading its own token to fill in a field, and every row it could
    /// reach is guarded by what Postgres reads out of the same token
    /// server-side. A forged one would buy nothing but a wrong label.
    public static func subject(of token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload =
            String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["sub"] as? String
    }
}

public enum EmailAddress {
    /// The web's `/^\S+@\S+\.\S+$/`, and as much as a client should claim to
    /// know. Whether an address exists is a question only the mail can
    /// answer, and a stricter rule here would only turn away real people
    /// with unusual addresses.
    public static func looksValid(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return false }
        let halves = text.split(separator: "@", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return false }
        let local = halves[0]
        let domain = halves[1]
        return !local.isEmpty && domain.contains(".")
            && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}
