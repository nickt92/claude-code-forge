import Foundation
import SwiftUI

@MainActor
@Observable
public final class ForgeState {
    public var loadState: LoadState = .idle {
        didSet { refreshSelectedRepoCache() }
    }
    public var forgePath: String?
    public var setupPhase: SetupPhase = .complete
    public var doctorResult: DoctorResult?
    public var doctorLoading: Bool = false
    public var claudeAvailable: Bool = false
    /// Latest `forge status --json`, refreshed alongside the dashboard.
    /// Drives the "update ready to install" affordances.
    public var forgeStatus: ForgeStatus?
    /// Single source of truth for the doctor sheet — previously duplicated across
    /// ForgeApp and DashboardView, which could race two sheets.
    public var showDoctor: Bool = false

    /// Sidebar selection, owned here so the menu bar can deep-link into the dashboard.
    public var selectedRepoPath: String? {
        didSet { refreshSelectedRepoCache() }
    }

    /// Last resolved selection, served while `loadState` is not `.loaded` so the
    /// detail pane doesn't flicker during re-audits. Updated only from property
    /// observers — never during view body evaluation.
    @ObservationIgnored private var cachedSelectedRepo: RepoData?

    /// The selected repo derived from the latest dashboard data. Pure read:
    /// falls back to the cached value while loading.
    public var selectedRepo: RepoData? {
        guard let path = selectedRepoPath else { return nil }
        if case .loaded(let data) = loadState {
            return data.repos.first { $0.path == path }
        }
        return cachedSelectedRepo
    }

    private func refreshSelectedRepoCache() {
        guard case .loaded(let data) = loadState, let path = selectedRepoPath else { return }
        if let repo = data.repos.first(where: { $0.path == path }) {
            cachedSelectedRepo = repo
        }
    }

    public var dashboard: DashboardData? {
        if case .loaded(let data) = loadState { return data }
        return nil
    }

    public var error: ForgeError? {
        if case .failed(let error) = loadState { return error }
        return nil
    }

    /// True while a background refresh runs behind already-rendered (cached or
    /// stale) data — the stale-while-revalidate path. Distinct from `.loading`,
    /// which means there is nothing to show yet.
    public var isRefreshing: Bool = false

    /// Set when a background refresh fails while cached data is on screen, so the
    /// failure is surfaced without discarding a usable dashboard.
    public var refreshError: String?

    public var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    /// Any load activity — used to disable refresh controls.
    public var isBusy: Bool { isLoading || isRefreshing }

    public enum LoadState: Sendable {
        case idle
        case loading
        case loaded(DashboardData)
        case failed(ForgeError)
    }

    public enum SetupPhase: Sendable {
        case detectCLI
        case detectClaude
        case configurePermissions
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
