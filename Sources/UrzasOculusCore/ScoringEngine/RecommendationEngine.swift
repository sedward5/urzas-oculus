import Foundation

public enum RecommendationEngineError: Error, Equatable {
    case datasetNotReady([RecommendationReadinessIssue])
    case readinessScopeMismatch
    case invalidConfiguration
}

/// Versioned, explicit inputs to the baseline evaluator.
///
/// baselineWinRate must come from the overall win rate for the same set,
/// event, and user-group dataset. priorWeight is a regularization strength,
/// not an independent-observation count or confidence interval. 17Lands
/// counts are copy-weighted and may contain correlated observations.
public struct RecommendationScoringConfiguration: Equatable, Sendable {
    public let version: String
    public let schemaVersion: Int
    public let baselineWinRate: Double
    /// Regularization strength; must be tuned and versioned with the strategy.
    public let priorWeight: Double

    public init(
        version: String,
        schemaVersion: Int = 1,
        baselineWinRate: Double,
        priorWeight: Double
    ) {
        self.version = version
        self.schemaVersion = schemaVersion
        self.baselineWinRate = baselineWinRate
        self.priorWeight = priorWeight
    }
}

public struct RecommendationCandidateInput: Equatable, Sendable {
    public let card: CardRecord
    public let performance: CardPerformanceRecord?

    public init(card: CardRecord, performance: CardPerformanceRecord?) {
        self.card = card
        self.performance = performance
    }
}

public struct RecommendationEvaluationRequest: Equatable, Sendable {
    public let dataset: RecommendationDatasetRequest
    public let readiness: RecommendationDataReadiness
    public let candidates: [RecommendationCandidateInput]
    public let configuration: RecommendationScoringConfiguration

    public init(
        dataset: RecommendationDatasetRequest,
        readiness: RecommendationDataReadiness,
        candidates: [RecommendationCandidateInput],
        configuration: RecommendationScoringConfiguration
    ) {
        self.dataset = dataset
        self.readiness = readiness
        self.candidates = candidates
        self.configuration = configuration
    }
}

public struct ScoredRecommendation: Equatable, Sendable, Identifiable {
    public let id: String
    public let cardName: String
    public let score: Double
    public let observedGamesInHandWinRate: Double
    public let gamesInHandCount: Int
    public let averageLastSeen: Double?
    public let averageTakenAt: Double?
    public let explanation: String

    public init(
        id: String,
        cardName: String,
        score: Double,
        observedGamesInHandWinRate: Double,
        gamesInHandCount: Int,
        averageLastSeen: Double?,
        averageTakenAt: Double?,
        explanation: String
    ) {
        self.id = id
        self.cardName = cardName
        self.score = score
        self.observedGamesInHandWinRate = observedGamesInHandWinRate
        self.gamesInHandCount = gamesInHandCount
        self.averageLastSeen = averageLastSeen
        self.averageTakenAt = averageTakenAt
        self.explanation = explanation
    }
}

public enum RecommendationExclusionReason: Equatable, Sendable {
    case missingPerformance
    case missingGamesInHandSample
    case mismatchedDatasetScope
    case mismatchedSnapshot
}

public struct ExcludedRecommendation: Equatable, Sendable, Identifiable {
    public let id: String
    public let cardName: String
    public let reason: RecommendationExclusionReason

    public init(id: String, cardName: String, reason: RecommendationExclusionReason) {
        self.id = id
        self.cardName = cardName
        self.reason = reason
    }
}

/// A deterministic baseline result. Generation timestamps belong to the
/// publication adapter, not this pure evaluation result.
public struct RecommendationResult: Equatable, Sendable {
    public let datasetKey: String
    public let gameSnapshotID: String
    public let engineVersion: String
    public let scoringConfigurationVersion: String
    public let schemaVersion: Int
    public let ranked: [ScoredRecommendation]
    public let excluded: [ExcludedRecommendation]

    public var hasRecommendations: Bool { !ranked.isEmpty }

    public init(
        datasetKey: String,
        gameSnapshotID: String,
        engineVersion: String,
        scoringConfigurationVersion: String,
        schemaVersion: Int,
        ranked: [ScoredRecommendation],
        excluded: [ExcludedRecommendation]
    ) {
        self.datasetKey = datasetKey
        self.gameSnapshotID = gameSnapshotID
        self.engineVersion = engineVersion
        self.scoringConfigurationVersion = scoringConfigurationVersion
        self.schemaVersion = schemaVersion
        self.ranked = ranked
        self.excluded = excluded
    }
}

/// The single maintained recommendation implementation used by the app
/// and future headless CI jobs. This first version ranks standalone card
/// strength only; pool synergy and deck-needs factors are intentionally
/// deferred until their inputs and behavior can be validated.
public enum ScoringEngine {
    public static let engineVersion = "0.1.0"

