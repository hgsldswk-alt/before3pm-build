import Foundation
import Security

actor LocalStorage {
    private let isTesting: Bool
    private var cachedURL: URL?

    init(isTesting: Bool) { self.isTesting = isTesting }

    func load(reset: Bool) throws -> LocalState {
        let url = try stateURL()
        if reset, isTesting, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return LocalState() }
        return try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: url))
    }

    func save(_ state: LocalState) throws {
        try JSONEncoder().encode(state).write(to: stateURL(), options: .atomic)
    }

    private func stateURL() throws -> URL {
        if let cachedURL { return cachedURL }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        var directory = base.appendingPathComponent(isTesting ? "Before3PM-UITesting" : "Before3PM", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let result = directory.appendingPathComponent("state.json")
        cachedURL = result
        return result
    }
}

actor EntitlementStorage {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hgsldswk.before3pm.entitlement",
        kSecAttrAccount as String: "access"
    ]

    func load() throws -> Entitlement? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw StorageError.keychain(status) }
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    func save(_ entitlement: Entitlement) throws {
        let data = try JSONEncoder().encode(entitlement)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StorageError.keychain(status) }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(item as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw StorageError.keychain(insertStatus) }
    }

    enum StorageError: Error { case keychain(OSStatus) }
}
