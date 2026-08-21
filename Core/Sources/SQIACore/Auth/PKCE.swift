// Proof Key for Code Exchange, RFC 7636.
//
// The app opens a browser it does not control, and the provider hands the
// authorisation code back through a URL scheme any app on the phone could
// have claimed. PKCE is what makes that code useless to whoever else caught
// it: the exchange only completes for whoever can produce the verifier the
// challenge was made from, and that never leaves the process.

import Foundation

public struct PKCE: Sendable, Equatable {
    /// 43–128 characters of unreserved ASCII, per §4.1.
    public let verifier: String
    /// base64url(SHA256(verifier)), which is what the `s256` method means.
    public let challenge: String

    public static let method = "s256"

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = SHA256.digest(verifier).base64URL
    }

    /// 32 bytes of randomness as base64url is 43 characters — the shortest
    /// the spec allows, and the length every server is known to accept.
    ///
    /// A byte per draw rather than eight: `next()` is `[0, 1)`, so scaling
    /// it gives one uniform byte and nothing about the rest of the double is
    /// assumed. `SystemRandomSource` is the system generator underneath,
    /// which is where the entropy has to come from.
    public init(using random: RandomSource) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        for _ in 0..<32 { bytes.append(UInt8(random.next() * 256)) }
        self.init(verifier: bytes.base64URL)
    }
}
