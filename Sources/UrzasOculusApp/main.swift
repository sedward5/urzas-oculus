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
