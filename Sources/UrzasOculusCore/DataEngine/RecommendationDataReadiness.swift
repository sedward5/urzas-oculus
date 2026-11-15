import Foundation

/// The independently acquired components required for a complete 17Lands
/// recommendation dataset.
public enum DatasetComponentKind: String, Codable, CaseIterable, Sendable {
    case game
    case draft
}

/// Provenance for one successfully imported component of a logical dataset.
public struct DatasetComponentSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let datasetKey: String
    public let kind: DatasetComponentKind
    public let snapshotID: String
    public let sourceUpdatedAt: Date?
    public let importedAt: Date
    public let recordCount: Int

    public init(datasetKey: String, kind: DatasetComponentKind, snapshotID: String,
                sourceUpdatedAt: Date?, importedAt: Date, recordCount: Int) {
        self.datasetKey = datasetKey
        self.kind = kind
        self.snapshotID = snapshotID
        self.id = "\(datasetKey)|\(kind.rawValue)"
        self.sourceUpdatedAt = sourceUpdatedAt
        self.importedAt = importedAt
        self.recordCount = recordCount
    }
}

/// The logical identity against which recommendation data is evaluated.
public struct RecommendationDatasetRequest: Equatable, Sendable {
    public let setCode: String
    public let eventType: String
    public let userGroup: String
    public let colorFilter: String?

    public init(setCode: String, eventType: String = "PremierDraft",
                userGroup: String = "all", colorFilter: String? = nil) {
        self.setCode = setCode.uppercased()
        self.eventType = eventType
        self.userGroup = userGroup
        self.colorFilter = colorFilter?.uppercased()
    }

    public var datasetKey: String {
        "\(setCode):\(eventType):\(userGroup):\(colorFilter ?? "all")"
    }
}

public enum RecommendationReadinessIssue: Equatable, Sendable {
    case missingComponent(DatasetComponentKind)
    case emptyComponent(DatasetComponentKind)
    case staleComponent(DatasetComponentKind)
    case mismatchedSourceUpdate
    case mismatchedSnapshot
    case unknownSourceUpdate
    case unsupportedUserGroup(String)
}

/// A deterministic readiness result shared by local and batch callers.
public struct RecommendationDataReadiness: Equatable, Sendable {
    public let datasetKey: String
    public let components: [DatasetComponentKind: DatasetComponentSnapshot]
    public let issues: [RecommendationReadinessIssue]

    public var isReady: Bool { issues.isEmpty }

    public init(request: RecommendationDatasetRequest,
                components: [DatasetComponentSnapshot],
                now: Date = .now,
                maximumSourceAge: TimeInterval? = nil,
                maximumAcquisitionAge: TimeInterval? = nil) {
        datasetKey = request.datasetKey
        var indexed: [DatasetComponentKind: DatasetComponentSnapshot] = [:]
        for component in components where component.datasetKey == request.datasetKey {
            indexed[component.kind] = component
        }
        self.components = indexed

        var findings: [RecommendationReadinessIssue] = []
        if request.userGroup != "all" {
            findings.append(.unsupportedUserGroup(request.userGroup))
        }
        for kind in DatasetComponentKind.allCases {
            guard let component = indexed[kind] else {
                findings.append(.missingComponent(kind))
                continue
            }
            if component.recordCount <= 0 {
                findings.append(.emptyComponent(kind))
            }
            if let maximumSourceAge {
                guard let updatedAt = component.sourceUpdatedAt else {
                    findings.append(.unknownSourceUpdate)
                    continue
                }
                if now.timeIntervalSince(updatedAt) > maximumSourceAge {
                    findings.append(.staleComponent(kind))
                }
            }
            if let maximumAcquisitionAge,
               now.timeIntervalSince(component.importedAt) > maximumAcquisitionAge {
                findings.append(.staleComponent(kind))
            }
        }
        if let game = indexed[.game], let draft = indexed[.draft] {
            if game.snapshotID != draft.snapshotID {
                findings.append(.mismatchedSnapshot)
            }
            if let gameUpdate = game.sourceUpdatedAt, let draftUpdate = draft.sourceUpdatedAt {
                if gameUpdate != draftUpdate { findings.append(.mismatchedSourceUpdate) }
            } else {
                findings.append(.unknownSourceUpdate)
            }
        }
        issues = findings
    }
}


public extension LocalDataStore {
    /// Uses the same readiness evaluator for local app and headless batch callers.
    func recommendationReadiness(
        for request: RecommendationDatasetRequest,
        now: Date = .now,
        maximumSourceAge: TimeInterval? = nil,
        maximumAcquisitionAge: TimeInterval? = nil
    ) throws -> RecommendationDataReadiness {
        RecommendationDataReadiness(
            request: request,
            components: try components(datasetKey: request.datasetKey),
            now: now,
            maximumSourceAge: maximumSourceAge,
            maximumAcquisitionAge: maximumAcquisitionAge
        )
    }
}
