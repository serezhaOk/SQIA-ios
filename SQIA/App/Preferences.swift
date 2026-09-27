// The few choices the app remembers per phone rather than per project.
// Keys only: each screen that cares reads its own through `@AppStorage`.

enum Preferences {
    /// Whether a pattern keeps playing once the app is out of sight. Off by
    /// default — the app goes quiet when it is left, the same as a browser
    /// tab losing its audio context — and on only when somebody asks.
    ///
    /// SQIA Plus: the switch is only ever obeyed together with
    /// `Access.allows(.backgroundPlayback)`, so a switch left on when a
    /// subscription lapsed goes back to meaning off.
    static let backgroundPlayback = "backgroundPlayback"
}
