# Images in Stickies — Implementation Plan

**Status**: ready to execute
**Date**: 2026-05-26
**Companion**: [PRD](2026-05-26-images-in-stickies-prd.md) · [TRD](2026-05-26-images-in-stickies-trd.md)

**Goal:** Add inline image support to Stickies — drag, paste, or right-click → Add Image…; images auto-fit note width and persist across restart.

**Architecture:** Flip NSTextView from plain → rich, add a width-fitting `NSTextAttachment` subclass, persist rich bodies as `.rtfd` sidecar bundles next to the existing JSON. Spec details in the TRD.

**Testing note:** Matches the existing project posture — no automated tests for v1. Each task ends with a `xcodebuild` and a commit. The final task is a manual QA pass driven from [the human doc](2026-05-26-images-in-stickies-human.md).

**Working directory:** `apps/stickies/` (its own git repo). All paths below are relative to that repo root.

---

## Task 1: Bump Note model to schema v3 with `hasRichBody`

**Files:**
- Modify: `Stickies/Models/Note.swift`

- [ ] **Step 1: Replace `Note.swift` with the v3 version**

```swift
import Foundation
import CoreGraphics

struct Note: Codable, Identifiable, Equatable {
    var schemaVersion: Int
    var id: UUID
    var text: String
    var hasRichBody: Bool
    var frame: NoteFrame
    var tintStyle: NoteTintStyle
    var isHidden: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         text: String = "",
         hasRichBody: Bool = false,
         frame: NoteFrame,
         tintStyle: NoteTintStyle = .slate,
         isHidden: Bool = false,
         createdAt: Date = .init(),
         updatedAt: Date = .init()) {
        self.schemaVersion = 3
        self.id = id
        self.text = text
        self.hasRichBody = hasRichBody
        self.frame = frame
        self.tintStyle = tintStyle
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, text, hasRichBody, frame, tintStyle, isHidden, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.hasRichBody = (try? c.decode(Bool.self, forKey: .hasRichBody)) ?? false
        self.frame = try c.decode(NoteFrame.self, forKey: .frame)
        self.tintStyle = (try? c.decode(NoteTintStyle.self, forKey: .tintStyle)) ?? .slate
        self.isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// AppKit-coordinate rect (origin bottom-left), stored as primitives for stable JSON.
struct NoteFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    init(_ r: CGRect) { self.x = r.origin.x; self.y = r.origin.y; self.w = r.size.width; self.h = r.size.height }
}

/// How much the dark palette tints the frosted-glass background.
enum NoteTintStyle: String, Codable, CaseIterable {
    case mist
    case smoke
    case slate
    case obsidian

    var tintOpacity: Double {
        switch self {
        case .mist:     return 0.00
        case .smoke:    return 0.08
        case .slate:    return 0.18
        case .obsidian: return 0.38
        }
    }

    var swatchLightness: Double {
        switch self {
        case .mist:     return 0.92
        case .smoke:    return 0.70
        case .slate:    return 0.35
        case .obsidian: return 0.15
        }
    }
}
```

- [ ] **Step 2: Build**

```
xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```
git add Stickies/Models/Note.swift
git commit -m "Bump Note schema to v3 with hasRichBody flag"
```

---

## Task 2: Add `FitWidthImageAttachment`

**Files:**
- Create: `Stickies/Models/FitWidthImageAttachment.swift`

- [ ] **Step 1: Create the file**

```swift
import AppKit

/// NSTextAttachment that always scales its image to the line fragment width,
/// preserving aspect ratio. AppKit calls attachmentBounds(...) on every layout
/// pass — so window resize → image refit, no extra plumbing.
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

- [ ] **Step 2: Regenerate the Xcode project (new source file)**

```
xcodegen generate
```

- [ ] **Step 3: Build**

```
xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```
git add Stickies/Models/FitWidthImageAttachment.swift
git commit -m "Add FitWidthImageAttachment (width-fitting NSTextAttachment)"
```

---

## Task 3: NoteStore — body API + RTFD persistence

**Files:**
- Modify: `Stickies/Storage/NoteStore.swift`

This task adds the in-memory body cache, lazy-load on first access, and the RTFD sidecar write/delete path. The existing JSON path is untouched.

- [ ] **Step 1: Replace `NoteStore.swift` with the new version**

```swift
import Foundation
import AppKit
import Combine
import os

