import Foundation
import Security
import FitnessCore

/// Speichert OAuth-Token im iOS-Schlüsselbund.
/// `AfterFirstUnlockThisDeviceOnly`: verfügbar für Hintergrund-Sync, nicht in Backups/auf andere Geräte übertragbar.
struct KeychainTokenStore: TokenStore {
    let service = "de.kbtrx.oauth"

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    func loadToken(for key: String) throws -> OAuthToken? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    func saveToken(_ token: OAuthToken, for key: String) throws {
        let data = try JSONEncoder().encode(token)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(key) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add.merge(attrs) { $1 }
            let s = SecItemAdd(add as CFDictionary, nil)
            guard s == errSecSuccess else { throw KeychainError(status: s) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func deleteToken(for key: String) throws {
        let s = SecItemDelete(query(key) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw KeychainError(status: s) }
    }
}

struct KeychainError: Error, LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Schlüsselbund-Fehler (\(status))" }
}
