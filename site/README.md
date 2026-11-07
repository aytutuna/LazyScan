# Lazy Scan website

The product page for Lazy Scan: a single static `index.html` (CSS and JavaScript inline) plus `privacy.html` and the screenshots in `assets/`. The pages use system fonts and make no requests to other hosts, which `privacy.html` says; keep it that way, or change the policy in the same commit.
To preview it, open `index.html` in a browser, or serve the folder with any static server, for example `python -m http.server 8000` from this folder and then visit http://localhost:8000.
There is no build step. `.github/workflows/pages.yml` deploys the folder to GitHub Pages on every push to `main` that touches `site/` (and by hand from the Actions tab); Pages must be set to the GitHub Actions source under Settings > Pages, with scan.alazy.app as the custom domain (a CNAME record on scan pointing at aytutuna.github.io). `privacy.html` and the Support section are the privacy and support URLs given to App Store Connect.
