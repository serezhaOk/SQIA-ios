// Holding on to the sign-in.
//
// The hard part of auth is not signing in, it is not signing out by
// accident. A phone spends its life going in and out of coverage, and a
// refresh that never reached the server says nothing at all about whether
// the token on disk is still good. Treating that as a signed-out state is
// how an app throws somebody back to a sign-in screen on a train, with no
// explanation, having lost nothing but its nerve.
//
// So the whole of this turns on one distinction, which `AuthError` carries:
// rejected means the server looked and said no, and the sign-in is over;
// unreachable means nobody looked, and the sign-in is still whatever it was.
// A rejection also gets written down, because otherwise the user just meets
// the sign-in screen again with no idea why.

import Foundation

/// Where the session lives between launches. The app puts it in the
/// Keychain; a test puts it in a dictionary.
public protocol SessionStorage: Sendable {
    func load() async -> AuthSession?
    func save(_ session: AuthSession) async
    func clear() async

    /// Why the last session ended, if it ended on its own.
    func loadIssue() async -> AuthIssue?
    func save(issue: AuthIssue) async
    func clearIssue() async
}

/// A note about a sign-in that ended without the user asking.
public struct AuthIssue: Codable, Sendable, Equatable {
    public let reason: String
    /// Seconds since the epoch.
    public let at: Double

    public init(reason: String, at: Double) {
        self.reason = reason
        self.at = at
    }

    /// Older than a day is not about this visit any more.
    public static let maximumAge: Double = 24 * 60 * 60

    public func describe(now: Date) -> String? {
        let elapsed = now.timeIntervalSince1970 - at
        guard elapsed <= Self.maximumAge else { return nil }
        let minutes = Int((elapsed / 60).rounded())
        let when = minutes < 2 ? "just now" : "\(minutes) min ago"
        return "Session ended \(when): \(reason)"
    }
}

public actor SessionKeeper {
    /// After a refresh that could not reach the server, try again on this
    /// schedule — and again whenever the network comes back.
    public static let retryDelays: [Duration] = [.seconds(5), .seconds(20)]

    public typealias Wait = @Sendable (Duration) async -> Void

    private let client: AuthClient
    private let storage: any SessionStorage
    private let now: @Sendable () -> Date
    private let waiting: Wait

    private(set) var session: AuthSession?
    /// True while `signOut` is running, so its own clearing is not written
    /// down as a session that ended on its own.
    private var signingOut = false
    private var retrying = false

    public init(
        client: AuthClient,
        storage: any SessionStorage,
        now: @escaping @Sendable () -> Date = { Date() },
        waiting: @escaping Wait = { try? await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.storage = storage
        self.now = now
        self.waiting = waiting
    }

    public var current: AuthSession? { session }
    public var isSignedIn: Bool { session != nil }

    /// Is a sign-in cached on this device? Straight from storage, no network
    /// — so a returning user lands in the library instead of watching the
    /// sign-in screen while a token is confirmed.
    public func peek() async -> Bool {
        await storage.load() != nil
    }

    /// Read what is stored and make it usable. Returns whether the app is
    /// signed in as far as anything can tell right now.
    @discardableResult
    public func restore() async -> Bool {
        guard let stored = await storage.load() else { return false }
        session = stored
        guard !stored.isFresh(at: now()) else { return true }

        do {
            try await renew(stored.refreshToken)
            return true
        } catch let error as AuthError where error.isNetwork {
            // Nothing says the stored sign-in is bad. Hold it, and try
            // again rather than announcing a signed-out state.
            retrySoon()
            return true
        } catch {
            await end(because: message(of: error))
            return false
        }
    }

    /// A token good enough to send. Refreshes if the one held is spent.
    ///
    /// Offline, this hands back the token it has: the request it is for will
    /// fail anyway, and failing a request is a great deal better than
    /// deciding the user is signed out because a train went into a tunnel.
    public func accessToken() async -> String? {
        guard let held = session else { return nil }
        if held.isFresh(at: now()) { return held.accessToken }
        do {
            try await renew(held.refreshToken)
            return session?.accessToken
        } catch let error as AuthError where error.isNetwork {
            retrySoon()
            return held.accessToken
        } catch {
            await end(because: message(of: error))
            return nil
        }
    }

    /// What the project store needs: a token and the user it belongs to.
    public func supabaseSession() async -> SupabaseSession? {
        guard let token = await accessToken(), let user = session?.user.id else { return nil }
        return SupabaseSession(accessToken: token, userId: user)
    }

    // ------------------------------------------------------------ signing --

    public func adopt(_ new: AuthSession) async {
        session = new
        await storage.save(new)
        await storage.clearIssue()
    }

    public func signIn(code: String, verifier: String) async throws {
        await adopt(try await client.exchange(code: code, verifier: verifier))
    }

    public func signIn(appleIdentityToken: String, nonce: String?) async throws {
        await adopt(
            try await client.signIn(appleIdentityToken: appleIdentityToken, nonce: nonce))
    }

    /// Local only. Ending every session would sign the user's other devices
    /// out too, which is not what the menu item says.
    public func signOut() async {
        signingOut = true
        session = nil
        await storage.clear()
        await storage.clearIssue()
        signingOut = false
    }

    /// Guideline 5.1.1(v). The rows go with the account: `projects` and
    /// `profiles` both cascade from `auth.users`.
    public func deleteAccount() async throws {
        guard let token = await accessToken() else { throw AuthError.rejected("Not signed in") }
        try await client.deleteAccount(accessToken: token)
        await signOut()
    }

    /// Why the last session ended, if it ended on its own. Reads once.
    public func takeIssue() async -> String? {
        guard let issue = await storage.loadIssue() else { return nil }
        await storage.clearIssue()
        return issue.describe(now: now())
    }

    // ------------------------------------------------------------ the work --

    private func renew(_ refreshToken: String) async throws {
        let fresh = try await client.refresh(refreshToken)
        session = fresh
        await storage.save(fresh)
        await storage.clearIssue()
    }

    /// Come back to it. Called after a refresh that never reached the
    /// server, and by the app when the network returns.
    public func retrySoon() {
        guard !retrying else { return }
        retrying = true
        Task { await self.runRetries() }
    }

    private func runRetries() async {
        defer { retrying = false }
        for delay in Self.retryDelays {
            await waiting(delay)
            guard let held = session, !held.isFresh(at: now()) else { return }
            do {
                try await renew(held.refreshToken)
                return
            } catch let error as AuthError where error.isNetwork {
                continue
            } catch {
                await end(because: message(of: error))
                return
            }
        }
    }

    private func end(because reason: String) async {
        session = nil
        await storage.clear()
        if !signingOut {
            await storage.save(issue: AuthIssue(reason: reason, at: now().timeIntervalSince1970))
        }
    }

    private func message(of error: Error) -> String {
        (error as? AuthError)?.message ?? "this device's sign-in was rejected"
    }
}

/// A session in a dictionary. For tests, and for a preview that must not
/// touch the Keychain.
public actor InMemorySessionStorage: SessionStorage {
    private var stored: AuthSession?
    private var issue: AuthIssue?

    public init(session: AuthSession? = nil, issue: AuthIssue? = nil) {
        self.stored = session
        self.issue = issue
    }

    public func load() async -> AuthSession? { stored }
    public func save(_ session: AuthSession) async { stored = session }
    public func clear() async { stored = nil }
    public func loadIssue() async -> AuthIssue? { issue }
    public func save(issue: AuthIssue) async { self.issue = issue }
    public func clearIssue() async { issue = nil }
}
