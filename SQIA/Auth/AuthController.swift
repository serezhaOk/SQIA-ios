// The three ways in, as the phone does them.
//
// Google goes out to `ASWebAuthenticationSession`, which is a browser the
// app cannot read — that is the point, and it is why Google allows it where
// it refuses an embedded web view. Apple never leaves the app at all: it
// hands back an identity token and the nonce it was signed against, and
// GoTrue trades those for a session. Email goes through a bridge page,
// because no mail client will follow a custom scheme.
//
// The decisions all live in `SessionKeeper`, in Core, under test. What is
// here is the parts that need UIKit: a presentation anchor, a nonce that
// Apple wants hashed, and a path monitor that says when the network is back.

import AuthenticationServices
import Foundation
import Network
import SQIACore
import SwiftUI
import UIKit

@MainActor
@Observable
final class AuthController: NSObject {
    /// What the sign-in screen shows under the buttons.
    struct Message: Equatable {
        var text: String
        var isError: Bool
    }

    private(set) var session: AuthSession?
    private(set) var message: Message?
    private(set) var isWorking = false
    /// True from the moment a cached sign-in is seen, before the network has
    /// confirmed anything — so a returning user goes straight to the library.
    private(set) var isSignedIn = false
    private(set) var hasSettled = false

    @ObservationIgnored let keeper: SessionKeeper
    @ObservationIgnored private let client: AuthClient
    @ObservationIgnored private let random = SystemRandomSource()
    /// Apple signs the token against the hash of this.
    @ObservationIgnored private var appleNonce: String?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private var monitor: NWPathMonitor?

    init(client: AuthClient = AuthClient(), storage: any SessionStorage = KeychainSessionStorage())
    {
        self.client = client
        keeper = SessionKeeper(client: client, storage: storage)
        super.init()
    }

    // ------------------------------------------------------------ starting --

    /// Read what is stored, then confirm it. The first half is instant and
    /// decides which screen opens; the second may take a round trip.
    func start() async {
        // Straight from storage, no network: the library opens now rather
        // than after a token has been confirmed.
        isSignedIn = await keeper.peek()
        let ok = await keeper.restore()
        isSignedIn = ok
        session = await keeper.current
        if !ok, let issue = await keeper.takeIssue() {
            message = Message(text: issue, isError: true)
        }
        hasSettled = true
        watchTheNetwork()
    }

    /// A refresh that could not reach the server is worth trying again the
    /// moment there is a network. `online` in the web; this here.
    private func watchTheNetwork() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, self.isSignedIn else { return }
                await self.keeper.retrySoon()
                self.session = await self.keeper.current
                self.isSignedIn = await self.keeper.isSignedIn
            }
        }
        monitor.start(queue: DispatchQueue(label: "sqia.network"))
        self.monitor = monitor
    }

    // -------------------------------------------------------------- Google --

    func signInWithGoogle() {
        let pkce = PKCE(using: random)
        guard let url = client.authorizeURL(provider: "google", pkce: pkce) else {
            message = Message(text: "Could not start sign-in", isError: true)
            return
        }

        isWorking = true
        message = nil
        Task { await keeper.expect(pkce) }
        // Named for what it is: `session` here would shadow the sign-in.
        let browser = ASWebAuthenticationSession(
            url: url, callbackURLScheme: "sqia"
        ) { [weak self] callback, error in
            Task { @MainActor in
                guard let self else { return }
                self.isWorking = false
                if let callback {
                    await self.handle(callback)
                } else if let error {
                    self.report(error)
                }
            }
        }
        browser.presentationContextProvider = self
        // A sign-in the user can see the address bar of, and one that does
        // not inherit whatever is in Safari already.
        browser.prefersEphemeralWebBrowserSession = true
        webSession = browser
        browser.start()
    }

    // --------------------------------------------------------------- Apple --

    /// Apple wants the nonce hashed in the request and the raw one in the
    /// exchange, so it can check the token it signed is the one we asked for.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = PKCE(using: random).verifier
        appleNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = SHA256.digest(nonce).hex
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential
                    as? ASAuthorizationAppleIDCredential,
                let data = credential.identityToken,
                let token = String(data: data, encoding: .utf8)
            else {
                message = Message(text: "Apple sent no identity token", isError: true)
                return
            }
            let nonce = appleNonce
            isWorking = true
            Task {
                do {
                    try await keeper.signIn(appleIdentityToken: token, nonce: nonce)
                    await self.settle()
                } catch {
                    self.report(error)
                }
                self.isWorking = false
            }
        case .failure(let error):
            report(error)
        }
    }

    // --------------------------------------------------------------- email --

    func sendMagicLink(to email: String) {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddress.looksValid(address) else {
            message = Message(text: "Enter a valid email address.", isError: true)
            return
        }
        isWorking = true
        message = Message(text: "Sending a sign-in link…", isError: false)
        let pkce = PKCE(using: random)
        Task {
            // Stored before the mail is asked for: the link may well arrive
            // at a process that did not exist when it was sent.
            await keeper.expect(pkce)
            do {
                try await client.sendMagicLink(to: address, pkce: pkce)
                message = Message(text: "Check \(address) for your sign-in link.", isError: false)
            } catch {
                report(error)
            }
            isWorking = false
        }
    }

    // ------------------------------------------------------------ coming in --

    /// `sqia://auth…`, from the browser or from the bridge page.
    func handle(_ url: URL) async {
        switch AuthCallback.read(url) {
        case .code(let code):
            isWorking = true
            do {
                try await keeper.signIn(code: code)
                await settle()
            } catch {
                report(error)
            }
            isWorking = false

        case .session(let accessToken, let refreshToken, let expiresIn):
            await keeper.adopt(
                AuthSession(
                    accessToken: accessToken, refreshToken: refreshToken,
                    expiresAt: Date().timeIntervalSince1970 + expiresIn,
                    user: AuthUser(id: JWT.subject(of: accessToken) ?? "", email: nil)))
            await settle()

        case .failure(let reason):
            message = Message(text: reason, isError: true)

        case .none:
            break
        }
    }

    // ------------------------------------------------------------ leaving --

    func signOut() async {
        await keeper.signOut()
        session = nil
        isSignedIn = false
        message = nil
    }

    func deleteAccount() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await keeper.deleteAccount()
            session = nil
            isSignedIn = false
            return true
        } catch {
            report(error)
            return false
        }
    }

    // ------------------------------------------------------------ plumbing --

    private func settle() async {
        session = await keeper.current
        isSignedIn = await keeper.isSignedIn
        message = nil
    }

    private func report(_ error: Error) {
        if let error = error as? ASWebAuthenticationSessionError,
            error.code == .canceledLogin
        {
            // Backing out of the browser is not a failure to announce.
            message = nil
            return
        }
        if let error = error as? ASAuthorizationError, error.code == .canceled {
            message = nil
            return
        }
        let text = (error as? AuthError)?.message ?? error.localizedDescription
        message = Message(text: text, isError: true)
    }
}

extension AuthController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
