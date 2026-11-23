import Foundation
import UrzasOculusCore

enum CardEvaluationToolError: Error, CustomStringConvertible {
    case usage
    case duplicateCardID(String)
    case invalidReview(String)
    case invalidInput(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: CardEvaluationTool --input cards.json [--reviews reviews.json]\nInput must be a JSON array of normalized UrzasOculusCore CardRecord objects. Output is a JSON array on stdout."
        case .duplicateCardID(let id):
            return "Duplicate Scryfall printing ID in input: \(id)"
        case .invalidReview(let id):
            return "Review does not match input card identity: \(id)"
        case .invalidInput(let message):
            return message
        }
    }
}

func argumentValue(_ flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let inputPath = argumentValue("--input", in: arguments) else {
        throw CardEvaluationToolError.usage
    }

    let inputData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    let cards: [CardRecord]
    do {
        cards = try JSONDecoder().decode([CardRecord].self, from: inputData)
    } catch {
        throw CardEvaluationToolError.invalidInput("Unable to decode normalized card records: \(error)")
    }

    var seen = Set<String>()
    for card in cards {
        guard seen.insert(card.id).inserted else {
            throw CardEvaluationToolError.duplicateCardID(card.id)
        }
    }

    var reviewsByID: [String: CardEvaluationReview] = [:]
    if let reviewsPath = argumentValue("--reviews", in: arguments) {
        let data = try Data(contentsOf: URL(fileURLWithPath: reviewsPath))
        let reviews = try JSONDecoder().decode([CardEvaluationReview].self, from: data)
        for review in reviews {
            guard let card = cards.first(where: { $0.id == review.scryfallID }),
                  card.setCode == review.setCode,
                  card.oracleID == review.oracleID else {
                throw CardEvaluationToolError.invalidReview(review.scryfallID)
            }
            guard reviewsByID[review.scryfallID] == nil else {
                throw CardEvaluationToolError.invalidReview("duplicate review for \(review.scryfallID)")
            }
            reviewsByID[review.scryfallID] = review
        }
    }

    let results = cards.map { card in
        CardEvaluationEngine.evaluate(card: card, review: reviewsByID[card.id])
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let output = try encoder.encode(results)
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data([0x0A]))
} catch {
    FileHandle.standardError.write(Data("CardEvaluationTool: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
