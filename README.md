# Stickies

A minimal, beautiful floating sticky-notes app for macOS. Built in public.

- Frosted-glass dark notes, always on top.
- Drag-from-anywhere window, native edge resize.
- Hover-reveal tint picker (Mist / Smoke / Slate / Obsidian) and hide button.
- Hidden notes live in a Manager window for restore or permanent delete.
- Inline images: drag from Finder or a browser, paste from clipboard, or right-click → **Add Image…**. Images auto-fit the note's width.
- Local-only storage in `~/Library/Application Support/Stickies/notes/`.

## Build

Requires Xcode and [`xcodegen`](https://github.com/yonaskolb/XcodeGen).

```
brew install xcodegen
xcodegen generate
open Stickies.xcodeproj
```

Then ⌘R in Xcode.

## Design docs

- [`docs/2026-04-22-stickies-design.md`](docs/2026-04-22-stickies-design.md) — original v1 design spec
- [`docs/2026-04-22-stickies-plan.md`](docs/2026-04-22-stickies-plan.md) — v1 implementation plan
- [`docs/2026-05-14-hide-stickies-design.md`](docs/2026-05-14-hide-stickies-design.md) — hide + Manager design
- [`docs/2026-05-26-images-in-stickies-prd.md`](docs/2026-05-26-images-in-stickies-prd.md) — inline images PRD
- [`docs/2026-05-26-images-in-stickies-trd.md`](docs/2026-05-26-images-in-stickies-trd.md) — inline images TRD
- [`docs/2026-05-26-images-in-stickies-plan.md`](docs/2026-05-26-images-in-stickies-plan.md) — inline images implementation plan

## License

MIT — see [`LICENSE`](LICENSE).

Bundles [Geist Mono](https://github.com/vercel/geist-font) by Vercel under the SIL Open Font License 1.1 — see [`Stickies/Fonts/GeistMono-OFL.txt`](Stickies/Fonts/GeistMono-OFL.txt).
