import SwiftUI

struct AudioVisualizerView: View {
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            let barCount = levels.count
            guard barCount > 0 else { return }

            let barWidth = size.width / CGFloat(barCount) * 0.8
            let gap = size.width / CGFloat(barCount) * 0.2
            let totalBarWidth = barWidth + gap

            for i in 0..<barCount {
                let height = CGFloat(levels[i]) * size.height * 0.8
                let x = CGFloat(i) * totalBarWidth
                let y = size.height - height

                let rect = CGRect(x: x, y: y, width: barWidth, height: height)

                // Color gradient from blue to purple (hue 210-270)
                let hue = Double(i) / Double(barCount) * 60.0 / 360.0 + 210.0 / 360.0
                let color = Color(hue: hue, saturation: 0.7, brightness: 0.55)

                context.fill(
                    Path(rect),
                    with: .color(color.opacity(0.9))
                )
            }
        }
        .background(Color(.systemGray6))
    }
}
