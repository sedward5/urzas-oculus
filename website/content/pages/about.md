---
title: "About the project"
description: "How Urza's Oculus is being built, what it values, and where the project is headed."
---

Urza's Oculus is a native macOS companion for Magic: The Gathering Arena drafting. It is being built around a simple idea: useful recommendations should be explainable, grounded in evidence, and honest about what the data can and cannot say.

## The principles

### Your draft is the source of truth

The record of cards observed and choices made should drive the draft state. The drafted pool is derived from that history, rather than maintained as a separate, potentially conflicting source.

### Recommendations should explain themselves

A score without context is not enough. Oculus aims to show the evidence behind a recommendation, including relevant card performance, format context, and uncertainty.

### Data should be reproducible

Published results should identify their engine version, scoring configuration, schema, set, event, and dataset provenance. The same Swift recommendation core is intended to power the macOS app and generate public data artifacts.

### Local first, player controlled

The application is designed for local processing. It will not automate Arena interactions or make picks on the player's behalf.

## Development roadmap

- **Phase 0 — Capture feasibility:** validate window capture and frame collection, including scrolling in the mirrored Arena experience.
- **Recognition:** investigate local OCR and card identification against real captured frames.
- **Draft tracking:** record packs, observed cards, selections, corrections, and confidence.
- **Recommendations:** connect the draft state to versioned data and explainable local scoring.
- **Public statistics:** publish selected, reproducible data artifacts for exploration on this site.

These are development goals, not claims that the features are already available. The current prototype is in Phase 0.

## Data and attribution

17Lands public datasets are an important source for draft and game statistics. Dataset availability, coverage, and metric definitions can change. Oculus aims to preserve provenance and communicate known limitations rather than imply perfect parity or certainty.

Card metadata and imagery may use Scryfall services and data. Magic: The Gathering and Arena are trademarks of Wizards of the Coast. Urza's Oculus is an independent, unofficial project and is not affiliated with or endorsed by Wizards of the Coast.

## Follow development

The source code, technical notes, and project decisions are available in the [Urza's Oculus GitHub repository](https://github.com/sedward5/urzas-oculus).
