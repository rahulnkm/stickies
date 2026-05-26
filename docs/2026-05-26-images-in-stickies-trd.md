# Images in Stickies — TRD

**Status**: approved
**Date**: 2026-05-26
**Companion**: [`2026-05-26-images-in-stickies-prd.md`](2026-05-26-images-in-stickies-prd.md)

## 1. Summary

Flip the existing `NSTextView`-backed sticky body from plain text to rich text. Images are inserted as inline `NSTextAttachment`s. A custom `NSTextAttachment` subclass returns width-fit bounds, so AppKit's own layout engine handles scale-on-resize. Persistence adds an `.rtfd` sidecar bundle next to the existing JSON, only when the note actually has rich content.

The change is local to two files and adds three new files. No new dependencies.

## 2. Architecture deltas

### 2.1 Existing pipeline (text-only)

```
NoteView (SwiftUI)
  └─ NoteTextEditor (NSViewRepresentable)
       └─ NSTextView (isRichText = false)
            └─ String binding ─► NoteStore.update(id:, text:)
                                   └─ writes <id>.json (single file)
```

### 2.2 New pipeline

```
NoteView (SwiftUI)
  └─ NoteTextEditor (NSViewRepresentable)
       └─ NoteTextView (NSTextView subclass; isRichText = true, importsGraphics = true)
            ├─ paste / drag / right-click → insertImage(NSImage)
            │     └─ FitWidthImageAttachment (NSTextAttachment subclass)
            └─ textDidChange → onBodyChange(NSAttributedString)
                  └─ NoteStore.update(id:, body:)
                       ├─ derives plain text (body.string) → Note.text
                       ├─ derives hasRichBody (attachment count > 0) → Note.hasRichBody
                       ├─ writes <id>.json (metadata only)
                       └─ writes <id>.rtfd/ (only if hasRichBody) else removes it
```

`@Published var notes: [Note]` keeps holding only the lightweight metadata. The body lives as an `NSAttributedString` cache in the store, keyed by note ID, lazily loaded on first read.

## 3. Data model

### 3.1 `Note` (schemaVersion 3)

```swift
struct Note: Codable, Identifiable, Equatable {
    var schemaVersion: Int       // 3
    var id: UUID
    var text: String             // plain-text projection of the body
    var hasRichBody: Bool        // if true, <id>.rtfd/ exists alongside <id>.json
    var frame: NoteFrame
    var tintStyle: NoteTintStyle
    var isHidden: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

**Why both `text` and `hasRichBody`:** `text` stays as a plain-text fallback so corrupted or missing RTFD bundles don't lose user data. `hasRichBody` is the disambiguator — if true, the canonical body is the RTFD bundle; if false, `text` is canonical and no RTFD bundle is on disk.

### 3.2 Backward compatibility

| Schema | Decoder behavior |
|--------|------------------|
| v1 (no `schemaVersion`) | `tintStyle = .slate`, `isHidden = false`, `hasRichBody = false` |
| v2 | `hasRichBody = false` (no rtfd lookup) |
| v3 | normal — read all fields |

A v2 note becomes a v3 note on first save (the writer always emits `schemaVersion = 3` going forward). Existing v2 notes work indefinitely without touching them.

## 4. Storage layout

```
~/Library/Application Support/Stickies/notes/
├── <uuid-a>.json                  # text-only note
├── <uuid-b>.json                  # note with images
└── <uuid-b>.rtfd/                 # ← new, present iff hasRichBody = true
    ├── TXT.rtf
    └── <attachment files>.png/jpg/…
```

- The `.rtfd` bundle is a directory wrapper produced by `NSAttributedString.fileWrapper(from:_:documentAttributes:)` with `.rtfd` document type. It is written atomically via `NSFileWrapper.write(to:options:[.atomic], originalContentsURL:)`.
- Deletion: `commitDelete(id:)` removes *both* `<id>.json` and `<id>.rtfd/` (recursive). `.fileNoSuchFile` is ignored for either.

## 5. Components

### 5.1 New file — `Stickies/Models/FitWidthImageAttachment.swift`

```swift
import AppKit

