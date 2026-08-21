// The sign-in on disk.
//
// The session goes in the Keychain because the refresh token in it is a
// bearer credential for the account: anything that reads it is signed in as
// that user until it is revoked. `AfterFirstUnlock` rather than
// `WhenUnlocked` so a phone in a pocket can still refresh a token in the
// background — the app has to survive being away for a day and coming back
// signed in.
//
// The note about why a session ended is not secret and does not want to
// outlive a reinstall, so it lives in UserDefaults. Keychain items survive
// deleting the app; a stale "Session ended 4 min ago" greeting a fresh
// install would be a small lie.

import Foundation
import SQIACore
import Security

struct KeychainSessionStorage: SessionStorage {
    private let service = "com.serezhaok.sqia"
    private let account = "supabase-session"
    private let issueKey = "sqia.auth.issue"
    /// Read fresh each time rather than held: `UserDefaults` is not
    /// Sendable, and this type has to be.
    private var defaults: UserDefaults { .standard }

    // ------------------------------------------------------------ session --

    func load() async -> AuthSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) async {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func clear() async {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    // -------------------------------------------------------------- issue --

    func loadIssue() async -> AuthIssue? {
        guard let data = defaults.data(forKey: issueKey) else { return nil }
        return try? JSONDecoder().decode(AuthIssue.self, from: data)
    }

    func save(issue: AuthIssue) async {
        guard let data = try? JSONEncoder().encode(issue) else { return }
        defaults.set(data, forKey: issueKey)
    }

    func clearIssue() async {
        defaults.removeObject(forKey: issueKey)
    }
}
