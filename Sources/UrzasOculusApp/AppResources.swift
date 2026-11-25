import Foundation

/// Locates the SwiftPM resource bundle without trapping.
///
/// SwiftPM's generated `Bundle.module` calls `fatalError` when the bundle is missing, which
/// crashes the app at launch if packaging omits it. This lookup covers the packaged app
/// (`Contents/Resources`) and `swift run` (bundle beside the executable), and returns nil
/// otherwise so callers can show their existing "catalog unavailable" state.
enum AppResources {
    static let bundleName = "UrzasOculus_UrzasOculusApp.bundle"

    static let bundle: Bundle? = {
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent()
        ]
        for base in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: base.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        return nil
    }()
}
