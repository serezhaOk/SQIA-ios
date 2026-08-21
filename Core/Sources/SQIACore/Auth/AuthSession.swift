// A signed-in user, as GoTrue hands it over and as the Keychain keeps it.
//
// The field names are the server's, so the reply decodes straight into this
// and the same bytes go back into storage. The one thing computed here is
// whether it is worth using: an access token lives an hour, and a phone that
// has been asleep for two days holds one that is long past.

import Foundation

public struct AuthUser: Codable, Sendable, Equatable {
    public let id: String
    public let email: String?

    public init(id: String, email: String?) {
        self.id = id
        self.email = email
    }
}

public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    /// Seconds since the epoch, which is what the server sends.
    public var expiresAt: Double
    public var user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case user
    }

    public init(accessToken: String, refreshToken: String, expiresAt: Double, user: AuthUser) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.user = user
    }

    /// GoTrue sends `expires_at` on most replies and only `expires_in` on
    /// some. Taking either means one shape to hold rather than two.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try box.decode(String.self, forKey: .accessToken)
        refreshToken = try box.decode(String.self, forKey: .refreshToken)
        user = try box.decode(AuthUser.self, forKey: .user)
        if let at = try box.decodeIfPresent(Double.self, forKey: .expiresAt) {
            expiresAt = at
        } else {
            let seconds = try box.decodeIfPresent(Double.self, forKey: .expiresIn) ?? 3600
            expiresAt = Date().timeIntervalSince1970 + seconds
        }
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(accessToken, forKey: .accessToken)
        try box.encode(refreshToken, forKey: .refreshToken)
        try box.encode(expiresAt, forKey: .expiresAt)
        try box.encode(user, forKey: .user)
    }

    /// A minute of margin, so a token is not spent on a request that will
    /// arrive after it has died.
    public static let margin: Double = 60

    public func isFresh(at now: Date = Date()) -> Bool {
        expiresAt - now.timeIntervalSince1970 > Self.margin
    }

    public func secondsUntilRefresh(at now: Date = Date()) -> Double {
        max(0, expiresAt - Self.margin - now.timeIntervalSince1970)
    }
}
