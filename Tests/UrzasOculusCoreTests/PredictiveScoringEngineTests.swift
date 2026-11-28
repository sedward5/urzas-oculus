import XCTest
@testable import UrzasOculusCore

final class PredictiveScoringEngineTests: XCTestCase {
    func testPredictiveScoreIsDeterministicAndIndependentOfRarity() {
        let common = CardRecord(
            id: "card-1", name: "Cheap Removal", setCode: "TRK",
            rarity: "common", manaValue: 2, typeLine: "Instant",
            oracleText: "Destroy target creature."
        )
        let mythic = CardRecord(
            id: "card-1", name: "Cheap Removal", setCode: "TRK",
            rarity: "mythic", manaValue: 2, typeLine: "Instant",
            oracleText: "Destroy target creature."
        )
        XCTAssertEqual(PredictiveScoringEngine.evaluate(card: common), PredictiveScoringEngine.evaluate(card: mythic))
        XCTAssertEqual(PredictiveScoringEngine.evaluate(card: common), PredictiveScoringEngine.evaluate(card: common))
    }

    func testReviewedArchetypeRelationshipsAreExplicitAndScoped() {
        let card = CardRecord(id: "card-2", name: "Engine", setCode: "HOB", oracleText: "Create a token.")
        let reviewed = PredictiveArchetypeRelationship(archetypeID: "goblins", role: "payoff", evidence: "Official guide relationship.")
        let unreviewed = PredictiveArchetypeRelationship(archetypeID: "elves", role: "payoff", reviewStatus: "candidate")
        let score = PredictiveScoringEngine.evaluate(card: card, relationships: [reviewed, unreviewed])
        XCTAssertEqual(score.archetypeFits.map(\.archetypeID), ["goblins"])
        XCTAssertEqual(score.archetypeFits.first?.value, 4)
        XCTAssertEqual(score.synergyPotential.value, 3)
    }

    func testNoAggregateGradeOr17LandsInputExists() {
        let card = CardRecord(id: "card-3", name: "Plain Bear", setCode: "TRK", manaValue: 2, typeLine: "Creature — Bear")
        let score = PredictiveScoringEngine.evaluate(card: card)
        XCTAssertEqual(score.modelVersion, "predictive-rules-0.1.0")
        XCTAssertEqual(score.baselinePower.value, 3)
        XCTAssertTrue(score.archetypeFits.isEmpty)
        XCTAssertEqual(score.limitations.count, 4)
    }
}
