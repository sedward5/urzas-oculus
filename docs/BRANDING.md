# Urza's Oculus Brand & Visual Style Guide

This document is the shared visual reference for the macOS app, website, documentation, and future public data views.

## Brand idea

**An arcane instrument for seeing the shape of a draft.**

Urza's Oculus combines the craft and mystery of a finely made astrolabe with the clarity of a modern analytical tool. The visual identity should feel curious, precise, and quietly powerful—not ominous, noisy, or overly theatrical.

The central symbol is a brass oculus containing a luminous blue crystal. The instrument represents observation and measurement; the crystal represents insight.

## Brand personality

- **Perceptive:** helps players notice patterns and make better-informed decisions.
- **Thoughtful:** explains recommendations and their evidence.
- **Crafted:** feels carefully made, with details that reward attention.
- **Approachable:** supports learning and experimentation without judging the player.
- **Honest:** communicates data coverage, uncertainty, and limitations plainly.

Avoid fear-based language, claims of perfect picks, and visual cues associated with gambling or competitive esports.

## Core palette

Use these values as the initial shared design tokens. Keep the bright colors for emphasis rather than filling every surface.

| Token | Hex | Role |
|---|---|---|
| Oculus Navy | #101D32 | Primary dark canvas and brand background |
| Deep Slate | #263B55 | Raised surfaces, panels, secondary backgrounds |
| Arcane Blue | #35BDF2 | Primary accent, links, focus, active states |
| Crystal Cyan | #8CEBFF | Highlights, selected data, luminous details |
| Aged Brass | #C49A52 | Brand ornament, dividers, restrained emphasis |
| Pale Brass | #E7C98B | High-contrast brass details on dark surfaces |
| Mist | #D8E2EF | Primary text on dark surfaces |
| Muted Mist | #9EADC1 | Secondary text and supporting labels |

### Color usage

- Navy is the anchor. Prefer layered navy/slate surfaces over pure black.
- Arcane Blue is the primary interactive accent.
- Crystal Cyan is brighter and should be used sparingly for the most important signal.
- Brass is decorative and editorial. Do not use it as the default color for every button or data series.
- Pair every status color with text or an icon; never communicate meaning through color alone.
- Provide a light appearance only when it can preserve contrast and hierarchy. The brand's default presentation is dark.

## Typography

Use system-native typography so the app feels at home on macOS and the website remains fast and dependable.

- **App:** SF system typography. Use clear hierarchy, comfortable line lengths, and native control sizing.
- **Website:** a modern system sans-serif stack (for example, system-ui, -apple-system, BlinkMacSystemFont, and Segoe UI).
- **Headings:** medium to semibold weights. Avoid fantasy, medieval, or sci-fi display fonts.
- **Data:** use tabular numerals for aligned statistics where available.
- **Body copy:** concise, plain-language explanations. Explain draft and statistical terminology when it first appears.

## Shape, surfaces, and materials

- Prefer clean geometry, restrained corner radii, and clear spacing.
- Use subtle gradients, soft radial light, and layered navy surfaces to echo the crystal.
- Use fine brass lines or astrolabe-inspired arcs as occasional framing details.
- Keep ornament behind content. Do not put elaborate borders around every card, table, or control.
- Use translucency and blur only where they improve hierarchy; preserve legibility and respect macOS appearance conventions.
- Let native macOS controls look native. Do not imitate the operating system's chrome in custom components.

## Iconography and artwork

### App icon concept

The icon is a symmetrical brass astrolabe/oculus surrounding a luminous cyan-blue crystal, set against a deep navy cosmic field.

- Keep the crystal as the strongest focal point.
- Preserve the brass instrument silhouette and circular geometry.
- Favor strong large-scale shapes over tiny engraved detail.
- Do not add a wordmark or small text to the icon.
- The icon artwork is square source artwork. Let macOS apply its own icon mask and presentation; do not add a second rounded-square frame or shadow baked into future source artwork.

The current compact source is Resources/AppIcon.jpg. It is a 512 × 512 JPEG chosen to keep the repository asset lightweight. The packaging script converts it into the required PNG icon sizes and .icns bundle resource. Keep a higher-resolution archival master outside the runtime bundle if one is needed for future re-export.

### Other imagery

Use the oculus, crystal facets, orbit lines, and restrained astrolabe geometry as supporting motifs. Do not use copyrighted Magic: The Gathering card art as general brand decoration. Card imagery shown as product data should remain clearly attributable to its source.

## Data visualization

Statistics are a core product feature, not decoration.

- Use Arcane Blue for the primary series or selected metric.
- Use Aged Brass for a meaningful comparison or secondary emphasis.
- Use Crystal Cyan for a standout value, not every data point.
- Use muted slate and mist for axes, labels, and supporting context.
- Prefer direct labels, clear units, and explicit sample sizes.
- Show set, format, time window, and data provenance where relevant.
- Distinguish missing data from zero.
- Explain that 17Lands metrics may be weighted and that coverage can vary.
- Do not imply a causal relationship from descriptive statistics.

## Interaction and accessibility

- Provide visible keyboard focus using Arcane Blue with sufficient contrast.
- Ensure body text and controls meet WCAG AA contrast targets.
- Never use color as the only signal for success, warning, selection, or recommendation.
- Keep hover and motion effects subtle. Respect reduced-motion preferences.
- Use plain-language labels and explain abbreviations.
- Recommendations should show useful reasoning and uncertainty, not just a score.

## Website direction

The public website should feel like a polished analytical tool with a touch of arcane character—not a fantasy game landing page.

- Use a deep navy canvas, restrained brass details, and blue/cyan accents.
- Keep navigation, headings, and content layouts simple.
- Give methodology, data provenance, and limitations clear space.
- Use decorative astrolabe geometry sparingly, preferably as low-contrast background artwork.
- Make the site useful even when no current card-statistics artifact is published.

## macOS app direction

- Prioritize native SwiftUI controls and platform conventions.
- Use navy/slate surfaces only where custom presentation is appropriate.
- Reserve cyan for active capture, selection, and recommendation emphasis.
- Use brass as a small brand accent rather than a dominant UI color.
- Keep dense draft information scannable, with clear labels and compact explanations.

## Do

- Lead with the crystal and oculus as recognizable brand cues.
- Keep data presentation calm, precise, and explainable.
- Use a consistent palette across the app and website.
- Make uncertainty and data coverage visible.
- Prefer clarity over ornament.

## Avoid

- Pure black/red security-style palettes.
- Excessive gold gradients, glowing borders, and lens flares.
- Tiny illegible runes or decorative text.
- Generic fantasy typography.
- Overly dense dashboards and unexplained scores.
- Treating the brand icon as a literal UI component repeated everywhere.

## Change control

This guide is the starting point, not a reason to block sensible platform conventions. When app and website needs differ, preserve the shared palette and personality while adapting layout and interaction to each platform. Update this document when a deliberate brand decision changes.
