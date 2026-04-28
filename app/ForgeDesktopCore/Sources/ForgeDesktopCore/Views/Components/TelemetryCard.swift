import SwiftUI

struct TelemetryMetricRow: View {
    let label: String
    let value: Int
    let total: Int
    let index: Int

    @State private var barWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 120, alignment: .trailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GeometryReader { geo in
                let fraction = total > 0 ? CGFloat(value) / CGFloat(total) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(ForgeTheme.Gradients.forge)
                        .frame(width: max(0, barWidth * geo.size.width))
                }
                .onAppear {
                    withAnimation(ForgeTheme.Animations.springSnappy.delay(Double(index) * ForgeTheme.Animations.staggerDelay)) {
                        barWidth = fraction
                    }
                }
                .onChange(of: value) { _, _ in
                    let newFraction = total > 0 ? CGFloat(value) / CGFloat(total) : 0
                    withAnimation(ForgeTheme.Animations.springSnappy) {
                        barWidth = newFraction
                    }
                }
            }
            .frame(height: 8)

            Text("\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(ForgeTheme.Colors.forgeOrange)
        }
    }
}

struct BlockRateGauge: View {
    let rate: Int

    @State private var animatedRate: CGFloat = 0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0.25, to: 0.75)
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(0))
                Circle()
                    .trim(from: 0.25, to: 0.25 + animatedRate * 0.5)
                    .stroke(
                        rate > 50 ? Color.red : (rate > 20 ? ForgeTheme.Colors.forgeOrange : Color.green),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(0))
                Text("\(rate)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .offset(y: 4)
            }
            .frame(width: 64, height: 64)
            .onAppear {
                withAnimation(ForgeTheme.Animations.springBouncy) {
                    animatedRate = CGFloat(rate) / 100
                }
            }
            .onChange(of: rate) { _, newValue in
                withAnimation(ForgeTheme.Animations.springBouncy) {
                    animatedRate = CGFloat(newValue) / 100
                }
            }
            .accessibilityLabel("Block rate \(rate) percent")

            Text("Block Rate")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
