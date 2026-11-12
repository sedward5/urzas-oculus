# Phase 0 — Screen Capture Feasibility

## Objective

Determine whether ScreenCaptureKit can reliably capture the macOS
iPhone Mirroring window on macOS 14 or newer.

The goal is to validate the capture path before investing in OCR,
card recognition, or draft-state tracking.

## Prototype capabilities

The current prototype provides:

- Screen Recording permission status.
- A permission request action.
- Enumeration of visible shareable application windows.
- A heuristic that highlights likely iPhone Mirroring windows.
- Manual selection of a window.
- Still-frame capture of the selected window.
- Display of the captured image and its pixel dimensions.
- Basic error reporting.

The window-identification heuristic is advisory. The user remains
responsible for selecting the correct window.

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

- [ ] Capture a short sequence of frames.
- [ ] Measure frame delivery and processing costs.
- [ ] Determine whether continuous capture is necessary.
- [ ] Evaluate capture behavior while the mirrored display changes.

### 5. Recognition suitability

- [ ] Capture representative Arena draft screens.
- [ ] Record actual image dimensions.
- [ ] Inspect card text and visual detail.
- [ ] Evaluate whether the captured image is suitable for Vision OCR.

Do not begin substantial card recognition implementation until
capture quality has been evaluated.

## Acceptance criteria

- The mirrored window can be identified consistently.
- Captured frames contain only the selected window.
- Captured images preserve sufficient detail for OCR.
- Permission failures are understandable and recoverable.
- Capture does not require administrator privileges.
- The application does not automate or interact with Arena.
- The application does not transmit captured screen contents.

## Current limitations

The prototype captures still images only.

It does not yet provide:

- Continuous frame capture.
- OCR.
- Card recognition.
- Draft-state tracking.
- Automated window selection.

The iPhone Mirroring identification heuristic has not yet been
validated against real-world window metadata.

## Deliverable

A working capture prototype, representative observations, and a
written go/no-go assessment.

The next milestone is to validate the prototype on a real macOS
installation with iPhone Mirroring active.
