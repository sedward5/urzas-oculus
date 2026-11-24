import XCTest
@testable import UrzasOculusCore

final class CardEvaluationEngineTests: XCTestCase {
    func testSuggestsStructuralRolesWithoutAssigningStrength() {
        let card = CardRecord(
            id: "printing-1",
            oracleID: "oracle-1",
            name: "Example Removal",
            setCode: "TRK",
            manaCost: "{1}{B}",
            manaValue: 2,
            typeLine: "Instant",
            oracleText: "Destroy target creature.",
            colors: ["B"],
            colorIdentity: ["B"]
        )

        let result = CardEvaluationEngine.evaluate(card: card)

        XCTAssertEqual(result.engineVersion, "1.0.0")
        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.scryfallID, "printing-1")
        XCTAssertEqual(result.oracleID, "oracle-1")
        XCTAssertTrue(result.suggestions.contains { $0.role == .removal })
        XCTAssertTrue(result.suggestions.contains { $0.role == .interaction })
        XCTAssertFalse(result.suggestions.contains { $0.role == .twoForOne })
        XCTAssertNil(result.confirmedReview)
    }

    func testDetectsMultipleIndependentStructuralSuggestions() {
        let card = CardRecord(
            id: "printing-2",
            name: "Flexible Engine",
            setCode: "TRK",
            typeLine: "Creature — Artificer",
            oracleText: "Choose one — Draw two cards; or create a 1/1 token. Add {U}.",
            colors: ["U"],
            colorIdentity: ["U"]
        )

        let roles = Set(CardEvaluationEngine.evaluate(card: card).suggestions.map(\.role))

        XCTAssertTrue(roles.contains(.modal))
        XCTAssertTrue(roles.contains(.cardAdvantage))
        XCTAssertTrue(roles.contains(.tokenMaker))
        XCTAssertTrue(roles.contains(.ramp))
        XCTAssertTrue(roles.contains(.curveFiller))
    }

    func testCarriesHumanReviewWithoutMutatingIt() throws {
        let card = CardRecord(id: "printing-3", name: "Reviewed", setCode: "TRK")
        let evidence = EvaluationEvidence(
            kind: .structural,
            source: "Scryfall",
            reference: "printing-3",
            excerpt: "Destroy target creature.",
            note: "Targeted creature removal."
        )
        let review = CardEvaluationReview(
            modelVersion: "prediction-v1",
            scryfallID: "printing-3",
            oracleID: nil,
            setCode: "TRK",
            roles: [
                CardRoleAnnotation(
                    role: .removal,
                    confidence: .high,
                    evidence: [evidence],
                    rationale: "Clean creature removal."
                )
            ],
            baselinePower: CardDimensionAssessment(
                value: 4,
                confidence: .medium,
                evidence: [evidence],
                rationale: "Efficient interaction for its cost."
            ),
            rate: .aboveRate,
            rateRationale: "Answers most common creature threats at low cost.",
            reviewer: "reviewer",
            reviewedAt: "2026-11-23"
        )

        let result = CardEvaluationEngine.evaluate(card: card, review: review)
        XCTAssertEqual(result.confirmedReview, review)
        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CardEvaluationResult.self, from: encoded)
        XCTAssertEqual(decoded, result)
    }

    func testRejectsInvalidReviewDimensionsAndMissingEvidence() throws {
        let card = CardRecord(id: "printing-5", name: "Invalid", setCode: "TRK")
        let invalid = CardEvaluationReview(
            modelVersion: "prediction-v1",
            scryfallID: "printing-5",
            setCode: "TRK",
            baselinePower: CardDimensionAssessment(
                value: 6,
                confidence: .high,
                evidence: [],
                rationale: "Invalid scale."
            ),
            rate: .onRate,
            rateRationale: "Looks fine."
        )

        XCTAssertThrowsError(try CardEvaluationEngine.validate(review: invalid, for: card)) {
            XCTAssertEqual($0 as? CardEvaluationValidationError, .invalidDimension("baselinePower"))
        }

        let mismatched = CardEvaluationReview(
            modelVersion: "prediction-v1",
            scryfallID: "another-printing",
            setCode: "TRK"
        )
        XCTAssertThrowsError(try CardEvaluationEngine.validate(review: mismatched, for: card)) {
            XCTAssertEqual($0 as? CardEvaluationValidationError, .mismatchedCardIdentity)
        }
    }

    func testSuggestsSweeperAndGraveyardHateSeparately() {
        let card = CardRecord(
            id: "printing-6",
            name: "Clean the Board",
            setCode: "TRK",
            typeLine: "Sorcery",
            oracleText: "Destroy all creatures. Exile all cards from target player's graveyard."
        )

        let roles = Set(CardEvaluationEngine.evaluate(card: card).suggestions.map(\.role))
        XCTAssertTrue(roles.contains(.sweeper))
        XCTAssertTrue(roles.contains(.removal))
        XCTAssertTrue(roles.contains(.graveyardHate))
    }

    func testSuggestionsAreDeterministicAndSorted() {
        let card = CardRecord(
            id: "printing-4",
            name: "Utility",
            setCode: "TRK",
            typeLine: "Creature",
            oracleText: "Flying. When this enters, draw a card. Create a 1/1 token."
        )

        XCTAssertEqual(
            CardEvaluationEngine.evaluate(card: card),
            CardEvaluationEngine.evaluate(card: card)
        )
    }
}
