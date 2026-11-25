// persuara

import SwiftUI

struct MenuVisibility {
    var cpu = true, gpu = true, ram = true, temp = true, disk = true, country = true, speeds = true, graph = false, swap = false, ping = false
    var anyVisible: Bool { cpu || gpu || ram || temp || disk || country || speeds || graph || swap || ping }
}

let downColor = Color(red: 0.25, green: 0.65, blue: 1.00)
let upColor   = Color(red: 1.00, green: 0.60, blue: 0.20)

struct SparkShape: Shape {
    let values: [Double]
    let peak: Double
    var closed = false

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1, peak > 0 else { return p }
        let step = rect.width / CGFloat(values.count - 1)
        func point(_ i: Int) -> CGPoint {
            CGPoint(x: CGFloat(i) * step,
                    y: rect.maxY - CGFloat(min(values[i] / peak, 1)) * rect.height)
        }
        p.move(to: closed ? CGPoint(x: 0, y: rect.maxY) : point(0))
        if closed { p.addLine(to: point(0)) }
        for i in 1..<values.count { p.addLine(to: point(i)) }
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

struct NetworkGraph: View {
    let down: [Double]
    let up: [Double]
    var lineWidth: CGFloat = 1.2

    static func peak(_ down: [Double], _ up: [Double]) -> Double {
        max(10_240, down.max() ?? 0, up.max() ?? 0)
    }

    var body: some View {
        let peak = Self.peak(down, up)
        ZStack {
            SparkShape(values: down, peak: peak, closed: true).fill(downColor.opacity(0.25))
            SparkShape(values: up, peak: peak, closed: true).fill(upColor.opacity(0.20))
            SparkShape(values: down, peak: peak).stroke(downColor, lineWidth: lineWidth)
            SparkShape(values: up, peak: peak).stroke(upColor, lineWidth: lineWidth)
        }
    }
}

struct HistoryGraph: View {
    let title: String
    let values: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(((values.last ?? 0) * 100).rounded()))%").monospacedDigit()
            }
            .font(.system(size: 9))
            ZStack {
                SparkShape(values: values, peak: 1, closed: true).fill(color.opacity(0.25))
                SparkShape(values: values, peak: 1).stroke(color, lineWidth: 1.2)
            }
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.5)))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
