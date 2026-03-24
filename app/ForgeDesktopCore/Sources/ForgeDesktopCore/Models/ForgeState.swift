import Foundation
import SwiftUI

@MainActor
@Observable
public final class ForgeState {
    public var loadState: LoadState = .idle
    public var forgePath: String?
    public var setupPhase: SetupPhase = .complete
    public var doctorResult: DoctorResult?
    public var doctorLoading: Bool = false
    public var claudeAvailable: Bool = false

    public var dashboard: DashboardData? {
        if case .loaded(let data) = loadState { return data }
        return nil
    }

    public var error: ForgeError? {
        if case .failed(let error) = loadState { return error }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    public enum LoadState: Sendable {
        case idle
        case loading
        case loaded(DashboardData)
        case failed(ForgeError)
    }

    public enum SetupPhase: Sendable {
        case detectCLI
        case detectClaude
        case setScanPath
        case initialLoad
        case complete
    }

    public func updateRepo(path: String, audit: AuditData) {
        guard case .loaded(let data) = loadState else { return }
        var repos = data.repos
        if let idx = repos.firstIndex(where: { $0.path == path }) {
            repos[idx] = repos[idx].withUpdatedAudit(audit)
            let updated = DashboardData(
                schemaVersion: data.schemaVersion,
                global: data.global,
                globalScore: data.globalScore,
                repos: repos,
                generatedAt: data.generatedAt
            )
            loadState = .loaded(updated)
        }
    }

    public init() {}
}
