import Foundation
import Darwin
import UrzasOculusCore

private struct GameMetricOutput: Encodable {
    let cardName: String
    let gamesPlayedCount: Int
    let gamesPlayedWinRate: Double?
    let playRate: Double?
    let gamesInHandCount: Int
    let gamesInHandWinRate: Double?
    let openingHandCount: Int
    let openingHandWinRate: Double?
    let drawnCount: Int
    let drawnWinRate: Double?
    let gamesNotSeenCount: Int
    let gamesNotSeenWinRate: Double?
}

private struct DraftMetricOutput: Encodable {
    let cardName: String
    let seenCount: Int
    let averageLastSeen: Double?
    let pickCount: Int
    let averageTakenAt: Double?
}

private struct ProbeOutput: Encodable {
    let gameRows: Int
    let gameWins: Int
    let gameWinRate: Double?
    let gameMetrics: [GameMetricOutput]
    let draftRows: Int
    let draftRowsConsumed: Int
    let draftPrimaryPickCount: Int
    let draftSecondaryPickCount: Int
    let draftMetricPickCountTotal: Int
    let draftMetrics: [DraftMetricOutput]
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Archive probe: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3 else {
    fail("usage: SeventeenLandsArchiveProbe <game.csv.gz> <draft.csv.gz> <output.json>")
}
let gameURL = URL(fileURLWithPath: arguments[0])
let draftURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

do {
    var gameAccumulator: SeventeenLandsGameMetricsAccumulator?
    let gameRows = try SeventeenLandsCSVReader.readTable(
        from: gameURL,
        onHeader: { header in
            gameAccumulator = try SeventeenLandsGameMetricsAccumulator(header: header)
        },
        onRow: { row in try gameAccumulator?.consume(row) }
    )
    guard let gameAccumulator, gameRows > 0 else {
        fail("game archive contained no usable rows")
    }

    var draftAccumulator: SeventeenLandsDraftMetricsAccumulator?
    let draftRows = try SeventeenLandsCSVReader.readTable(
        from: draftURL,
        onHeader: { header in
            draftAccumulator = try SeventeenLandsDraftMetricsAccumulator(header: header)
        },
        onRow: { row in try draftAccumulator?.consume(row) }
    )
    guard let draftAccumulator, draftRows > 0 else {
        fail("draft archive contained no usable rows")
    }

    let games = gameAccumulator.finish().map {
        GameMetricOutput(
            cardName: $0.cardName,
            gamesPlayedCount: $0.gamesPlayedCount,
            gamesPlayedWinRate: $0.gamesPlayedWinRate,
            playRate: $0.playRate,
            gamesInHandCount: $0.gamesInHandCount,
            gamesInHandWinRate: $0.gamesInHandWinRate,
            openingHandCount: $0.openingHandCount,
            openingHandWinRate: $0.openingHandWinRate,
            drawnCount: $0.drawnCount,
            drawnWinRate: $0.drawnWinRate,
            gamesNotSeenCount: $0.gamesNotSeenCount,
            gamesNotSeenWinRate: $0.gamesNotSeenWinRate
        )
    }
    let drafts = draftAccumulator.finish().map {
        DraftMetricOutput(
            cardName: $0.cardName,
            seenCount: $0.seenCount,
            averageLastSeen: $0.averageLastSeen,
            pickCount: $0.pickCount,
            averageTakenAt: $0.averageTakenAt
        )
    }
    let result = ProbeOutput(
        gameRows: gameRows,
        gameWins: gameAccumulator.overallGameWins,
        gameWinRate: gameAccumulator.overallWinRate,
        gameMetrics: games,
        draftRows: draftRows,
        draftRowsConsumed: draftAccumulator.consumedRowCount,
        draftPrimaryPickCount: draftAccumulator.primaryPickCount,
        draftSecondaryPickCount: draftAccumulator.secondaryPickCount,
        draftMetricPickCountTotal: drafts.reduce(0) { $0 + $1.pickCount },
        draftMetrics: drafts
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(to: outputURL, options: .atomic)
} catch {
    fail(String(describing: error))
}
