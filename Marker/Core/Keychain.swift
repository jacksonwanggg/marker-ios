import Foundation
import Security

struct Credentials: Codable, Sendable, Equatable {
    var username: String
    var authToken: String
    var refreshToken: String?
    var userID: Int?
    var firstName: String?
    var lastName: String?
    var signedInAt: Date
    /// The refresh cookie lasts 7 days, then the tutor has to sign in again.
    var refreshExpiry: Date
    var tokenIssuedAt: Date
}

enum Keychain {
    private static let service = "com.jacksonwang.marker"
    private static let account = "formatif-session"

    static func saveCredentials(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            // background refresh runs while the phone is locked
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static func loadCredentials() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
