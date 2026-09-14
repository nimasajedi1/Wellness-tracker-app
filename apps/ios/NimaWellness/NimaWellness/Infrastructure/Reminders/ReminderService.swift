import Foundation
import UserNotifications
import Observation
import WellnessCore

/// Local reminders (DEVICE-004): user-configured only, explicit notification
/// permission requested on first enable, quiet hours respected, neutral
/// wording, and no repeat-failure or shaming messages. A delivered
/// notification is never treated as evidence the task happened.
@MainActor
@Observable
final class ReminderService {

    enum PermissionState: String {
        case notAsked, granted, denied
    }

    private(set) var rules: [ReminderRule] = []
    var quietHoursEnabled: Bool {
        didSet { persist(); Task { await resync() } }
    }
    var quietStartMinute: Int {
        didSet { persist(); Task { await resync() } }
    }
    var quietEndMinute: Int {
        didSet { persist(); Task { await resync() } }
    }
    private(set) var permissionState: PermissionState = .notAsked

    private let center = UNUserNotificationCenter.current()
    private static let requestPrefix = "nimawellness.reminder."

    init() {
        let defaults = UserDefaults.standard
        quietHoursEnabled = defaults.object(forKey: "reminders.quietEnabled") as? Bool ?? true
        quietStartMinute = defaults.object(forKey: "reminders.quietStart") as? Int ?? 22 * 60
        quietEndMinute = defaults.object(forKey: "reminders.quietEnd") as? Int ?? 7 * 60
        if let data = defaults.data(forKey: "reminders.rules"),
           let decoded = try? JSONDecoder().decode([ReminderRule].self, from: data) {
            rules = decoded
        }
        Task { await refreshPermissionState() }
    }

    var quietHours: QuietHours? {
        quietHoursEnabled ? QuietHours(startMinute: quietStartMinute, endMinute: quietEndMinute) : nil
    }

    func refreshPermissionState() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: permissionState = .granted
        case .denied: permissionState = .denied
        case .notDetermined: permissionState = .notAsked
        @unknown default: permissionState = .notAsked
        }
    }

    /// Explicit permission, requested only when the user enables reminders.
    func requestPermissionIfNeeded() async -> Bool {
        await refreshPermissionState()
        switch permissionState {
        case .granted: return true
        case .denied: return false
        case .notAsked:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            permissionState = granted ? .granted : .denied
            return granted
        }
    }

    func add(_ rule: ReminderRule) async {
        guard await requestPermissionIfNeeded() else { return }
        rules.append(rule)
        persist()
        await resync()
    }

    func remove(_ rule: ReminderRule) async {
        rules.removeAll { $0.id == rule.id }
        persist()
        await resync()
    }

    func setEnabled(_ rule: ReminderRule, enabled: Bool) async {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].isEnabled = enabled
            persist()
            await resync()
        }
    }

    /// Rebuild all pending requests from the rules. Times shift out of quiet
    /// hours via the pure rule logic; repeating calendar triggers follow the
    /// device's current time zone (reminder policy; stored history unaffected).
    func resync() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard permissionState == .granted else { return }
        for rule in rules where rule.isEnabled {
            let effectiveMinute = rule.effectiveMinuteOfDay(quietHours: quietHours)
            let content = UNMutableNotificationContent()
            content.title = rule.title
            content.body = "A reminder you set. Recording it in the app is up to you."
            content.sound = .default

            let weekdays: [Int?] = rule.weekdays.isEmpty ? [nil] : rule.weekdays.map { Optional($0) }
            for weekday in weekdays {
                var components = DateComponents()
                components.hour = effectiveMinute / 60
                components.minute = effectiveMinute % 60
                components.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let identifier = "\(Self.requestPrefix)\(rule.id.uuidString).\(weekday.map(String.init) ?? "daily")"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(quietHoursEnabled, forKey: "reminders.quietEnabled")
        defaults.set(quietStartMinute, forKey: "reminders.quietStart")
        defaults.set(quietEndMinute, forKey: "reminders.quietEnd")
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: "reminders.rules")
        }
    }
}
