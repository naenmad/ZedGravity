import Foundation
import UserNotifications

/// Handles native macOS UserNotifications for quota threshold breaches and auto-switch events
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationManager()

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    private var recentlyNotifiedAccounts: [String: Date] = [:]
    private let lock = NSLock()

    override private init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    /// Requests authorization from macOS notification system
    public func requestAuthorization() {
        guard let center = center else {
            print("[NotificationManager] Running in unbundled mode. Notifications require an app bundle.")
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NotificationManager] Authorization error: \(error.localizedDescription)")
            } else {
                print("[NotificationManager] Notification authorization granted: \(granted)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Ensure notifications display as foreground banners even when AntiBox is the active app
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    // MARK: - Quota Alerts

    /// Evaluates account quotas (Gemini and Claude/GPT) and fires critical alert if below threshold
    public func evaluateQuotaThreshold(for account: Account, threshold: Double = 15.0) {
        let geminiPct = account.remainingPercentage
        let claudeModels = account.quotas.filter { $0.provider == .claude || $0.name.lowercased().contains("gpt") }
        let claudePct = claudeModels.map { $0.remainingPercentage }.min() ?? 100.0

        if geminiPct <= threshold {
            dispatchThrottledAlert(
                account: account,
                modelCategory: "Gemini",
                percentage: geminiPct,
                body: "Gemini quota dropped to \(Int(geminiPct))%. Consider switching account or conserving quota."
            )
        }

        if !claudeModels.isEmpty && claudePct <= threshold {
            dispatchThrottledAlert(
                account: account,
                modelCategory: "Claude / GPT",
                percentage: claudePct,
                body: "Claude & GPT quota dropped to \(Int(claudePct))%. Consider switching account or conserving quota."
            )
        }
    }

    private func dispatchThrottledAlert(account: Account, modelCategory: String, percentage: Double, body: String) {
        let key = "\(account.id.uuidString)-\(modelCategory)"
        let now = Date()

        lock.lock()
        if let last = recentlyNotifiedAccounts[key], now.timeIntervalSince(last) < 1800 { // 30 min cooldown
            lock.unlock()
            return
        }
        recentlyNotifiedAccounts[key] = now
        lock.unlock()

        sendNotification(
            title: "⚠️ \(modelCategory) Quota Critical (\(Int(percentage))%)",
            subtitle: account.email.isEmpty ? account.name : account.email,
            body: body
        )
    }

    /// Dispatches an immediate notification when Zed ACP auto-switches accounts
    public func notifyAutoSwitched(oldEmail: String, newEmail: String, reason: String) {
        sendNotification(
            title: "🔄 Zed ACP Auto-Switched",
            subtitle: "\(newEmail) Activated",
            body: "Switched from \(oldEmail) because \(reason). Chat history in Zed is preserved."
        )
    }

    /// Dispatches an immediate notification when Antigravity CLI auto-switches accounts
    public func notifyCLIAutoSwitched(oldEmail: String, newEmail: String, reason: String) {
        sendNotification(
            title: "🔄 Antigravity CLI Auto-Switched",
            subtitle: "\(newEmail) Activated",
            body: "Switched from \(oldEmail) because \(reason). Sesi Ghostex & CLI otomatis menggunakan akun ini."
        )
    }

    /// Dispatches an arbitrary notification to macOS
    public func sendNotification(title: String, subtitle: String? = nil, body: String) {
        guard let center = center else {
            print("[NotificationManager] \(title) | \(subtitle ?? ""): \(body)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default

        let identifier = "antibox-alert-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(6))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { error in
            if let error = error {
                print("[NotificationManager] Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
}
