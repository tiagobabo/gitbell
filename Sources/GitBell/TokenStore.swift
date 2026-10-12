import Foundation
import Security

enum TokenStore {
    enum Mode: String {
        case githubCLI, token, signedOut
    }

    private static let service = "dev.tiagobabo.GitBell"
    private static let account = "github-token"
    private static let modeKey = "authMode"

    static var mode: Mode? {
        get { UserDefaults.standard.string(forKey: modeKey).flatMap(Mode.init) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: modeKey) }
    }

    // GUI apps don't inherit the shell PATH.
    static let ghPath: String? = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        NSHomeDirectory() + "/.local/bin/gh",
    ].first { FileManager.default.isExecutableFile(atPath: $0) }

    static func load() async -> String? {
        switch mode {
        case .token:
            return keychainToken()
        case .githubCLI:
            return await ghToken()
        case .signedOut:
            return nil
        case nil:
            guard let token = await ghToken() else { return nil }
            mode = .githubCLI
            return token
        }
    }

    static func ghToken() async -> String? {
        guard let ghPath else { return nil }
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do { try process.run() } catch { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        }.value
    }

    static func saveToken(_ token: String) {
        deleteToken()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func keychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
