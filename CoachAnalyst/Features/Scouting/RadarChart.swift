import SwiftUI

/// A lightweight, dependency-free radar (spider) chart. Values are 0...1 and
/// map linearly from the centre (0) to the outer ring (1).
struct RadarChart: View {
    struct Series: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
        let values: [Double]
    }

    let axes: [String]
    let series: [Series]
    var rings: Int = 4

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side / 2 - 34

            ZStack {
                ForEach(1...max(rings, 1), id: \.self) { ring in
                    polygon(center: center, radius: radius * Double(ring) / Double(rings), values: nil)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }

                ForEach(axes.indices, id: \.self) { index in
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point(center: center, radius: radius, index: index, count: axes.count))
                    }
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }

                ForEach(series) { item in
                    polygon(center: center, radius: radius, values: item.values)
                        .fill(item.color.opacity(0.18))
                    polygon(center: center, radius: radius, values: item.values)
                        .stroke(item.color, lineWidth: 2)
                }

                ForEach(axes.indices, id: \.self) { index in
                    Text(axes[index])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(point(center: center, radius: radius + 20, index: index, count: axes.count))
                }
            }
        }
    }

    private func point(center: CGPoint, radius: Double, index: Int, count: Int) -> CGPoint {
        guard count > 0 else { return center }
        let angle = 2 * Double.pi * Double(index) / Double(count) - Double.pi / 2
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func polygon(center: CGPoint, radius: Double, values: [Double]?) -> Path {
        Path { path in
            guard !axes.isEmpty else { return }
            for index in axes.indices {
                let scale = values.map { max(0, min(1, $0[index])) } ?? 1
                let point = point(center: center, radius: radius * scale, index: index, count: axes.count)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

#Preview {
    RadarChart(
        axes: ["Goals", "xG", "Shots", "Assists", "KeyP", "Drib"],
        series: [
            .init(name: "A", color: .green, values: [0.9, 0.7, 0.8, 0.4, 0.6, 0.5]),
            .init(name: "B", color: .orange, values: [0.5, 0.6, 0.4, 0.7, 0.5, 0.9])
        ]
    )
    .frame(height: 300)
    .padding()
}
