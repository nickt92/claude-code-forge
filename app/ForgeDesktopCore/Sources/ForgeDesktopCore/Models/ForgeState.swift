import Foundation
import SwiftUI

@MainActor
@Observable
public final class ForgeState {
    public var loadState: LoadState = .idle
    public var forgePath: String?

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

    public init() {}
}
