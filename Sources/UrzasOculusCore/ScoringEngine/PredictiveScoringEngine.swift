import Foundation

/// A source-backed relationship between a card and a named set archetype.
/// Only reviewed relationships are accepted as archetype-fit evidence.
public struct PredictiveArchetypeRelationship: Codable, Equatable, Sendable {
    public let archetypeID: String
    public let role: String
    public let reviewStatus: String
    public let evidence: String?

    public init(archetypeID: String, role: String, reviewStatus: String = "reviewed", evidence: String? = nil) {
        self.archetypeID = archetypeID
        self.role = role
        self.reviewStatus = reviewStatus
        self.evidence = evidence
    }
}

public struct PredictiveDimensionScore: Codable, Equatable, Sendable {
    public let value: Int
    public let confidence: EvaluationConfidence
    public let rationale: String
    public let featureIDs: [String]

    public init(value: Int, confidence: EvaluationConfidence, rationale: String, featureIDs: [String]) {
        self.value = value
        self.confidence = confidence
        self.rationale = rationale
        self.featureIDs = featureIDs
    }
}

public struct PredictiveArchetypeFit: Codable, Equatable, Sendable {
    public let archetypeID: String
    public let value: Int
    public let confidence: EvaluationConfidence
    public let evidence: String

    public init(archetypeID: String, value: Int, confidence: EvaluationConfidence, evidence: String) {
        self.archetypeID = archetypeID
        self.value = value
        self.confidence = confidence
        self.evidence = evidence
    }
}

/// Intrinsic, pre-17Lands card assessment. There is deliberately no aggregate grade:
/// the dimensions describe different properties and have no validated exchange rate.
public struct PredictiveCardScore: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let oracleID: String?
    public let cardName: String
    public let setCode: String
    public let modelVersion: String
    public let baselinePower: PredictiveDimensionScore
    public let roleValue: PredictiveDimensionScore
    public let synergyPotential: PredictiveDimensionScore
    public let archetypeFits: [PredictiveArchetypeFit]
    public let contextSensitivity: PredictiveDimensionScore
    public let roles: [CardRole]
    public let limitations: [String]

    public init(id: String, oracleID: String?, cardName: String, setCode: String, modelVersion: String,
                baselinePower: PredictiveDimensionScore, roleValue: PredictiveDimensionScore,
                synergyPotential: PredictiveDimensionScore, archetypeFits: [PredictiveArchetypeFit],
                contextSensitivity: PredictiveDimensionScore, roles: [CardRole], limitations: [String]) {
        self.id = id
        self.oracleID = oracleID
        self.cardName = cardName
        self.setCode = setCode
        self.modelVersion = modelVersion
        self.baselinePower = baselinePower
        self.roleValue = roleValue
        self.synergyPotential = synergyPotential
        self.archetypeFits = archetypeFits
        self.contextSensitivity = contextSensitivity
        self.roles = roles
        self.limitations = limitations
    }
}

/// First deterministic feature-rule model. It uses normalized Scryfall facts and
/// explicitly reviewed archetype relationships only. It never reads 17Lands data,
/// rarity, pick behavior, or game outcomes.
public enum PredictiveScoringEngine {
    public static let modelVersion = "predictive-rules-0.1.0"

