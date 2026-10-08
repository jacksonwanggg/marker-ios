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
    var refreshExpiry: Date
    var tokenIssuedAt: Date
}

enum Keychain {
    private static var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jacksonwang.marker",
            kSecAttrAccount as String: "formatif-session",
        ]
    }

    static func saveCredentials(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            // readable while locked for background refresh, never backed up or moved to another phone
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(item as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(item.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static func loadCredentials() -> Credentials? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func deleteCredentials() {
        SecItemDelete(item as CFDictionary)
    }
}
