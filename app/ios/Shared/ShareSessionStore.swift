import Foundation
import Security

/// The small amount of session state that the iOS Share Extension needs.
///
/// The Firebase ID token is kept in a shared Keychain access group rather than
/// UserDefaults. The API base URL is not secret, so it is kept in the App Group
/// defaults suite alongside the extension's other non-sensitive configuration.
enum ShareSessionStore {
  static let appGroupIdentifier = "group.com.intpsquad.modi"

  private static let keychainService = "com.nomara.modi.share-auth"
  private static let keychainAccount = "firebase-id-token"

  private static var keychainAccessGroup: String {
    // AppIdentifierPrefix is expanded by Xcode in each target's Info.plist.
    // Keeping this in the plist lets the same source work with another
    // development team without baking a Team ID into the repository.
    (Bundle.main.object(forInfoDictionaryKey: "ShareKeychainAccessGroup") as? String)
      ?? "$(AppIdentifierPrefix)group.com.intpsquad.modi"
  }

  static func save(idToken: String) throws {
    guard !idToken.isEmpty else {
      throw ShareSessionStoreError.invalidToken
    }

    var query = keychainQuery()
    let value = idToken.data(using: .utf8) ?? Data()
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData: value] as CFDictionary
    )

    if updateStatus == errSecItemNotFound {
      query[kSecValueData] = value
      query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw ShareSessionStoreError.keychainStatus(addStatus)
      }
      return
    }

    guard updateStatus == errSecSuccess else {
      throw ShareSessionStoreError.keychainStatus(updateStatus)
    }
  }

  static func loadIDToken() -> String? {
    var query = keychainQuery()
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func clear() throws {
    let status = SecItemDelete(keychainQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw ShareSessionStoreError.keychainStatus(status)
    }
  }

  static func saveAPIBaseURL(_ value: String) {
    guard let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          url.host != nil else {
      return
    }
    UserDefaults(suiteName: appGroupIdentifier)?.set(value, forKey: "apiBaseURL")
  }

  static var apiBaseURL: URL? {
    guard let value = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: "apiBaseURL"),
          let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          url.host != nil else {
      return nil
    }
    return url
  }

  private static func keychainQuery() -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: keychainService,
      kSecAttrAccount: keychainAccount,
      kSecAttrAccessGroup: keychainAccessGroup,
    ]
  }
}

enum ShareSessionStoreError: Error {
  case invalidToken
  case keychainStatus(OSStatus)
}
