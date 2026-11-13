import Foundation

/// Reconstructs authoritative draft state from an append-only event history.
///
/// Recognition systems may propose observations, but only events explicitly
/// appended to this engine affect draft state.
public struct DraftEngine {
    public private(set) var events: [DraftEvent]
    public private(set) var state: DraftState

    public init() {
        events = []
        state = DraftState()
    }

    /// Validates and applies one event. Failed events leave history and state unchanged.
    public mutating func append(_ event: DraftEvent) throws {
        var nextState = state
        try nextState.apply(event)
        events.append(event)
        state = nextState
    }

    /// Rebuilds state by replaying events in their original order.
    public static func replay(_ events: [DraftEvent]) throws -> DraftState {
        var state = DraftState()
        for event in events {
            try state.apply(event)
        }
        return state
    }
}

// MARK: - Event model

public struct DraftEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let occurredAt: Date
    public let payload: DraftEventPayload

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        occurredAt: Date = .now,
        payload: DraftEventPayload
    ) {
        self.id = id
        self.sessionID = sessionID
        self.occurredAt = occurredAt
        self.payload = payload
    }
}

public enum DraftEventPayload: Codable, Equatable, Sendable {
    case sessionStarted(DraftSession)
    case packObserved(PackObservation)
    case pickRecorded(PickRecord)
    case pickCorrected(PickCorrection)
}

public struct DraftSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let formatName: String?
    public let setCode: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        formatName: String? = nil,
        setCode: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.formatName = formatName
        self.setCode = setCode
    }
}

/// One explicit snapshot of the cards available at a draft position.
///
/// Card identifiers are opaque stable identifiers supplied by DataEngine.
/// This type deliberately does not depend on a particular card-data provider.
public struct PackObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let position: DraftPosition
    public let candidateCardIDs: [String]
    public let sourceObservationID: UUID?

    public init(
        id: UUID = UUID(),
        position: DraftPosition,
        candidateCardIDs: [String],
        sourceObservationID: UUID? = nil
    ) {
        self.id = id
        self.position = position
        self.candidateCardIDs = candidateCardIDs
        self.sourceObservationID = sourceObservationID
    }
}

public struct DraftPosition: Codable, Equatable, Hashable, Sendable {
    public let packNumber: Int
    public let pickNumber: Int

    public init(packNumber: Int, pickNumber: Int) {
        self.packNumber = packNumber
        self.pickNumber = pickNumber
    }
}

public struct PickRecord: Codable, Equatable, Sendable {
    public let packObservationID: UUID
    public let selectedCardID: String

    public init(packObservationID: UUID, selectedCardID: String) {
        self.packObservationID = packObservationID
        self.selectedCardID = selectedCardID
    }
}

/// A correction is a new event; it never rewrites the original pick event.
public struct PickCorrection: Codable, Equatable, Sendable {
    public let pickEventID: UUID
    public let replacementCardID: String
    public let reason: String?

    public init(
        pickEventID: UUID,
        replacementCardID: String,
        reason: String? = nil
    ) {
        self.pickEventID = pickEventID
        self.replacementCardID = replacementCardID
        self.reason = reason
    }
}

public struct DraftPick: Codable, Equatable, Identifiable, Sendable {
    /// The event that originally recorded this pick.
    public let id: UUID
    public let packObservationID: UUID
    public let position: DraftPosition
    public fileprivate(set) var selectedCardID: String
    public let selectedAt: Date

    fileprivate init(
        id: UUID,
        packObservationID: UUID,
        position: DraftPosition,
        selectedCardID: String,
        selectedAt: Date
    ) {
        self.id = id
        self.packObservationID = packObservationID
        self.position = position
        self.selectedCardID = selectedCardID
        self.selectedAt = selectedAt
    }
}

// MARK: - Reconstructed state

public struct DraftState: Codable, Equatable, Sendable {
    public private(set) var session: DraftSession?
    public private(set) var packObservations: [UUID: PackObservation]
    public private(set) var picks: [DraftPick]
    public private(set) var appliedEventIDs: Set<UUID>

    public var draftedCardIDs: [String] {
        picks.map(\.selectedCardID)
    }

    public var currentPosition: DraftPosition? {
        packObservations.values.max {
            if $0.position.packNumber != $1.position.packNumber {
                return $0.position.packNumber < $1.position.packNumber
            }
            return $0.position.pickNumber < $1.position.pickNumber
        }?.position
    }

