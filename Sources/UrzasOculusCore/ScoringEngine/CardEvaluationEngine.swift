import Foundation

/// A functional role a card may fill. Cards may have multiple roles.
public enum CardRole: String, Codable, CaseIterable, Equatable, Sendable {
    case removal
    case interaction
    case enabler
    case payoff
    case buildAround
    case cardAdvantage
    case twoForOne
    case modal
    case ramp
    case fixing
    case curveFiller
    case evasion
    case combatTrick
    case resilientThreat
    case finisher
    case sweeper
    case recursion
    case tokenMaker
    case sacrificeOutlet
    case graveyardHate
    case artifactHate
    case lifegain
}

/// The kind of source supporting a classification or assessment.
public enum EvaluationEvidenceKind: String, Codable, CaseIterable, Sendable {
    case structural
    case official
    case expert
    case observational
    case inferred
}

/// Confidence describes certainty in an assessment, not card strength.
public enum EvaluationConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

/// An ordinal, dimension-specific assessment. No aggregate grade is calculated.
public struct CardDimensionAssessment: Codable, Equatable, Sendable {
    public let value: Int?
    public let confidence: EvaluationConfidence
    public let evidence: [EvaluationEvidence]
    public let rationale: String

    public init(value: Int?, confidence: EvaluationConfidence, evidence: [EvaluationEvidence], rationale: String) {
        self.value = value
        self.confidence = confidence
        self.evidence = evidence
        self.rationale = rationale
    }
}

/// A per-archetype fit assessment; one card may fit multiple archetypes differently.
public struct CardArchetypeFitAssessment: Codable, Equatable, Sendable {
    public let archetypeID: String
    public let value: Int
    public let confidence: EvaluationConfidence
    public let evidence: [EvaluationEvidence]
    public let rationale: String

    public init(archetypeID: String, value: Int, confidence: EvaluationConfidence,
                evidence: [EvaluationEvidence], rationale: String) {
        self.archetypeID = archetypeID
        self.value = value
        self.confidence = confidence
        self.evidence = evidence
        self.rationale = rationale
    }
}

/// A traceable evidence item. References should point to source records or review artifacts.
public struct EvaluationEvidence: Codable, Equatable, Sendable {
    public let kind: EvaluationEvidenceKind
    public let source: String
    public let reference: String?
    public let excerpt: String?
    public let note: String

    public init(kind: EvaluationEvidenceKind, source: String, reference: String? = nil,
                excerpt: String? = nil, note: String) {
        self.kind = kind
        self.source = source
        self.reference = reference
        self.excerpt = excerpt
        self.note = note
    }
}

public enum RateAssessment: String, Codable, CaseIterable, Sendable {
    case belowRate
    case onRate
    case aboveRate
    case exceptional
    case contextDependent
    case insufficientEvidence
    case notApplicable
}

/// A reviewer-authored classification. Suggestions never become confirmed roles automatically.
public struct CardRoleAnnotation: Codable, Equatable, Sendable {
    public let role: CardRole
    public let confidence: EvaluationConfidence
    public let evidence: [EvaluationEvidence]
    public let rationale: String

    public init(role: CardRole, confidence: EvaluationConfidence, evidence: [EvaluationEvidence], rationale: String) {
        self.role = role
        self.confidence = confidence
        self.evidence = evidence
        self.rationale = rationale
    }
}

/// The editable, versioned human review record for one Scryfall printing.
public struct CardEvaluationReview: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let modelVersion: String
    public let scryfallID: String
    public let oracleID: String?
    public let setCode: String
    public let roles: [CardRoleAnnotation]
    public let baselinePower: CardDimensionAssessment?
    public let roleValue: CardDimensionAssessment?
    public let synergyPotential: CardDimensionAssessment?
    public let archetypeFits: [CardArchetypeFitAssessment]
    public let contextSensitivity: CardDimensionAssessment?
    public let rate: RateAssessment
    public let rateRationale: String
    public let reviewer: String?
    public let reviewedAt: String?

    public init(schemaVersion: Int = 1, modelVersion: String, scryfallID: String,
                oracleID: String? = nil, setCode: String, roles: [CardRoleAnnotation] = [],
                baselinePower: CardDimensionAssessment? = nil, roleValue: CardDimensionAssessment? = nil,
                synergyPotential: CardDimensionAssessment? = nil, archetypeFits: [CardArchetypeFitAssessment] = [],
                contextSensitivity: CardDimensionAssessment? = nil,
                rate: RateAssessment = .insufficientEvidence, rateRationale: String = "",
                reviewer: String? = nil, reviewedAt: String? = nil) {
        self.schemaVersion = schemaVersion
        self.modelVersion = modelVersion
        self.scryfallID = scryfallID
        self.oracleID = oracleID
        self.setCode = setCode.uppercased()
        self.roles = roles
        self.baselinePower = baselinePower
        self.roleValue = roleValue
        self.synergyPotential = synergyPotential
        self.archetypeFits = archetypeFits
        self.contextSensitivity = contextSensitivity
        self.rate = rate
        self.rateRationale = rateRationale
        self.reviewer = reviewer
        self.reviewedAt = reviewedAt
    }
}

