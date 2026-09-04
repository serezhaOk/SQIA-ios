// Signing in, and — the part that actually matters — not signing out by
// accident.

import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@testable import SQIACore

@Suite("SHA-256")
struct SHA256Tests {
    @Test("The published vectors")
    func vectors() {
        // FIPS 180-4 examples, and the empty string, which is the one a
        // padding mistake gets wrong.
        #expect(
            SHA256.digest("").hex
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(
            SHA256.digest("abc").hex
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(
            SHA256.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").hex
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    @Test("A message that lands on the block boundary")
    func boundaries() {
        // 55, 56 and 64 bytes: one block, one that spills into a second
        // only because of the length field, and one that fills a block
        // exactly. Every off-by-one in the padding shows up in these.
        #expect(
            SHA256.digest(String(repeating: "a", count: 55)).hex
                == "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318")
        #expect(
            SHA256.digest(String(repeating: "a", count: 56)).hex
                == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a")
        #expect(
            SHA256.digest(String(repeating: "a", count: 64)).hex
                == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")
        #expect(
            SHA256.digest(String(repeating: "a", count: 1000)).hex
                == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    @Test("base64url leaves nothing a URL would have to escape")
    func urlSafe() {
        let text = SHA256.digest("abc").base64URL
        #expect(!text.contains("+"))
        #expect(!text.contains("/"))
        #expect(!text.contains("="))
        #expect(text.count == 43)
    }
}

@Suite("PKCE")
struct PKCETests {
    @Test("The worked example from RFC 7636")
    func specExample() {
        // §4.4. If this matches, the verifier, the digest and the encoding
        // are all right together — which is more than any of them alone.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("A generated verifier is the length and alphabet the spec allows")
    func generated() {
        let pkce = PKCE(using: Mulberry32(seed: 7))
        #expect(pkce.verifier.count == 43)
        #expect((43...128).contains(pkce.verifier.count))
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(pkce.verifier.allSatisfy(allowed.contains))
        #expect(pkce.challenge.count == 43)
    }

    @Test("Two goes do not produce the same verifier")
    func notRepeating() {
        let random = SystemRandomSource()
        let first = PKCE(using: random)
        let second = PKCE(using: random)
        #expect(first.verifier != second.verifier)
    }
}

@Suite("The callback URL")
struct AuthCallbackTests {
    @Test("A code in the query")
    func codeInQuery() {
        #expect(
            AuthCallback.read(URL(string: "sqia://auth?code=abc123")!) == .code("abc123"))
    }

    @Test("A whole session in the fragment, which a mailed link can be")
    func sessionInFragment() {
        let url = URL(
            string: "sqia://auth#access_token=at&refresh_token=rt&expires_in=3600&token_type=bearer"
        )!
        #expect(
            AuthCallback.read(url)
                == .session(accessToken: "at", refreshToken: "rt", expiresIn: 3600))
    }

    @Test("A provider that refused says so, wherever it put the reason")
    func failures() {
        let inQuery = URL(
            string: "sqia://auth?error=access_denied&error_description=User%20cancelled")!
        #expect(AuthCallback.read(inQuery) == .failure("User cancelled"))

        let inFragment = URL(
            string: "sqia://auth#error_description=Email+link+is+invalid&error_code=otp_expired")!
        #expect(
            AuthCallback.read(inFragment) == .failure("Email link is invalid (otp_expired)"))

        // Bare `error` with nothing to elaborate.
        #expect(AuthCallback.read(URL(string: "sqia://auth?error=server_error")!)
                == .failure("server_error"))
    }

    @Test("An error alongside a code is still an error")
    func failureWins() {
        // Spending the code would burn it for nothing, and the reason is
        // what the user needs to see.
        let url = URL(string: "sqia://auth?code=abc&error=access_denied")!
        #expect(AuthCallback.read(url) == .failure("access_denied"))
    }

    @Test("Anything else is not a sign-in")
    func notOurs() {
        #expect(AuthCallback.read(URL(string: "sqia://auth")!) == .none)
        #expect(AuthCallback.read(URL(string: "https://example.com/")!) == .none)
        // Half a session is not a session.
        #expect(AuthCallback.read(URL(string: "sqia://auth#access_token=at")!) == .none)
    }
}

// ------------------------------------------------------------------ client --

