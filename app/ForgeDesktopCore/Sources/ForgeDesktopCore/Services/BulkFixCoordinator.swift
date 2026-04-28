import Foundation
import SwiftUI

/// Coordinates bulk fix operations: running fixes sequentially, tracking progress,
/// and managing the review queue for pending changes.
@Observable
@MainActor
public final class BulkFixCoordinator {
    var bulkFixState: BulkFixState?
    var reviewQueue: [(finding: Finding, before: String, after: String)] = []
    var currentReview: (finding: Finding, before: String, after: String)?
    var showReview = false
    var totalPendingReviews: Int = 0
    var completedReviews: Int = 0

    private let fixService: FixService
    private let dismissalService: DismissalService

    public init(fixService: FixService, dismissalService: DismissalService) {
        self.fixService = fixService
        self.dismissalService = dismissalService
    }

    var isRunning: Bool { bulkFixState != nil }
    var isReviewing: Bool { totalPendingReviews > 0 && currentReview != nil }

    func handleStreamEvent(_ event: ClaudeStreamEvent) {
        switch event {
        case .toolUse(let name, let input):
            bulkFixState?.currentActivities.append(ToolActivity(name: name, input: input))
        case .toolResult(let name, _):
            if let idx = bulkFixState?.currentActivities.lastIndex(where: { $0.name == name && !$0.isComplete }) {
                bulkFixState?.currentActivities[idx].isComplete = true
            }
        default:
            break
        }
    }

    func runBulkFix(
        findings: [Finding],
        repoPath: String,
        claudeMdPath: String?,
        contentHashAtLoad: String?,
        onDismissed: @escaping (String) -> Void,
        onContentChanged: @escaping () -> Void,
        onRefresh: @escaping () async -> Void
    ) {
        let state = BulkFixState(total: findings.count)
        bulkFixState = state

        Task {
            for (index, finding) in findings.enumerated() {
                bulkFixState?.currentIndex = index
                bulkFixState?.currentFinding = finding.detail
                bulkFixState?.currentActivities = []

                let usesClaudeFix = ["missing_section", "tech_gap", "low_coverage"].contains(finding.code)

                do {
                    let result = try await fixService.fix(
                        finding: finding,
                        repoPath: repoPath,
                        claudeMdPath: claudeMdPath,
                        contentHashAtLoad: contentHashAtLoad,
                        onEvent: usesClaudeFix ? handleStreamEvent : nil
                    )

                    switch result {
                    case .success:
                        bulkFixState?.completedCount += 1
                        onDismissed(finding.id)
                        onContentChanged()
                    case .pendingReview(let before, let after):
                        reviewQueue.append((finding: finding, before: before, after: after))
                        bulkFixState?.completedCount += 1
                        onContentChanged()
                    default:
                        bulkFixState?.failedFinding = finding.detail
                        break
                    }
                } catch {
                    bulkFixState?.failedFinding = finding.detail
                    break
                }

                if bulkFixState?.failedFinding != nil { break }
            }

            bulkFixState = nil

            if !reviewQueue.isEmpty {
                totalPendingReviews = reviewQueue.count
                completedReviews = 0
                currentReview = reviewQueue.removeFirst()
                showReview = true
            } else {
                await onRefresh()
            }
        }
    }

    func handleReviewApprove(
        afterContent: String,
        finding: Finding,
        repoPath: String,
        claudeMdPath: String?,
        onDismissed: @escaping (String) -> Void,
        onContentChanged: @escaping () -> Void,
        onRefresh: @escaping () async -> Void
    ) {
        showReview = false
        guard let mdPath = claudeMdPath else {
            advanceReview(onRefresh: onRefresh)
            return
        }
        do {
            let consistent = try fixService.approveChange(mdPath: mdPath, expectedAfterContent: afterContent)
            if consistent {
                onDismissed(finding.id)
                onContentChanged()
            }
        } catch {
            // Approval failed — the file remains as-is on disk
        }
        advanceReview(onRefresh: onRefresh)
    }

    func handleReviewReject(
        beforeContent: String,
        claudeMdPath: String?,
        onContentChanged: @escaping () -> Void,
        onRefresh: @escaping () async -> Void
    ) {
        showReview = false
        guard let mdPath = claudeMdPath else {
            advanceReview(onRefresh: onRefresh)
            return
        }
        try? fixService.rejectChange(mdPath: mdPath, originalContent: beforeContent)
        onContentChanged()
        advanceReview(onRefresh: onRefresh)
    }

    private func advanceReview(onRefresh: @escaping () async -> Void) {
        completedReviews += 1
        if reviewQueue.isEmpty {
            currentReview = nil
            totalPendingReviews = 0
            completedReviews = 0
            Task { await onRefresh() }
        } else {
            currentReview = reviewQueue.removeFirst()
            showReview = true
        }
    }
}
