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

    static func saveToken(_ token: String, account: String = account) {
        deleteToken(account: account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteToken(account: String = account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: CircleCI

    static let circleCIAccount = "circleci-token"

    enum CircleCISource { case keychain, cli }

    // Where the CircleCI token would come from, without reading it: asking only for the item's attributes
    // never needs the Keychain to decrypt anything, so it can't prompt.
    static func circleCISource() -> CircleCISource? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: circleCIAccount,
            kSecReturnAttributes as String: true,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess { return .keychain }
        return circleCICLIToken() == nil ? nil : .cli
    }

    // A personal API token for approving held jobs: the one pasted into Settings, else the CircleCI CLI's.
    static func circleCIToken() -> (token: String, source: CircleCISource)? {
        if let token = keychainToken(account: circleCIAccount), !token.isEmpty { return (token, .keychain) }
        return circleCICLIToken().map { ($0, .cli) }
    }

    // `circleci setup` writes "token: …" to ~/.circleci/cli.yml.
    private static func circleCICLIToken() -> String? {
        let path = NSHomeDirectory() + "/.circleci/cli.yml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("token:") {
            let token = line.dropFirst("token:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if !token.isEmpty { return token }
        }
        return nil
    }

    private static func keychainToken(account: String = account) -> String? {
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
