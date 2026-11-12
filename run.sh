set -euo pipefail

REPO="sedward5/urzas-oculus"
BRANCH="chore/initial-project-scaffold"

REMOTE="$(git remote get-url origin)"
case "$REMOTE" in
  *"$REPO"*) ;;
  *) echo "Wrong repository: $REMOTE"; exit 1 ;;
esac

git fetch origin main
git switch main
git pull --ff-only origin main

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "Branch already exists: $BRANCH"
  echo "Stopping to avoid overwriting existing work."
  exit 1
fi

git switch -c "$BRANCH"

mkdir -p \
  docs \
  Sources/UrzasOculusCore/CaptureEngine \
  Sources/UrzasOculusCore/RecognitionEngine \
  Sources/UrzasOculusCore/DraftEngine \
  Sources/UrzasOculusCore/ScoringEngine \
  Sources/UrzasOculusCore/DataEngine \
  Sources/UrzasOculusCore/CollectionEngine \
  Sources/UrzasOculusApp \
  Tests/UrzasOculusCoreTests \
  scripts \
  .github/workflows

cat > README.md <<'EOF'
# Urza's Oculus

A native macOS companion for drafting Magic: The Gathering Arena on an
iPhone using macOS iPhone Mirroring.

Urza's Oculus observes the mirrored draft, identifies cards and packs,
tracks the draft, and provides deterministic pick recommendations.

## Project status

**Foundation scaffold.** The initial architecture and build pipeline are
being established. Screen capture and recognition are not implemented yet.

## Goals

- Capture the iPhone Mirroring window using macOS ScreenCaptureKit.
- Recognize packs and cards using local computer vision and OCR.
- Maintain an accurate record of the draft and drafted pool.
- Produce explainable, deterministic pick recommendations.
- Use versioned local reference data from sources such as Scryfall and
  17Lands.

## Design principles

- Native macOS application; minimum supported version macOS 14.
- Swift and SwiftUI.
- Local processing. No runtime AI inference or paid APIs.
- No automated interaction with Arena.
- No overlays or attempts to control the mirrored iPhone.
- Draft history is the source of truth.
- Keep capture, recognition, draft state, and scoring independently testable.

## Repository layout

    Sources/
      UrzasOculusApp/
      UrzasOculusCore/
        CaptureEngine/
        RecognitionEngine/
        DraftEngine/
        ScoringEngine/
        DataEngine/
        CollectionEngine/
    Tests/
      UrzasOculusCoreTests/
    docs/
    scripts/
    .github/workflows/

## Development

The project uses Swift Package Manager.

On a compatible Mac:

    swift test
    swift run

To create an application bundle:

    ./scripts/package-app.sh

The script produces dist/UrzasOculus-macos.zip.

GitHub Actions runs the native macOS build and tests. GitHub Codespaces
can be used for browser-based editing and Git operations, but its Linux
environment cannot run the native macOS application.

## Project documentation

- [Project steering](docs/PROJECT_STEERING.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Technical spike](docs/TECHNICAL_SPIKE.md)
- [Architecture decisions](docs/DECISIONS.md)

## License

License to be determined before public distribution.
EOF

cat > AGENTS.md <<'EOF'
# Instructions for coding agents

## Project authority

Read `docs/PROJECT_STEERING.md` and `docs/ARCHITECTURE.md` before making
architectural changes. These documents are the project's source of truth.

## Core constraints

- Target native macOS 14 or newer.
- Use Swift and SwiftUI.
- Keep OCR, recognition, draft state, and scoring deterministic and local.
- Do not introduce runtime AI inference, cloud inference, or paid APIs.
- Do not automate clicks or input into MTG Arena.
- Do not introduce overlays or require administrator privileges.
- Keep the user in control of all draft decisions.

## Engineering expectations

- Prefer small, independently testable components.
- Separate raw observations from interpreted card identities.
- Treat draft history as the authoritative record of state.
- Make uncertainty explicit; do not silently guess card identities.
- Preserve provenance and version information for reference datasets.
- Add or update tests with behavior changes.
- Avoid speculative abstractions before a real requirement exists.
- Document significant architectural decisions.

## Workflow

