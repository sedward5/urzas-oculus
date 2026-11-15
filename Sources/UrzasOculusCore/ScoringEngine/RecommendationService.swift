import Foundation

public enum RecommendationServiceError: Error, Equatable {
    case duplicateCandidateID(String)
    case missingCardRecord(String)
}

/// Loads a complete, scope-matched evaluation request from the local store
/// and delegates all ranking to the shared ScoringEngine.
public enum RecommendationService {
    public static func evaluate(
        candidateCardIDs: [String],
        dataset: RecommendationDatasetRequest,
        configuration: RecommendationScoringConfiguration,
        in store: LocalDataStore,
        now: Date = .now,
        maximumSourceAge: TimeInterval? = nil,
        maximumAcquisitionAge: TimeInterval? = nil
    ) throws -> RecommendationResult {
        var seen = Set<String>()
        for id in candidateCardIDs {
            guard seen.insert(id).inserted else {
                throw RecommendationServiceError.duplicateCandidateID(id)
            }
        }

        let readiness = try store.recommendationReadiness(
            for: dataset,
            now: now,
            maximumSourceAge: maximumSourceAge,
            maximumAcquisitionAge: maximumAcquisitionAge
        )

        guard readiness.isReady else {
            throw RecommendationEngineError.datasetNotReady(readiness.issues)
        }

        let candidates = try candidateCardIDs.map { id -> RecommendationCandidateInput in
            guard let card = try store.card(scryfallID: id) else {
                throw RecommendationServiceError.missingCardRecord(id)
            }
            let performance = try store.performance(
                setCode: dataset.setCode,
                eventType: dataset.eventType,
                cardName: card.name,
                userGroup: dataset.userGroup,
                colorFilter: dataset.colorFilter
            )
            return RecommendationCandidateInput(card: card, performance: performance)
        }

        return try ScoringEngine.evaluate(RecommendationEvaluationRequest(
            dataset: dataset,
            readiness: readiness,
            candidates: candidates,
            configuration: configuration
        ))
    }
}