    public static func evaluate(
        card: CardRecord,
        relationships: [PredictiveArchetypeRelationship] = []
    ) -> PredictiveCardScore {
        let text = ([card.oracleText] + card.cardFaces.map(\.oracleText))
            .compactMap { $0 }.joined(separator: "\n").lowercased()
        let typeLine = ([card.typeLine] + card.cardFaces.map(\.typeLine))
            .compactMap { $0 }.joined(separator: "\n").lowercased()
        let roles = CardEvaluationEngine.evaluate(card: card).suggestions.map(\.role)
        let roleSet = Set(roles)
        let manaValue = card.manaValue
        let creature = typeLine.contains("creature")
        let body = bestCreatureBody(card: card)
        let reviewed = relationships.filter { $0.reviewStatus == "reviewed" && !$0.archetypeID.isEmpty }
        let archetypeFits = Dictionary(grouping: reviewed, by: \.archetypeID).map { id, items in
            let roleNames = Set(items.map { $0.role.lowercased() })
            let strong = roleNames.contains("payoff") || roleNames.contains("signpost")
            let value = strong ? 4 : 3
            let evidence = items.compactMap(\.evidence).filter { !$0.isEmpty }.joined(separator: " ")
            return PredictiveArchetypeFit(
                archetypeID: id,
                value: value,
                confidence: .medium,
                evidence: evidence.isEmpty ? "Reviewed card-to-archetype relationship." : evidence
            )
        }.sorted { $0.archetypeID < $1.archetypeID }

        var power = 3
        var powerFeatures = ["baseline.neutral"]
        var powerNotes = ["Starts at the functional Limited baseline."]
        if creature, let manaValue, let body {
            if body >= manaValue * 2 + 1 {
                power = 4; powerFeatures.append("creature.body-above-cost")
                powerNotes.append("Printed power and toughness are above the model's simple mana-value body benchmark.")
            } else if body < manaValue * 2 {
                power = 2; powerFeatures.append("creature.body-below-cost")
                powerNotes.append("Printed body is below the simple mana-value benchmark; text may compensate.")
            } else {
                powerFeatures.append("creature.body-on-benchmark")
                powerNotes.append("Printed body is near the simple mana-value benchmark.")
            }
        } else if roleSet.contains(.removal), (manaValue ?? 99) <= 3 {
            power = 4; powerFeatures.append("spell.cheap-removal")
            powerNotes.append("Low-cost interaction is a meaningful standalone contribution.")
        } else if roleSet.contains(.cardAdvantage) || roleSet.contains(.sweeper) || roleSet.contains(.finisher) {
            power = 4; powerFeatures.append("spell.high-impact-effect")
            powerNotes.append("Rules text contains a high-impact Limited effect.")
        } else if (manaValue ?? 0) >= 6 && !roleSet.contains(.finisher) {
            power = 2; powerFeatures.append("cost.high-mana-value")
            powerNotes.append("High mana value without a detected closing role raises the opportunity cost.")
        }
        if card.keywords.contains(where: { ["flying", "menace", "deathtouch", "ward", "hexproof"].contains($0.lowercased()) }) {
            power = min(5, power + 1)
            powerFeatures.append("keyword.relevant-combat-or-resilience")
            powerNotes.append("A recognized evasion or resilience keyword improves the card's baseline contribution.")
        }

        let highValueRoles: Set<CardRole> = [.removal, .cardAdvantage, .ramp, .fixing, .evasion, .finisher, .sweeper, .recursion]
        let usefulRoleCount = roleSet.intersection(highValueRoles).count
        let roleValue = min(5, max(2, 2 + usefulRoleCount))
        let roleFeatures = roles.sorted { $0.rawValue < $1.rawValue }.map { "role.\($0.rawValue)" }
        let roleRationale = usefulRoleCount == 0
            ? "No high-value Limited role was confidently detected by the current structural rules."
            : "The structural rules detect \(usefulRoleCount) distinct high-value role(s); role quality and restrictions still need format review."

        let synergyRoles = reviewed.filter { ["enabler", "payoff", "supporting", "signpost"].contains($0.role.lowercased()) }
        let mechanicalSignals = ["artifact", "graveyard", "token", "second card", "sacrifice", "modified", "counter"]
            .filter { text.contains($0) }
        let synergyValue = min(5, 2 + min(2, synergyRoles.count) + (mechanicalSignals.count >= 2 ? 1 : 0))
        var synergyFeatures = synergyRoles.map { "relationship.\($0.role.lowercased())" }
        synergyFeatures += mechanicalSignals.map { "text.\($0.replacingOccurrences(of: " ", with: "-"))" }
        let synergyRationale = synergyRoles.isEmpty && mechanicalSignals.isEmpty
            ? "No reviewed archetype relationship or repeated mechanic signal was supplied."
            : "Synergy potential is supported by explicit reviewed relationships and/or repeated mechanic signals; actual deck density is not known."

        let conditionalTerms = ["if you", "whenever", "when you", "for each", "as long as", "unless", "choose one", "you may", "among"]
        let conditions = conditionalTerms.filter { text.contains($0) }
        let contextValue = min(5, 2 + min(3, conditions.count))
        let contextFeatures = conditions.map { "context.\($0.replacingOccurrences(of: " ", with: "-"))" }
        let contextRationale = conditions.isEmpty
            ? "Few explicit conditional phrases were detected; actual matchup and deck context can still matter."
            : "Rules text contains \(conditions.count) conditional or choice signal(s), so realized value is more context-sensitive."

        return PredictiveCardScore(
            id: card.id,
            oracleID: card.oracleID,
            cardName: card.name,
            setCode: card.setCode,
            modelVersion: modelVersion,
            baselinePower: PredictiveDimensionScore(value: power, confidence: .low, rationale: powerNotes.joined(separator: " "), featureIDs: powerFeatures),
            roleValue: PredictiveDimensionScore(value: roleValue, confidence: .low, rationale: roleRationale, featureIDs: roleFeatures),
            synergyPotential: PredictiveDimensionScore(value: synergyValue, confidence: .low, rationale: synergyRationale, featureIDs: synergyFeatures),
            archetypeFits: archetypeFits,
            contextSensitivity: PredictiveDimensionScore(value: contextValue, confidence: .low, rationale: contextRationale, featureIDs: contextFeatures),
            roles: roles.sorted { $0.rawValue < $1.rawValue },
            limitations: [
                "Experimental rule model; ordinal dimensions are not a pick score or probability.",
                "Creature body benchmark is intentionally simple and does not understand combat math or format-specific removal.",
                "Archetype fit is absent unless reviewed relationships are explicitly supplied.",
                "Set speed, curve demand, deck composition, and draft state are not modeled yet."
            ]
        )
    }

    private static func bestCreatureBody(card: CardRecord) -> Double? {
        let faces = card.cardFaces
        var topLevel: Double?
        if let powerText = card.power, let toughnessText = card.toughness,
           let power = Double(powerText), let toughness = Double(toughnessText) {
            topLevel = power + toughness
        }
        let stats = faces.compactMap { face -> Double? in
            guard let power = face.power.flatMap(Double.init),
                  let toughness = face.toughness.flatMap(Double.init) else { return nil }
            return power + toughness
        }
        var allStats = stats
        if let topLevel { allStats.append(topLevel) }
        return allStats.max()
    }
}