- Run `swift test` on a compatible macOS environment.
- Keep pull requests focused.
- Explain assumptions and known limitations.
- Never claim a feature is implemented when it is only scaffolded.
EOF

cat > docs/PROJECT_STEERING.md <<'EOF'
# Urza's Oculus — Project Steering

## 1. Purpose

Urza's Oculus is a native macOS companion application that assists a
player drafting Magic: The Gathering Arena on an iPhone through macOS
iPhone Mirroring.

The application observes the mirrored draft, identifies the current
pack and its cards, tracks the player's selections, and provides
algorithmic pick recommendations.

The player remains in control. The application advises; it does not
play the game.

## 2. Product principles

1. Local first: capture, OCR, recognition, state tracking, and scoring
   happen locally.
2. Deterministic: given the same observations, draft state, and data
   versions, scoring should produce the same result.
3. Explainable: recommendations should expose the factors that
   contributed to a pick.
4. Non-invasive: the application is a companion window, not an
   overlay or input automation tool.
5. Resilient: uncertain recognition must not silently corrupt draft
   state.
6. Incremental: validate difficult technical assumptions before
   building dependent systems.

## 3. Platform and technology

- Native macOS application.
- Minimum target: macOS 14.
- Swift and SwiftUI.
- ScreenCaptureKit for screen capture.
- Vision and local image processing for OCR and recognition.
- Swift Package Manager as the initial build system.
- XcodeGen may be introduced when application packaging or project
  organization warrants it.
- Bundle identifier: com.local.urzas-oculus.

## 4. Explicit constraints

- No runtime AI or cloud inference.
- No paid APIs or required subscriptions.
- No server dependency for the core drafting workflow.
- No automated clicks, keyboard input, or game interaction.
- No overlays on top of the mirrored iPhone window.
- No administrator privileges.
- No collection or transmission of screen contents.

Public reference datasets may be downloaded or imported as explicit,
versioned data updates. Individual pick decisions must not depend on
live API calls.

## 5. Core workflow

1. Locate and capture the iPhone Mirroring window.
2. Observe the current draft screen.
3. Identify the pack and visible card candidates.
4. Associate recognized cards with authoritative card records.
5. Present uncertain recognition for user correction.
6. Record the selected card and advance draft state.
7. Evaluate remaining cards using the current draft context.
8. Present recommendations with useful explanations.

## 6. Architectural boundaries

- Capture produces observations, not card identities.
- Recognition interprets observations and reports confidence.
- DraftEngine owns the authoritative draft history and state.
- ScoringEngine consumes draft state and reference data. It does not
  mutate the draft.
- DataEngine owns reference data normalization, versioning, and
  provenance.
- CollectionEngine provides collection context without becoming the
  source of truth for draft history.

## 7. Initial milestone

The first milestone is a technical feasibility spike:

Can ScreenCaptureKit reliably capture the macOS iPhone Mirroring window
while preserving enough visual information for local OCR and card
recognition?

Do not build a large recognition or scoring system before answering
that question.

## 8. Definition of done

A change should include:

- A clear description of behavior.
- Tests for meaningful logic.
- Updated documentation where appropriate.
- No violation of the platform or privacy constraints.
- A successful macOS CI build and test run.
EOF

cat > docs/ARCHITECTURE.md <<'EOF'
# Architecture

## Processing pipeline

    ScreenCaptureKit
           |
           v
      Observation
           |
           v
     Recognition Engine
           |
           v
      Interpreted Pack
           |
           v
       Draft Engine <---- User correction / selection
           |
           v
        Draft State
           |
           v
       Scoring Engine
           |
           v
      Recommendation

## CaptureEngine

Responsible for discovering and capturing the iPhone Mirroring window.

Responsibilities:
- ScreenCaptureKit integration.
- Window selection and capture lifecycle.
- Frame delivery and capture metadata.
- Permission and capture error reporting.

It must not make card identity or draft-state decisions.

## RecognitionEngine

Responsible for interpreting captured frames.

Responsibilities:
- OCR and visual feature extraction.
- Card candidate identification.
- Pack layout interpretation.
- Confidence and ambiguity reporting.

Recognition results should retain their relationship to the source
observation.

## DraftEngine

Owns the authoritative draft history.

