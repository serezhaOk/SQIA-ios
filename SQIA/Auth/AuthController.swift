// The two ways in, as the phone does them.
//
// Google goes out to `ASWebAuthenticationSession`, which is a browser the
// app cannot read — that is the point, and it is why Google allows it where
// it refuses an embedded web view. Apple never leaves the app at all: it
// hands back an identity token and the nonce it was signed against, and
// GoTrue trades those for a session.
//
// A mailed link was the third way and is not offered any more. Nothing on
// the way back in has been removed with it: `handle(_:)` still reads the
// session a bridge page hands over, so a link somebody was already sent
// still opens.
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
    /// Held for as long as the sheet is up: `ASAuthorizationController` does
    /// not retain itself, and a released one never calls back.
    @ObservationIgnored private var appleRequest: ASAuthorizationController?
    @ObservationIgnored private var monitor: NWPathMonitor?

    init(client: AuthClient = AuthClient(), storage: any SessionStorage = KeychainSessionStorage())
    {
        self.client = client
        keeper = SessionKeeper(client: client, storage: storage)
        super.init()
    }

    // ------------------------------------------------------------ starting --

    /// What storage says, with no network in it. Enough to know which screen
    /// opens, not enough to trust — `start()` is what confirms it.
    func peek() async -> Bool {
        isSignedIn = await keeper.peek()
        return isSignedIn
    }

    /// Read what is stored, then confirm it. The first half is instant and
    /// decides which screen opens; the second may take a round trip.
    func start() async {
        // Straight from storage, no network: the library opens now rather
        // than after a token has been confirmed.
        _ = await peek()
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

    /// The design's Apple button is a 114-point pill with nothing in it but
    /// the mark, which `SignInWithAppleButton` cannot be made into — so the
    /// request is driven here and the button is an ordinary one.
    func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepareAppleRequest(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        appleRequest = controller
        isWorking = true
        message = nil
        controller.performRequests()
    }

    /// Apple wants the nonce hashed in the request and the raw one in the
    /// exchange, so it can check the token it signed is the one we asked for.
    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = PKCE(using: random).verifier
        appleNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = SHA256.digest(nonce).hex
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
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
        Self.anchor
    }
}

extension AuthController: ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        appleRequest = nil
        handleApple(.success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
        appleRequest = nil
        isWorking = false
        // Backing out of Apple's sheet lands here, and `report` knows not to
        // announce it.
        handleApple(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        Self.anchor
    }

    /// The window both sheets are put up over.
    private static var anchor: ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
