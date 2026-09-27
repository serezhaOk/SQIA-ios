// The documents the app links out to. The profile lists them and the
// paywall has to — App Review wants the terms and the privacy policy on
// any screen that sells a subscription — so they are written down once.

import Foundation

enum Links {
    static let privacy = URL(string: "https://sqia.serezhaok.com/privacy.html")!
    static let terms = URL(string: "https://sqia.serezhaok.com/terms.html")!
    static let about = URL(string: "https://serezhaok.com")!
}
