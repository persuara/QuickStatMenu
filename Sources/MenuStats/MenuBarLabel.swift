// persuara

import SwiftUI
import AppKit

struct MenuBarLabel: View {
    let cpu: Double
    let gpu: Double
    let ram: Double
    let ramPressure: Int
    let swapUsed: UInt64
    let ping: Double?
    let temp: Double?
    let diskFree: Int64?
    let down: Double
    let up: Double
    let vpn: Bool
    let country: String?
    let dark: Bool
    let show: MenuVisibility
    let downHistory: [Double]
    let upHistory: [Double]

    var body: some View {
        HStack(spacing: 4) {
            if !show.anyVisible {
                Image(systemName: "chart.bar.fill").font(.system(size: 13))
            }
            if show.disk, let diskFree {
                VStack(alignment: .leading, spacing: 0) {
                    Text("FREE").font(.system(size: 7, weight: .semibold)).opacity(0.7)
                    Text(formatBytes(diskFree))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .frame(width: 48, alignment: .leading)
            }
            if show.cpu { metric("CPU", cpu) }
            if show.gpu { metric("GPU", gpu) }
            if show.ram { metric("RAM", ram, color: pressureColor(ramPressure)) }
            if show.swap {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SWAP").font(.system(size: 7, weight: .semibold)).opacity(0.7)
                    Text(formatBytes(Int64(swapUsed)))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .frame(width: 44, alignment: .leading)
            }
            if show.temp, let temp {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TEMP").font(.system(size: 7, weight: .semibold)).opacity(0.7)
                    Text("\(Int(temp.rounded()))°C")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .frame(width: 34, alignment: .leading)
            }
            if show.ping {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PING").font(.system(size: 7, weight: .semibold)).opacity(0.7)
                    Text(ping.map { "\(Int($0.rounded())) ms" } ?? "--")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(pingColor(ping))
                }
                .frame(width: 42, alignment: .leading)
            }
            if show.country {
            VStack(alignment: .leading, spacing: 0) {
                Text(vpn ? "VPN" : "IP").font(.system(size: 7, weight: .semibold)).opacity(0.7)
                HStack(spacing: 3) {
                    if let country {
                        Text(flagEmoji(country)).font(.system(size: 10))
                        Text(country).font(.system(size: 11, weight: .medium))
                    } else {
                        Text("--").font(.system(size: 11, weight: .medium)).opacity(0.6)
                    }
                }
                .foregroundStyle(vpn ? Color(red: 0.20, green: 0.80, blue: 0.35) : (dark ? Color.white : Color.black))
            }
            .frame(width: 40, alignment: .leading)
            }
            if show.speeds {
                VStack(alignment: .trailing, spacing: 0) {
                    row("arrow.up", up)
                    row("arrow.down", down)
                }
            }
            if show.graph {
                NetworkGraph(down: downHistory, up: upHistory, lineWidth: 1)
                    .frame(width: 44, height: 16)
            }
        }
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(.horizontal, 2)
        .frame(height: 22)
    }

    private func loadColor(_ v: Double) -> Color {
        switch v {
        case ..<0.5:  return Color(red: 0.20, green: 0.80, blue: 0.35)
        case ..<0.75: return Color(red: 1.00, green: 0.80, blue: 0.10)
        case ..<0.90: return Color(red: 1.00, green: 0.55, blue: 0.10)
        default:      return Color(red: 1.00, green: 0.27, blue: 0.23)
        }
    }

    private func pingColor(_ ms: Double?) -> Color {
        guard let ms else { return dark ? .white : .black }
        if ms < 60 { return Color(red: 0.20, green: 0.80, blue: 0.35) }
        if ms < 150 { return Color(red: 1.00, green: 0.80, blue: 0.10) }
        return Color(red: 1.00, green: 0.27, blue: 0.23)
    }

    private func pressureColor(_ level: Int) -> Color {
        switch level {
        case ..<2: return Color(red: 0.20, green: 0.80, blue: 0.35)
        case 2:    return Color(red: 1.00, green: 0.80, blue: 0.10)
        default:   return Color(red: 1.00, green: 0.27, blue: 0.23)
        }
    }

    private func metric(_ name: String, _ value: Double, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1).opacity(0.6)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color ?? loadColor(value))
                    .frame(height: max(1, 14 * value))
                    .padding(1.5)
            }
            .frame(width: 8, height: 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.system(size: 7, weight: .semibold)).opacity(0.7)
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .frame(width: 34, alignment: .leading)
        }
    }

    private func row(_ symbol: String, _ bps: Double) -> some View {
        HStack(spacing: 2) {
            Text(formatSpeed(bps))
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .frame(width: 52, alignment: .trailing)
            Image(systemName: symbol).font(.system(size: 7, weight: .bold))
        }
    }
}

@MainActor
func renderMenuBarImage(cpu: Double, gpu: Double, ram: Double, ramPressure: Int, swapUsed: UInt64, ping: Double?, temp: Double?, diskFree: Int64?, down: Double, up: Double, vpn: Bool, country: String?, dark: Bool,
                         show: MenuVisibility, downHistory: [Double], upHistory: [Double]) -> NSImage {
    let renderer = ImageRenderer(content: MenuBarLabel(cpu: cpu, gpu: gpu, ram: ram, ramPressure: ramPressure, swapUsed: swapUsed, ping: ping, temp: temp, diskFree: diskFree, down: down, up: up, vpn: vpn, country: country, dark: dark,
                                                  show: show, downHistory: downHistory, upHistory: upHistory))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    let image = renderer.nsImage ?? NSImage()
    image.isTemplate = false
    return image
}
