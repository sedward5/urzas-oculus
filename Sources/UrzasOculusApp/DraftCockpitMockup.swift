import SwiftUI

/// A data-only, interactive SwiftUI mockup of the intended draft workspace.
/// All card and deck values are illustrative; this view is not connected to
/// capture, recognition, draft persistence, or the recommendation engine.
struct DraftCockpitMockupView: View {
    @State private var showingSetup = false
    @State private var selectedCardID: Int? = 2
    @State private var confirmedCardIDs: Set<Int> = []
    @State private var showingMissedPickRecovery = false
    @State private var recoverySelection: Int?
    @State private var showingPickConfirmation = false
    @State private var expandedHistory: Set<Int> = [1]
    @State private var sortByScore = true

    private let cards = MockCard.samples
    private let drafted = MockCard.deck

    private var selectedCard: MockCard? {
        cards.first { $0.id == selectedCardID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingSetup {
                setupView
            } else {
                cockpitView
            }
        }
        .background(OculusPalette.canvas)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingMissedPickRecovery) {
            missedPickSheet
        }
        .alert("Confirm this pick?", isPresented: $showingPickConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm Pick") {
                if let selectedCardID {
                    confirmedCardIDs.insert(selectedCardID)
                }
            }
        } message: {
            Text("This demo adds the selected card to the drafted pool. A real session will record an append-only pick event.")
        }
    }

    private var cockpitView: some View {
        VStack(spacing: 0) {
            sessionHeader
            HStack(alignment: .top, spacing: 14) {
                packPanel
                    .frame(minWidth: 390, maxWidth: .infinity)
                VStack(spacing: 14) {
                    deckPanel
                    strategyPanel
                }
                .frame(width: 280)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var sessionHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "眼睛")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(OculusPalette.cyan)
                .overlay {
                    Image(systemName: "scope")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(OculusPalette.cyan)
                }
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("URZA'S OCULUS")
                    .font(.caption.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(OculusPalette.brass)
                Text("The Draft Cockpit")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(OculusPalette.text)
            }
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("LOREHOLD LEGACIES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OculusPalette.text)
                Text("Premier Draft  ·  P1P5")
                    .font(.caption)
                    .foregroundStyle(OculusPalette.muted)
            }
            Spacer()
            statusPill("Capture active", icon: "viewfinder", color: OculusPalette.cyan)
            statusPill("Data ready", icon: "checkmark.circle.fill", color: OculusPalette.green)
            Button {
                showingSetup = true
            } label: {
                Label("New Draft", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .tint(OculusPalette.brass)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(OculusPalette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OculusPalette.brass.opacity(0.35)).frame(height: 1)
        }
    }

    private var packPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT PACK")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(OculusPalette.brass)
                    Text("Pack 1  ·  Pick 5")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(OculusPalette.text)
                }
                Spacer()
                Label("14 cards observed", systemImage: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(OculusPalette.muted)
            }

            HStack(spacing: 8) {
                Label("Sorted by recommendation", systemImage: "arrow.down")
                    .font(.caption)
                    .foregroundStyle(OculusPalette.muted)
                Spacer()
                Toggle("Score order", isOn: $sortByScore)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
            }

            VStack(spacing: 6) {
                ForEach(orderedCards) { card in
                    cardRow(card)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(OculusPalette.cyan)
                Text("Wheel watch is a signal, not a promise. It estimates whether a card may return based on pick position and historical data.")
                    .font(.caption)
                    .foregroundStyle(OculusPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(OculusPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button {
                    showingMissedPickRecovery = true
                } label: {
                    Label("I missed a pick", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .tint(OculusPalette.brass)

                Spacer()

                Button {
                    showingPickConfirmation = true
                } label: {
                    Label("Confirm Pick", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(OculusPalette.blue)
                .disabled(selectedCard == nil || confirmedCardIDs.contains(selectedCardID ?? -1))
            }
        }
        .padding(16)
        .background(OculusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(OculusPalette.brass.opacity(0.22), lineWidth: 1)
        }
    }

    private var orderedCards: [MockCard] {
        let available = cards.filter { !confirmedCardIDs.contains($0.id) }
        return sortByScore ? available.sorted { $0.score > $1.score } : available.sorted { $0.id < $1.id }
    }

    private func cardRow(_ card: MockCard) -> some View {
        let isSelected = selectedCardID == card.id
        return Button {
            selectedCardID = card.id
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(card.color)
                    .frame(width: 4, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(card.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OculusPalette.text)
                        if card.wheelWatch {
                            Image(systemName: "arrow.uturn.clockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(OculusPalette.brass)
                                .help("Wheel watch: this card may be seen again. Not guaranteed.")
                        }
                    }
                    Text("\(card.kind)  ·  MV \(card.manaValue)")
                        .font(.caption2)
                        .foregroundStyle(OculusPalette.muted)
                }
                Spacer(minLength: 4)
                Text(card.score.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(OculusPalette.cyan)
                Text("score")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(OculusPalette.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? OculusPalette.blue.opacity(0.20) : OculusPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? OculusPalette.cyan : OculusPalette.line, lineWidth: isSelected ? 1.5 : 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.name), mana value \(card.manaValue), recommendation score \(Int(card.score))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var deckPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR DECK")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(OculusPalette.brass)
                Spacer()
                Text("\(drafted.count + confirmedCardIDs.count) / 45")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OculusPalette.muted)
            }
            HStack(spacing: 8) {
                statTile("Creatures", value: "3", icon: "pawprint.fill")
                statTile("Other", value: "1", icon: "sparkles")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("COLOR BALANCE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(OculusPalette.muted)
                    Spacer()
                    Text("W 2  U 1  R 1")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(OculusPalette.text)
                }
                HStack(spacing: 3) {
                    colorSegment(OculusPalette.whiteMana, width: 0.5)
                    colorSegment(OculusPalette.blueMana, width: 0.25)
                    colorSegment(OculusPalette.redMana, width: 0.25)
                }
                .frame(height: 7)
                .clipShape(Capsule())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("MANA CURVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(OculusPalette.muted)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array([0.12, 0.48, 0.82, 0.38, 0.18, 0.08].enumerated()), id: \.offset) { index, height in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(OculusPalette.blue.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .frame(height: 54 * height + 5)
                            Text(index == 5 ? "6+" : "\(index + 1)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(OculusPalette.muted)
                        }
                    }
                }
                .frame(height: 65, alignment: .bottom)
            }
            Divider().overlay(OculusPalette.line)
            Text("DRAFTED CARDS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(OculusPalette.muted)
            ForEach(drafted) { card in
                HStack(spacing: 7) {
                    Circle().fill(card.color).frame(width: 7, height: 7)
                    Text(card.name)
                        .font(.caption)
                        .foregroundStyle(OculusPalette.text)
                    Spacer()
                    Text("MV \(card.manaValue)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(OculusPalette.muted)
                }
            }
            if !confirmedCardIDs.isEmpty {
                ForEach(cards.filter { confirmedCardIDs.contains($0.id) }) { card in
                    HStack(spacing: 7) {
                        Circle().fill(card.color).frame(width: 7, height: 7)
                        Text(card.name).font(.caption).foregroundStyle(OculusPalette.cyan)
                        Spacer()
                        Text("Just picked").font(.caption2).foregroundStyle(OculusPalette.cyan)
                    }
                }
            }
        }
        .padding(14)
        .background(OculusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(OculusPalette.line, lineWidth: 1)
        }
    }

    private var strategyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STRATEGY")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(OculusPalette.brass)
                Spacer()
                Text("Early read")
                    .font(.caption2)
                    .foregroundStyle(OculusPalette.muted)
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WU Artifacts")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OculusPalette.text)
                    Text("Your current direction")
                        .font(.caption2)
                        .foregroundStyle(OculusPalette.muted)
                }
                Spacer()
                Text("Emerging")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(OculusPalette.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(OculusPalette.blue.opacity(0.18))
                    .clipShape(Capsule())
            }
            ProgressView(value: 0.42)
                .tint(OculusPalette.cyan)
            Text("2 picks support this direction. Too early to call the archetype open.")
                .font(.caption)
                .foregroundStyle(OculusPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(OculusPalette.line)
            Label("Splash check", systemImage: "drop.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OculusPalette.text)
            Text("No splash recommended yet. No fixing drafted; stay focused on primary colors.")
                .font(.caption)
                .foregroundStyle(OculusPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(OculusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(OculusPalette.line, lineWidth: 1)
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("URZA'S OCULUS", systemImage: "scope")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(OculusPalette.brass)
                Spacer()
                Button("Back to mock draft") { showingSetup = false }
                    .buttonStyle(.bordered)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("Prepare your next draft")
                    .font(.largeTitle.bold())
                    .foregroundStyle(OculusPalette.text)
                Text("Choose the event in Oculus, then join the same event in Arena.")
                    .font(.title3)
                    .foregroundStyle(OculusPalette.muted)
            }
            HStack(spacing: 16) {
                setupCard(title: "EVENT TYPE", value: "Premier Draft", detail: "17Lands data available", icon: "rectangle.stack")
                setupCard(title: "SET", value: "Lorehold Legacies", detail: "Newest release first", icon: "calendar")
            }
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(OculusPalette.green)
                Text("Recommendations ready · Scryfall reference current · 17Lands snapshot pinned at session start")
                    .font(.callout)
                    .foregroundStyle(OculusPalette.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OculusPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Button {
                showingSetup = false
            } label: {
                Label("Start draft session", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(OculusPalette.blue)
            Text("Optional set archetype briefing appears here when reviewed Wizards information is available.")
                .font(.caption)
                .foregroundStyle(OculusPalette.muted)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setupCard(title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(OculusPalette.brass)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(OculusPalette.text)
            Text(detail)
                .font(.caption)
                .foregroundStyle(OculusPalette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OculusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var missedPickSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recover a missed pick")
                .font(.title2.bold())
                .foregroundStyle(OculusPalette.text)
            Text("If Oculus missed the moment you picked, start with the last observed pack. This is more reliable than trying to reconstruct the whole deck.")
                .font(.callout)
                .foregroundStyle(OculusPalette.muted)
            Text("Which card did you take from P1P4?")
                .font(.headline)
                .foregroundStyle(OculusPalette.text)
            ForEach(cards) { card in
                Button {
                    recoverySelection = card.id
                } label: {
                    HStack {
                        Text(card.name).foregroundStyle(OculusPalette.text)
                        Spacer()
                        if recoverySelection == card.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(OculusPalette.cyan)
                        }
                    }
                    .padding(9)
                    .background(recoverySelection == card.id ? OculusPalette.blue.opacity(0.2) : OculusPalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("Cancel") { showingMissedPickRecovery = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Record corrected pick") {
                    if let recoverySelection { confirmedCardIDs.insert(recoverySelection) }
                    showingMissedPickRecovery = false
                }
                .buttonStyle(.borderedProminent)
                .tint(OculusPalette.blue)
                .disabled(recoverySelection == nil)
            }
            Divider().overlay(OculusPalette.line)
            Label("If the original pack is unavailable", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OculusPalette.brass)
            Text("Fallback: guided Arena deck review. Oculus can capture the deck list as you scroll, accumulate the visible cards, and reconcile it against confirmed picks. Manual search is the last resort—not the normal workflow.")
                .font(.caption)
                .foregroundStyle(OculusPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 440)
        .background(OculusPalette.canvas)
    }

    private func statusPill(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statTile(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(OculusPalette.muted)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(OculusPalette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(OculusPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func colorSegment(_ color: Color, width: CGFloat) -> some View {
        GeometryReader { proxy in
            Rectangle().fill(color).frame(width: proxy.size.width * width)
        }
    }
}

private struct MockCard: Identifiable {
    let id: Int
    let name: String
    let kind: String
    let manaValue: Int
    let score: Double
    let color: Color
    let wheelWatch: Bool

    static let samples = [
        MockCard(id: 1, name: "Archive Wing Captain", kind: "Creature · Human Artificer", manaValue: 3, score: 78, color: OculusPalette.whiteMana, wheelWatch: false),
        MockCard(id: 2, name: "Mnemonic Foundry", kind: "Enchantment", manaValue: 2, score: 74, color: OculusPalette.blueMana, wheelWatch: false),
        MockCard(id: 3, name: "Gilded Gearsmith", kind: "Creature · Dwarf", manaValue: 4, score: 69, color: OculusPalette.redMana, wheelWatch: true),
        MockCard(id: 4, name: "Quietus of the Archive", kind: "Instant", manaValue: 2, score: 63, color: OculusPalette.blueMana, wheelWatch: true),
        MockCard(id: 5, name: "Unresolved card", kind: "Needs review · identity unknown", manaValue: 0, score: 0, color: OculusPalette.muted, wheelWatch: false),
        MockCard(id: 6, name: "Foundry Apprentice", kind: "Creature · Artificer", manaValue: 2, score: 58, color: OculusPalette.whiteMana, wheelWatch: false),
        MockCard(id: 7, name: "Cindercoil Adept", kind: "Creature · Wizard", manaValue: 3, score: 55, color: OculusPalette.redMana, wheelWatch: true),
        MockCard(id: 8, name: "Brassbound Courier", kind: "Artifact Creature", manaValue: 2, score: 51, color: OculusPalette.gold, wheelWatch: false)
    ]

    static let deck = [
        MockCard(id: 101, name: "Pilgrim of the Spire", kind: "Creature", manaValue: 2, score: 0, color: OculusPalette.whiteMana, wheelWatch: false),
        MockCard(id: 102, name: "Tideglass Adept", kind: "Creature", manaValue: 3, score: 0, color: OculusPalette.blueMana, wheelWatch: false),
        MockCard(id: 103, name: "Sanctum Sentry", kind: "Creature", manaValue: 4, score: 0, color: OculusPalette.whiteMana, wheelWatch: false),
        MockCard(id: 104, name: "Dawnlit Archive", kind: "Noncreature", manaValue: 2, score: 0, color: OculusPalette.whiteMana, wheelWatch: false)
    ]
}

private enum OculusPalette {
    static let canvas = Color(red: 0.055, green: 0.090, blue: 0.153)
    static let panel = Color(red: 0.085, green: 0.133, blue: 0.204)
    static let surface = Color(red: 0.115, green: 0.176, blue: 0.259)
    static let line = Color(red: 0.20, green: 0.28, blue: 0.38)
    static let blue = Color(red: 0.10, green: 0.53, blue: 0.82)
    static let cyan = Color(red: 0.22, green: 0.74, blue: 0.95)
    static let brass = Color(red: 0.77, green: 0.60, blue: 0.32)
    static let green = Color(red: 0.38, green: 0.78, blue: 0.59)
    static let text = Color(red: 0.90, green: 0.93, blue: 0.97)
    static let muted = Color(red: 0.62, green: 0.69, blue: 0.78)
    static let whiteMana = Color(red: 0.91, green: 0.87, blue: 0.69)
    static let blueMana = Color(red: 0.30, green: 0.63, blue: 0.88)
    static let redMana = Color(red: 0.83, green: 0.39, blue: 0.31)
    static let gold = Color(red: 0.70, green: 0.60, blue: 0.35)
}
