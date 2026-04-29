import Foundation

extension String {
    /// Converts snake_case or kebab-case identifiers to a human-readable title.
    /// e.g. "missing_section" → "Missing Section", "tech-gap" → "Tech Gap"
    var formattedAsTitle: String {
        self.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
