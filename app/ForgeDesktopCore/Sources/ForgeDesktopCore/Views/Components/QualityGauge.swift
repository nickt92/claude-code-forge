import SwiftUI

struct QualityGauge: View {
    let lineCount: Int?
    let imperativeRatio: Int?
    let lengthAssessment: String

    @State private var animatedRatio: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let ratio = imperativeRatio {
                HStack(spacing: 16) {
                    // Semi-circular gauge
                    ZStack {
                        Circle()
                            .trim(from: 0.25, to: 0.75)
                            .stroke(.quaternary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        Circle()
                            .trim(from: 0.25, to: 0.25 + animatedRatio * 0.5)
                            .stroke(ratioColor(ratio), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        VStack(spacing: 0) {
                            Text("\(ratio)%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("imperative")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                        .offset(y: 4)
                    }
                    .frame(width: 60, height: 60)
                    .onAppear {
                        withAnimation(ForgeTheme.Animations.springBouncy) {
                            animatedRatio = CGFloat(ratio) / 100
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let count = lineCount {
                            HStack(spacing: 4) {
                                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text("\(count) lines")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        Text(lengthAssessment.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let count = lineCount {
                HStack(spacing: 4) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(count) lines (\(lengthAssessment))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ratioColor(_ ratio: Int) -> Color {
        switch ratio {
        case 80...100: return .green
        case 60..<80: return ForgeTheme.Colors.forgeOrange
        default: return .red
        }
    }
}
