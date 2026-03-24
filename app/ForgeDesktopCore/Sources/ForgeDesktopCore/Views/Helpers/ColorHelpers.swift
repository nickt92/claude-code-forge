import SwiftUI

public func scoreColor(_ score: Int) -> Color {
    switch score {
    case 90...100: return .green
    case 70..<90: return .yellow
    case 50..<70: return .orange
    default: return .red
    }
}

public func severityColor(_ severity: String) -> Color {
    switch severity {
    case "error": return .red
    case "warn": return .orange
    case "info": return .blue
    default: return .secondary
    }
}
