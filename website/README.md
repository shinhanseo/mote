# Mote introduction page

A static Korean product page inspired by the explanatory structure of cracker.im, with Mote’s own olive palette, typography, character and illustrative product demos. No reference assets or copy are reused.

## Preview

From the repository root:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open http://127.0.0.1:4173. `index.html` can also be opened directly; there is no build step, JavaScript dependency, analytics, account or backend. Demo controls only change the page and never connect to Codex. All illustrated task names are fictional.

## Before publishing

- Public URL: https://shinhanseo.github.io/mote/
- GitHub Pages deploys `website/` from main through `.github/workflows/pages.yml`.
- Current installation CTA links to the real GitHub source/build instructions. No fake downloadable app, pricing, testimonials or waitlist are shown.
- Complete Developer ID signing/notarization and publish an approved release before adding a general download button. Keep Apple Silicon/Intel availability accurate for the files actually released.
- Canonical URL and social metadata use the GitHub Pages URL. Update them if a custom domain is added.
- For a static host, use `website/` as the root with no build command. Can be deployed to Sites, GitHub Pages or another static host. No server compute is required.
- To deploy with Sites later, register the Site and set its hosting manifest; no Site identity has been created for this local draft.

The website lives beside the Swift app in the same Git repository but runs and deploys independently. App changes do not automatically become website updates; update the truthful feature descriptions and version together.

Public notarized download: https://github.com/shinhanseo/mote/releases/download/v0.2.0/Mote-0.2.0.dmg

Public notarized download: https://github.com/shinhanseo/mote/releases/download/v0.3.0/Mote-0.3.0.dmg

Public notarized download: https://github.com/shinhanseo/mote/releases/download/v0.3.1/Mote-0.3.1.dmg

Public notarized download: https://github.com/shinhanseo/mote/releases/download/v0.4.0/Mote-0.4.0.dmg

Public notarized download: https://github.com/shinhanseo/mote/releases/download/v0.4.1/Mote-0.4.1.dmg
