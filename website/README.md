# Urza's Oculus website

This directory contains the standalone Hugo site.

## Local development

Install Hugo Extended, then run:

```sh
cd website
hugo server
```

Build a production copy:

```sh
hugo --minify --destination public
```

## Cloudflare Pages

Configure the Pages project with:

- **Root directory:** `website`
- **Build command:** `hugo --minify`
- **Build output directory:** `public`
- **Environment variable:** `HUGO_VERSION` set to the version used by `.github/workflows/website-ci.yml`

Cloudflare Pages handles deployment and preview deployments. GitHub Actions validates pull requests but does not deploy the site. Keep the Hugo version in this file, the GitHub workflow, and the Cloudflare environment variable in sync.

## Content status

Keep public claims aligned with the actual project phase. The current app is in Phase 0 capture feasibility; OCR, recognition, draft tracking, and recommendations are roadmap goals rather than shipped capabilities.
