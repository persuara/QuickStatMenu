// persuara

import SwiftUI

@main
struct MenuStatsApp: App {
    @StateObject private var monitor = SystemMonitor()
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage("alerts.enabled") private var alertsEnabled = true
    @AppStorage("alerts.diskGB") private var alertDiskGB = 10
    @AppStorage("show.cpu") private var showCPU = true
    @AppStorage("show.gpu") private var showGPU = true
    @AppStorage("show.ram") private var showRAM = true
    @AppStorage("show.temp") private var showTemp = true
    @AppStorage("show.disk") private var showDisk = true
    @AppStorage("show.country") private var showCountry = true
    @AppStorage("show.speeds") private var showSpeeds = true
    @AppStorage("show.graph") private var showGraph = false
    @AppStorage("show.swap") private var showSwap = false
    @AppStorage("show.ping") private var showPing = false

    private var visibility: MenuVisibility {
        MenuVisibility(cpu: showCPU, gpu: showGPU, ram: showRAM, temp: showTemp, disk: showDisk,
                       country: showCountry, speeds: showSpeeds, graph: showGraph,
                       swap: showSwap, ping: showPing)
    }

    init() { LaunchAtLogin.enableOnFirstRun() }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    column("System") {
                        stat("CPU", "\(Int((monitor.cpuUsage * 100).rounded()))%")
                        stat("GPU", "\(Int((monitor.gpuUsage * 100).rounded()))%")
                        stat("RAM", "\(formatBytes(Int64(monitor.ramUsedBytes))) / \(formatBytes(Int64(ProcessInfo.processInfo.physicalMemory)))")
                        stat("Memory pressure", pressureName)
                        stat("Swap used", formatBytes(Int64(monitor.swapUsedBytes)))
                        stat("Temperature", monitor.temperature.map { "\(Int($0.rounded()))°C" } ?? "N/A")
                        stat("Thermal", thermalName)
                        stat("Free disk", monitor.diskFreeBytes.map(formatBytes) ?? "--")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CPU cores").font(.caption).foregroundStyle(.secondary)
                            CoreBars(usage: monitor.coreUsage)
                        }
                        .padding(.top, 2)
                        HStack(spacing: 8) {
                            HistoryGraph(title: "CPU", values: monitor.cpuHistory,
                                         color: Color(red: 0.60, green: 0.50, blue: 1.00))
                            HistoryGraph(title: "RAM", values: monitor.ramHistory,
                                         color: Color(red: 0.20, green: 0.80, blue: 0.80))
                        }
                    }
                    Divider()
                    column("Network") {
                        stat("Download", formatSpeed(monitor.downloadBps))
                        stat("Upload", formatSpeed(monitor.uploadBps))
                        stat("Ping", monitor.pingMs.map { "\(Int($0.rounded())) ms" } ?? "no reply")
                        stat("VPN", monitor.vpnActive ? "On" : "Off")
                        PrivacyRow(checker: monitor.privacy)
                        stat("Country", monitor.countryCode.map { "\(flagEmoji($0)) \($0)" } ?? "--")
                        if let ip = monitor.localIP { CopyRow(name: "Local IP", value: ip) }
                        stat("Today ↓", formatBytes(Int64(monitor.todayDown)))
                        stat("Today ↑", formatBytes(Int64(monitor.todayUp)))
                        graphPanel.padding(.top, 2)
                    }
                    Divider()
                    column("Busiest apps") {
                        processList("Top by CPU", monitor.topCPU) { "\(Int($0.cpu))%" }
                        processList("Top by memory", monitor.topMem) { formatBytes(Int64($0.rssBytes)) }
                    }
                }
                Divider()
                Text("Show in menu bar").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 5),
                          alignment: .leading, spacing: 4) {
                    Toggle("CPU", isOn: $showCPU)
                    Toggle("GPU", isOn: $showGPU)
                    Toggle("RAM", isOn: $showRAM)
                    Toggle("Swap", isOn: $showSwap)
                    Toggle("Temp", isOn: $showTemp)
                    Toggle("Free disk", isOn: $showDisk)
                    Toggle("Country", isOn: $showCountry)
                    Toggle("Speed", isOn: $showSpeeds)
                    Toggle("Graph", isOn: $showGraph)
                    Toggle("Ping", isOn: $showPing)
                }
                .font(.system(size: 12))
                Divider()
                HStack(spacing: 12) {
                    Toggle("Alert when usage stays high", isOn: $alertsEnabled)
                    if alertsEnabled {
                        Picker("Low disk", selection: $alertDiskGB) {
                            ForEach([5, 10, 20, 50], id: \.self) { Text("below \($0) GB").tag($0) }
                        }
                        .fixedSize()
                        .font(.caption)
                    }
                    Spacer()
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { LaunchAtLogin.set($0) }
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                }
            }
            .padding(14)
            .frame(width: 700)
        } label: {
            Image(nsImage: renderMenuBarImage(cpu: monitor.cpuUsage,
                                              gpu: monitor.gpuUsage,
                                              ram: monitor.ramUsage,
                                              ramPressure: monitor.memoryPressure,
                                              swapUsed: monitor.swapUsedBytes,
                                              ping: monitor.pingMs,
                                              temp: monitor.temperature,
                                              diskFree: monitor.diskFreeBytes,
                                              down: monitor.downloadBps,
                                              up: monitor.uploadBps,
                                              vpn: monitor.vpnActive,
                                              country: monitor.countryCode,
                                              dark: monitor.isDark,
                                              show: visibility,
                                              downHistory: monitor.downHistory,
                                              upHistory: monitor.upHistory))
        }
        .menuBarExtraStyle(.window)
    }

    private var graphPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Down", systemImage: "circle.fill").foregroundStyle(downColor)
                Label("Up", systemImage: "circle.fill").foregroundStyle(upColor)
                Spacer()
                Text("peak " + formatSpeed(NetworkGraph.peak(monitor.downHistory, monitor.upHistory)))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 9)).labelStyle(SmallDotLabelStyle())
            NetworkGraph(down: monitor.downHistory, up: monitor.upHistory)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("last 60 seconds").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    private func column<Content: View>(_ title: String,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var thermalName: String {
        switch monitor.thermalState {
        case 0:  return "🟢 Normal"
        case 1:  return "🟡 Fair"
        case 2:  return "🟠 Throttling"
        default: return "🔴 Heavy throttling"
        }
    }

    private func confirmForceQuit(_ p: ProcInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Force quit \(p.name)?"
        alert.informativeText = "Unsaved changes in \(p.name) will be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { monitor.quit(p, force: true) }
    }

    private var pressureName: String {
        switch monitor.memoryPressure {
        case ..<2: return "🟢 Normal"
        case 2:    return "🟡 Warning"
        default:   return "🔴 Critical"
        }
    }

    private func processList(_ title: String, _ items: [ProcInfo],
                             value: @escaping (ProcInfo) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(items) { p in
                HStack {
                    Text(p.name).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Text(value(p)).monospacedDigit().foregroundStyle(.secondary)
                    if p.canQuit {
                        Menu {
                            Button("Quit \(p.name)") { monitor.quit(p, force: false) }
                            Button("Force Quit…") { confirmForceQuit(p) }
                        } label: {
                            Image(systemName: "xmark.circle").font(.system(size: 11))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Quit or force quit \(p.name)")
                    } else {
                        Image(systemName: "xmark.circle").font(.system(size: 11)).hidden()
                    }
                }
                .font(.system(size: 11))
            }
            if items.isEmpty { Text("…").font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
    }

    private func stat(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}

private struct SmallDotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 5))
            configuration.title.foregroundStyle(.primary)
        }
    }
}

private struct CopyRow: View {
    let name: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            HStack(spacing: 4) {
                Text(name).foregroundStyle(.secondary)
                Spacer()
                Text(copied ? "Copied ✓" : value).monospacedDigit()
                Image(systemName: "doc.on.doc").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to copy")
    }
}
