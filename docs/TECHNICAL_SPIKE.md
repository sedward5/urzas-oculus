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