private func reply(_ status: Int, _ body: String) -> AuthClient.Transport {
    { request in
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private let sessionJSON = """
    {"access_token":"at-1","refresh_token":"rt-1","expires_in":3600,\
    "token_type":"bearer","user":{"id":"user-1","email":"a@b.co"}}
    """

/// Every request the client made.
private actor Recorder {
    private(set) var requests: [URLRequest] = []
    private let status: Int
    private let body: String

    init(status: Int = 200, body: String = sessionJSON) {
        self.status = status
        self.body = body
    }

    func take(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }

    var last: URLRequest? { requests.last }
    var count: Int { requests.count }
}

private func client(_ recorder: Recorder) -> AuthClient {
    AuthClient(
        baseURL: URL(string: "https://example.supabase.co")!,
        key: "publishable-key",
        transport: { await recorder.take($0) })
}

@Suite("Auth client")
struct AuthClientTests {
    @Test("The browser is sent somewhere that carries the challenge, not the verifier")
    func authorizeURL() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = try #require(client(Recorder()).authorizeURL(provider: "google", pkce: pkce))
        let text = url.absoluteString

        #expect(text.hasPrefix("https://example.supabase.co/auth/v1/authorize?"))
        #expect(text.contains("provider=google"))
        #expect(text.contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"))
        #expect(text.contains("code_challenge_method=s256"))
        #expect(text.contains("redirect_to=sqia://auth".addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? "redirect_to"))
        // The verifier is the secret. It must not be anywhere near this.
        #expect(!text.contains(pkce.verifier))
    }

    @Test("Spending a code sends the verifier with it")
    func exchange() async throws {
        let recorder = Recorder()
        let session = try await client(recorder).exchange(code: "abc", verifier: "v-1")

        #expect(session.accessToken == "at-1")
        #expect(session.user.email == "a@b.co")

        let request = try #require(await recorder.last)
        #expect(request.url?.absoluteString.contains("grant_type=pkce") == true)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["auth_code"] as? String == "abc")
        #expect(json["code_verifier"] as? String == "v-1")
    }

    @Test("Apple is an id-token exchange, with the nonce it was signed against")
    func appleIdToken() async throws {
        let recorder = Recorder()
        _ = try await client(recorder).signIn(appleIdentityToken: "jwt", nonce: "n-1")

        let request = try #require(await recorder.last)
        #expect(request.url?.absoluteString.contains("grant_type=id_token") == true)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["provider"] as? String == "apple")
        #expect(json["id_token"] as? String == "jwt")
        #expect(json["nonce"] as? String == "n-1")
    }

    @Test("The mailed link goes to the bridge page, because mail will not follow a scheme")
    func magicLink() async throws {
        let recorder = Recorder(body: "{}")
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        try await client(recorder).sendMagicLink(to: "a@b.co", pkce: pkce)

        let request = try #require(await recorder.last)
        let url = try #require(request.url?.absoluteString)
        #expect(url.contains("/auth/v1/otp"))
        #expect(url.contains("redirect_to="))
        #expect(!url.contains("sqia://"), "a mail client will not follow a custom scheme")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["email"] as? String == "a@b.co")
        #expect(json["create_user"] as? Bool == true)
        // With a challenge, so the link comes back as a code this app can
        // spend. Without one the server would hand over a whole session in
        // a fragment instead, and which of the two arrives is not something
        // to leave to how the project happens to be configured.
        #expect(json["code_challenge"] as? String == pkce.challenge)
        #expect(json["code_challenge_method"] as? String == "s256")
        #expect(json["code_verifier"] == nil, "the verifier must never leave the device")
    }

    @Test("A refused refresh carries the server's own words")
    func refusedRefresh() async throws {
        // "Already Used" is two refreshes racing; an expired session is a
        // policy. They need different words, so the reason is carried up
        // rather than flattened.
        let subject = AuthClient(
            baseURL: URL(string: "https://example.supabase.co")!, key: "k",
            transport: reply(400, #"{"error":"invalid_grant","error_description":"Already Used"}"#))
        await #expect(throws: AuthError.rejected("Already Used")) {
            _ = try await subject.refresh("rt")
        }
    }

    @Test("GoTrue's other spellings of the same thing")
    func complaintShapes() {
        #expect(AuthClient.complaint(400, Data(#"{"msg":"bad"}"#.utf8)) == "bad")
        #expect(AuthClient.complaint(400, Data(#"{"message":"worse"}"#.utf8)) == "worse")
        #expect(AuthClient.complaint(500, Data("<html>".utf8)) == "HTTP 500")
    }

    @Test("A request that never arrived is not a refusal")
    func unreachable() async throws {
        let subject = AuthClient(
            baseURL: URL(string: "https://example.supabase.co")!, key: "k",
            transport: { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await subject.refresh("rt")
            Issue.record("should have thrown")
        } catch let error as AuthError {
            #expect(error.isNetwork, "an unreachable server must not read as a rejection")
        }
    }

    @Test("Deleting the account goes with the user's own token, not the anon key")
    func deleteAccount() async throws {
        let recorder = Recorder(body: "{}")
        try await client(recorder).deleteAccount(accessToken: "user-jwt")

        let request = try #require(await recorder.last)
        #expect(request.url?.absoluteString.contains("/functions/v1/delete-account") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-jwt")
    }
}

// ------------------------------------------------------------------ keeper --

private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

private func session(expiresIn: Double, refresh: String = "rt-0") -> AuthSession {
    AuthSession(
        accessToken: "at-0", refreshToken: refresh,
        expiresAt: epoch.timeIntervalSince1970 + expiresIn,
        user: AuthUser(id: "user-1", email: "a@b.co"))
}

private func keeper(
    _ storage: InMemorySessionStorage,
    transport: @escaping AuthClient.Transport,
    now: Date = epoch
) -> SessionKeeper {
    SessionKeeper(
        client: AuthClient(
            baseURL: URL(string: "https://example.supabase.co")!, key: "k",
            transport: transport),
        storage: storage,
        now: { now },
        waiting: { _ in })
}

/// Counts refreshes and parks the first one mid-flight, so a test can hold
/// the actor's refresh door open and see whether a second caller walks
/// through it. Only the first parks; a second — which a working single-flight
/// never makes — returns at once, so a regression fails the count rather than
/// hanging.
private actor RefreshCounter {
    private(set) var count = 0
    private var arrived: [CheckedContinuation<Void, Never>] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var parked = false

    func hit() async {
        count += 1
        guard count == 1 else { return }
        parked = true
        for waiter in arrived { waiter.resume() }
        arrived = []
        await withCheckedContinuation { gate = $0 }
    }

    func waitForFirst() async {
        if parked { return }
        await withCheckedContinuation { arrived.append($0) }
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

@Suite("Holding the sign-in")
struct SessionKeeperTests {
    @Test("A cached sign-in is seen without asking the network")
    func peekIsLocal() async throws {
        let storage = InMemorySessionStorage(session: session(expiresIn: 3600))
        let subject = keeper(storage, transport: { _ in
            Issue.record("peek reached the network")
            throw URLError(.badURL)
        })
        let cached = await subject.peek()
        #expect(cached)
    }

    @Test("A session with time left is used as it is")
    func freshNeedsNothing() async throws {
        let storage = InMemorySessionStorage(session: session(expiresIn: 3600))
        let subject = keeper(storage, transport: { _ in
            Issue.record("a fresh session was refreshed anyway")
            throw URLError(.badURL)
        })
        let ok = await subject.restore()
        #expect(ok)
        let token = await subject.accessToken()
        #expect(token == "at-0")
    }

    @Test("A spent session is refreshed before it is used")
    func staleIsRefreshed() async throws {
        let storage = InMemorySessionStorage(session: session(expiresIn: 10))
        let subject = keeper(storage, transport: reply(200, sessionJSON))

        let ok = await subject.restore()
        #expect(ok)
        let token = await subject.accessToken()
        #expect(token == "at-1")
        // And the new one is what a relaunch would find.
        let saved = await storage.load()
        #expect(saved?.refreshToken == "rt-1")
    }

    @Test("Two callers racing at launch spend the refresh token once")
    func refreshIsSingleFlight() async throws {
        // The launch race, in a test: a stale session, and two callers —
        // `restore` confirming it and `accessToken` fetching a token for the
        // first project load — arriving together. The refresh parks the first
        // one in the middle of its round trip, which is the exact gap the
        // actor used to let the second in through to spend the same rotated
        // token a second time. Once, or the sign-in is revoked.
        let storage = InMemorySessionStorage(session: session(expiresIn: 10))
        let counter = RefreshCounter()
        let base = reply(200, sessionJSON)
        let subject = keeper(storage, transport: { request in
            await counter.hit()
            return try await base(request)
        })

        async let restored = subject.restore()
        async let token = subject.accessToken()

        await counter.waitForFirst()
        await counter.release()

        #expect(await restored)
        #expect(await token == "at-1")
        #expect(await counter.count == 1, "the refresh token was spent more than once")
        let saved = await storage.load()
        #expect(saved?.refreshToken == "rt-1")
    }

    @Test("A train tunnel is not a sign-out")
    func offlineHoldsTheSession() async throws {
        // The refresh never reached the server, so nothing has said the
        // stored sign-in is bad. This is the case the whole file is about.
        let storage = InMemorySessionStorage(session: session(expiresIn: 10))
        let subject = keeper(storage, transport: { _ in
            throw URLError(.notConnectedToInternet)
        })

        let ok = await subject.restore()
        #expect(ok, "an unreachable server signed the user out")
        let stillThere = await storage.load()
        #expect(stillThere != nil, "the stored sign-in was thrown away for a network failure")
        let issue = await subject.takeIssue()
        #expect(issue == nil, "a network failure was written down as a rejection")
        // And the token it has is handed out, so the request fails rather
        // than the session.
        let token = await subject.accessToken()
        #expect(token == "at-0")
    }

    @Test("A refusal ends the session and says why")
    func rejectionEndsIt() async throws {
        let storage = InMemorySessionStorage(session: session(expiresIn: 10))
        let subject = keeper(
            storage,
            transport: reply(400, #"{"error_description":"Already Used"}"#))

        let ok = await subject.restore()
        #expect(!ok)
        let gone = await storage.load()
        #expect(gone == nil)
        let issue = await subject.takeIssue()
        #expect(issue == "Session ended just now: Already Used")
        // Read once.
        let again = await subject.takeIssue()
        #expect(again == nil)
    }

    @Test("Signing out on purpose is not written down as something that went wrong")
    func signOutLeavesNoNote() async throws {
        let storage = InMemorySessionStorage(session: session(expiresIn: 3600))
        let subject = keeper(storage, transport: reply(200, sessionJSON))
        await subject.restore()
        await subject.signOut()

        let signedIn = await subject.isSignedIn
        #expect(!signedIn)
        let gone = await storage.load()
        #expect(gone == nil)
        let issue = await subject.takeIssue()
        #expect(issue == nil)
    }

    @Test("Nothing stored is simply signed out, with nothing to explain")
    func nothingStored() async throws {
        let storage = InMemorySessionStorage()
        let subject = keeper(storage, transport: reply(200, sessionJSON))
        let ok = await subject.restore()
        #expect(!ok)
        let issue = await subject.takeIssue()
        #expect(issue == nil)
    }

    @Test("The store gets a token and the user it belongs to")
    func supabaseSession() async throws {
        let storage = InMemorySessionStorage(session: session(expiresIn: 3600))
        let subject = keeper(storage, transport: reply(200, sessionJSON))
        await subject.restore()

        let handed = await subject.supabaseSession()
        #expect(handed?.accessToken == "at-0")
        #expect(handed?.userId == "user-1")
    }

    @Test("Signing in keeps the session and clears the last complaint")
    func signInClearsTheNote() async throws {
        let storage = InMemorySessionStorage(
            issue: AuthIssue(reason: "Already Used", at: epoch.timeIntervalSince1970),
            verifier: "v")
        let subject = keeper(storage, transport: reply(200, sessionJSON))

        try await subject.signIn(code: "abc")
        let signedIn = await subject.isSignedIn
        #expect(signedIn)
        let saved = await storage.load()
        #expect(saved?.accessToken == "at-1")
        let issue = await subject.takeIssue()
        #expect(issue == nil, "a fresh sign-in still showed the last one's complaint")
    }
}

@Suite("Why the session ended")
struct AuthIssueTests {
    @Test("How long ago it was, in the words the web uses")
    func phrasing() {
        let issue = AuthIssue(reason: "Already Used", at: epoch.timeIntervalSince1970)
        #expect(
            issue.describe(now: epoch) == "Session ended just now: Already Used")
        #expect(
            issue.describe(now: epoch.addingTimeInterval(60))
                == "Session ended just now: Already Used")
        #expect(
            issue.describe(now: epoch.addingTimeInterval(12 * 60))
                == "Session ended 12 min ago: Already Used")
    }

    @Test("Past a day it is not about this visit")
    func tooOld() {
        let issue = AuthIssue(reason: "Already Used", at: epoch.timeIntervalSince1970)
        #expect(issue.describe(now: epoch.addingTimeInterval(23 * 3600)) != nil)
        #expect(issue.describe(now: epoch.addingTimeInterval(25 * 3600)) == nil)
    }
}

@Suite("The session on the wire")
struct AuthSessionTests {
    @Test("Either shape the server sends decodes")
    func bothShapes() throws {
        let withExpiresAt = """
            {"access_token":"a","refresh_token":"r","expires_at":1800003600,\
            "user":{"id":"u","email":null}}
            """
        let decoded = try JSONDecoder().decode(
            AuthSession.self, from: Data(withExpiresAt.utf8))
        #expect(decoded.expiresAt == 1_800_003_600)
        #expect(decoded.user.email == nil)

        let withExpiresIn = try JSONDecoder().decode(
            AuthSession.self, from: Data(sessionJSON.utf8))
        // Roughly an hour out from now, whenever now is.
        let ahead = withExpiresIn.expiresAt - Date().timeIntervalSince1970
        #expect(ahead > 3500 && ahead <= 3600)
    }

    @Test("A token about to die is not fresh")
    func freshness() {
        #expect(session(expiresIn: 3600).isFresh(at: epoch))
        #expect(!session(expiresIn: 30).isFresh(at: epoch), "half a minute is not enough margin")
        #expect(!session(expiresIn: -10).isFresh(at: epoch))
        #expect(session(expiresIn: 3600).secondsUntilRefresh(at: epoch) == 3540)
        #expect(session(expiresIn: 10).secondsUntilRefresh(at: epoch) == 0)
    }

    @Test("What goes into storage is what comes back out")
    func roundTrip() throws {
        let original = session(expiresIn: 3600)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(AuthSession.self, from: data) == original)
    }
}

@Suite("Reading the token, and the address")
struct TokenAndAddressTests {
    @Test("The subject comes out of the middle segment")
    func subject() {
        // {"sub":"user-1","email":"a@b.co"} in base64url, unpadded — which
        // is how a real one arrives, and the padding has to be put back.
        let token = "header.eyJzdWIiOiJ1c2VyLTEiLCJlbWFpbCI6ImFAYi5jbyJ9.signature"
        #expect(JWT.subject(of: token) == "user-1")
    }

    @Test("Anything that is not a token gives nothing rather than a guess")
    func notAToken() {
        #expect(JWT.subject(of: "") == nil)
        #expect(JWT.subject(of: "a.b") == nil)
        #expect(JWT.subject(of: "a.!!!!.c") == nil)
        // Valid base64, valid JSON, no subject.
        #expect(JWT.subject(of: "h.eyJlbWFpbCI6ImFAYi5jbyJ9.s") == nil)
    }

    @Test("An address is checked as loosely as the web checks it")
    func addresses() {
        #expect(EmailAddress.looksValid("a@b.co"))
        #expect(EmailAddress.looksValid("first.last+tag@sub.example.museum"))
        // Real addresses that a stricter rule would turn away.
        #expect(EmailAddress.looksValid("i_like_underscores@but.example"))

        #expect(!EmailAddress.looksValid(""))
        #expect(!EmailAddress.looksValid("nobody"))
        #expect(!EmailAddress.looksValid("no@domain"))
        #expect(!EmailAddress.looksValid("@b.co"))
        #expect(!EmailAddress.looksValid("a@.co"))
        #expect(!EmailAddress.looksValid("a@b."))
        #expect(!EmailAddress.looksValid("two@at@b.co"))
        #expect(!EmailAddress.looksValid("has space@b.co"))
    }
}

@Suite("The half-finished sign-in")
struct PendingSignInTests {
    @Test("The verifier outlives the process that asked for the link")
    func verifierIsStored() async throws {
        // A link from Mail arrives at an app iOS has very likely killed, so
        // a verifier held in memory would be gone exactly when it is needed.
        let storage = InMemorySessionStorage()
        let started = keeper(storage, transport: reply(200, sessionJSON))
        await started.expect(PKCE(verifier: "the-verifier"))

        // A fresh keeper over the same storage is what the relaunch is.
        let relaunched = keeper(storage, transport: reply(200, sessionJSON))
        try await relaunched.signIn(code: "abc")
        let signedIn = await relaunched.isSignedIn
        #expect(signedIn)
    }

    @Test("The verifier is spent once and not kept")
    func verifierIsCleared() async throws {
        let storage = InMemorySessionStorage(verifier: "the-verifier")
        let subject = keeper(storage, transport: reply(200, sessionJSON))
        try await subject.signIn(code: "abc")

        let left = await storage.loadVerifier()
        #expect(left == nil, "a spent verifier was kept")
    }

    @Test("A code with no sign-in behind it says which device to use")
    func codeWithoutVerifier() async throws {
        let storage = InMemorySessionStorage()
        let subject = keeper(storage, transport: reply(200, sessionJSON))
        await #expect(throws: AuthError.rejected("Open the link on the device you asked from.")) {
            try await subject.signIn(code: "abc")
        }
    }

    @Test("Signing out drops a sign-in that was only half made")
    func signOutClearsTheVerifier() async throws {
        let storage = InMemorySessionStorage(verifier: "the-verifier")
        let subject = keeper(storage, transport: reply(200, sessionJSON))
        await subject.signOut()
        let left = await storage.loadVerifier()
        #expect(left == nil)
    }
}
