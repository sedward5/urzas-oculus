import SwiftUI
import UrzasOculusCore

@main
struct UrzasOculusApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 600)
        }
    }
}

private struct ContentView: View {
    @StateObject private var captureEngine = CaptureEngine()
    @State private var selectedWindowID: UInt32?

    private var selectedWindow: CaptureWindow? {
        captureEngine.windows.first {
            $0.id == selectedWindowID
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            permissionSection

            windowSection

            captureSection

            statusSection
        }
        .padding(24)
        .task {
            await refreshWindows()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Urza's Oculus")
                .font(.largeTitle.bold())

            Text("Screen Capture Feasibility Prototype")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionSection: some View {
        GroupBox("Screen Recording Permission") {
            HStack {
                if captureEngine.hasScreenRecordingPermission {
                    Label(
                        "Permission available",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "Permission required",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }

                Spacer()

                Button("Request Permission") {
                    captureEngine.requestPermission()
                }
                .disabled(captureEngine.hasScreenRecordingPermission)
            }
            .padding(.vertical, 4)
        }
    }

    private var windowSection: some View {
        GroupBox("Available Windows") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(captureEngine.windows.count) windows found")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Refresh Windows") {
                        Task {
                            await refreshWindows()
                        }
                    }
                    .disabled(captureEngine.isBusy)
                }

                if captureEngine.windows.isEmpty {
                    ContentUnavailableView(
                        "No Windows Found",
                        systemImage: "macwindow",
                        description: Text(
                            "Grant Screen Recording permission and refresh."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    Picker("Window", selection: $selectedWindowID) {
                        Text("Select a window")
                            .tag(Optional<UInt32>.none)

                        ForEach(captureEngine.windows) { window in
                            Text(windowOptionTitle(window))
                                .tag(Optional(window.id))
                        }
                    }
                    .labelsHidden()

                    if let selectedWindow {
                        HStack {
                            Text(
                                "\(selectedWindow.width) × \(selectedWindow.height)"
                            )
                            .foregroundStyle(.secondary)

                            Spacer()

                            if selectedWindow.isMirroringCandidate {
                                Label(
                                    "Possible iPhone Mirroring window",
                                    systemImage: "iphone"
                                )
                                .foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var captureSection: some View {
        GroupBox("Captured Frame") {
            VStack(spacing: 12) {
                HStack {
                    Button("Capture Still Frame") {
                        guard let selectedWindowID else { return }

                        Task {
                            await captureEngine.capture(
                                windowID: selectedWindowID
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        selectedWindowID == nil
                            || captureEngine.isBusy
                            || !captureEngine.hasScreenRecordingPermission
                    )

                    if captureEngine.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if let image = captureEngine.capturedImage {
                        Text("\(image.width) × \(image.height)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let image = captureEngine.capturedImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .background(.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ContentUnavailableView(
                        "No Capture Yet",
                        systemImage: "viewfinder",
                        description: Text(
                            "Select a window and capture a still frame."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text(captureEngine.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func windowOptionTitle(_ window: CaptureWindow) -> String {
        let marker = window.isMirroringCandidate ? " ★" : ""

        return "\(window.applicationName): \(window.title)\(marker)"
    }

    private func refreshWindows() async {
        await captureEngine.refreshWindows()

        if !captureEngine.windows.contains(where: {
            $0.id == selectedWindowID
        }) {
            selectedWindowID = captureEngine.windows.first(
                where: \.isMirroringCandidate
            )?.id ?? captureEngine.windows.first?.id
        }
    }
}
