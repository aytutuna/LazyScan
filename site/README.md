# Lazy Scan website

The product page for Lazy Scan: a single static `index.html` (CSS and JavaScript inline) plus `privacy.html` and the screenshots in `assets/`. The pages use system fonts and make no requests to other hosts, which `privacy.html` says; keep it that way, or change the policy in the same commit.
To preview it, open `index.html` in a browser, or serve the folder with any static server, for example `python -m http.server 8000` from this folder and then visit http://localhost:8000.
There is no build step. The folder is copied into the `scan/` folder of the alazy repo, which Cloudflare Pages serves at https://alazy.app/scan/. `privacy.html` and the Support section are the privacy and support URLs given to the stores.
