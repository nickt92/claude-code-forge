import Foundation

/// Persists the last successful `forge dashboard` JSON so the app can render
/// instantly on launch (stale-while-revalidate) instead of showing a scan wait.
/// Stores the raw CLI bytes — decoding stays the single concern of ForgeService.
public struct DashboardCache: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ForgeDesktop", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
        self.fileURL = base.appendingPathComponent("dashboard-cache.json")
    }

    public func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    public func save(_ data: Data) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
