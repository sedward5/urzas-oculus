import AppKit
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
    let setName: String
    let sourceUrl: URL
    let archetypes: [ArchetypeEntry]
    let overviewImage: OverviewImage
}
private struct OverviewImage: Decodable { let sourceUrl: URL; let alt: String; let attribution: String }
private struct ArchetypeEntry: Decodable, Identifiable {
    let id: String; let displayName: String; let colorIdentity: String
    let archetypeType: String; let strategyText: String
}

@MainActor private final class ArchetypeImageCache: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var loading = false
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("UrzasOculus/ArchetypeImages", isDirectory: true)

    func load(_ sets: [String: ArchetypeSet]) async {
        for (code, _) in sets {
            let file = folder.appendingPathComponent("\(code).jpg")
            if let image = NSImage(contentsOf: file) { images[code] = image }
        }
        let missing = sets.filter { images[$0.key] == nil }
        guard !missing.isEmpty else { return }
        loading = true
        defer { loading = false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await withTaskGroup(of: (String, NSImage?).self) { group in
            for (code, set) in missing {
                group.addTask {
                    guard let (data, _) = try? await URLSession.shared.data(from: set.overviewImage.sourceUrl),
                          let image = NSImage(data: data) else { return (code, nil) }
                    try? data.write(to: self.folder.appendingPathComponent("\(code).jpg"), options: .atomic)
                    return (code, image)
                }
            }
            for await (code, image) in group { if let image { images[code] = image } }
        }
    }
}

struct ArchetypeReferenceView: View {
    @State private var catalog = ArchetypeCatalog.load()
    @State private var selectedCode = "HOB"
    @StateObject private var cache = ArchetypeImageCache()
    private var codes: [String] { ["HOB", "ECL", "TDM"].filter { catalog?.sets[$0] != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FORMAT REFERENCE").font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
                    Text("Draft Archetypes").font(.largeTitle.bold())
                }
                Spacer()
                Picker("Set", selection: $selectedCode) {
                    ForEach(codes, id: \.self) { Text($0).tag($0) }
                }.frame(width: 130)
            }
            if let set = catalog?.sets[selectedCode] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let image = cache.images[selectedCode] {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel(set.overviewImage.alt)
                        } else {
                            ContentUnavailableView("Overview image unavailable", systemImage: "photo",
                                description: Text("The image will be cached when network access is available."))
                                .frame(height: 170)
                        }
                        HStack { Text(set.setName).font(.title2.bold()); Spacer(); Link("Wizards source ↗", destination: set.sourceUrl) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], alignment: .leading, spacing: 14) {
                            ForEach(set.archetypes) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Text(item.displayName).font(.headline); Spacer(); Text(item.colorIdentity).font(.caption.monospaced().bold()).foregroundStyle(.cyan) }
                                    Text(item.strategyText).font(.callout).foregroundStyle(.secondary)
                                    Text(item.archetypeType.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(.tertiary)
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text(set.overviewImage.attribution).font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.bottom, 24)
                }
            } else {
                ContentUnavailableView("Catalog unavailable", systemImage: "books.vertical")
            }
            if cache.loading { ProgressView("Caching set images…").controlSize(.small) }
        }
        .padding(24)
        .task { if let catalog { await cache.load(catalog.sets) } }
    }
}