/// NSTextAttachment that always scales its image to the line fragment width,
/// preserving aspect ratio. AppKit calls attachmentBounds(...) on every layout
/// pass, so window resize → live image rescale, no extra plumbing.
final class FitWidthImageAttachment: NSTextAttachment {
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                    proposedLineFragment lineFrag: CGRect,
                                    glyphPosition position: CGPoint,
                                    characterIndex charIndex: Int) -> CGRect {
        guard let image = self.image,
              image.size.width > 0,
              lineFrag.width > 0 else {
            return super.attachmentBounds(for: textContainer,
                                          proposedLineFragment: lineFrag,
                                          glyphPosition: position,
                                          characterIndex: charIndex)
        }
        let width = lineFrag.width
        let aspect = image.size.height / image.size.width
        return CGRect(x: 0, y: 0, width: width, height: width * aspect)
    }
}
```

### 5.2 Modified file — `Stickies/Models/Note.swift`

- Bump `schemaVersion` initializer default from `2` to `3`.
- Add `var hasRichBody: Bool` (default false on init).
- Add `hasRichBody` to `CodingKeys`.
- In `init(from:)`, decode `hasRichBody` with `?? false` for older schemas.

### 5.3 Modified file — `Stickies/Storage/NoteStore.swift`

**New properties:**

```swift
private var bodies: [UUID: NSAttributedString] = [:]
```

**New public methods:**

```swift
func body(for id: UUID) -> NSAttributedString
func update(id: UUID, body: NSAttributedString)
```

**Behavior:**

- `body(for:)` returns the cached body, loading from disk on first access. If `hasRichBody` and `<id>.rtfd/` exists, load via `FileWrapper(url:)` + `NSAttributedString(rtfd:)`. Else build from `Note.text` with default typing attributes. After load, walk the attributed string and replace any plain `NSTextAttachment` with `FitWidthImageAttachment` (preserving `image`, `fileType`, `fileWrapper`).
- `update(id:body:)` caches the body, computes `plain = body.string`, computes `hasRich = body.containsAttachments`, mutates the matching `Note`, schedules a write.

**Write path:**

`writeNow(_:)` becomes:

1. Encode and atomically write `<id>.json` (existing path).
2. If `note.hasRichBody`, write `<id>.rtfd/` from `bodies[id]` via `NSAttributedString.fileWrapper(from:_:documentAttributes: [.documentType: .rtfd])` and `FileWrapper.write(to:_:options:[.atomic], originalContentsURL:)`.
3. If `!note.hasRichBody`, remove `<id>.rtfd/` if it exists (`removeItem(at:)`; ignore `fileNoSuchFile`).

**Delete path:**

`removeFile(for:)` removes both `<id>.json` and `<id>.rtfd/`. (Ignore missing.)

**Flush path:**

`flush()` already iterates `pendingWrites`. The new writer path inherits that logic — bodies are read from `bodies[id]` cache, which is in-memory and synchronously available.

### 5.4 New file — `Stickies/Windows/NoteTextView.swift`

NSTextView subclass; replaces the inline `NSTextView` instance produced by `NSTextView.scrollableTextView()` in `NoteTextEditor`.

```swift
import AppKit
import UniformTypeIdentifiers

final class NoteTextView: NSTextView {

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        let item = NSMenuItem(title: "Add Image…", action: #selector(addImageFromPicker), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func addImageFromPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Insert"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        insertImage(image)
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        if let image = NoteTextView.imageFromPasteboard(NSPasteboard.general) {
            insertImage(image)
            return
        }
        super.paste(sender)
    }

