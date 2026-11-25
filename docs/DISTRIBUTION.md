# macOS app distribution

## Local packaging

On macOS 14 or later, run:

```sh
./scripts/package-app.sh
```

The script creates:

- `dist/UrzasOculus.app` — the application bundle
- `dist/UrzasOculus.dmg` — a compressed disk image containing the app and an `Applications` shortcut
- `dist/UrzasOculus-macos.zip` — a ZIP archive for alternate installation and developer workflows

The app bundle includes the SwiftPM resource bundle (`Contents/Resources/UrzasOculus_UrzasOculusApp.bundle`) containing the reviewed archetype and card catalogs. Packaging fails if that bundle is missing from the build output.

A local build defaults to bundle version `0.1.0`. CI supplies a monotonically increasing patch version for each macOS CI run.

## Automated releases

When a change affecting the macOS app or its packaging is pushed to `main`, the macOS CI workflow:

1. Runs the Swift test suite.
2. Packages the app as a ZIP and drag-to-install DMG.
3. Verifies the disk image and app bundle.
4. Publishes both files as assets on a GitHub Release.

The release tag includes the workflow run number and commit prefix. Releases are regular (not prereleases), so the website's stable `releases/latest/download/UrzasOculus.dmg` URL always points to the newest published build.

Changes limited to the website or Python-only scripts do not publish a new macOS release.

## Installation

1. Download and open `UrzasOculus.dmg`.
2. Drag `Urza's Oculus.app` onto the `Applications` shortcut.
3. Eject the mounted disk image and launch the app from Applications.

The current build is ad-hoc signed, not Developer ID signed or notarized. macOS may display an unidentified-developer warning on first launch. A Developer ID certificate and Apple notarization credentials are required to remove that warning for normal distribution.

## Release assets

Each automated release contains:

- `UrzasOculus.dmg` — recommended drag-to-install package
- `UrzasOculus-macos.zip` — alternate archive

The website links directly to the latest DMG and also provides a link to the full release history.
