# Images in Stickies — Things only Rahul can do

**Status**: live
**Date**: 2026-05-26
**Companions**: [PRD](2026-05-26-images-in-stickies-prd.md) · [TRD](2026-05-26-images-in-stickies-trd.md) · [Plan](2026-05-26-images-in-stickies-plan.md)

This doc is the human-only surface of this change — confirmations needed, QA you have to drive, and end-of-feature decisions.

---

## 1. Decisions already captured

Confirmed verbally on 2026-05-26 during the why-chain pass. Recorded here so it doesn't get lost:

- **Paste from clipboard (cmd-V)** → included.
- **Image rescales live as the note window resizes** → yes.
- **Deleting the note deletes its images** → yes, no recovery flow.
- **No image editing tools** → confirmed in PRD.

If any of these change before code lands, ping me and I'll revise the TRD before continuing.

---

## 2. Manual QA after I finish implementing

I'll build the app and confirm it compiles cleanly. Everything below requires you because it needs a real cursor, real drag gestures, and your eyeballs.

Launch the built app:

```
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Stickies.app' -type d -path '*Debug*' 2>/dev/null | head -1)"
```

### 2.1 Entry points — does each one work?

- [ ] **Drag from Finder.** Drag a PNG/JPG from a Finder window onto an open sticky. Image appears at cursor (or drop point).
- [ ] **Drag from Safari.** Right-click an image in Safari → drag the preview thumbnail onto a sticky. Image appears.
- [ ] **Paste from screenshot.** Hit cmd-shift-4, capture a region, then cmd-V into a sticky. Image appears.
- [ ] **Right-click → Add Image…** Right-click inside a sticky → the menu shows "Add Image…" → click it → Finder picker opens → pick an image → it appears.

### 2.2 Sizing

- [ ] Insert an image into a sticky. Its width should equal the note's text area width (so, note width minus the 16-px padding on each side).
- [ ] Drag the sticky's right edge to make the window wider. The image grows in real time. Aspect stays correct (no squashing).
- [ ] Drag the edge back narrower. The image shrinks. Still no squashing.
- [ ] Insert a portrait image (taller than wide). It still fits to width — meaning very tall, like a phone screenshot column. Confirm it's not capped.
- [ ] Insert a square image. Width-fit, height = width.

### 2.3 Text + image flow

- [ ] Type some text into a sticky. Cursor on a new line. Insert an image. Type more text. Both blocks of text are visible — above and below the image.
- [ ] Click between two paragraphs and insert an image. Text reflows around it.
- [ ] Insert two images one after the other. Each gets its own line.
- [ ] Click immediately after an image and hit backspace. The image deletes (like any character).

### 2.4 Persistence

- [ ] Create a note with an image. Quit Stickies (⌘Q). Relaunch. Note + image are restored at the same position with the same image.
- [ ] Force-kill mid-paste: cmd-V an image, then immediately `killall -9 Stickies`. Relaunch. Either the image is fully there or fully absent — not a half-baked corrupt state.
- [ ] Delete a note that has images via the yellow × → confirm in `~/Library/Application Support/Stickies/notes/` that both the `.json` and the `.rtfd` directory are gone.

### 2.5 Rejection of non-image drops

- [ ] Drag a PDF from Finder onto a sticky. **Nothing is inserted.** The cursor doesn't move, the note doesn't accept it. No error popup.
- [ ] Drag an .rtf document (TextEdit rich-text file) onto a sticky. Same — silently rejected.
- [ ] Drag plain text (select a sentence in Safari and drag) onto a sticky. The text IS inserted — only file-document drops are rejected.

### 2.6 Backward compat with existing notes

If you have notes you wrote before this update:

- [ ] Launch the new build. Existing notes appear with their text intact, at their saved positions.
- [ ] Edit one (just type a character). Quit. Relaunch. Still fine. (This is the v2→v3 migration path — the schema bump should be invisible.)
- [ ] Open `~/Library/Application Support/Stickies/notes/<uuid-of-a-text-only-note>.json` in a text editor. Confirm `schemaVersion` is now `3` and there is **no** `.rtfd` directory next to it (because that note has no images).

### 2.7 Multiple notes, mixed content

- [ ] Create three notes. Put images in two, leave one text-only. Resize each independently. Quit, relaunch. All three come back correctly.

### 2.8 Stress

- [ ] Paste a really big image (~5–10 MB screenshot). It should appear within a second or two. Saving (debounce 500 ms) should not stutter the cursor.
- [ ] Put 10 images in one note. The note scrolls vertically (it should — the existing scroll behavior carries through). Resizing the window still works.

---

## 3. Things to flag if you see them

These would mean my implementation missed something:

- **Image appears at wrong size** (not width-fit, or aspect distorted).
- **A non-image drop embeds something** (a PDF preview, an RTF block).
- **Cursor jumps unexpectedly** after an insert.
- **Resize stutters or lags** noticeably on a normal-size image (under ~2 MB).
- **Image silently disappears** after quit/relaunch.
- **Right-click menu doesn't show "Add Image…"** or it's grayed out.
- **Existing text-only notes look different** in font, color, or layout after the rich-text switch.

Tell me which of those happened and I'll fix it.

---

## 4. Decisions at the end of QA

Once QA is clean:

1. **Push to GitHub?** I'll have made local commits to `rahulnkm/stickies`. Pushing is your call — I'll wait for an explicit "push it." (Default: don't push.)
2. **Version bump?** Current `MARKETING_VERSION` is `0.1.0` in `project.yml`. This is a meaningful feature add — bump to `0.2.0` is the obvious move, but you might want to wait until you have a few more changes batched up. Your call.
3. **Update README?** Nothing in the README references rich-text capability today. Consider a one-liner under features once this is shipped.
4. **Future "image polish" follow-ups** — none are in scope for this change. Candidates I'd consider for a v2 of the image feature, ordered by my guess at value-to-effort:
   - Click an image to open it full-size in Preview (cheap; AppKit gives `quickLookPreviewItems:` for free on NSTextView).
   - Drag an image *out* of a sticky into Finder to save it (already works in AppKit; just verify in QA).
   - Right-click on an image → "Copy Image" / "Save Image As…" (15 min of work).
   - Auto-shrink really-tall images so a phone screenshot doesn't dominate the note (judgment call — width-fit is the simpler rule; auto-shrink adds a special case).

Not building any of these now unless you ask.

---

## 5. If anything is unclear

I'm trying to be specific so this doc is actionable. If a QA bullet is ambiguous, or you're not sure what "correct" looks like for a step, ping me — better to clarify than to ship a half-checked feature.
