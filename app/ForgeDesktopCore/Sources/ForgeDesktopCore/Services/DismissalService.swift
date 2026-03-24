import Foundation
import CryptoKit

public final class DismissalService: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isDismissed(repoPath: String, findingId: String) -> Bool {
        dismissedIds(for: repoPath).contains(findingId)
    }

    public func dismiss(repoPath: String, findingId: String) {
        var ids = dismissedIds(for: repoPath)
        ids.insert(findingId)
        save(ids: ids, for: repoPath)
    }

    public func undismiss(repoPath: String, findingId: String) {
        var ids = dismissedIds(for: repoPath)
        ids.remove(findingId)
        save(ids: ids, for: repoPath)
    }

    public func dismissedIds(for repoPath: String) -> Set<String> {
        let key = storageKey(for: repoPath)
        let array = defaults.stringArray(forKey: key) ?? []
        return Set(array)
    }

    public func dismissAll(repoPath: String, findingIds: [String]) {
        var ids = dismissedIds(for: repoPath)
        for id in findingIds {
            ids.insert(id)
        }
        save(ids: ids, for: repoPath)
    }

    private func save(ids: Set<String>, for repoPath: String) {
        let key = storageKey(for: repoPath)
        defaults.set(Array(ids), forKey: key)
    }

    private func storageKey(for repoPath: String) -> String {
        let hash = SHA256.hash(data: Data(repoPath.utf8))
        let prefix = hash.prefix(6).map { String(format: "%02x", $0) }.joined()
        return "dismissedFindings.\(prefix)"
    }
}
