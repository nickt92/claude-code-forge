import SwiftUI

public enum ForgeTheme {
    public enum Colors {
        public static let forgeOrange = Color(red: 0.902, green: 0.494, blue: 0.133)
        public static let forgeAmber = Color(red: 0.937, green: 0.604, blue: 0.157)
        public static let forgeDark = Color(red: 0.169, green: 0.122, blue: 0.075)
        public static let forgeGlow = Color(red: 1.0, green: 0.647, blue: 0.0)
    }

    public enum Gradients {
        public static let forge = LinearGradient(
            colors: [Colors.forgeOrange, Colors.forgeAmber],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        public static let subtleBg = LinearGradient(
            colors: [Colors.forgeOrange.opacity(0.06), Color.clear],
            startPoint: .top, endPoint: .bottom
        )
    }

    public enum Animations {
        public static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.7)
        public static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.6)
        public static let easeReveal = Animation.easeOut(duration: 0.4)
        public static let staggerDelay: Double = 0.05
    }

    public enum Metrics {
        public static let cardRadius: CGFloat = 10
        public static let chipRadius: CGFloat = 6
        public static let spacing: CGFloat = 8
    }
}
