import Foundation

/// Production synchronization service that switches and auto-rotates accounts
/// for Antigravity CLI (`agy`) and Ghostex terminal agent sessions.
public final class AntigravityCLISyncService: Sendable {
    public static let shared = AntigravityCLISyncService()

    private let keychain = KeychainManager.shared
    private let directEngine = DirectCloudCodeEngine.shared

    private let cliDir: URL
    private let cliTokenFile: URL
    private let jetskiTokenFile: URL
    private let googleAccountsFile: URL
    private let oauthCredsFile: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let geminiDir = home.appendingPathComponent(".gemini")
        self.cliDir = geminiDir.appendingPathComponent("antigravity-cli")
        self.cliTokenFile = cliDir.appendingPathComponent("antigravity-oauth-token")
        self.jetskiTokenFile = geminiDir.appendingPathComponent("jetski-standalone-oauth-token")
        self.googleAccountsFile = geminiDir.appendingPathComponent("google_accounts.json")
        self.oauthCredsFile = geminiDir.appendingPathComponent("oauth_creds.json")
    }

    /// Whether Antigravity CLI or Ghostex is installed/present on this Mac
    public var isCLIInstalled: Bool {
        FileManager.default.fileExists(atPath: cliDir.path) ||
        FileManager.default.fileExists(atPath: "/Users/mac/.local/bin/agy") ||
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ghostex")
    }

    /// Whether Ghostex daemon or agy process is currently running
    public var isGhostexOrCLIRunning: Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "ghostex|gxserver|agy"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0
    }

    /// Reads the currently active account for Antigravity CLI by inspecting tokens or cached state
    public func getActiveAccount(from accounts: [Account]) -> (email: String?, account: Account?) {
        // Priority 1: Check id_token in ~/.gemini/antigravity-cli/antigravity-oauth-token
        if let tokenEmail = extractEmailFromTokenFile(cliTokenFile) {
            if let matched = accounts.first(where: { $0.email.lowercased() == tokenEmail.lowercased() }) {
                return (matched.email, matched)
            }
            return (tokenEmail, nil)
        }

        // Priority 2: Check jetski-standalone-oauth-token
        if let tokenEmail = extractEmailFromTokenFile(jetskiTokenFile) {
            if let matched = accounts.first(where: { $0.email.lowercased() == tokenEmail.lowercased() }) {
                return (matched.email, matched)
            }
            return (tokenEmail, nil)
        }

        // Priority 3: Match via refresh_token in cliTokenFile
        if let rf = extractRefreshToken(from: cliTokenFile) {
            if let matched = findAccount(forRefreshToken: rf, in: accounts) {
                return (matched.email, matched)
            }
        }

        // Priority 4: Check ~/.gemini/google_accounts.json
        if FileManager.default.fileExists(atPath: googleAccountsFile.path),
           let data = try? Data(contentsOf: googleAccountsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let activeEmail = json["active"] as? String, !activeEmail.isEmpty {
            if let matched = accounts.first(where: { $0.email.lowercased() == activeEmail.lowercased() }) {
                return (matched.email, matched)
            }
            return (activeEmail, nil)
        }

        // Priority 5: Check cached UserDefaults identifier
        if let cachedEmail = UserDefaults.standard.string(forKey: "com.antibox.active_cli_email"), !cachedEmail.isEmpty {
            if let matched = accounts.first(where: { $0.email.lowercased() == cachedEmail.lowercased() }) {
                return (matched.email, matched)
            }
            return (cachedEmail, nil)
        }

        return (nil, nil)
    }

    /// Switches Antigravity CLI / Ghostex to the target account credentials
    public func switchToAccount(account: Account) async -> (success: Bool, message: String) {
        let accountEmail = account.email.isEmpty ? account.name : account.email

        // 1. Resolve refresh token for account
        var refreshToken = (try? keychain.retrieve(forAccount: account.id)) ?? ""

        // Fallback: check ~/.antigravity_tools/accounts/<id>.json or match by email
        if refreshToken.isEmpty {
            let toolsBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools/accounts")
            let idFile = toolsBase.appendingPathComponent("\(account.id.uuidString.lowercased()).json")
            if let data = try? Data(contentsOf: idFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tokenObj = json["token"] as? [String: Any],
               let rf = tokenObj["refresh_token"] as? String, !rf.isEmpty {
                refreshToken = rf
            }
        }

        if refreshToken.isEmpty {
            let toolsBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools/accounts")
            if let files = try? FileManager.default.contentsOfDirectory(at: toolsBase, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "json" {
                    if let data = try? Data(contentsOf: file),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let em = json["email"] as? String,
                       em.lowercased() == account.email.lowercased(),
                       let tokenObj = json["token"] as? [String: Any],
                       let rf = tokenObj["refresh_token"] as? String, !rf.isEmpty {
                        refreshToken = rf
                        break
                    }
                }
            }
        }

        guard !refreshToken.isEmpty else {
            return (false, "No OAuth refresh token found for \(accountEmail). Please reconnect this account.")
        }

        // 2. Fetch fresh Google OAuth access token and id_token directly
        let details: DirectCloudCodeEngine.OAuthTokenDetails
        do {
            details = try await directEngine.refreshOAuthTokenDetails(refreshToken: refreshToken)
        } catch {
            return (false, "Failed to refresh Google OAuth token: \(error.localizedDescription)")
        }

        // Format ISO8601 expiry string with fractional seconds and timezone
        let expiryDate = Date().addingTimeInterval(Double(details.expiresIn))
        let isoFormatter = DateFormatter()
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        let expiryIsoString = isoFormatter.string(from: expiryDate)

        // Ensure directories exist
        if !FileManager.default.fileExists(atPath: cliDir.path) {
            try? FileManager.default.createDirectory(at: cliDir, withIntermediateDirectories: true)
        }

        // 3. Write ~/.gemini/antigravity-cli/antigravity-oauth-token
        var cliTokenDict: [String: Any] = [
            "token": [
                "access_token": details.accessToken,
                "token_type": details.tokenType,
                "refresh_token": refreshToken,
                "expiry": expiryIsoString
            ],
            "auth_method": "consumer"
        ]
        if let idTok = details.idToken, !idTok.isEmpty {
            cliTokenDict["id_token"] = idTok
        } else if let existingIdTok = extractExistingIdToken(from: cliTokenFile) {
            cliTokenDict["id_token"] = existingIdTok
        }

        if let data = try? JSONSerialization.data(withJSONObject: cliTokenDict, options: [.prettyPrinted]) {
            try? data.write(to: cliTokenFile, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cliTokenFile.path)
            // Also write to jetski-standalone-oauth-token
            try? data.write(to: jetskiTokenFile, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: jetskiTokenFile.path)
        }

        // 4. Update ~/.gemini/google_accounts.json
        var oldAccounts: [String] = []
        if FileManager.default.fileExists(atPath: googleAccountsFile.path),
           let data = try? Data(contentsOf: googleAccountsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let prevActive = json["active"] as? String, prevActive.lowercased() != accountEmail.lowercased() {
                oldAccounts.append(prevActive)
            }
            if let prevOld = json["old"] as? [String] {
                for item in prevOld where item.lowercased() != accountEmail.lowercased() && !oldAccounts.contains(item) {
                    oldAccounts.append(item)
                }
            }
        }
        let googleAccDict: [String: Any] = [
            "active": accountEmail,
            "old": oldAccounts
        ]
        if let gData = try? JSONSerialization.data(withJSONObject: googleAccDict, options: [.prettyPrinted]) {
            try? gData.write(to: googleAccountsFile, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: googleAccountsFile.path)
        }

        // 5. Update ~/.gemini/oauth_creds.json
        let oauthCredsDict: [String: Any] = [
            "access_token": details.accessToken,
            "refresh_token": refreshToken,
            "scope": details.scope ?? "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/cloud-platform openid",
            "token_type": details.tokenType,
            "id_token": details.idToken ?? "",
            "expiry_date": Int64(expiryDate.timeIntervalSince1970 * 1000)
        ]
        if let credsData = try? JSONSerialization.data(withJSONObject: oauthCredsDict, options: [.prettyPrinted]) {
            try? credsData.write(to: oauthCredsFile, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: oauthCredsFile.path)
        }

        // 6. Update ~/.antigravity_tools/accounts.json if present
        updateAntigravityToolsCurrentAccount(id: account.id)

        // 7. Persist active CLI state in UserDefaults
        UserDefaults.standard.set(account.id.uuidString, forKey: "com.antibox.active_cli_account_id")
        UserDefaults.standard.set(accountEmail, forKey: "com.antibox.active_cli_email")

        return (true, "Successfully switched Antigravity CLI to \(accountEmail)!")
    }

    /// Checks if the currently active Antigravity CLI account has low/depleted quota,
    /// and automatically rotates to the best available healthy account based on selected focus.
    public func checkAndAutoRotateIfNeeded(
        accounts: [Account],
        focus: AutoSwitchQuotaFocus = .both,
        thresholdPercent: Double = 5.0
    ) async -> (rotated: Bool, oldEmail: String?, newEmail: String?, reason: String?) {
        guard !accounts.isEmpty else { return (false, nil, nil, nil) }

        let (_, activeAcc) = getActiveAccount(from: accounts)
        guard let currentAccount = activeAcc else { return (false, nil, nil, nil) }

        let geminiPct = currentAccount.remainingPercentage
        let claudeModels = currentAccount.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }
        let claudePct = claudeModels.map { $0.remainingPercentage }.min() ?? 100.0

        var isDepleted = false
        var reason = ""

        switch focus {
        case .both:
            if claudePct <= thresholdPercent {
                isDepleted = true
                reason = "Claude/GPT quota is \(Int(claudePct))%"
            } else if geminiPct <= thresholdPercent {
                isDepleted = true
                reason = "Gemini quota is \(Int(geminiPct))%"
            }
        case .claude:
            if claudePct <= thresholdPercent {
                isDepleted = true
                reason = "Claude/GPT quota reached \(Int(claudePct))%"
            }
        case .gemini:
            if geminiPct <= thresholdPercent {
                isDepleted = true
                reason = "Gemini quota reached \(Int(geminiPct))%"
            }
        }

        if isDepleted {
            // Find candidates with healthy quota according to the active focus strategy
            let candidates = accounts.filter { acc in
                guard acc.id != currentAccount.id else { return false }
                let accGemini = acc.remainingPercentage
                let accClaude = acc.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }.map { $0.remainingPercentage }.min() ?? 100.0

                switch focus {
                case .both:
                    return accClaude > thresholdPercent && accGemini > thresholdPercent
                case .claude:
                    return accClaude > thresholdPercent
                case .gemini:
                    return accGemini > thresholdPercent
                }
            }.sorted { a, b in
                switch focus {
                case .both:
                    return a.effectiveQuotaPercentage > b.effectiveQuotaPercentage
                case .claude:
                    let aC = a.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }.map { $0.remainingPercentage }.min() ?? 0.0
                    let bC = b.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }.map { $0.remainingPercentage }.min() ?? 0.0
                    return aC > bC
                case .gemini:
                    return a.remainingPercentage > b.remainingPercentage
                }
            }

            if let targetCandidate = candidates.first {
                let switchResult = await switchToAccount(account: targetCandidate)
                if switchResult.success {
                    return (true, currentAccount.email, targetCandidate.email, reason)
                }
            }
        }

        return (false, nil, nil, nil)
    }

    // MARK: - Private Helpers

    private func extractEmailFromTokenFile(_ file: URL) -> String? {
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            return nil
        }
        return extractEmailFromIdToken(idToken)
    }

    private func extractRefreshToken(from file: URL) -> String? {
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokenObj = json["token"] as? [String: Any],
              let rf = tokenObj["refresh_token"] as? String else {
            return nil
        }
        return rf.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractExistingIdToken(from file: URL) -> String? {
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String, !idToken.isEmpty else {
            return nil
        }
        return idToken
    }

    private func extractEmailFromIdToken(_ idToken: String) -> String? {
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String, !email.isEmpty else {
            return nil
        }
        return email
    }

    private func findAccount(forRefreshToken token: String, in accounts: [Account]) -> Account? {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return nil }

        for acc in accounts {
            if let stored = try? keychain.retrieve(forAccount: acc.id),
               stored.trimmingCharacters(in: .whitespacesAndNewlines) == cleanToken {
                return acc
            }

            let toolsBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools/accounts")
            let idFiles = [
                toolsBase.appendingPathComponent("\(acc.id.uuidString.lowercased()).json"),
                toolsBase.appendingPathComponent("\(acc.id.uuidString).json")
            ]
            for idFile in idFiles {
                if let data = try? Data(contentsOf: idFile),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tokenObj = json["token"] as? [String: Any],
                   let rf = (tokenObj["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   rf == cleanToken {
                    return acc
                }
            }
        }

        return nil
    }

    private func updateAntigravityToolsCurrentAccount(id: UUID) {
        let toolsBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools")
        let accountsFile = toolsBase.appendingPathComponent("accounts.json")
        guard FileManager.default.fileExists(atPath: accountsFile.path),
              let data = try? Data(contentsOf: accountsFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        json["current_account_id"] = id.uuidString.lowercased()
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? updatedData.write(to: accountsFile, options: [.atomic])
        }
    }
}
