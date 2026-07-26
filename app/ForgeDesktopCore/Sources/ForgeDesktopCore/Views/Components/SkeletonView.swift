import SwiftUI

// MARK: - Shimmer Phase

/// One shared phase drives every skeleton in a group — a single TimelineView ancestor
/// instead of per-row repeatForever animations, which multiply compositor work.
/// `nil` phase = shimmer disabled (Reduce Motion or loading finished).
private struct ShimmerPhaseKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    fileprivate var shimmerPhase: Double? {
        get { self[ShimmerPhaseKey.self] }
        set { self[ShimmerPhaseKey.self] = newValue }
    }
}

/// Wrap skeleton placeholders in this container. It owns the single TimelineView
/// driving the shimmer; tearing the container down stops the animation.
struct SkeletonGroup<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: Content

    private static var period: Double { 1.4 }

    var body: some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let phase = elapsed.truncatingRemainder(dividingBy: Self.period) / Self.period
                content.environment(\.shimmerPhase, phase)
            }
        }
    }
}

// MARK: - Skeleton Primitives

struct SkeletonBox: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 4

    @Environment(\.shimmerPhase) private var phase

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.primary.opacity(0.07))
            .overlay(shimmerOverlay)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        if let phase {
            // Band sweeps left→right by sliding unit points; values outside 0...1 are valid.
            let x = phase * 3 - 1.5
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.25), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: UnitPoint(x: x - 0.5, y: 0.4),
                endPoint: UnitPoint(x: x + 0.5, y: 0.6)
            )
        }
    }
}

struct SkeletonCircle: View {
    var diameter: CGFloat

    var body: some View {
        SkeletonBox(width: diameter, height: diameter, radius: diameter / 2)
    }
}

// MARK: - Prebuilt Placeholders

/// Sidebar repo row placeholder: score ring + name/branch lines.
struct SkeletonRepoRow: View {
    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.sm + 2) {
            SkeletonCircle(diameter: 28)
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs + 1) {
                SkeletonBox(width: 110, height: 11)
                SkeletonBox(width: 70, height: 9)
            }
            Spacer()
        }
        .padding(.vertical, ForgeTheme.Spacing.xs)
    }
}

/// Global health card placeholder.
struct SkeletonHealthCard: View {
    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.md) {
            SkeletonCircle(diameter: 56)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBox(width: 120, height: 12)
                SkeletonBox(width: 90, height: 10)
                SkeletonBox(width: 140, height: 10)
            }
            Spacer()
        }
        .padding(ForgeTheme.Spacing.lg)
        .background(
            ForgeTheme.Colors.surface,
            in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
                .stroke(.quaternary)
        )
    }
}

/// Doctor check-row placeholder.
struct SkeletonCheckRow: View {
    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.sm + 2) {
            SkeletonCircle(diameter: 14)
            SkeletonBox(width: 180, height: 11)
            Spacer()
            SkeletonBox(width: 60, height: 10)
        }
        .padding(.vertical, 6)
    }
}

/// Detail card placeholder.
struct SkeletonDetailCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.md) {
            SkeletonBox(width: 110, height: 11)
            SkeletonBox(width: nil, height: 12)
            SkeletonBox(width: 220, height: 12)
        }
        .padding(ForgeTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ForgeTheme.Colors.surface,
            in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
                .stroke(.quaternary)
        )
    }
}

#Preview("Skeletons") {
    SkeletonGroup {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.lg) {
            SkeletonHealthCard()
            ForEach(0..<4, id: \.self) { _ in
                SkeletonRepoRow()
            }
            SkeletonDetailCard()
        }
    }
    .padding(ForgeTheme.Spacing.xl)
    .frame(width: 320)
}
