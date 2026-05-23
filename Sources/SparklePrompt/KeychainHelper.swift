import Foundation
import Security

/// A modern, thread-safe wrapper for the macOS Keychain.
final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    private let queue = DispatchQueue(label: "com.sparkle.keychain", qos: .userInitiated)

    enum KeychainError: Error {
        case stringToDataConversionError
        case dataToStringConversionError
        case unhandledError(status: OSStatus)
        case notFound
    }

    func save(_ value: String, for key: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let data = value.data(using: .utf8) else {
                    continuation.resume(throwing: KeychainError.stringToDataConversionError)
                    return
                }

                // Use Update-first strategy to avoid the non-atomic Delete+Add pattern.
                // This prevents data loss if the app crashes between delete and add.
                let searchQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "com.sparkle.prompt.api-keys",
                    kSecAttrAccount as String: key,
                ]

                let updateAttributes: [String: Any] = [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
                ]

                let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)

                if updateStatus == errSecSuccess {
                    continuation.resume()
                } else if updateStatus == errSecItemNotFound {
                    // Item doesn't exist yet — add it
                    var addQuery = searchQuery
                    addQuery[kSecValueData as String] = data
                    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

                    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                    if addStatus == errSecSuccess {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: KeychainError.unhandledError(status: addStatus))
                    }
                } else {
                    continuation.resume(throwing: KeychainError.unhandledError(status: updateStatus))
                }
            }
        }
    }

    func read(for key: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "com.sparkle.prompt.api-keys",
                    kSecAttrAccount as String: key,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]

                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                if status == errSecItemNotFound {
                    continuation.resume(throwing: KeychainError.notFound)
                    return
                }

                if status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                } else if status != errSecSuccess {
                    continuation.resume(throwing: KeychainError.unhandledError(status: status))
                } else {
                    continuation.resume(throwing: KeychainError.dataToStringConversionError)
                }
            }
        }
    }

    /// Synchronous delete — blocks until the Keychain item is removed.
    /// This is critical for `resetAllSettings()` to ensure keys are actually
    /// deleted before the reset sequence completes.
    func delete(for key: String) {
        queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.sparkle.prompt.api-keys",
                kSecAttrAccount as String: key
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
