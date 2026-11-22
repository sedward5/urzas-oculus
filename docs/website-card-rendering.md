# Website card-rendering shortcodes

The website exposes three reusable shortcodes. Keep card metadata and relationships in the reviewed catalog; shortcodes only render presentation.

## Mana symbols

Use one symbol per shortcode. The value may include braces or omit them.

```text
{{< mana "W" >}} {{< mana "2/W" >}} {{< mana "W/U" >}} {{< mana "W/P" >}}
{{< mana "S" >}} {{< mana "T" >}} {{< mana "Q" >}} {{< mana "E" >}}
```

The shortcode maps hybrid and phyrexian separators to Scryfall's SVG symbol filenames. It uses Scryfall's public card-symbol artwork rather than a five-symbol local approximation.

## Full card image

Provide an image URL from reviewed card metadata:

```text
{{< card-image name="Example Card" src="https://cards.scryfall.io/normal/front/..." >}}
```

## Inline card name with preview

```text
{{< card name="Example Card" image="https://cards.scryfall.io/normal/front/..." >}}
```

The preview appears on hover for pointer users and can be opened by tapping the name on touch devices. An image URL is explicit because a card name alone is not a stable image identifier; later catalog enrichment should supply the verified Scryfall image URI.

## Image provenance

The macOS app reads the reviewed catalog bundled in its app target. Overview images are fetched and checksum-verified before being cached in Application Support. Fetching happens when the reference view opens, not during a draft. The website currently references the official Wizards media URLs directly.
