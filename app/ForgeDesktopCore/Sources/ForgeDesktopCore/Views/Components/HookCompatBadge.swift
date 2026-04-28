import SwiftUI

struct HookCompatBadge: View {
    let hookCompat: HookCompatInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Hook Compatibility")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 5) {
                ForEach(hookCompat.installed, id: \.self) { hook in
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                        Text(hook)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.1), in: Capsule())
                    .foregroundStyle(.green)
                }

                ForEach(hookCompat.missing, id: \.self) { hook in
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text(hook)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ForgeTheme.Colors.forgeOrange.opacity(0.12), in: Capsule())
                    .foregroundStyle(ForgeTheme.Colors.forgeOrange)
                }
            }
        }
        .accessibilityLabel("\(hookCompat.installed.count) hooks installed, \(hookCompat.missing.count) missing: \(hookCompat.missing.joined(separator: ", "))")
    }
}
