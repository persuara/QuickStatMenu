// persuara

import Foundation
import Darwin
import Combine
import IOKit
import AppKit

@MainActor
final class SystemMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var ramUsage: Double = 0
    @Published var ramUsedBytes: UInt64 = 0
    @Published var memoryPressure: Int = 1
    @Published var topCPU: [ProcInfo] = []
    @Published var topMem: [ProcInfo] = []
    @Published var coreUsage: [Double] = []
    @Published var swapUsedBytes: UInt64 = 0
    @Published var pingMs: Double? = nil
    @Published var todayDown: UInt64 = 0
    @Published var todayUp: UInt64 = 0
    @Published var thermalState: Int = 0
    @Published var localIP: String? = nil
    @Published var cpuHistory = [Double](repeating: 0, count: SystemMonitor.historyLength)
    @Published var ramHistory = [Double](repeating: 0, count: SystemMonitor.historyLength)
    @Published var gpuUsage: Double = 0
    @Published var temperature: Double? = nil
    @Published var diskFreeBytes: Int64? = nil
    @Published var vpnActive: Bool = false
    @Published var countryCode: String? = nil
    @Published var downHistory = [Double](repeating: 0, count: SystemMonitor.historyLength)
    @Published var upHistory = [Double](repeating: 0, count: SystemMonitor.historyLength)
    @Published var isDark: Bool = true
    @Published var downloadBps: Double = 0
    @Published var uploadBps: Double = 0

    static let historyLength = 60
    private let alerts = AlertEngine()
    let privacy = PrivacyChecker()
    private let tempReader = TemperatureReader()
    private var tick = 0
    private var lastCountryFetch = Date.distantPast
    private var timer: Timer?
    private var prevCores: [[UInt32]] = []
    private var totalsDay = ""
    private var prevNet: (rx: UInt64, tx: UInt64, time: Date)?

    init() {
        loadTraffic()
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if dark != isDark { isDark = dark }
        sampleCPU()
        sampleGPU()
        sampleRAM()
        cpuHistory.removeFirst(); cpuHistory.append(cpuUsage)
        ramHistory.removeFirst(); ramHistory.append(ramUsage)
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        if thermal != thermalState { thermalState = thermal }
        let ip = Self.readLocalIP()
        if ip != localIP { localIP = ip }
        if tick % 5 == 0 { refreshProcesses(); refreshPing() }
        if tick % 2 == 0 { temperature = tempReader.read() }
        if tick % 10 == 0 { diskFreeBytes = Self.readFreeDisk() }
        tick += 1
        sampleNetwork()
        let vpn = Self.detectVPN()
        alerts.evaluate(cpu: cpuUsage, pressure: memoryPressure, thermal: thermalState, temp: temperature,
                        diskFree: diskFreeBytes, topCPU: topCPU.first, topMem: topMem.first)
        privacy.vpnActive = vpn
        if vpn != vpnActive {
            vpnActive = vpn
            refreshCountry(after: 2)
            privacy.run(after: 4)
        } else if privacy.isStale {
            privacy.run()
        } else if Date().timeIntervalSince(lastCountryFetch) > 60 {
            refreshCountry(after: 0)
        }
    }

    private func sampleCPU() {
        var numCPUs: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &numCPUs, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var cores: [[UInt32]] = []
        for i in 0..<Int(numCPUs) {
            let base = i * Int(CPU_STATE_MAX)
            cores.append([UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                          UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                          UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                          UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])])
        }
        defer { prevCores = cores }
        guard prevCores.count == cores.count else { return }

        var busyAll: UInt64 = 0, totalAll: UInt64 = 0
        var perCore: [Double] = []
        for i in cores.indices {
            let d = (0..<4).map { UInt64(cores[i][$0] &- prevCores[i][$0]) }
            let total = d.reduce(0, +), busy = d[0] + d[1] + d[3]
            perCore.append(total > 0 ? Double(busy) / Double(total) : 0)
            busyAll += busy; totalAll += total
        }
        coreUsage = perCore
        if totalAll > 0 { cpuUsage = min(1, max(0, Double(busyAll) / Double(totalAll))) }
    }

    private func sampleRAM() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let total = ProcessInfo.processInfo.physicalMemory
        ramUsedBytes = used
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { swapUsedBytes = swap.xsu_used }
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            memoryPressure = Int(level)
        }
        ramUsage = min(1, Double(used) / Double(total))
    }

    func refreshProcesses() {
        Task.detached { [weak self] in
            let (cpu, mem) = Self.readTopProcesses()
            await self?.applyProcesses(cpu, mem)
        }
    }

    private func applyProcesses(_ cpu: [ProcInfo], _ mem: [ProcInfo]) {
        topCPU = cpu
        topMem = mem
    }

    private nonisolated static func readTopProcesses() -> ([ProcInfo], [ProcInfo]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pid=,uid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return ([], []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let me = Int32(getuid())
        var byName: [String: (cpu: Double, rss: UInt64, pids: [Int32], mine: Bool)] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5, let pid = Int32(parts[0]), let uid = Int32(parts[1]),
                  let cpu = Double(parts[2]), let rssKB = UInt64(parts[3]) else { continue }
            let name = String(parts[4])
            if name == "ps" { continue }
            var e = byName[name] ?? (0, 0, [], true)
            e.cpu += cpu; e.rss += rssKB * 1024; e.pids.append(pid)
            if uid != me { e.mine = false }
            byName[name] = e
        }
        let protected: Set<String> = ["launchd", "kernel_task", "loginwindow", "WindowServer", "MenuStats"]
        let all = byName.map {
            ProcInfo(name: $0.key, cpu: $0.value.cpu, rssBytes: $0.value.rss, pids: $0.value.pids,
                     canQuit: $0.value.mine && !protected.contains($0.key))
        }
        return (Array(all.sorted { $0.cpu > $1.cpu }.prefix(3)),
                Array(all.sorted { $0.rssBytes > $1.rssBytes }.prefix(3)))
    }

    func quit(_ p: ProcInfo, force: Bool) {
        guard p.canQuit else { return }
        for pid in p.pids {
            if let app = NSRunningApplication(processIdentifier: pid) {
                if force { _ = app.forceTerminate() } else { _ = app.terminate() }
            } else {
                kill(pid, force ? SIGKILL : SIGTERM)
            }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.refreshProcesses()
        }
    }

    private nonisolated static func readLocalIP() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var best: (name: String, ip: String)?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            let flags = Int32(ifa.pointee.ifa_flags)
            guard name.hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  let addr = ifa.pointee.ifa_addr,
                  Int32(addr.pointee.sa_family) == AF_INET else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if ip.hasPrefix("169.254.") { continue }
            if best == nil || name < best!.name { best = (name, ip) }
        }
        return best?.ip
    }

    private func refreshPing() {
        Task.detached { [weak self] in
            let ms = Self.measurePing()
            await self?.applyPing(ms)
        }
    }

    private func applyPing(_ ms: Double?) { pingMs = ms }

    private nonisolated static func measurePing() -> Double? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        task.arguments = ["-c", "1", "-t", "2", "1.1.1.1"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard let r = text.range(of: "time=") else { return nil }
        return Double(text[r.upperBound...].prefix { $0.isNumber || $0 == "." })
    }

    private func sampleGPU() {
        guard let matching = IOServiceMatching("IOAccelerator") else { return }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }

        var best = 0
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any],
               let v = (stats["Device Utilization %"] as? NSNumber)?.intValue {
                best = max(best, v)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        gpuUsage = min(1, max(0, Double(best) / 100))
    }

    private static func readFreeDisk() -> Int64? {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func refreshCountry(after delay: TimeInterval) {
        lastCountryFetch = Date()
        Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            var req = URLRequest(url: URL(string: "https://ipinfo.io/country")!)
            req.timeoutInterval = 8
            req.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  text.count == 2, text.allSatisfy(\.isLetter) else { return }
            await MainActor.run { self?.countryCode = text.uppercased() }
        }
    }

    private static func detectVPN() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            guard ["utun", "ppp", "ipsec", "tun", "tap"].contains(where: name.hasPrefix) else { continue }
            let flags = Int32(ifa.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  let addr = ifa.pointee.ifa_addr else { continue }
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                return true
            case AF_INET6:
                let sin6 = UnsafeRawPointer(addr).load(as: sockaddr_in6.self)
                let b = sin6.sin6_addr.__u6_addr.__u6_addr8
                let linkLocal = b.0 == 0xfe && (b.1 & 0xc0) == 0x80
                if !linkLocal { return true }
            default: break
            }
        }
        return false
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private func loadTraffic() {
        let d = UserDefaults.standard
        let today = Self.dayFormatter.string(from: Date())
        totalsDay = today
        if d.string(forKey: "traffic.day") == today {
            todayDown = UInt64(max(0, d.integer(forKey: "traffic.down")))
            todayUp = UInt64(max(0, d.integer(forKey: "traffic.up")))
        }
    }

    private func addTraffic(_ down: UInt64, _ up: UInt64) {
        let today = Self.dayFormatter.string(from: Date())
        if today != totalsDay { totalsDay = today; todayDown = 0; todayUp = 0 }
        todayDown += down
        todayUp += up
        if tick % 10 == 0 {
            let d = UserDefaults.standard
            d.set(today, forKey: "traffic.day")
            d.set(Int(todayDown), forKey: "traffic.down")
            d.set(Int(todayUp), forKey: "traffic.up")
        }
    }

    private func sampleNetwork() {
        let now = Date()
        let (rx, tx) = Self.readNetworkBytes()
        defer { prevNet = (rx, tx, now) }
        guard let prev = prevNet else { return }
        let dt = now.timeIntervalSince(prev.time)
        guard dt > 0 else { return }
        let dRx = rx >= prev.rx ? rx - prev.rx : 0
        let dTx = tx >= prev.tx ? tx - prev.tx : 0
        downloadBps = Double(dRx) / dt
        uploadBps   = Double(dTx) / dt
        addTraffic(dRx, dTx)
        downHistory.removeFirst(); downHistory.append(downloadBps)
        upHistory.removeFirst();   upHistory.append(uploadBps)
    }

    private static func readNetworkBytes() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return (0, 0) }

        var rx: UInt64 = 0, tx: UInt64 = 0
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let msgLen = Int(hdr.ifm_msglen)
                if msgLen == 0 { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(h2.ifm_index), &nameBuf) != nil,
                       String(cString: nameBuf).hasPrefix("en"),
                       h2.ifm_flags & IFF_UP != 0 {
                        rx += h2.ifm_data.ifi_ibytes
                        tx += h2.ifm_data.ifi_obytes
                    }
                }
                offset += msgLen
            }
        }
        return (rx, tx)
    }
}

func formatSpeed(_ bps: Double) -> String {
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var v = bps
    var i = 0
    while v >= 1000 && i < units.count - 1 { v /= 1024; i += 1 }
    if i == 0 { return String(format: "%.0f %@", v, units[i]) }
    return String(format: v < 10 ? "%.1f %@" : "%.0f %@", v, units[i])
}

func flagEmoji(_ code: String) -> String {
    code.uppercased().unicodeScalars
        .compactMap { UnicodeScalar(127397 + $0.value) }
        .map { String($0) }.joined()
}

func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb < 1 { return String(format: "%.0f MB", Double(bytes) / 1_000_000) }
    if gb >= 1000 { return String(format: "%.1f TB", gb / 1000) }
    return String(format: gb >= 100 ? "%.0f GB" : "%.1f GB", gb)
}
