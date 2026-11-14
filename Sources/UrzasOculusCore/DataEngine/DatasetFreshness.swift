import Foundation

/// A point-in-time view of how old a local dataset acquisition is and how
/// old the upstream source data was when it was acquired.
public struct DatasetFreshness: Equatable, Sendable {
    /// Time elapsed since this copy was imported on this device.
    public let acquisitionAge: TimeInterval

    /// Time elapsed since the source last published/updated the dataset.
    /// Nil means the source did not provide a trustworthy update timestamp.
    public let sourceDataAge: TimeInterval?

    public init(snapshot: DatasetSnapshot, now: Date = .now) {
        acquisitionAge = max(0, now.timeIntervalSince(snapshot.importedAt))
        sourceDataAge = snapshot.sourceUpdatedAt.map {
            max(0, now.timeIntervalSince($0))
        }
    }

    public var acquisitionAgeDays: Double {
        acquisitionAge / 86_400
    }

    public var sourceDataAgeDays: Double? {
        sourceDataAge.map { $0 / 86_400 }
    }
}

public extension DatasetSnapshot {
    /// Freshness is deliberately descriptive rather than a hard-coded
    /// stale/fresh judgment. Set activity and update cadence vary over time.
    func freshness(at now: Date = .now) -> DatasetFreshness {
        DatasetFreshness(snapshot: self, now: now)
    }
}