    public var pendingPackObservation: PackObservation? {
        guard let latest = packObservations.values.first(where: {
            $0.position == currentPosition
        }) else {
            return nil
        }
        return picks.contains(where: { $0.packObservationID == latest.id }) ? nil : latest
    }

    fileprivate init() {
        session = nil
        packObservations = [:]
        picks = []
        appliedEventIDs = []
    }

    fileprivate mutating func apply(_ event: DraftEvent) throws {
        guard !appliedEventIDs.contains(event.id) else {
            throw DraftEngineError.duplicateEventID(event.id)
        }

        switch event.payload {
        case let .sessionStarted(newSession):
            guard session == nil, eventsAreEmpty else {
                throw DraftEngineError.sessionAlreadyStarted
            }
            guard newSession.id == event.sessionID else {
                throw DraftEngineError.sessionIDMismatch
            }
            session = newSession

        case let .packObserved(observation):
            try requireSession(event.sessionID)
            try validate(observation)
            guard !packObservations.values.contains(where: {
                $0.position == observation.position
            }) else {
                throw DraftEngineError.packPositionAlreadyObserved(observation.position)
            }
            guard observation.id != UUID() else {
                throw DraftEngineError.invalidObservation
            }
            guard nextExpectedPosition == observation.position else {
                throw DraftEngineError.unexpectedPackPosition(
                    expected: nextExpectedPosition,
                    received: observation.position
                )
            }
            packObservations[observation.id] = observation

        case let .pickRecorded(record):
            try requireSession(event.sessionID)
            guard let observation = packObservations[record.packObservationID] else {
                throw DraftEngineError.unknownPackObservation(record.packObservationID)
            }
            guard pendingPackObservation?.id == observation.id else {
                throw DraftEngineError.noPendingPick(observation.position)
            }
            guard observation.candidateCardIDs.contains(record.selectedCardID) else {
                throw DraftEngineError.selectedCardNotInPack(record.selectedCardID)
            }
            picks.append(
                DraftPick(
                    id: event.id,
                    packObservationID: observation.id,
                    position: observation.position,
                    selectedCardID: record.selectedCardID,
                    selectedAt: event.occurredAt
                )
            )

        case let .pickCorrected(correction):
            try requireSession(event.sessionID)
            guard let pickIndex = picks.firstIndex(where: { $0.id == correction.pickEventID }) else {
                throw DraftEngineError.unknownPickEvent(correction.pickEventID)
            }
            let pick = picks[pickIndex]
            guard let observation = packObservations[pick.packObservationID] else {
                throw DraftEngineError.unknownPackObservation(pick.packObservationID)
            }
            guard observation.candidateCardIDs.contains(correction.replacementCardID) else {
                throw DraftEngineError.correctedCardNotInPack(correction.replacementCardID)
            }
            picks[pickIndex].selectedCardID = correction.replacementCardID
        }

        appliedEventIDs.insert(event.id)
    }

    private var eventsAreEmpty: Bool {
        appliedEventIDs.isEmpty
    }

    private var nextExpectedPosition: DraftPosition {
        guard let previous = picks.last?.position else {
            return DraftPosition(packNumber: 1, pickNumber: 1)
        }

        // Pack size is deliberately not hard-coded. A new pack begins at pick 1.
        return DraftPosition(
            packNumber: previous.packNumber,
            pickNumber: previous.pickNumber + 1
        )
    }

    private func requireSession(_ eventSessionID: UUID) throws {
        guard let session else {
            throw DraftEngineError.sessionNotStarted
        }
        guard session.id == eventSessionID else {
            throw DraftEngineError.sessionIDMismatch
        }
    }

    private func validate(_ observation: PackObservation) throws {
        guard observation.position.packNumber > 0,
              observation.position.pickNumber > 0,
              !observation.candidateCardIDs.isEmpty,
              observation.candidateCardIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(observation.candidateCardIDs).count == observation.candidateCardIDs.count else {
            throw DraftEngineError.invalidObservation
        }
    }
}

public enum DraftEngineError: Error, Equatable {
    case duplicateEventID(UUID)
    case sessionAlreadyStarted
    case sessionNotStarted
    case sessionIDMismatch
    case invalidObservation
    case packPositionAlreadyObserved(DraftPosition)
    case unexpectedPackPosition(expected: DraftPosition, received: DraftPosition)
    case unknownPackObservation(UUID)
    case noPendingPick(DraftPosition)
    case selectedCardNotInPack(String)
    case unknownPickEvent(UUID)
    case correctedCardNotInPack(String)
}
