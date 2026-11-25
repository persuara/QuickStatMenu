// persuara

import SwiftUI
import AppKit
import Darwin

struct PrivacyFinding: Identifiable {
    enum Level { case ok, notice, risk }
    let id = UUID()
    let level: Level
    let title: String
    let detail: String
}

struct IPDetails {
    var ip: String
    var provider: String?
    var asn: String?
    var country: String?
    var countryCode: String?
    var city: String?
    var timezone: String?
    var isProxy = false

    var place: String { [city, country].compactMap { $0 }.joined(separator: ", ") }
    var network: String { [provider, asn.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ") }
}

struct PrivacyReport {
    var checkedAt = Date()
    var vpnActive: Bool
    var exit: IPDetails?
    var dnsServers: [String] = []
    var dnsLeaking: [String] = []
    var physicalIPv6: String?
    var ipv6Seen: IPDetails?
    var findings: [PrivacyFinding] = []

    var worst: PrivacyFinding.Level {
        if findings.contains(where: { $0.level == .risk }) { return .risk }
        if findings.contains(where: { $0.level == .notice }) { return .notice }
        return .ok
    }

    mutating func buildFindings() {
        var f: [PrivacyFinding] = []
        guard let exit else {
            findings = [PrivacyFinding(level: .notice, title: "Couldn't check your public IP",
                                       detail: "No reply from the lookup services. Check your connection and run the check again.")]
            return
        }
        let where_ = [exit.network, exit.place].filter { !$0.isEmpty }.joined(separator: " · ")

        if !vpnActive {
            f.append(PrivacyFinding(level: .notice, title: "VPN is off",
                                    detail: "Websites see your real IP \(exit.ip)\(where_.isEmpty ? "" : " — \(where_)")."))
        } else {
            if exit.isProxy {
                f.append(PrivacyFinding(level: .notice, title: "Your exit IP is recognised as a VPN",
                                        detail: "\(exit.ip) — \(where_). Your real IP is hidden, but sites that block VPNs or enforce region rules can tell you aren't connecting directly."))
            } else {
                f.append(PrivacyFinding(level: .ok, title: "Your exit IP looks like a normal connection",
                                        detail: "\(exit.ip) — \(where_). Websites see you here, not at your real location."))
            }

            if !dnsLeaking.isEmpty {
                f.append(PrivacyFinding(level: .risk, title: "DNS requests leave the VPN tunnel",
                                        detail: "\(dnsLeaking.joined(separator: ", ")) is reached outside the tunnel, so your ISP or router can see which sites you look up."))
            } else if !dnsServers.isEmpty {
                f.append(PrivacyFinding(level: .ok, title: "DNS goes through the VPN",
                                        detail: "Lookups use \(dnsServers.joined(separator: ", ")) inside the tunnel."))
            }

            if physicalIPv6 != nil {
                if let seen = ipv6Seen {
                    if seen.asn != nil, seen.asn == exit.asn {
                        f.append(PrivacyFinding(level: .ok, title: "IPv6 goes through the VPN",
                                                detail: "Sites that support IPv6 see \(seen.ip), the VPN's address."))
                    } else {
                        f.append(PrivacyFinding(level: .risk, title: "IPv6 leak: your real address is visible",
                                                detail: "Sites that support IPv6 see \(seen.ip)\(seen.network.isEmpty ? "" : " — \(seen.network)"), not the VPN. Turn IPv6 off for your network service or enable your VPN's IPv6 protection."))
                    }
                } else {
                    f.append(PrivacyFinding(level: .ok, title: "IPv6 isn't reachable",
                                            detail: "Your network has IPv6, but nothing connected over it during the test."))
                }
            } else {
                f.append(PrivacyFinding(level: .ok, title: "No IPv6 leak possible",
                                        detail: "Your Wi-Fi/Ethernet has no public IPv6 address to leak."))
            }

            if let id = exit.timezone, let exitTZ = TimeZone(identifier: id) {
                let mine = TimeZone.current
                if exitTZ.secondsFromGMT() != mine.secondsFromGMT() {
                    f.append(PrivacyFinding(level: .notice, title: "Time zone doesn't match your VPN location",
                                            detail: "Your Mac is set to \(mine.identifier) but your exit IP is in \(id). Websites and apps can read your time zone and notice the difference."))
                } else {
                    f.append(PrivacyFinding(level: .ok, title: "Time zone matches your VPN location",
                                            detail: "\(mine.identifier)"))
                }
            }
        }
        findings = f
    }
}

@MainActor
final class PrivacyChecker: ObservableObject {
    @Published var report: PrivacyReport?
    @Published var running = false
    var vpnActive = false

    private var lastRun = Date.distantPast
    private var rerunRequested = false
    private var cache: [String: IPDetails] = [:]

    var isStale: Bool { !running && Date().timeIntervalSince(lastRun) > 600 }

    func run(after delay: TimeInterval = 0) {
        if running { rerunRequested = true; return }
        running = true
        lastRun = Date()
        let known = cache
        Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            let vpn = self?.vpnActive ?? false
            let (report, newCache) = await Self.collect(vpn: vpn, cache: known)
            self?.finish(report, newCache)
        }
    }

    private func finish(_ r: PrivacyReport, _ newCache: [String: IPDetails]) {
        report = r
        cache = newCache
        running = false
        if rerunRequested { rerunRequested = false; run() }
    }

    private nonisolated static func collect(vpn: Bool, cache: [String: IPDetails]) async
        -> (PrivacyReport, [String: IPDetails]) {
        var cache = cache
        var r = PrivacyReport(vpnActive: vpn)

        if let ip = await fetchText("https://api.ipify.org"), isValidIP(ip) {
            if let c = cache[ip] { r.exit = c } else {
                let d = await lookup(ip); cache[ip] = d; r.exit = d
            }
        }

        r.dnsServers = readDNSServers()
        if vpn {
            r.dnsLeaking = r.dnsServers.filter { routeInterface(for: $0)?.hasPrefix("en") == true }
        }

        r.physicalIPv6 = physicalGlobalIPv6()
        if r.physicalIPv6 != nil, let ip6 = await fetchText("https://api6.ipify.org"), isValidIP(ip6) {
            if let c = cache[ip6] { r.ipv6Seen = c } else {
                let d = await lookup(ip6); cache[ip6] = d; r.ipv6Seen = d
            }
        }

        r.buildFindings()
        return (r, cache)
    }

    private nonisolated static func fetchText(_ urlString: String) async -> String? {
        guard let data = await fetch(urlString) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func fetch(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return try? await URLSession.shared.data(for: req).0
    }

    private nonisolated static func isValidIP(_ s: String) -> Bool {
        var a4 = in_addr(), a6 = in6_addr()
        return inet_pton(AF_INET, s, &a4) == 1 || inet_pton(AF_INET6, s, &a6) == 1
    }

    private nonisolated static func lookup(_ ip: String) async -> IPDetails {
        var d = IPDetails(ip: ip)
        guard let data = await fetch("https://proxycheck.io/v2/\(ip)?vpn=1&asn=1"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json[ip] as? [String: Any] else { return d }
        d.provider = info["provider"] as? String
        d.asn = info["asn"] as? String
        d.country = info["country"] as? String
        d.countryCode = info["isocode"] as? String
        d.city = info["city"] as? String
        d.timezone = info["timezone"] as? String
        d.isProxy = (info["proxy"] as? String) == "yes"
        return d
    }

    private nonisolated static func run(_ path: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated static func readDNSServers() -> [String] {
        let text = run("/usr/sbin/scutil", ["--dns"])
        let main = text.components(separatedBy: "DNS configuration (for scoped queries)").first ?? text
        var out: [String] = []
        for line in main.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("nameserver["), let r = l.range(of: " : ") else { continue }
            let server = String(l[r.upperBound...])
            if !out.contains(server) { out.append(server) }
        }
        return out
    }

    private nonisolated static func routeInterface(for server: String) -> String? {
        if let pct = server.firstIndex(of: "%") { return String(server[server.index(after: pct)...]) }
        guard isValidIP(server) else { return nil }
        let args = ["-n", "get"] + (server.contains(":") ? ["-inet6"] : []) + [server]
        for line in run("/sbin/route", args).split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("interface:") {
                return l.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private nonisolated static func physicalGlobalIPv6() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            let flags = Int32(ifa.pointee.ifa_flags)
            guard name.hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  let addr = ifa.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET6 else { continue }
            let sin6 = UnsafeRawPointer(addr).load(as: sockaddr_in6.self)
            let b = sin6.sin6_addr.__u6_addr.__u6_addr8
            let linkLocal = b.0 == 0xfe && (b.1 & 0xc0) == 0x80
            let uniqueLocal = (b.0 & 0xfe) == 0xfc
            if linkLocal || uniqueLocal { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 { return String(cString: host) }
        }
        return nil
    }
}

struct PrivacyRow: View {
    @ObservedObject var checker: PrivacyChecker

    private var summary: String {
        guard let r = checker.report else { return "Checking…" }
        if r.exit == nil { return "🟡 No reply" }
        if !r.vpnActive { return "🟠 VPN off" }
        switch r.worst {
        case .risk:   return "🔴 Leak found"
        case .notice: return "🟡 See details"
        case .ok:     return "🟢 No leaks"
        }
    }

    var body: some View {
        Button { PrivacyWindow.show(checker: checker) } label: {
            HStack(spacing: 4) {
                Text("Privacy").foregroundStyle(.secondary)
                Spacer()
                Text(summary)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the privacy check")
    }
}

struct PrivacyView: View {
    @ObservedObject var checker: PrivacyChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy check").font(.title3.weight(.semibold))

            if let r = checker.report {
                if let exit = r.exit {
                    HStack(spacing: 6) {
                        Text(exit.countryCode.map { flagEmoji($0) } ?? "🌐").font(.title2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Websites see \(exit.ip)").font(.system(size: 13, weight: .medium))
                            Text([exit.network, exit.place].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                ForEach(r.findings) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Text(dot(finding.level)).font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title).font(.system(size: 12, weight: .semibold))
                            Text(finding.detail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…") }
            }

            Divider()
            Text("Not covered: browser (WebRTC) leaks — test those in your browser — and whether any company has flagged you; no service reports that. Location Services can still place you by nearby Wi-Fi networks if an app or site has permission, whatever your VPN says.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Lookups use ipify.org and proxycheck.io, which see your public IP.")
                .font(.caption2).foregroundStyle(.tertiary)

            HStack {
                if let r = checker.report {
                    HStack(spacing: 3) {
                        Text("Checked")
                        Text(r.checkedAt, style: .relative)
                        Text("ago")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(checker.running ? "Checking…" : "Run again") { checker.run() }
                    .disabled(checker.running)
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    private func dot(_ l: PrivacyFinding.Level) -> String {
        switch l { case .ok: return "🟢"; case .notice: return "🟡"; case .risk: return "🔴" }
    }
}

@MainActor
enum PrivacyWindow {
    private static var window: NSWindow?

    static func show(checker: PrivacyChecker) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PrivacyView(checker: checker)))
            w.title = "Privacy check"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