    public static func evaluate(
        _ request: RecommendationEvaluationRequest
    ) throws -> RecommendationResult {
        guard request.readiness.datasetKey == request.dataset.datasetKey else {
            throw RecommendationEngineError.readinessScopeMismatch
        }
        guard request.readiness.isReady else {
            throw RecommendationEngineError.datasetNotReady(request.readiness.issues)
        }

        let configuration = request.configuration
        guard !configuration.version.isEmpty,
              configuration.schemaVersion > 0,
              configuration.baselineWinRate.isFinite,
              (0...1).contains(configuration.baselineWinRate),
              configuration.priorWeight.isFinite,
              configuration.priorWeight >= 0,
              let gameComponent = request.readiness.components[.game],
              let draftComponent = request.readiness.components[.draft],
              gameComponent.snapshotID == draftComponent.snapshotID else {
            throw RecommendationEngineError.invalidConfiguration
        }

        var ranked: [ScoredRecommendation] = []
        var excluded: [ExcludedRecommendation] = []

        for candidate in request.candidates {
            let card = candidate.card
            guard card.setCode == request.dataset.setCode else {
                excluded.append(ExcludedRecommendation(
                    id: card.id, cardName: card.name, reason: .mismatchedDatasetScope
                ))
                continue
            }
            guard let performance = candidate.performance else {
                excluded.append(ExcludedRecommendation(
                    id: card.id, cardName: card.name, reason: .missingPerformance
                ))
                continue
            }
            guard performance.snapshotID == gameComponent.snapshotID else {
                excluded.append(ExcludedRecommendation(
                    id: card.id, cardName: card.name, reason: .mismatchedSnapshot
                ))
                continue
            }
            guard performance.setCode == request.dataset.setCode,
                  performance.eventType == request.dataset.eventType,
                  performance.userGroup == request.dataset.userGroup,
                  performance.colorFilter == request.dataset.colorFilter,
                  CardRecord.normalizeName(performance.cardName) == CardRecord.normalizeName(card.name),
                  performance.cardScryfallID == nil || performance.cardScryfallID == card.id else {
                excluded.append(ExcludedRecommendation(
                    id: card.id, cardName: card.name, reason: .mismatchedDatasetScope
                ))
                continue
            }

            guard let observedRate = performance.winRate,
                  observedRate.isFinite,
                  (0...1).contains(observedRate),
                  let sampleCount = performance.gamesInHandCount,
                  sampleCount > 0 else {
                excluded.append(ExcludedRecommendation(
                    id: card.id, cardName: card.name, reason: .missingGamesInHandSample
                ))
                continue
            }

            let sample = Double(sampleCount)
            let prior = configuration.priorWeight
            let score = prior + sample > 0
                ? ((observedRate * sample) +
                   (configuration.baselineWinRate * prior)) / (sample + prior)
                : observedRate

            ranked.append(ScoredRecommendation(
                id: card.id,
                cardName: card.name,
                score: score,
                observedGamesInHandWinRate: observedRate,
                gamesInHandCount: sampleCount,
                averageLastSeen: performance.averageLastSeen,
                averageTakenAt: performance.averageTakenAt,
                explanation: explanation(
                    observedRate: observedRate,
                    sampleCount: sampleCount,
                    score: score,
                    configuration: configuration
                )
            ))
        }

        ranked.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.observedGamesInHandWinRate != $1.observedGamesInHandWinRate {
                return $0.observedGamesInHandWinRate > $1.observedGamesInHandWinRate
            }
            if $0.gamesInHandCount != $1.gamesInHandCount {
                return $0.gamesInHandCount > $1.gamesInHandCount
            }
            return CardRecord.normalizeName($0.cardName) <
                CardRecord.normalizeName($1.cardName)
        }
        excluded.sort {
            CardRecord.normalizeName($0.cardName) <
                CardRecord.normalizeName($1.cardName)
        }

        return RecommendationResult(
            datasetKey: request.dataset.datasetKey,
            gameSnapshotID: gameComponent.snapshotID,
            engineVersion: engineVersion,
            scoringConfigurationVersion: configuration.version,
            schemaVersion: configuration.schemaVersion,
            ranked: ranked,
            excluded: excluded
        )
    }

    private static func explanation(
        observedRate: Double,
        sampleCount: Int,
        score: Double,
        configuration: RecommendationScoringConfiguration
    ) -> String {
        let observed = observedRate.formatted(.percent.precision(.fractionLength(1)))
        let adjusted = score.formatted(.percent.precision(.fractionLength(1)))
        return "GIH win rate \(observed) across \(sampleCount) copy-weighted observations; " +
            "regularized toward the \(configuration.baselineWinRate.formatted(.percent.precision(.fractionLength(1)))) " +
            "format baseline to \(adjusted)."
    }
}
