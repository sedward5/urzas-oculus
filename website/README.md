# Urza's Oculus website

This directory contains the standalone Hugo site.

## Local development

Install Hugo Extended, then run:

```sh
cd website
python3 ../scripts/generate_website_archetype_pages.py\nhugo server
```

Build a production copy:

```sh
python3 ../scripts/generate_website_archetype_pages.py\nhugo --minify --destination public
```

## Cloudflare Pages

Configure the Pages project with:

- **Root directory:** `website`
- **Build command:** `python3 ../scripts/generate_website_archetype_pages.py && hugo --minify`
- **Build output directory:** `public`
- **Environment variable:** `HUGO_VERSION` set to the version used by `.github/workflows/website-ci.yml`

The page generator reads only `scripts/data/reviewed_archetypes.json`; acquired evidence is not promoted automatically. A set page appears only after its archetypes enter the human-reviewed catalog.\n\nCloudflare Pages handles deployment and preview deployments. GitHub Actions validates pull requests but does not deploy the site. Keep the Hugo version in this file, the GitHub workflow, and the Cloudflare environment variable in sync.

## Content status

Keep public claims aligned with the actual project phase. The current app is in Phase 0 capture feasibility; OCR, recognition, draft tracking, and recommendations are roadmap goals rather than shipped capabilities.