Responsibilities:
- Pack and pick sequencing.
- Player selections.
- Drafted pool.
- State transitions and recovery.
- User corrections to recognized information.

Draft history should be sufficient to reconstruct the current state.

## ScoringEngine

Evaluates available picks against the current draft context.

Responsibilities:
- Card evaluation.
- Synergy and archetype context.
- Curve and color considerations.
- Pick recommendations and explanations.

Scoring must be deterministic for a given state and data version.

## DataEngine

Owns reference data and normalization.

Potential sources:
- Scryfall card records.
- 17Lands card and game data.

Data must be versioned, locally available, and traceable to its source.
Avoid making a live network request during a pick.

## CollectionEngine

Provides optional collection context. It must not be required for the
core draft workflow.

## Data flow rules

- Raw observations are immutable inputs to recognition.
- Recognition output is not automatically trusted.
- User corrections become explicit draft events.
- Draft history is the source of truth.
- Scoring consumes state; it does not mutate it.
- Reference data versions should be recorded with scoring results.
EOF

cat > docs/DECISIONS.md <<'EOF'
# Architecture Decision Records

## ADR-001: Native macOS application

**Status:** Accepted

Urza's Oculus is a native macOS companion application. Swift and SwiftUI
provide the application foundation, with ScreenCaptureKit and Vision
used for local capture and recognition.

## ADR-002: Local deterministic processing

**Status:** Accepted

The core workflow must not depend on runtime AI inference, cloud
inference, paid APIs, or a server.

The same draft state and data versions should produce repeatable
recommendations.

## ADR-003: Draft history is authoritative

**Status:** Accepted

Draft state is reconstructed from explicit draft events and user
corrections. Recognition is an input to the state machine, not the
authority on what the player selected.

## ADR-004: Validate capture before building dependent systems

**Status:** Accepted

ScreenCaptureKit compatibility with the iPhone Mirroring window is a
critical technical risk. Validate capture quality and permissions before
investing heavily in OCR, recognition, and scoring.
EOF

cat > docs/TECHNICAL_SPIKE.md <<'EOF'
# Phase 0 — Screen Capture Feasibility

## Question

Can the application reliably capture the iPhone Mirroring window using
ScreenCaptureKit on macOS 14 or newer?

## Goals

- Discover the mirrored iPhone window.
- Capture frames without capturing unrelated desktop content.
- Confirm that card text and visual details remain usable.
- Measure frame delivery and processing costs.
- Understand macOS screen recording permissions and failure modes.

## Experiments

1. Enumerate shareable windows with ScreenCaptureKit.
2. Identify the iPhone Mirroring window.
3. Capture a still frame.
4. Capture a short sequence of frames.
5. Inspect frame dimensions and image quality.
6. Run Vision OCR against a representative draft screen.
7. Record permission and reliability limitations.

## Acceptance criteria

- The mirrored window can be identified consistently.
- Captured frames contain enough detail to attempt card recognition.
- Capture does not require administrator privileges.
- Permission failures are understandable and recoverable.
- The application does not need to automate or interact with Arena.

## Deliverable

A small working capture prototype, sample observations, and a written
go/no-go assessment.

Do not proceed to a large recognition implementation until this
milestone has been evaluated.
EOF

