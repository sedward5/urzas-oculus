import AppKit
import CryptoKit
import SwiftUI

private struct ArchetypeCatalog: Decodable {
    let sets: [String: ArchetypeSet]
    static func load() -> ArchetypeCatalog? {
        guard let url = Bundle.module.url(forResource: "reviewed_archetypes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ArchetypeCatalog.self, from: data)
    }
}
private struct ArchetypeSet: Decodable {
    let setName: String; let sourceUrl: URL; let archetypes: [ArchetypeEntry]; let overviewImage: OverviewImage
}
private struct OverviewImage: Decodable { let sourceUrl: URL; let sourceSha256: String; let alt: String; let attribution: String }
private struct ArchetypeEntry: Decodable, Identifiable {
    let id: String; let displayName: String; let colorIdentity: String; let archetypeType: String; let strategyText: String
}
private struct ReviewedCardCatalog: Decodable {
    let sets: [String: ReviewedCardSet]
    static func load() -> ReviewedCardCatalog? {
        guard let url = Bundle.module.url(forResource: "reviewed_cards", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ReviewedCardCatalog.self, from: data)
    }
}
private struct ReviewedCardSet: Decodable { let cards: [ReviewedCard] }
private struct ReviewedCard: Decodable, Identifiable {
    let name: String; let relationships: [CardRelationship]; let sourceReferences: [CardSourceReference]
    let imageUris: CardImageURIs?; let scryfallUri: URL?
    var id: String { name }
}
private struct CardRelationship: Decodable { let archetypeId: String; let role: String; let reviewStatus: String; let evidence: String? }
private struct CardSourceReference: Decodable { let source: String; let title: String; let url: URL }
private struct CardImageURIs: Decodable { let normal: URL?; let large: URL? }

@MainActor private final class ArchetypeImageCache: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var loading = false
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("UrzasOculus/ArchetypeImages", isDirectory: true)
    private func matchesChecksum(_ data: Data, expected: String) -> Bool {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expected
    }
    func load(_ sets: [String: ArchetypeSet]) async {
        for (code, set) in sets {
            let file = folder.appendingPathComponent("\(code).jpg")
            if let data = try? Data(contentsOf: file), matchesChecksum(data, expected: set.overviewImage.sourceSha256), let image = NSImage(data: data) { images[code] = image }
        }
        let missing = sets.filter { images[$0.key] == nil }
        guard !missing.isEmpty else { return }
        loading = true; defer { loading = false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (code, set) in missing {
            guard let (data, response) = try? await URLSession.shared.data(from: set.overviewImage.sourceUrl),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  matchesChecksum(data, expected: set.overviewImage.sourceSha256), let image = NSImage(data: data) else { continue }
            try? data.write(to: folder.appendingPathComponent("\(code).jpg"), options: .atomic); images[code] = image
        }
    }
}

struct ArchetypeReferenceView: View {
    @State private var catalog = ArchetypeCatalog.load()
    @State private var cardCatalog = ReviewedCardCatalog.load()
    @State private var selectedCode = "HOB"
    @StateObject private var cache = ArchetypeImageCache()
    private var codes: [String] { ["HOB", "ECL", "TDM"].filter { catalog?.sets[$0] != nil } }
    private let roles = ["signpost", "enabler", "payoff", "supporting"]
    private func cards(for archetype: ArchetypeEntry, role: String) -> [ReviewedCard] {
        (cardCatalog?.sets[selectedCode]?.cards ?? []).filter { card in
            card.relationships.contains { $0.archetypeId == archetype.id && $0.role == role && $0.reviewStatus == "reviewed" }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FORMAT REFERENCE").font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
                    Text("Draft Archetypes").font(.largeTitle.bold())
                }
                Spacer()
                Picker("Set", selection: $selectedCode) { ForEach(codes, id: \.self) { Text($0).tag($0) } }.frame(width: 130)
            }
            if let set = catalog?.sets[selectedCode] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let image = cache.images[selectedCode] {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel(set.overviewImage.alt)
                        } else {
                            ContentUnavailableView("Overview image unavailable", systemImage: "photo", description: Text("The image will be cached when network access is available.")).frame(height: 170)
                        }
                        HStack { Text(set.setName).font(.title2.bold()); Spacer(); Link("Wizards source ↗", destination: set.sourceUrl) }
                        ForEach(set.archetypes) { archetype in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Text(archetype.displayName).font(.headline); Spacer(); Text(archetype.colorIdentity).font(.caption.monospaced().bold()).foregroundStyle(.cyan) }
                                Text(archetype.strategyText).font(.callout).foregroundStyle(.secondary)
                                ForEach(roles, id: \.self) { role in
                                    let matching = cards(for: archetype, role: role)
                                    if !matching.isEmpty {
                                        VStack(alignment: .leading, spacing: 7) {
                                            Text(role.capitalized).font(.subheadline.bold()).foregroundStyle(.secondary)
                                            ForEach(matching) { card in
                                                HStack(alignment: .top, spacing: 10) {
                                                    if let url = card.imageUris?.normal ?? card.imageUris?.large {
                                                        AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) } placeholder: { RoundedRectangle(cornerRadius: 5).fill(.quaternary) }.frame(width: 72, height: 100)
                                                    }
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(card.name).font(.callout.weight(.medium))
                                                        if let evidence = card.relationships.first(where: { $0.archetypeId == archetype.id && $0.role == role })?.evidence { Text(evidence).font(.caption).foregroundStyle(.secondary) }
                                                        HStack(spacing: 12) {
                                                            if let url = card.scryfallUri { Link("Scryfall", destination: url) }
                                                            if let source = card.sourceReferences.first { Link(source.source, destination: source.url) }
                                                        }.font(.caption)
                                                    }
                                                    Spacer(minLength: 0)
                                                }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Text(set.overviewImage.attribution).font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.bottom, 24)
                }
            } else { ContentUnavailableView("Catalog unavailable", systemImage: "books.vertical") }
            if cache.loading { ProgressView("Caching set images…").controlSize(.small) }
        }.padding(24).task { if let catalog { await cache.load(catalog.sets) } }
    }
}
