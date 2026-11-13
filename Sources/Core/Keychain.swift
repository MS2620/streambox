import Foundation
import Security

enum Keychain {
    private static let service = "com.mauro.streambox"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func setData(_ data: Data?, for key: String) {
        let query = baseQuery(key)
        SecItemDelete(query as CFDictionary)
        guard let data, !data.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func data(for key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func set(_ value: String, for key: String) {
        setData(value.isEmpty ? nil : Data(value.utf8), for: key)
    }

    static func string(for key: String) -> String? {
        data(for: key).map { String(decoding: $0, as: UTF8.self) }
    }

    static func setCodable<T: Encodable>(_ value: T, for key: String) {
        setData(try? JSONEncoder().encode(value), for: key)
    }

    static func codable<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        data(for: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
