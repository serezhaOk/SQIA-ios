// GoTrue, the four ways in and the one way out.
//
// Port of the web app's src/auth.ts, minus the parts that were the client
// library's job. Three sign-in routes here rather than the web's two: Apple
// is a native id-token exchange, because Guideline 4.8 requires the button
// once Google is on the screen and because a phone can do it without a
// browser at all.
//
// Sign-out is local and only local — the web says so in a comment and means
// it: ending every session would sign the user's other devices out too,
// which is not what a menu item called "Log out" promises.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum AuthError: Error, Equatable {
    /// The server turned the sign-in down and said why.
    case rejected(String)
    /// Nothing reached the server. Nothing is known about the sign-in, and
    /// in particular a stored one is not known to be bad.
    case unreachable(String)
    /// The provider redirected back with an error instead of a code.
    case provider(String)

    public var message: String {
        switch self {
        case .rejected(let text), .unreachable(let text), .provider(let text):
            return text
        }
    }

    /// Whether the sign-in is still worth keeping. A request that never
    /// arrived says nothing about the token on disk.
    public var isNetwork: Bool {
        if case .unreachable = self { return true }
        return false
    }
}

public actor AuthClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Where the provider and the email link send the user back. A custom
    /// scheme rather than a universal link: Pages cannot serve an AASA file
    /// reliably, and a scheme needs no infrastructure that is not already
    /// there.
    public static let redirectURI = "sqia://auth"
    /// The static page that forwards a mailed link into the app. Mail
    /// clients will not follow a custom scheme, so the link has to land on
    /// the web first.
    public static let emailBridge = "https://sqia.serezhaok.com/ios"

    private let baseURL: URL
    private let key: String
    private let transport: Transport

    public init(
        baseURL: URL = SupabaseProjectStore.projectURL,
        key: String = SupabaseProjectStore.publishableKey,
        transport: @escaping Transport = AuthClient.urlSession
    ) {
        self.baseURL = baseURL
        self.key = key
        self.transport = transport
    }

    // ------------------------------------------------------------- Google --

    /// Where to send the browser. The verifier stays here; only its hash
    /// travels.
    public nonisolated func authorizeURL(provider: String, pkce: PKCE) -> URL? {
        var items = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: PKCE.method),
        ]
        items.append(URLQueryItem(name: "apikey", value: key))
        var components = URLComponents(
            url: baseURL.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = items
        return components?.url
    }

    /// Spend the code the browser came back with.
    public func exchange(code: String, verifier: String) async throws -> AuthSession {
        try await token(
            grant: "pkce",
            body: ["auth_code": code, "code_verifier": verifier])
    }

    // -------------------------------------------------------------- Apple --

    /// Native sign-in: Apple hands over an identity token and the nonce it
    /// was signed with, and GoTrue trades them for a session. No browser.
    public func signIn(appleIdentityToken: String, nonce: String?) async throws -> AuthSession {
        var body = ["provider": "apple", "id_token": appleIdentityToken]
        if let nonce { body["nonce"] = nonce }
        return try await token(grant: "id_token", body: body)
    }

    // -------------------------------------------------------------- email --

    /// Passwordless: the server mails a link back to the bridge page.
    public func sendMagicLink(to email: String) async throws {
        var request = post(
            "auth/v1/otp",
            query: [URLQueryItem(name: "redirect_to", value: Self.emailBridge)])
        request.httpBody = try JSONEncoder().encode(
            MagicLink(email: email, createUser: true))
        _ = try await send(request)
    }

    // ------------------------------------------------------------ keeping --

    public func refresh(_ refreshToken: String) async throws -> AuthSession {
        try await token(grant: "refresh_token", body: ["refresh_token": refreshToken])
    }

    /// Guideline 5.1.1(v). The row and the account go together: `projects`
    /// and `profiles` both cascade from `auth.users`, so the function only
    /// has to reach the user.
    public func deleteAccount(accessToken: String) async throws {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(request)
    }

    // ------------------------------------------------------------ the wire --

    private func token(grant: String, body: [String: String]) async throws -> AuthSession {
        var request = post(
            "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: grant)])
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            throw AuthError.rejected("The sign-in reply could not be read")
        }
    }

    private func post(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        var request = URLRequest(url: components?.url ?? baseURL)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            // This is the distinction the whole session policy turns on: a
            // request that never arrived is not a rejected sign-in.
            throw AuthError.unreachable(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AuthError.rejected(Self.complaint(response.statusCode, data))
        }
        return data
    }

    /// What the server said, in the order GoTrue says it. The web pulls the
    /// same three fields out of a failed `/token` reply, because the reason
    /// is the whole diagnosis — "Already Used" is two refreshes racing, and
    /// an expired session is a policy, and they need different words.
    static func complaint(_ status: Int, _ data: Data) -> String {
        if let body = try? JSONDecoder().decode(Complaint.self, from: data) {
            for text in [body.errorDescription, body.msg, body.message, body.error] {
                if let text, !text.isEmpty { return text }
            }
        }
        return "HTTP \(status)"
    }

    public static let urlSession: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.unreachable("Not an HTTP reply")
        }
        return (data, http)
    }

    // ------------------------------------------------------------ the body --

    private struct MagicLink: Encodable {
        let email: String
        let createUser: Bool

        enum CodingKeys: String, CodingKey {
            case email
            case createUser = "create_user"
        }
    }

    struct Complaint: Decodable {
        let error: String?
        let errorDescription: String?
        let msg: String?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
            case msg
            case message
        }
    }
}
