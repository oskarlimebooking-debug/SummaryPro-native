import Foundation
import Security

enum KeychainService {
    static let speechKeyId = "sp_speech_key"
    static let geminiKeyId = "sp_gemini_key"
    static let openaiKeyId = "sp_openai_key"
    static let sonioxKeyId = "sp_soniox_key"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.summarypro.keys",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.summarypro.keys",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.summarypro.keys",
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        delete(key: speechKeyId)
        delete(key: geminiKeyId)
        delete(key: openaiKeyId)
        delete(key: sonioxKeyId)
    }
}
