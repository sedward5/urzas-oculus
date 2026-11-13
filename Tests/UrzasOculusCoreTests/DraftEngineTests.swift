import XCTest
@testable import UrzasOculusCore

final class DraftEngineTests: XCTestCase {
    func testStartsSessionAndRecordsPackAndPick() throws {
        var engine = DraftEngine()
        let session = DraftSession(formatName: "Quick Draft", setCode: "TST")
        try engine.append(startEvent(for: session))

        let observation = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 1),
            candidateCardIDs: ["card-a", "card-b", "card-c"]
        )
        try engine.append(event(for: session, payload: .packObserved(observation)))
        let pickEvent = event(
            for: session,
            payload: .pickRecorded(
                PickRecord(packObservationID: observation.id, selectedCardID: "card-b")
            )
        )
        try engine.append(pickEvent)

        XCTAssertEqual(engine.state.session, session)
        XCTAssertEqual(engine.state.draftedCardIDs, ["card-b"])
        XCTAssertEqual(engine.state.picks.first?.id, pickEvent.id)
        XCTAssertNil(engine.state.pendingPackObservation)
    }

    func testReplayReconstructsSameState() throws {
        let session = DraftSession(setCode: "TST")
        let observation = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 1),
            candidateCardIDs: ["card-a", "card-b"]
        )
        let events = [
            startEvent(for: session),
            event(for: session, payload: .packObserved(observation)),
            event(
                for: session,
                payload: .pickRecorded(
                    PickRecord(packObservationID: observation.id, selectedCardID: "card-a")
                )
            )
        ]

        var engine = DraftEngine()
        for event in events {
            try engine.append(event)
        }

        XCTAssertEqual(try DraftEngine.replay(events), engine.state)
    }

    func testCorrectionAppendsEventAndChangesEffectivePool() throws {
        let session = DraftSession()
        let observation = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 1),
            candidateCardIDs: ["card-a", "card-b"]
        )
        let pickEvent = event(
            for: session,
            payload: .pickRecorded(
                PickRecord(packObservationID: observation.id, selectedCardID: "card-a")
            )
        )
        let correction = event(
            for: session,
            payload: .pickCorrected(
                PickCorrection(
                    pickEventID: pickEvent.id,
                    replacementCardID: "card-b",
                    reason: "Corrected after reviewing the pack"
                )
            )
        )

        var engine = DraftEngine()
        try engine.append(startEvent(for: session))
        try engine.append(event(for: session, payload: .packObserved(observation)))
        try engine.append(pickEvent)
        try engine.append(correction)

        XCTAssertEqual(engine.events.count, 4)
        XCTAssertEqual(engine.events[2], pickEvent)
        XCTAssertEqual(engine.state.draftedCardIDs, ["card-b"])
    }

    func testRejectsPickNotPresentInObservedPack() throws {
        let session = DraftSession()
        let observation = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 1),
            candidateCardIDs: ["card-a"]
        )
        var engine = DraftEngine()
        try engine.append(startEvent(for: session))
        try engine.append(event(for: session, payload: .packObserved(observation)))

        XCTAssertThrowsError(
            try engine.append(
                event(
                    for: session,
                    payload: .pickRecorded(
                        PickRecord(packObservationID: observation.id, selectedCardID: "card-b")
                    )
                )
            )
        )
        XCTAssertEqual(engine.events.count, 2)
        XCTAssertTrue(engine.state.draftedCardIDs.isEmpty)
    }

    func testRejectsObservationBeforeSessionStarts() {
        let session = DraftSession()
        let observation = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 1),
            candidateCardIDs: ["card-a"]
        )
        var engine = DraftEngine()

        XCTAssertThrowsError(
            try engine.append(event(for: session, payload: .packObserved(observation)))
        )
        XCTAssertTrue(engine.events.isEmpty)
    }

    func testRequiresPickBeforeNextPackObservation() throws {
        let session = DraftSession()
        let first = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 1),
            candidateCardIDs: ["card-a"]
        )
        let second = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 2),
            candidateCardIDs: ["card-b"]
        )
        var engine = DraftEngine()
        try engine.append(startEvent(for: session))
        try engine.append(event(for: session, payload: .packObserved(first)))

        XCTAssertThrowsError(
            try engine.append(event(for: session, payload: .packObserved(second)))
        )
    }

    func testAdvancesPickAndPackPositions() throws {
        let session = DraftSession()
        var engine = DraftEngine()
        try engine.append(startEvent(for: session))

        let first = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 1),
            candidateCardIDs: ["card-a"]
        )
        try engine.append(event(for: session, payload: .packObserved(first)))
        try engine.append(
            event(
                for: session,
                payload: .pickRecorded(
                    PickRecord(packObservationID: first.id, selectedCardID: "card-a")
                )
            )
        )

        let second = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 2),
            candidateCardIDs: ["card-b"]
        )
        try engine.append(event(for: session, payload: .packObserved(second)))
        try engine.append(
            event(
                for: session,
                payload: .pickRecorded(
                    PickRecord(packObservationID: second.id, selectedCardID: "card-b")
                )
            )
        )

        let nextPack = PackObservation(
            position: DraftPosition(packNumber: 2, pickNumber: 1),
            candidateCardIDs: ["card-c"]
        )
        try engine.append(event(for: session, payload: .packObserved(nextPack)))

        XCTAssertEqual(engine.state.currentPosition, nextPack.position)
        XCTAssertEqual(engine.state.draftedCardIDs, ["card-a", "card-b"])
        XCTAssertEqual(engine.state.pendingPackObservation?.id, nextPack.id)
    }

    func testRejectsCorrectionToCardNotInOriginalPack() throws {
        let session = DraftSession()
        let observation = PackObservation(
            position: DraftPosition(packNumber: 1, pickNumber: 1),
            candidateCardIDs: ["card-a", "card-b"]
        )
        let pickEvent = event(
            for: session,
            payload: .pickRecorded(
                PickRecord(packObservationID: observation.id, selectedCardID: "card-a")
            )
        )
        var engine = DraftEngine()
        try engine.append(startEvent(for: session))
        try engine.append(event(for: session, payload: .packObserved(observation)))
        try engine.append(pickEvent)

        XCTAssertThrowsError(
            try engine.append(
                event(
                    for: session,
                    payload: .pickCorrected(
                        PickCorrection(pickEventID: pickEvent.id, replacementCardID: "card-c")
                    )
                )
            )
        )
        XCTAssertEqual(engine.state.draftedCardIDs, ["card-a"])
    }

    func testRejectsDuplicateEventID() throws {
        let session = DraftSession()
        let start = startEvent(for: session)
        var engine = DraftEngine()
        try engine.append(start)

        XCTAssertThrowsError(try engine.append(start))
        XCTAssertEqual(engine.events, [start])
    }

    private func startEvent(for session: DraftSession) -> DraftEvent {
        DraftEvent(sessionID: session.id, payload: .sessionStarted(session))
    }

    private func event(
        for session: DraftSession,
        payload: DraftEventPayload
    ) -> DraftEvent {
        DraftEvent(sessionID: session.id, payload: payload)
    }
}
