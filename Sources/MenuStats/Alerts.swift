// persuara

import Foundation
import UserNotifications

struct ProcInfo: Identifiable {
    var id: String { name }
    let name: String
    let cpu: Double
    let rssBytes: UInt64
    let pids: [Int32]
    let canQuit: Bool
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
final class AlertEngine {
    private var since: [String: Date] = [:]
    private var lastFired: [String: Date] = [:]
    private let delegate = NotificationDelegate()
    private let available = Bundle.main.bundleIdentifier != nil

    init() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(cpu: Double, pressure: Int, thermal: Int, temp: Double?, diskFree: Int64?,
                  topCPU: ProcInfo?, topMem: ProcInfo?) {
        let d = UserDefaults.standard
        guard available, (d.object(forKey: "alerts.enabled") as? Bool) ?? true else { return }
        let diskGB = (d.object(forKey: "alerts.diskGB") as? Int) ?? 10

        check("cpu", cpu >= 0.90, hold: 60, cooldown: 600,
              title: "CPU has been above 90%",
              body: topCPU.map { "\($0.name) is using \(Int($0.cpu))% of a core." } ?? "Something is working hard.")
        check("mem", pressure >= 2, hold: 60, cooldown: 600,
              title: pressure >= 4 ? "Memory pressure is critical" : "Memory pressure is high",
              body: topMem.map { "\($0.name) is using \(formatBytes(Int64($0.rssBytes)))." } ?? "Close some apps to free memory.")
        check("thermal", thermal >= 2, hold: 30, cooldown: 900,
              title: thermal >= 3 ? "Your Mac is heavily throttled" : "Your Mac is being throttled",
              body: "macOS is slowing things down to cool off. Close heavy apps and give it airflow.")
        check("temp", (temp ?? 0) >= 90, hold: 60, cooldown: 900,
              title: "Your Mac is running hot",
              body: "Internal temperature is \(Int((temp ?? 0).rounded()))°C.")
        check("disk", (diskFree ?? .max) < Int64(diskGB) * 1_000_000_000, hold: 0, cooldown: 3600,
              title: "Low disk space",
              body: "Only \(formatBytes(diskFree ?? 0)) left on your startup disk.")
    }

    private func check(_ key: String, _ exceeded: Bool, hold: TimeInterval, cooldown: TimeInterval,
                       title: String, body: String) {
        guard exceeded else { since[key] = nil; return }
        let now = Date()
        let start = since[key] ?? now
        since[key] = start
        guard now.timeIntervalSince(start) >= hold,
              now.timeIntervalSince(lastFired[key] ?? .distantPast) >= cooldown else { return }
        lastFired[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "\(key)-\(UUID())", content: content, trigger: nil))
    }
}