/// Single source of truth for all notes. Owns persistence (JSON metadata + optional
/// RTFD sidecar bundle) and undo-pending state.
final class NoteStore: ObservableObject {

    static let defaultSize = CGSize(width: 240, height: 240)
    static let cascadeOffset: CGFloat = 24
    static let debounceInterval: TimeInterval = 0.5

    @Published private(set) var notes: [Note] = []

    var visibleNotes: [Note] { notes.filter { !$0.isHidden } }
    var hiddenNotes: [Note] { notes.filter { $0.isHidden } }

    private(set) var pendingDeletions: [UUID: Note] = [:]

    /// In-memory cache of rich bodies, lazily filled on first body(for:) call.
    private var bodies: [UUID: NSAttributedString] = [:]

    private let notesDir: URL
    private let logger = Logger(subsystem: "com.rahulnkm.stickies", category: "NoteStore")

    private var pendingWrites: [UUID: DispatchWorkItem] = [:]
    private let queue = DispatchQueue(label: "com.rahulnkm.stickies.notestore", qos: .utility)

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.notesDir = appSupport.appendingPathComponent("Stickies", isDirectory: true)
                                  .appendingPathComponent("notes", isDirectory: true)
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        loadFromDisk()
    }

    // MARK: - Mutations

    @discardableResult
    func newNote() -> Note {
        let frame = nextCascadeFrame()
        let note = Note(frame: NoteFrame(frame))
        notes.append(note)
        scheduleWrite(for: note.id)
        return note
    }

    func update(id: UUID, text: String? = nil, frame: CGRect? = nil, tintStyle: NoteTintStyle? = nil) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if let text { notes[idx].text = text }
        if let frame { notes[idx].frame = NoteFrame(frame) }
        if let tintStyle { notes[idx].tintStyle = tintStyle }
        notes[idx].updatedAt = Date()
        scheduleWrite(for: id)
    }

    /// Rich-body update path. Called by the editor on every keystroke.
    func update(id: UUID, body: NSAttributedString) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        bodies[id] = body
        notes[idx].text = body.string
        notes[idx].hasRichBody = NoteStore.containsAttachment(body)
        notes[idx].updatedAt = Date()
        scheduleWrite(for: id)
    }

    func setHidden(id: UUID, _ hidden: Bool) {
        guard let idx = notes.firstIndex(where: { $0.id == id }), notes[idx].isHidden != hidden else { return }
        notes[idx].isHidden = hidden
        notes[idx].updatedAt = Date()
        scheduleWrite(for: id)
    }

    func hide(id: UUID) { setHidden(id: id, true) }
    func unhide(id: UUID) { setHidden(id: id, false) }

    func beginDelete(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        cancelPendingWrite(for: id)
        let note = notes.remove(at: idx)
        pendingDeletions[id] = note
    }

    @discardableResult
    func undelete(id: UUID) -> Note? {
        guard let note = pendingDeletions.removeValue(forKey: id) else { return nil }
        notes.append(note)
        return note
    }

    func commitDelete(id: UUID) {
        pendingDeletions.removeValue(forKey: id)
        bodies.removeValue(forKey: id)
        removeFiles(for: id)
    }

    func flush() {
        for (id, work) in pendingWrites {
            work.cancel()
            if let note = notes.first(where: { $0.id == id }) {
                Self.writeNow(note, body: bodies[id], notesDir: notesDir, logger: logger)
            }
        }
        pendingWrites.removeAll()
        queue.sync {}
    }

    // MARK: - Body access

    /// Returns the rich body for a note, loading from disk on first access.
    /// For notes without a rich body, returns an NSAttributedString built from `text`.
    func body(for id: UUID) -> NSAttributedString {
        if let cached = bodies[id] { return cached }
        let body = loadBody(for: id)
        bodies[id] = body
        return body
    }

    private func loadBody(for id: UUID) -> NSAttributedString {
        guard let note = notes.first(where: { $0.id == id }) else {
            return NSAttributedString()
        }
        if note.hasRichBody {
            let rtfdURL = rtfdURL(for: id)
            if let wrapper = try? FileWrapper(url: rtfdURL, options: []),
               let body = try? NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) {
                return NoteStore.upgradeAttachments(in: body)
            }
            logger.warning("RTFD load failed for \(id.uuidString, privacy: .public); falling back to plain text")
        }
        return NSAttributedString(string: note.text)
    }

    /// Walks `body` and replaces any plain `NSTextAttachment` with `FitWidthImageAttachment`,
    /// preserving the underlying image / file wrapper. Necessary because RTFD decode
    /// produces base-class attachments that don't know how to width-fit.
    static func upgradeAttachments(in body: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: body)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.attachment, in: full) { value, range, _ in
            guard let att = value as? NSTextAttachment,
                  !(att is FitWidthImageAttachment) else { return }
            let upgraded = FitWidthImageAttachment()
            upgraded.image = att.image
            upgraded.fileType = att.fileType
            upgraded.fileWrapper = att.fileWrapper
            mutable.removeAttribute(.attachment, range: range)
            mutable.addAttribute(.attachment, value: upgraded, range: range)
        }
        return mutable
    }

    static func containsAttachment(_ body: NSAttributedString) -> Bool {
        var found = false
        body.enumerateAttribute(.attachment, in: NSRange(location: 0, length: body.length)) { value, _, stop in
            if value is NSTextAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: - Cascade placement

    private func nextCascadeFrame() -> CGRect {
        let size = Self.defaultSize
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let startX = screen.minX + 80
        let startY = screen.maxY - size.height - 80
        let offset = Self.cascadeOffset
        let n = CGFloat(visibleNotes.count)
        var x = startX + n * offset
        var y = startY - n * offset
        if x + size.width > screen.maxX || y < screen.minY {
            x = startX
            y = startY
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: notesDir,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles]) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [Note] = []
        for url in urls where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                var note = try decoder.decode(Note.self, from: data)
                if let corrected = reframeIfOffScreen(note.frame.cgRect) {
                    note.frame = NoteFrame(corrected)
                    loaded.append(note)
                    scheduleWrite(for: note.id)
                } else {
                    loaded.append(note)
                }
            } catch {
                logger.warning("Skipping corrupt note file \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        self.notes = loaded.sorted(by: { $0.createdAt < $1.createdAt })
    }

    private func reframeIfOffScreen(_ frame: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        let union = screens.reduce(CGRect.null) { $0.union($1.frame) }
        if union.intersects(frame) { return nil }
        let size = Self.defaultSize
        let main = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(
            x: main.midX - size.width / 2,
            y: main.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func scheduleWrite(for id: UUID) {
        cancelPendingWrite(for: id)
        guard let note = notes.first(where: { $0.id == id }) else { return }
        let body = bodies[id]
        let dir = notesDir
        let log = logger
        let work = DispatchWorkItem {
            Self.writeNow(note, body: body, notesDir: dir, logger: log)
        }
        pendingWrites[id] = work
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private func cancelPendingWrite(for id: UUID) {
        if let w = pendingWrites.removeValue(forKey: id) {
            w.cancel()
        }
    }

    private static func writeNow(_ note: Note, body: NSAttributedString?, notesDir: URL, logger: Logger) {
        // 1) Write JSON metadata (always).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonURL = notesDir.appendingPathComponent("\(note.id.uuidString).json")
        let tmp = jsonURL.appendingPathExtension("tmp")
        do {
            let data = try encoder.encode(note)
            try data.write(to: tmp, options: .atomic)
            try FileManager.default.replaceItemAt(jsonURL, withItemAt: tmp)
        } catch {
            logger.error("Write JSON failed for \(note.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        // 2) Write or remove the RTFD bundle.
        let rtfdURL = notesDir.appendingPathComponent("\(note.id.uuidString).rtfd", isDirectory: true)
        if note.hasRichBody, let body {
            do {
                let wrapper = try body.fileWrapper(
                    from: NSRange(location: 0, length: body.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
                )
                try wrapper.write(to: rtfdURL, options: [.atomic], originalContentsURL: nil)
            } catch {
                logger.error("Write RTFD failed for \(note.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        } else {
            try? FileManager.default.removeItem(at: rtfdURL)
        }
    }

    private func removeFiles(for id: UUID) {
        let json = notesDir.appendingPathComponent("\(id.uuidString).json")
        let rtfd = rtfdURL(for: id)
        for url in [json, rtfd] {
            do { try FileManager.default.removeItem(at: url) }
            catch CocoaError.fileNoSuchFile { /* already gone */ }
            catch { logger.warning("Remove failed for \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)") }
        }
    }

    private func rtfdURL(for id: UUID) -> URL {
        notesDir.appendingPathComponent("\(id.uuidString).rtfd", isDirectory: true)
    }
}
```

- [ ] **Step 2: Build**

```
xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```
git add Stickies/Storage/NoteStore.swift
git commit -m "Add NoteStore body API + RTFD sidecar persistence"
```

---

## Task 4: NoteTextView subclass with image entry points

**Files:**
- Create: `Stickies/Windows/NoteTextView.swift`

NSTextView subclass with overridden paste/drag/menu. Handles all three image insertion paths.

- [ ] **Step 1: Create `NoteTextView.swift`**

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
        if !images.isEmpty {
            let dropPoint = convert(sender.draggingLocation, from: nil)
            let charIndex = characterIndexForInsertion(at: dropPoint)
            insertImages(images, at: charIndex)
            return true
        }
        if NoteTextView.pasteboardHasOnlyNonImageContent(pb) {
            return false
        }
        return super.performDragOperation(sender)
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
        let toInsert = NSMutableAttributedString()
        for (i, image) in images.enumerated() {
            let att = FitWidthImageAttachment()
            att.image = image
            if i > 0 { toInsert.append(NSAttributedString(string: "\n", attributes: typing)) }
            toInsert.append(NSAttributedString(attachment: att))
        }
        // Trailing newline so the user can type below the image without
        // first having to press return themselves.
        toInsert.append(NSAttributedString(string: "\n", attributes: typing))

        let safeIndex = min(insertionIndex, storage.length)
        let range = NSRange(location: safeIndex, length: 0)
        guard shouldChangeText(in: range, replacementString: toInsert.string) else { return }
        storage.replaceCharacters(in: range, with: toInsert)
        didChangeText()
        setSelectedRange(NSRange(location: safeIndex + toInsert.length, length: 0))
    }

    // MARK: - Pasteboard helpers

    static func imageFromPasteboard(_ pb: NSPasteboard) -> NSImage? {
        return allImagesFromPasteboard(pb).first
    }

    static func allImagesFromPasteboard(_ pb: NSPasteboard) -> [NSImage] {
        var out: [NSImage] = []
        // 1) File URLs that point at image files (drag from Finder).
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                guard let type = UTType(filenameExtension: url.pathExtension.lowercased()),
                      type.conforms(to: .image) else { continue }
                if let image = NSImage(contentsOf: url) { out.append(image) }
            }
        }
        if !out.isEmpty { return out }
        // 2) Direct image objects (clipboard screenshots, drag from browsers).
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage] {
            out.append(contentsOf: images)
        }
        return out
    }

    /// True iff the pasteboard has typed content but none of it is an image or a
    /// plain string — i.e., we should refuse rather than letting super embed a PDF/RTF.
    static func pasteboardHasOnlyNonImageContent(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types, !types.isEmpty else { return false }
        let imageHints: Set<String> = [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
            "public.image",
            "public.jpeg",
            "public.heic",
        ]
        let hasImageHint = types.contains(where: { imageHints.contains($0.rawValue) })
        let hasFileURL = types.contains(.fileURL)
        let hasPlainString = types.contains(.string)
        return !hasImageHint && !hasFileURL && !hasPlainString
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project**

```
xcodegen generate
```

- [ ] **Step 3: Build**

```
xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```
git add Stickies/Windows/NoteTextView.swift
git commit -m "Add NoteTextView subclass (paste/drag/menu image entry points)"
```

---

## Task 5: Switch NoteView to rich text mode

**Files:**
- Modify: `Stickies/Windows/NoteView.swift`

Replaces the `NSTextView.scrollableTextView()` plumbing with our `NoteTextView`, switches to rich text + import graphics, and changes the binding from `String` to `NSAttributedString` via a load-once + on-change callback (rather than a SwiftUI `Binding`, which doesn't behave well with attributed strings).

- [ ] **Step 1: Replace the body of `NoteView.swift`**

Keep the existing `NoteTheme` enum and `BlurView` and `TintSwatch` definitions unchanged. Replace `NoteView`'s `body` and the `NoteTextEditor` struct.

The full new file:

```swift
import SwiftUI
import AppKit

enum NoteTheme {
    static let bg = Color(red: 0x2C/255, green: 0x2A/255, blue: 0x33/255)
    static let text = Color(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255)
    static let nsBg = NSColor(red: 0x2C/255, green: 0x2A/255, blue: 0x33/255, alpha: 1)
    static let nsText = NSColor(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255, alpha: 1)
    static let cornerRadius: CGFloat = 6
    static let innerPadding: CGFloat = 16
    static let topPadding: CGFloat = 30
    static let hideSize: CGFloat = 8
    static let hideInset: CGFloat = 12
    static let hideYellow = Color(red: 0xFE/255, green: 0xBC/255, blue: 0x2E/255)
    static let fontSize: CGFloat = 13
    static let lineHeightMultiple: CGFloat = 1.0
    static let tracking: CGFloat = 0

    static func font(size: CGFloat = fontSize) -> NSFont {
        NSFont(name: "GeistMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

struct NoteView: View {
    let noteID: UUID
    @ObservedObject var store: NoteStore
    var onHide: () -> Void

    @State private var topBarHovering = false
    @State private var hideButtonHovering = false
    @State private var hoverHideTask: DispatchWorkItem?

    private var note: Note? { store.notes.first(where: { $0.id == noteID }) }
    private var currentTint: NoteTintStyle { note?.tintStyle ?? .slate }

    private func handleHover(_ isHovering: Bool) {
        hoverHideTask?.cancel()
        if isHovering {
            topBarHovering = true
        } else {
            let task = DispatchWorkItem { topBarHovering = false }
            hoverHideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            BlurView(material: .hudWindow, blendingMode: .behindWindow)
            RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous)
                .fill(NoteTheme.bg.opacity(currentTint.tintOpacity))

            NoteTextEditor(
                initialBody: store.body(for: noteID),
                onChange: { newBody in
                    store.update(id: noteID, body: newBody)
                }
            )
            .padding(.top, NoteTheme.topPadding)
            .padding(.horizontal, NoteTheme.innerPadding)
            .padding(.bottom, NoteTheme.innerPadding)

            topBar
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: NoteTheme.topPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous))
        .ignoresSafeArea()
    }

    private var topBar: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onHover(perform: handleHover)

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(NoteTintStyle.allCases, id: \.self) { style in
                        TintSwatch(style: style, isSelected: currentTint == style) {
                            store.update(id: noteID, tintStyle: style)
                        }
                    }
                }
                .padding(.leading, 6)
                .onHover(perform: handleHover)

                Spacer()

                Button(action: onHide) {
                    ZStack {
                        Circle()
                            .fill(NoteTheme.hideYellow)
                            .frame(width: NoteTheme.hideSize, height: NoteTheme.hideSize)
                        if hideButtonHovering {
                            Rectangle()
                                .fill(Color.black.opacity(0.55))
                                .frame(width: 4, height: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, NoteTheme.hideInset)
                .onHover { hovering in
                    hideButtonHovering = hovering
                    handleHover(hovering)
                }
                .help("Hide note")
            }
            .opacity(topBarHovering ? 0.9 : 0)
            .allowsHitTesting(topBarHovering)
            .animation(.easeInOut(duration: 0.12), value: topBarHovering)
        }
        .frame(maxWidth: .infinity)
        .frame(height: NoteTheme.topPadding, alignment: .top)
    }
}

private struct TintSwatch: View {
    let style: NoteTintStyle
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(white: style.swatchLightness))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().stroke(NoteTheme.text, lineWidth: isSelected ? 1.0 : 0)
                )
                .padding(EdgeInsets(top: 8, leading: 3, bottom: 8, trailing: 3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.rawValue.capitalized)
    }
}

private struct BlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = NoteTheme.cornerRadius
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// NSTextView (subclass NoteTextView) wrapper that accepts an initial rich body
/// and reports changes via a callback. We don't use a SwiftUI Binding here
/// because NSAttributedString equality is expensive and SwiftUI re-pushes
/// on every cycle, fighting the in-flight text view.
private struct NoteTextEditor: NSViewRepresentable {
    let initialBody: NSAttributedString
    let onChange: (NSAttributedString) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()

        let tv = NoteTextView(frame: .zero)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0

        tv.isRichText = true
        tv.importsGraphics = true
        tv.allowsImageEditing = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = NoteTheme.nsText
        tv.insertionPointColor = NoteTheme.nsText
        tv.font = NoteTheme.font()
        tv.textContainerInset = .zero
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.typingAttributes = Self.typingAttributes()
        tv.delegate = context.coordinator

        // Seed the body. enumerateAttribute-walk to ensure any plain attachments
        // (e.g. from a freshly-loaded RTFD) became FitWidthImageAttachment via
        // NoteStore.upgradeAttachments — we trust the store to have done that.
        tv.textStorage?.setAttributedString(initialBody)

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Intentional no-op: NSTextView is the source of truth for the body
        // in flight. External updates would fight the user's cursor.
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    static func typingAttributes() -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = NoteTheme.lineHeightMultiple
        return [
            .font: NoteTheme.font(),
            .foregroundColor: NoteTheme.nsText,
            .paragraphStyle: para,
            .kern: NoteTheme.tracking,
            .ligature: 0,
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let onChange: (NSAttributedString) -> Void
        init(onChange: @escaping (NSAttributedString) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            onChange(NSAttributedString(attributedString: storage))
        }
    }
}
```

- [ ] **Step 2: Build**

```
xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```
git add Stickies/Windows/NoteView.swift
git commit -m "Switch NoteView to rich text mode backed by NoteTextView"
```

---

## Task 6: Final build + manual QA pass

**Files:** none (verification only)

- [ ] **Step 1: Clean build**

```
xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug clean build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. No warnings about unused/missing files.

- [ ] **Step 2: Launch the built app**

```
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Stickies.app' -type d -path '*Debug*' 2>/dev/null | head -1)"
```

- [ ] **Step 3: Walk the manual QA checklist** from [the human doc](2026-05-26-images-in-stickies-human.md). Each item is something only a human can verify (drag, paste, visual checks). If any item fails, file the deviation under a new `## Known issues` section in `README.md` and decide fix-inline-now vs. defer.

- [ ] **Step 4: If a README update was needed, commit it**

```
git add README.md
git commit -m "Document known issues from images-in-stickies QA"
```

If nothing changed, skip.

---

## Implementation notes for the agent

- **Working directory:** `apps/stickies/` — that's the rahulnkm/stickies git repo. The outer `long-projects` worktree is separate and uninvolved.
- **Do not push to GitHub.** All commits stay local until Rahul explicitly says push.
- **Commit discipline:** one task = one commit. No batching.
- **Resize/layout gotcha:** if image rescale on resize stutters in QA, add explicit layout invalidation in `NoteWindowController.windowDidResize` — the NSTextView's layout manager may need a poke on very large images. Hold this until evidence shows it's needed.
- **Pasteboard typing is fragile:** the filter in `pasteboardHasOnlyNonImageContent` lists the common cases. If a drop type slips through and embeds something ugly during QA, add it to the filter rather than rewriting.
- **No new dependencies.** Everything in this plan uses AppKit + UniformTypeIdentifiers, both of which the project already links.