cat > Package.swift <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UrzasOculus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UrzasOculusCore",
            targets: ["UrzasOculusCore"]
        ),
        .executable(
            name: "UrzasOculus",
            targets: ["UrzasOculusApp"]
        )
    ],
    targets: [
        .target(
            name: "UrzasOculusCore"
        ),
        .executableTarget(
            name: "UrzasOculusApp",
            dependencies: ["UrzasOculusCore"]
        ),
        .testTarget(
            name: "UrzasOculusCoreTests",
            dependencies: ["UrzasOculusCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
EOF

cat > Sources/UrzasOculusCore/ProjectMetadata.swift <<'EOF'
public enum ProjectMetadata {
    public static let name = "Urza's Oculus"
    public static let bundleIdentifier = "com.local.urzas-oculus"
    public static let minimumMacOSVersion = "14.0"
}
EOF

cat > Sources/UrzasOculusCore/CaptureEngine/CaptureEngine.swift <<'EOF'
// ScreenCaptureKit integration will live here.
public enum CaptureEngineModule {}
EOF

cat > Sources/UrzasOculusCore/RecognitionEngine/RecognitionEngine.swift <<'EOF'
// OCR and card recognition will live here.
public enum RecognitionEngineModule {}
EOF

cat > Sources/UrzasOculusCore/DraftEngine/DraftEngine.swift <<'EOF'
// Draft history and state transitions will live here.
public enum DraftEngineModule {}
EOF

cat > Sources/UrzasOculusCore/ScoringEngine/ScoringEngine.swift <<'EOF'
// Deterministic pick evaluation will live here.
public enum ScoringEngineModule {}
EOF

cat > Sources/UrzasOculusCore/DataEngine/DataEngine.swift <<'EOF'
// Versioned reference data and normalization will live here.
public enum DataEngineModule {}
EOF

cat > Sources/UrzasOculusCore/CollectionEngine/CollectionEngine.swift <<'EOF'
// Optional collection context will live here.
public enum CollectionEngineModule {}
EOF

cat > Sources/UrzasOculusApp/main.swift <<'EOF'
import SwiftUI
import UrzasOculusCore

@main
struct UrzasOculusApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 520, minHeight: 360)
        }
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(ProjectMetadata.name)
                .font(.largeTitle)
                .bold()

            Text("MTG Arena draft companion")
                .font(.title3)

            Text("Foundation scaffold — capture and recognition are not yet implemented.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
EOF

cat > Tests/UrzasOculusCoreTests/ProjectMetadataTests.swift <<'EOF'
import XCTest
@testable import UrzasOculusCore

final class ProjectMetadataTests: XCTestCase {
    func testProjectMetadata() {
        XCTAssertEqual(ProjectMetadata.name, "Urza's Oculus")
        XCTAssertEqual(ProjectMetadata.bundleIdentifier, "com.local.urzas-oculus")
        XCTAssertEqual(ProjectMetadata.minimumMacOSVersion, "14.0")
    }
}
EOF

cat > scripts/package-app.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP_DIR="$ROOT_DIR/dist/UrzasOculus.app"
ZIP_FILE="$ROOT_DIR/dist/UrzasOculus-macos.zip"

rm -rf "$APP_DIR" "$ZIP_FILE"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$BIN_DIR/UrzasOculus" "$APP_DIR/Contents/MacOS/UrzasOculus"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>UrzasOculus</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.urzas-oculus</string>
    <key>CFBundleName</key>
    <string>Urza's Oculus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_FILE"

echo "Created: $ZIP_FILE"
EOF

chmod +x scripts/package-app.sh

cat > .gitignore <<'EOF'
.DS_Store
.build/
.swiftpm/
dist/
*.xcuserstate
xcuserdata/
.env
.env.*
EOF

cat > .github/workflows/ci.yml <<'EOF'
name: macOS CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  build-and-test:
    runs-on: macos-15

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Show Swift version
        run: swift --version

      - name: Run tests
        run: swift test

      - name: Package application
        run: ./scripts/package-app.sh

      - name: Upload macOS application
        uses: actions/upload-artifact@v4
        with:
          name: UrzasOculus-macos
          path: dist/UrzasOculus-macos.zip
          if-no-files-found: error
          retention-days: 14
EOF

cat > .github/pull_request_template.md <<'EOF'
## Summary

<!-- What does this change do? -->

## Validation

- [ ] macOS CI passes
- [ ] Tests added or updated where appropriate
- [ ] Documentation updated where appropriate

## Project constraints

- [ ] No runtime cloud inference or paid API dependency
- [ ] No Arena input automation
- [ ] Local-first behavior preserved
EOF

git add .
git commit -m "chore: bootstrap Urza's Oculus project"
git push -u origin "$BRANCH"

echo
echo "Changes pushed to $BRANCH"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh pr create \
    --base main \
    --head "$BRANCH" \
    --title "Initial Urza's Oculus project scaffold" \
    --body "Establishes the initial SwiftPM project, project steering and architecture documentation, technical capture feasibility milestone, and macOS CI build/test/artifact workflow."
else
  echo "Git push succeeded. Create a pull request at:"
  echo "https://github.com/$REPO/compare/main...$BRANCH"
fi