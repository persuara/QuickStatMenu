// persuara

import SwiftUI
import Darwin

enum CoreTopology {
    static func count(_ name: String) -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : 0
    }
    static let performance = count("hw.perflevel0.logicalcpu")
    static let efficiency  = count("hw.perflevel1.logicalcpu")
}

struct CoreBars: View {
    let usage: [Double]

    var body: some View {
        let e = min(CoreTopology.efficiency, usage.count)
        let split = (CoreTopology.performance > 0 && e > 0) ? e : 0
        HStack(alignment: .bottom, spacing: 10) {
            if split > 0 {
                group("Efficiency", Array(usage[..<split]))
                group("Performance", Array(usage[split...]))
            } else {
                group("Cores", usage)
            }
        }
    }

    private func group(_ title: String, _ values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(values[i]))
                            .frame(height: max(2, 26 * values[i]))
                    }
                    .frame(width: 9, height: 26)
                }
            }
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    private func color(_ v: Double) -> Color {
        switch v {
        case ..<0.5:  return Color(red: 0.20, green: 0.80, blue: 0.35)
        case ..<0.75: return Color(red: 1.00, green: 0.80, blue: 0.10)
        case ..<0.90: return Color(red: 1.00, green: 0.55, blue: 0.10)
        default:      return Color(red: 1.00, green: 0.27, blue: 0.23)
        }
    }
}