    // MARK: - Drag

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let images = NoteTextView.allImagesFromPasteboard(pb)
        guard !images.isEmpty else {
            // Non-image drops: reject silently rather than embedding PDFs/RTF/etc.
            if NoteTextView.pasteboardHasOnlyNonImageContent(pb) { return false }
            return super.performDragOperation(sender)
        }
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let charIndex = characterIndexForInsertion(at: dropPoint)
        insertImages(images, at: charIndex)
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if !NoteTextView.allImagesFromPasteboard(pb).isEmpty { return .copy }
        if NoteTextView.pasteboardHasOnlyNonImageContent(pb) { return [] }
        return super.draggingEntered(sender)
    }

    // MARK: - Insertion

    func insertImage(_ image: NSImage) {
        insertImages([image], at: selectedRange().location)
    }

    private func insertImages(_ images: [NSImage], at insertionIndex: Int) {
        guard let storage = textStorage else { return }
        let typing = typingAttributes
        let mutable = NSMutableAttributedString()
        for (i, image) in images.enumerated() {
            let att = FitWidthImageAttachment()
            att.image = image
            if i > 0 { mutable.append(NSAttributedString(string: "\n", attributes: typing)) }
            mutable.append(NSAttributedString(attachment: att))
        }
        let range = NSRange(location: min(insertionIndex, storage.length), length: 0)
        if shouldChangeText(in: range, replacementString: nil) {
            storage.replaceCharacters(in: range, with: mutable)
            didChangeText()
        }
        // Move cursor past the inserted block so the next keystroke types below.
        let newCursor = range.location + mutable.length
        setSelectedRange(NSRange(location: newCursor, length: 0))
    }

    // MARK: - Pasteboard helpers

    static func imageFromPasteboard(_ pb: NSPasteboard) -> NSImage? {
        return allImagesFromPasteboard(pb).first
    }

    static func allImagesFromPasteboard(_ pb: NSPasteboard) -> [NSImage] {
        var out: [NSImage] = []
        // 1) File URLs that point at image files.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                guard let type = UTType(filenameExtension: url.pathExtension.lowercased()),
                      type.conforms(to: .image) else { continue }
                if let image = NSImage(contentsOf: url) { out.append(image) }
            }
        }
        if !out.isEmpty { return out }
        // 2) Direct image objects on the pasteboard (e.g., screenshots).
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage] {
            out.append(contentsOf: images)
        }
        return out
    }

    /// True iff the pasteboard has typed content but none of it is an image.
    /// Used to reject PDF/RTF/etc. drops without falling through to super.
    static func pasteboardHasOnlyNonImageContent(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types, !types.isEmpty else { return false }
        let imageTypes: Set<NSPasteboard.PasteboardType> = [
            .png, .tiff, .fileURL, .init(rawValue: "public.image"),
        ]
        let hasImage = types.contains(where: { imageTypes.contains($0) })
        // Fall through to default behavior for plain strings — they're not
        // file-like and won't embed surprising objects.
        let hasPlainString = types.contains(.string)
        return !hasImage && !hasPlainString
    }
}
```

Notes:

- `pasteboardHasOnlyNonImageContent` is the filter that stops PDFs / RTF documents from being embedded by the superclass's default drag handler. Plain strings are excluded so dragged text snippets still work.
- For paste, AppKit's `paste(_:)` defaults to "paste as rich" when `isRichText && importsGraphics`, which embeds PDF previews of dragged PDFs. Overriding paste to image-first short-circuits that.

### 5.5 Modified file — `Stickies/Windows/NoteView.swift`

Replace `NoteTextEditor` to:

- Use `NoteTextView` instead of `NSTextView.scrollableTextView()`.
- Set `tv.isRichText = true`, `tv.importsGraphics = true`, `tv.allowsImageEditing = false`.
- Take an `initialBody: NSAttributedString` and `onBodyChange: (NSAttributedString) -> Void` instead of `@Binding var text: String`.
- In `updateNSView`, don't push externally-driven body updates back into the text view (NSTextView is the in-flight source of truth; the store mirrors it). Only push on initial load.
- In the `NSTextViewDelegate.textDidChange` callback, copy the text storage to an immutable `NSAttributedString` and call `onBodyChange`.

`NoteView` reads the body once via `store.body(for: noteID)`, passes it to `NoteTextEditor`, and bridges `onBodyChange` to `store.update(id:, body:)`. No SwiftUI binding on the body — `NSAttributedString` doesn't play well with `Binding` equality checks.

### 5.6 Untouched files

- `NoteWindowController.swift` — frame observation already triggers layout invalidation in NSTextView via `windowDidResize`. No code change needed; verify in QA.
- `AppDelegate.swift` — no change.
- `MenuBarController.swift` — no change.
- `UndoToast.swift` — no change. Undo of a note with images restores the JSON+RTFD pair just like delete already restores JSON.

## 6. Reflow on resize

`NSTextView` recomputes layout when its text container's width changes. The text container's width tracks the view bounds because `isHorizontallyResizable = false`. When the SwiftUI `NSViewRepresentable` resizes the scroll view, layout invalidates automatically.

`FitWidthImageAttachment.attachmentBounds(for:_:_:_:)` is called once per attachment per layout pass with the new line fragment width — so images rescale on every frame of a window resize gesture, no debounce, no extra invalidation.

If QA finds resize stutters on very large images, fall back to invalidating layout explicitly in `windowDidResize` via `tv.layoutManager?.invalidateLayout(forCharacterRange:...)`. Hold this until evidence shows it's needed.

## 7. Premortem mitigations (from why-chain)

| Failure mode | Mitigation in design |
|--------------|----------------------|
| Storage bloat from base64-in-JSON | RTFD lives in a sidecar bundle, not in JSON |
| Migration corrupts v2 notes | New `hasRichBody` defaults to false; v2 `text` field is untouched; writers only emit `.rtfd/` when there's something to put there |
| Drag accepts unwanted file types | `pasteboardHasOnlyNonImageContent` filter in `draggingEntered` / `performDragOperation` |
| Paste embeds PDF previews | `paste(_:)` overridden to prefer images; falls through to super only for non-image pasteboards |
| RTFD load fails on a v3 note | Fallback path: build body from `Note.text` and treat note as text-only until user re-inserts the image |

## 8. Testing strategy

v1 of Stickies ships without automated tests (see [§7 of the original design](2026-04-22-stickies-design.md#7-testing-strategy-v1)). This change inherits that posture. Verification is manual; the checklist lives in [the human doc](2026-05-26-images-in-stickies-human.md).

Two narrow places where unit-level smoke testing would be cheap to add and high-value if a regression ever appears:

- `FitWidthImageAttachment.attachmentBounds` math (pure function of `lineFrag.width` × `image.size`).
- `NoteTextView.allImagesFromPasteboard` (deterministic on a fake `NSPasteboard`).

Not built in this pass. Tracked as a follow-up.

## 9. Out-of-band concerns

- **Sandboxing:** the app is unsandboxed (per the original design §6). `NSOpenPanel` and drag of file URLs both work without entitlements. If sandboxing is ever added, the file-URL drag path needs a security-scoped bookmark — unrelated to this change.
- **Code signing / notarization:** unchanged. RTFD bundles in `Application Support/` don't trigger Gatekeeper.
- **Schema version probing:** future migration tooling can grep `Application Support/Stickies/notes/*.json` for `"schemaVersion": 3`. No registry/manifest needed.

## 10. Open questions

None. All resolved by the PRD or this TRD.
