# Images in Stickies — PRD

**Status**: approved (why-chain validated 2026-05-26)
**Date**: 2026-05-26
**Scope**: incremental on v1 Stickies (apps/stickies)

## 1. Why this exists

When you're working on something — code, a doc, a design — and you want a visual reference (a Figma frame, a screenshot, a chart) to *stay on top of the work*, the current Stickies only lets you write text about the reference. The reference itself lives in some other window you keep tabbing to, or in a screenshot file you keep opening.

This change lets the reference and your notes about it live in the same always-on-top sticky pane.

> When Rahul is working with text/code/design and wants a visual reference to stay on top of the work surface alongside his thoughts about it, he wants to drop images directly into a sticky — so the reference and his notes live in one always-on-top pane, instead of swapping windows or babysitting a separate image viewer.

## 2. User story

- I take a screenshot (cmd-shift-4) → cmd-V into a sticky → it appears at the note's width, aspect-preserved.
- I drag a PNG from Finder → drop onto a sticky → same thing.
- I right-click in the sticky → **Add Image…** → Finder picker → choose a file → it appears.
- I move the cursor below the image and type. The image stays put. Text above and below it flows around the image like any inline block.
- I resize the sticky window wider → the image grows with it. Narrower → it shrinks. Aspect always preserved.
- I delete the image by putting my cursor next to it and hitting backspace, like any text character.
- I quit the app and reopen. The note has the image, in the same place, at the right size.

## 3. Goals

- **Inline.** Image lives in the text stream — text above, text below, no separate gallery panel.
- **Width-fit.** Image width always equals current note text width. Aspect ratio always preserved. No image-sizing handles.
- **Three entry points.** Drag (from anywhere), paste (cmd-V after a screenshot), right-click → Add Image…
- **Persists.** Image survives quit, relaunch, force-quit.
- **Zero new chrome.** No image toolbar, no edit buttons, no resize handles. The note still looks like a note.

## 4. Non-goals

- No image editing (crop, rotate, annotate, redact, filter).
- No multi-image-per-row layouts. One image per "line."
- No image captions as a distinct feature — anything you type below the image *is* the caption.
- No image-only "lightbox" mode. The note is still primarily a text surface that happens to also hold images.
- No image export / extraction UI. (You can drag the image *out* of a sticky into Finder, because AppKit gives that for free, but it's not a feature we're polishing.)
- No accepting non-image files dragged onto a sticky (PDFs, RTF documents, etc.) — those are silently rejected.
- No image search, no tagging, no metadata visible to the user.

## 5. Interaction model

### Insertion

| Trigger | Behavior |
|---------|----------|
| Drag image file from Finder onto a sticky | Image inserted at cursor (or at drop point if cursor isn't in the note); note becomes key window |
| Drag image from another app (Safari, Photos, Preview) | Same — image inserted |
| cmd-V with an image on the clipboard | Image inserted at cursor; replaces any selected text/image |
| cmd-V with text + image (mixed clipboard) | Text inserted (no image); existing behavior preserved |
| Right-click inside note → **Add Image…** | NSOpenPanel filtered to common image types; selection inserts at cursor |
| Drag a non-image file (e.g., a PDF) | Drop rejected silently — the note isn't disturbed |

### Sizing

- On insertion: image scales so its width equals the note's text content width (note width minus left/right padding). Height = width × original aspect ratio.
- On note resize: image rescales live as the window resizes. No discontinuity at any width.
- Minimum: the existing note minimum size (160 × 140) applies; images at very narrow widths just appear small but still visible.
- Maximum: none — if you make a note huge, the image grows huge.

### Removal

- Image behaves like a single character in the text stream.
- Backspace adjacent to it deletes it.
- Select it (cursor placement around it, shift-arrow) → backspace or cut also deletes.
- Deleting the note (× button) deletes the image with it. No orphan recovery, no export prompt.

### Multiple images

- A note can contain any number of images, interleaved with text in any order.
- Each image gets its own line. Two images cannot share a horizontal line.

## 6. Visual spec

- Image background: transparent. The note's dark frosted-glass shows through any image transparency.
- Image corners: square (no rounding). The note's outer corner radius is unaffected.
- Padding: same horizontal padding as text (16 px each side via `NoteTheme.innerPadding`). Image is centered in the available content width (which is the entire content width — no extra centering math needed because width-fit *is* the layout).
- Vertical spacing: image gets its own line; spacing above/below follows the existing line-height settings. Nothing custom.
- No border, no shadow, no caption styling.

## 7. Success criteria

1. **Insertion under 1 second** on a 5MB image from clipboard. Note: this is a "feels instant" target, not a hard SLA.
2. **Quit/relaunch round-trip preserves the image** at the same position with the same fidelity (no visual quality loss).
3. **Note resize repaints image at new width within one frame** — no visible stutter on a typical mid-line image.
4. **Force-quit during paste** (immediately after cmd-V) — on relaunch, either the image is fully there or fully absent; no half-saved corruption.
5. **Existing v2 notes load unchanged** — anyone with notes from before this update sees their text intact, no migration warnings.
6. **Non-image drops are silent** — dragging a PDF or RTF onto a note doesn't insert anything and doesn't show an error.

## 8. Out of scope (future)

- Click-to-zoom into an image (modal preview).
- Manual image sizing (drag corner handles to make an image smaller than note width).
- Image side-by-side layouts.
- Markdown-style image syntax (`![](url)`).
- Cloud-hosted images / pasted URLs that render as images.

These can land in a v3 of this feature if the v2 ergonomics surface real demand.

## 9. Risks

- **Pasteboard surprises.** macOS clipboard often has multiple representations (image + URL + RTF). The paste handler must pick deterministically.
- **NSTextView default drag behavior** accepts more than images. We filter, but if filtering misses an edge case, ugly content (e.g., RTF documents) could embed.
- **Performance with many large images.** Hold-current behavior at one note × ten 4K screenshots. If a single note routinely holds dozens of huge images, layout may become slow; that's beyond v1.

See the TRD for the engineering mitigations.

## 10. Open questions

None at PRD time. Three open items from brainstorming resolved verbally on 2026-05-26:

- **Paste via cmd-V** → yes, include.
- **Image rescales live on note resize** → yes.
- **Image deleted with the note** → yes, no recovery flow.
