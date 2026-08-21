// What came back through `sqia://auth`.
//
// Three things can arrive on that URL and they do not agree on where to put
// themselves. An authorisation code comes in the query. A mailed link that
// went through the bridge page can arrive as a code or as a whole session in
// the fragment, depending on which flow issued it. And a provider that
// refused puts its reason in the query, the fragment, or both.
//
// So this reads all of it, the same way the web's `consumeAuthError` does,
// and says which of the three it was.

import Foundation

public enum AuthCallback: Sendable, Equatable {
    /// An authorisation code, to be spent with the verifier that made the
    /// challenge it was issued against.
    case code(String)
    /// A session handed over whole, which is what an implicit-flow link does.
    case session(accessToken: String, refreshToken: String, expiresIn: Double)
    /// The provider said no, and this is what it said.
    case failure(String)
    /// Not a sign-in URL at all.
    case none

    public static func read(_ url: URL) -> AuthCallback {
        let fields = parameters(of: url)

        // Failure first: a URL carrying both an error and a stale code is
        // still a failure, and reading the code would spend it for nothing.
        let description = fields["error_description"] ?? fields["error"]
        if let description, !description.isEmpty {
            let text = description.removingPercentEncoding ?? description
            if let code = fields["error_code"], !code.isEmpty {
                return .failure("\(text) (\(code))")
            }
            return .failure(text)
        }

        if let code = fields["code"], !code.isEmpty {
            return .code(code)
        }

        if let access = fields["access_token"], !access.isEmpty,
            let refresh = fields["refresh_token"], !refresh.isEmpty
        {
            let seconds = fields["expires_in"].flatMap(Double.init) ?? 3600
            return .session(accessToken: access, refreshToken: refresh, expiresIn: seconds)
        }

        return .none
    }

    /// Query and fragment together. A key in both is the query's, which is
    /// the order a provider that sets both intends.
    static func parameters(of url: URL) -> [String: String] {
        var fields: [String: String] = [:]
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for pair in (components?.fragment).map(split) ?? [:] {
            fields[pair.key] = pair.value
        }
        for item in components?.queryItems ?? [] {
            if let value = item.value, !value.isEmpty { fields[item.name] = value }
        }
        return fields
    }

    /// A fragment is `a=1&b=2`, which URLComponents will not break up.
    private static func split(_ fragment: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let halves = pair.split(separator: "=", maxSplits: 1)
            guard halves.count == 2 else { continue }
            let key = String(halves[0])
            let value = String(halves[1]).replacingOccurrences(of: "+", with: " ")
            fields[key] = value.removingPercentEncoding ?? value
        }
        return fields
    }
}
