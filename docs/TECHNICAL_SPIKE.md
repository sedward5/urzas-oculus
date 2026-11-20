# Phase 0 — Screen Capture Feasibility

## Status (2026-11-20)

The ScreenCaptureKit prototype and bounded three-second sequence capture are implemented and merged. Real-world manual validation on the target Mac remains the next gate. A representative Arena draft recording is being prepared; capture quality, window identification, and OCR suitability have not yet been established.

## Objective

Determine whether ScreenCaptureKit can reliably capture the macOS
iPhone Mirroring window on macOS 14 or newer.

The goal is to validate the capture path before investing in OCR,
card recognition, or draft-state tracking.

## Prototype capabilities

The current prototype provides:

- Screen Recording permission status and a permission request action.
- Enumeration of visible shareable application windows.
- An advisory heuristic for likely iPhone Mirroring windows.
- Manual window selection.
- Still-frame capture of the selected window.
- A three-second, window-scoped frame sequence capture.
- Local sampling at up to four frames per second, capped at twenty frames.
- A thumbnail strip for inspecting the captured sequence.
- Pixel dimensions and basic capture error reporting.

The window-identification heuristic is advisory. The user remains
responsible for selecting the correct window.

The sequence capture is a bounded feasibility sample, not a production
continuous-capture service. It captures only the selected window and
does not capture audio or transmit frames.

## Experiments

### 1. Window discovery

- [x] Implement ScreenCaptureKit window enumeration.
- [x] Filter for visible application windows.
- [x] Add an initial iPhone Mirroring identification heuristic.
- [ ] Validate the heuristic on multiple macOS configurations.
- [ ] Record the actual application name and bundle identifier.

### 2. Still-frame capture

- [x] Capture a selected window using ScreenCaptureKit.
- [x] Exclude unrelated desktop content through a window-specific filter.
- [x] Display the resulting image.
- [ ] Verify capture quality at different iPhone display settings.
- [ ] Verify that the complete mirrored window is captured.

### 3. Permissions

- [x] Check Screen Recording permission.
- [x] Provide a permission request action.
- [x] Report basic permission and capture errors.
- [ ] Verify first-launch behavior.
- [ ] Verify behavior after permission is granted and the app restarts.
- [ ] Document any macOS-version-specific behavior.

### 4. Frame sequence

- [x] Capture a short sequence of frames.
- [x] Bound the sample duration, sampling rate, and retained frame count.
- [x] Display sampled frames for manual inspection.
- [ ] Measure frame delivery and processing costs on a real Mac.
- [ ] Determine whether continuous capture is necessary.
- [ ] Evaluate capture behavior while the mirrored display changes.

### 5. Recognition suitability

- [ ] Capture representative Arena draft screens.
- [ ] Record actual image dimensions.
- [ ] Inspect card text and visual detail.
- [ ] Evaluate whether the captured image is suitable for Vision OCR.

Do not begin substantial card recognition implementation until
capture quality has been evaluated.

## Manual validation procedure

On the target Mac:

1. Build and launch Urza's Oculus.
2. Grant Screen Recording permission if prompted. Restart the app if macOS requires it.
3. Open iPhone Mirroring and display a representative Arena draft pack.
4. Refresh the available windows and select the mirrored iPhone window.
5. Capture a still frame. Confirm the entire mirrored window is present.
6. Capture a three-second sequence while scrolling or otherwise changing the mirrored display.
7. Inspect the thumbnails. Confirm they show the selected window only and that changing content appears across the sequence.
8. Record the frame count, pixel dimensions, visible text clarity, and any dropped or repeated frames.

Do not use private or unrelated screen content as test fixtures. Captures remain
local to the app process and are not uploaded by this prototype.

## Acceptance criteria

- The mirrored window can be identified consistently.
- Captured frames contain only the selected window.
- Captured images preserve sufficient detail for OCR.
- Permission failures are understandable and recoverable.
- Capture does not require administrator privileges.
- The application does not automate or interact with Arena.
- The application does not transmit captured screen contents.

## Current limitations

The prototype supports still images and a bounded three-second sample.
It does not provide an always-on capture service or background monitoring.

It does not yet provide:

- OCR.
- Card recognition.
- Draft-state tracking.
- Automated window selection.

The iPhone Mirroring identification heuristic has not yet been
validated against real-world window metadata. Image quality and frame
delivery also remain unverified on the user's target Mac.

## Deliverable

A working capture prototype, representative observations, and a
written feasibility assessment.

The next milestone is manual validation on a real macOS installation
with iPhone Mirroring active. Recognition work remains gated on that
assessment.
