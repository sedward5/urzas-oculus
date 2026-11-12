import Combine
import CoreGraphics
import ScreenCaptureKit

public struct CaptureWindow: Identifiable, Equatable {
    public let id: UInt32
    public let title: String
    public let applicationName: String
    public let width: Int
    public let height: Int
    public let isMirroringCandidate: Bool

    public var displayName: String {
        "\(applicationName) — \(title)"
    }

    public static func isMirroringCandidate(
        ownerName: String,
        windowTitle: String?,
        bundleIdentifier: String?
    ) -> Bool {
        let owner = ownerName.lowercased()
        let title = (windowTitle ?? "").lowercased()
        let bundle = (bundleIdentifier ?? "").lowercased()

        return owner.contains("iphone mirroring")
            || title.contains("iphone mirroring")
            || bundle.contains("screencontinuity")
    }
}

@MainActor
public final class CaptureEngine: ObservableObject {
    @Published public private(set) var windows: [CaptureWindow] = []
    @Published public private(set) var capturedImage: CGImage?
    @Published public private(set) var hasScreenRecordingPermission = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var statusMessage = "Ready."

    private var windowsByID: [UInt32: SCWindow] = [:]

    public init() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }

    /// Requests macOS screen-recording permission.
    ///
    /// macOS may require the application to be restarted after permission
    /// is granted before capture becomes available.
    public func requestPermission() {
        hasScreenRecordingPermission = CGRequestScreenCaptureAccess()

        if hasScreenRecordingPermission {
            statusMessage = "Permission granted. Refresh the window list."
        } else {
            statusMessage = """
            Screen Recording permission is not available yet. Check \
            System Settings > Privacy & Security > Screen Recording.
            You may need to restart the application.
            """
        }
    }

    /// Enumerates visible, shareable application windows.
    public func refreshWindows() async {
        guard !isBusy else { return }

        isBusy = true
        defer { isBusy = false }

        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()

        guard hasScreenRecordingPermission else {
            windows = []
            windowsByID = [:]
            statusMessage = """
            Screen Recording permission is required. Use the permission \
            button below, then check System Settings if necessary.
            """
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            let eligibleWindows = content.windows.filter { window in
                window.isOnScreen
                    && window.owningApplication != nil
                    && window.frame.width > 200
                    && window.frame.height > 150
            }

            windowsByID = Dictionary(
                uniqueKeysWithValues: eligibleWindows.map {
                    ($0.windowID, $0)
                }
            )

            windows = eligibleWindows.map { window in
                let application = window.owningApplication
                let ownerName = application?.applicationName ?? "Unknown"
                let title = window.title ?? "Untitled window"

                let candidate = CaptureWindow.isMirroringCandidate(
                    ownerName: ownerName,
                    windowTitle: window.title,
                    bundleIdentifier: application?.bundleIdentifier
                )

                return CaptureWindow(
                    id: window.windowID,
                    title: title,
                    applicationName: ownerName,
                    width: Int(window.frame.width),
                    height: Int(window.frame.height),
                    isMirroringCandidate: candidate
                )
            }
            .sorted {
                if $0.isMirroringCandidate != $1.isMirroringCandidate {
                    return $0.isMirroringCandidate
                }

                return $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }

            statusMessage = windows.isEmpty
                ? "No eligible windows found."
                : "Found \(windows.count) visible windows."
        } catch {
            windows = []
            windowsByID = [:]
            statusMessage = "Unable to enumerate windows: \(error.localizedDescription)"
        }
    }

    /// Captures a still image of one selected window.
    public func capture(windowID: UInt32) async {
        guard !isBusy else { return }

        guard hasScreenRecordingPermission else {
            statusMessage = "Screen Recording permission is required."
            return
        }

        guard let window = windowsByID[windowID] else {
            statusMessage = "That window is no longer available. Refresh the list."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)

            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width))
            configuration.height = max(1, Int(window.frame.height))
            configuration.capturesAudio = false
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            capturedImage = image

            statusMessage = """
            Captured \(image.width) × \(image.height) pixels.
            """
        } catch {
            capturedImage = nil
            statusMessage = "Capture failed: \(error.localizedDescription)"
        }
    }
}