public struct CardRoleSuggestion: Codable, Equatable, Sendable {
    public let role: CardRole
    public let ruleID: String
    public let rationale: String
    public let matchedText: String?

    public init(role: CardRole, ruleID: String, rationale: String, matchedText: String? = nil) {
        self.role = role
        self.ruleID = ruleID
        self.rationale = rationale
        self.matchedText = matchedText
    }
}

public struct CardEvaluationResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let engineVersion: String
    public let scryfallID: String
    public let oracleID: String?
    public let cardName: String
    public let setCode: String
    public let suggestions: [CardRoleSuggestion]
    public let confirmedReview: CardEvaluationReview?

    public init(schemaVersion: Int, engineVersion: String, scryfallID: String, oracleID: String?,
                cardName: String, setCode: String, suggestions: [CardRoleSuggestion],
                confirmedReview: CardEvaluationReview?) {
        self.schemaVersion = schemaVersion
        self.engineVersion = engineVersion
        self.scryfallID = scryfallID
        self.oracleID = oracleID
        self.cardName = cardName
        self.setCode = setCode
        self.suggestions = suggestions
        self.confirmedReview = confirmedReview
    }
}

public enum CardEvaluationValidationError: Error, Equatable {
    case mismatchedCardIdentity
    case unsupportedSchemaVersion
    case emptyModelVersion
    case duplicateRole(CardRole)
    case invalidDimension(String)
    case missingRoleRationale(CardRole)
    case missingRoleEvidence(CardRole)
    case missingRateRationale
}

/// Deterministic structural suggestions. This engine deliberately does not infer
/// strategic strength, archetype fit, or "on rate" from keywords alone.
public enum CardEvaluationEngine {
    public static let engineVersion = "1.0.0"
    public static let schemaVersion = 1

    public static func validate(review: CardEvaluationReview, for card: CardRecord) throws {
        guard review.schemaVersion == schemaVersion else {
            throw CardEvaluationValidationError.unsupportedSchemaVersion
        }
        guard !review.modelVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CardEvaluationValidationError.emptyModelVersion
        }
        guard review.scryfallID == card.id,
              review.oracleID == card.oracleID,
              review.setCode == card.setCode else {
            throw CardEvaluationValidationError.mismatchedCardIdentity
        }

        var seenRoles = Set<CardRole>()
        for annotation in review.roles {
            guard seenRoles.insert(annotation.role).inserted else {
                throw CardEvaluationValidationError.duplicateRole(annotation.role)
            }
            guard !annotation.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CardEvaluationValidationError.missingRoleRationale(annotation.role)
            }
            guard !annotation.evidence.isEmpty else {
                throw CardEvaluationValidationError.missingRoleEvidence(annotation.role)
            }
        }

        let dimensions: [(String, CardDimensionAssessment?)] = [
            ("baselinePower", review.baselinePower),
            ("roleValue", review.roleValue),
            ("synergyPotential", review.synergyPotential),
            ("contextSensitivity", review.contextSensitivity)
        ]
        for (name, assessment) in dimensions {
            guard let assessment else { continue }
            if let value = assessment.value, !(1...5).contains(value) {
                throw CardEvaluationValidationError.invalidDimension(name)
            }
            if assessment.value != nil &&
                (assessment.evidence.isEmpty || assessment.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                throw CardEvaluationValidationError.invalidDimension(name)
            }
        }

        var seenArchetypes = Set<String>()
        for assessment in review.archetypeFits {
            guard !assessment.archetypeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seenArchetypes.insert(assessment.archetypeID).inserted,
                  (1...5).contains(assessment.value),
                  !assessment.evidence.isEmpty,
                  !assessment.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CardEvaluationValidationError.invalidDimension("archetypeFits")
            }
        }

        if ![RateAssessment.insufficientEvidence, .notApplicable].contains(review.rate) &&
            review.rateRationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CardEvaluationValidationError.missingRateRationale
        }
    }

    public static func evaluate(card: CardRecord, review: CardEvaluationReview? = nil) -> CardEvaluationResult {
        let text = ([card.oracleText] + card.cardFaces.map(\.oracleText))
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
        let typeLine = ([card.typeLine] + card.cardFaces.map(\.typeLine))
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
        var suggestions: [CardRoleSuggestion] = []

        func add(_ role: CardRole, _ rule: String, _ rationale: String, _ match: String? = nil) {
            guard !suggestions.contains(where: { $0.role == role }) else { return }
            suggestions.append(CardRoleSuggestion(role: role, ruleID: rule, rationale: rationale, matchedText: match))
        }

        if containsAny(text, ["destroy target ", "exile target ", "return target creature to its owner's hand"]) {
            add(.removal, "rules.removal.targeted-destroy-exile-bounce", "Rules text contains a targeted destroy, exile, or bounce effect.")
            add(.interaction, "rules.interaction.targeted-answer", "Rules text contains a targeted answer to a game object.")
        }
        if containsAny(text, ["destroy all creatures", "exile all creatures", "destroy all artifacts", "destroy all enchantments"]) {
            add(.sweeper, "rules.sweeper.mass-destroy-exile", "Rules text affects all permanents or creatures of a class; symmetry and scope require review.")
            add(.removal, "rules.removal.mass-answer", "Rules text can remove multiple opposing permanents; symmetry and board impact require review.")
        }
        if containsAny(text, ["exile all cards from target player's graveyard", "exile all cards from all graveyards", "target player exiles their graveyard"]) {
            add(.graveyardHate, "rules.hate.graveyard", "Rules text removes cards from graveyards.")
        }
        if containsAny(text, ["destroy target artifact", "exile target artifact", "destroy target enchantment", "exile target enchantment"]) {
            add(.artifactHate, "rules.hate.artifact-or-enchantment", "Rules text specifically answers an artifact or enchantment; verify the relevant permanent type.")
            add(.interaction, "rules.interaction.permanent-type-answer", "Rules text answers a restricted permanent type.")
        }
        if text.contains("deals ") && text.contains(" damage to target ") {
            add(.removal, "rules.removal.targeted-damage", "Rules text contains damage directed at a target; effectiveness depends on damage amount and target restrictions.")
            add(.interaction, "rules.interaction.targeted-damage", "Rules text contains targeted damage interaction.")
        }
        if containsAny(text, ["counter target spell", "counter target activated ability", "counter target triggered ability"]) {
            add(.interaction, "rules.interaction.counter", "Rules text contains a counter effect.")
        }
        if containsAny(text, ["add {", "add one mana", "add two mana"]) {
            add(.ramp, "rules.ramp.mana-production", "Rules text appears to produce mana; restrictions and timing require review.")
        }
        if containsAny(text, ["search your library for a basic land", "search your library for a land card", "search your library for a basic land card"]) {
            add(.fixing, "rules.fixing.land-search", "Rules text searches for a land; whether it fixes colors depends on the searched land and timing.")
        }
        if containsAny(text, ["draw a card", "draw two cards", "draw three cards", "draw X cards"]) {
            add(.cardAdvantage, "rules.advantage.card-draw", "Rules text contains card draw; replacement effects and costs still matter.")
        }
        if containsAny(text, ["create a ", "create two ", "create X "]) && containsAny(text, ["token", "tokens"]) {
            add(.tokenMaker, "rules.tokens.create", "Rules text creates tokens; token quality and repeatability require review.")
        }
        if containsAny(text, ["choose one", "choose two", "choose one or both", "choose any number"]) {
            add(.modal, "rules.modal.explicit-choice", "Rules text offers a choice among modes or options.")
        }
        if containsAny(text, ["return target card from your graveyard", "return up to one target card from your graveyard", "return all cards from your graveyard"]) {
            add(.recursion, "rules.recursion.graveyard-return", "Rules text returns cards from a graveyard.")
        }
        if containsAny(text, ["sacrifice a creature", "sacrifice another creature", "sacrifice a token"]) {
            add(.sacrificeOutlet, "rules.sacrifice.explicit-cost", "Rules text includes a sacrifice cost; verify that sacrificing is optional/repeatable and functions as an outlet.")
        }
        if containsAny(text, ["can't be blocked", "menace", "flying", "unblockable"]) {
            add(.evasion, "structure.evasion.keyword", "Card has an evasion keyword or rules-text phrase.")
        }
        if typeLine.contains("creature") {
            add(.curveFiller, "structure.creature", "Creature card; curve role depends on its cost, body, and format.")
        }
        if containsAny(text, ["each creature gets +", "target creature gets +", "creatures you control get +"]) {
            add(.combatTrick, "rules.combat.power-toughness-modification", "Rules text modifies creature power or toughness; timing and duration require review.")
        }

        return CardEvaluationResult(
            schemaVersion: schemaVersion,
            engineVersion: engineVersion,
            scryfallID: card.id,
            oracleID: card.oracleID,
            cardName: card.name,
            setCode: card.setCode,
            suggestions: suggestions.sorted { $0.role.rawValue < $1.role.rawValue },
            confirmedReview: review
        )
    }

    private static func containsAny(_ value: String, _ fragments: [String]) -> Bool {
        fragments.contains { value.contains($0) }
    }
}
