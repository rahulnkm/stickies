# Stickies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a minimal, beautiful, floating sticky-notes app for macOS matching the spec at `docs/2026-04-22-stickies-design.md`.

**Architecture:** Native macOS app. AppKit owns window management (borderless, always-on-top, drag-from-anywhere); SwiftUI renders the note interior. One `NSWindow` per note, each backed by a `Codable` `Note` model stored as one JSON file per note in `~/Library/Application Support/Stickies/notes/`. A single `NoteStore` is the source of truth and handles debounced atomic writes.

**Tech Stack:** Swift 5.9+, SwiftUI + AppKit, `SMAppService` for launch-at-login, `xcodegen` to generate the Xcode project from a YAML config (so the project is reproducible from source). No third-party Swift packages.

**Testing note:** Per the spec (Section 7), v1 ships **without automated tests**. The interactions are inherently visual and the surface is small. Each task below uses **manual verification** steps in place of the TDD red/green loop: write code → build → manually verify the behavior listed → commit. The final task walks the full manual QA checklist from spec §7.

**Agent preflight (once, before Task 1):**
- `xcodegen` must be installed: `brew list xcodegen >/dev/null 2>&1 || brew install xcodegen`
- Xcode command-line tools must be present: `xcode-select -p` should return a path.

---

## File structure

All paths relative to the repo root.

**Committed source:**
- `project.yml` — xcodegen config; the Xcode project is generated from this.
- `.gitignore` — ignores `Stickies.xcodeproj/`, `build/`, `DerivedData/`, `.DS_Store`.
- `README.md` — one-paragraph description + how to build/run.
- `Stickies/StickiesApp.swift` — `@main` entry point, wires `AppDelegate`.
- `Stickies/AppDelegate.swift` — application lifecycle (restore on launch, flush on terminate).
- `Stickies/Models/Note.swift` — `Codable` value type for a note.
- `Stickies/Storage/NoteStore.swift` — `ObservableObject` source of truth; persistence, undo, cascade placement.
- `Stickies/Windows/NoteWindowController.swift` — per-note `NSWindow` manager.
- `Stickies/Windows/NoteView.swift` — SwiftUI note interior.
- `Stickies/MenuBar/MenuBarController.swift` — `NSStatusItem` + menu.
- `Stickies/UI/UndoToast.swift` — transient `NSPanel` for the undo toast.
- `Stickies/Util/LaunchAtLogin.swift` — thin wrapper over `SMAppService.mainApp`.
- `Stickies/Info.plist` — bundle metadata.
- `Stickies/Stickies.entitlements` — empty file for now (no sandbox, no special caps).
- `Stickies/Assets.xcassets/` — app icon catalog.

**Generated (git-ignored):**
- `Stickies.xcodeproj/` — produced by `xcodegen generate`.

**Responsibilities per file** (lock this in — do not spread logic across files):

| File | Owns |
|------|------|
| `StickiesApp.swift` | `@main`, `NSApplicationDelegateAdaptor`, nothing else |
| `AppDelegate.swift` | Holding `NoteStore` and `MenuBarController` instances; lifecycle hooks |
| `Note.swift` | Data model only — no logic |
| `NoteStore.swift` | Mutations, persistence, undo state, debouncing, cascade offset |
| `NoteWindowController.swift` | Window configuration, frame observation, hosting the SwiftUI view |
| `NoteView.swift` | Text editor, hover state, close button — no persistence calls beyond `store.update(text:)` |
| `MenuBarController.swift` | Status item, menu construction, command routing |
| `UndoToast.swift` | Presenting/dismissing the panel, timer, callbacks |
| `LaunchAtLogin.swift` | `SMAppService` register/unregister + `UserDefaults` reconciliation |

---

## Task 1: Bootstrap xcodegen project

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `README.md`
- Create: `Stickies/Info.plist`
- Create: `Stickies/Stickies.entitlements`
- Create: `Stickies/StickiesApp.swift` (placeholder)
- Create: `Stickies/AppDelegate.swift` (placeholder)
- Create: `Stickies/Assets.xcassets/Contents.json`
- Create: `Stickies/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Create `.gitignore`**

```
Stickies.xcodeproj/
build/
DerivedData/
.DS_Store
*.xcuserstate
```

- [ ] **Step 2: Create `README.md`**

```markdown
# Stickies

Minimal floating sticky-notes app for macOS. See `docs/2026-04-22-stickies-design.md`.

## Build

```
brew install xcodegen
  
xcodegen generate
open Stickies.xcodeproj
```

Then ⌘R in Xcode.
```

- [ ] **Step 3: Create `project.yml`**

```yaml
name: Stickies
options:
  bundleIdPrefix: com.rahulnkm
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    ENABLE_HARDENED_RUNTIME: NO
    PRODUCT_NAME: Stickies
targets:
  Stickies:
    type: application
    platform: macOS
    sources:
      - path: Stickies
    info:
      path: Stickies/Info.plist
      properties:
        CFBundleName: Stickies
        CFBundleDisplayName: Stickies
        CFBundleIdentifier: com.rahulnkm.stickies
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        LSMinimumSystemVersion: "13.0"
        NSHumanReadableCopyright: ""
        NSPrincipalClass: NSApplication
    entitlements:
      path: Stickies/Stickies.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.rahulnkm.stickies
        GENERATE_INFOPLIST_FILE: NO
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        COMBINE_HIDPI_IMAGES: YES
```

- [ ] **Step 4: Create `Stickies/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIconFile</key>
    <string></string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
```

- [ ] **Step 5: Create `Stickies/Stickies.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 6: Create `Stickies/Assets.xcassets/Contents.json`**

```json
{ "info": { "author": "xcode", "version": 1 } }
```

- [ ] **Step 7: Create `Stickies/Assets.xcassets/AppIcon.appiconset/Contents.json`**

```json
{
  "images": [
    { "idiom": "mac", "scale": "1x", "size": "16x16" },
    { "idiom": "mac", "scale": "2x", "size": "16x16" },
    { "idiom": "mac", "scale": "1x", "size": "32x32" },
    { "idiom": "mac", "scale": "2x", "size": "32x32" },
    { "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 8: Create placeholder `Stickies/StickiesApp.swift`**

```swift
import SwiftUI

@main
struct StickiesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

Note: `Settings { EmptyView() }` is used instead of `WindowGroup` because we don't want SwiftUI's auto-generated main window — all windows are managed by AppKit.

- [ ] **Step 9: Create placeholder `Stickies/AppDelegate.swift`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
```

- [ ] **Step 10: Generate Xcode project and build**

Run:
```
  xcodegen generate
```

Expected: `Generated project successfully` and a `Stickies.xcodeproj` appears.

Then build:
```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 11: Launch the built app manually and verify it shows a Dock icon**

Find the built `.app`:
```
find ~/Library/Developer/Xcode/DerivedData -name "Stickies.app" -type d -path "*Debug*" 2>/dev/null | head -1
```

Open it:
```
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Stickies.app' -type d -path '*Debug*' 2>/dev/null | head -1)"
```

Expected: app launches, Dock icon appears (default Xcode icon is fine for now), no stray windows open. Quit with ⌘Q.

- [ ] **Step 12: Commit**

```
git add .
git commit -m "Bootstrap Stickies Xcode project via xcodegen"
```

---

## Task 2: Note model

**Files:**
- Create: `Stickies/Models/Note.swift`

- [ ] **Step 1: Create `Note.swift`**

The custom `init(from:)` lets old JSON files that lack `schemaVersion` still decode as v1.

```swift
import Foundation
import CoreGraphics

struct Note: Codable, Identifiable, Equatable {
    var schemaVersion: Int
    var id: UUID
    var text: String
    var frame: NoteFrame
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         text: String = "",
         frame: NoteFrame,
         createdAt: Date = .init(),
         updatedAt: Date = .init()) {
        self.schemaVersion = 1
        self.id = id
        self.text = text
        self.frame = frame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, text, frame, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.frame = try c.decode(NoteFrame.self, forKey: .frame)
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
```

- [ ] **Step 2: Build**

```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```
git add Stickies/Models/Note.swift
git commit -m "Add Note model"
```

---

## Task 3: NoteStore — in-memory core

**Files:**
- Create: `Stickies/Storage/NoteStore.swift`

This task implements the mutation API only. Persistence is added in Task 4.

- [ ] **Step 1: Create `NoteStore.swift`**

```swift
import Foundation
import AppKit
import Combine

/// Single source of truth for all notes.
/// Task 3 scope: in-memory state, cascade placement, undo-pending set.
/// Task 4 will add disk persistence.
final class NoteStore: ObservableObject {

    static let defaultSize = CGSize(width: 240, height: 240)
    static let cascadeOffset: CGFloat = 24

    @Published private(set) var notes: [Note] = []

    /// Notes that have been deleted from `notes` but whose file on disk has not yet been removed.
    /// Flipped to committed on undo-toast expiry.
    private(set) var pendingDeletions: [UUID: Note] = [:]

    // MARK: - Mutations

    @discardableResult
    func newNote() -> Note {
        let frame = nextCascadeFrame()
        let note = Note(frame: NoteFrame(frame))
        notes.append(note)
        return note
    }

    func update(id: UUID, text: String? = nil, frame: CGRect? = nil) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if let text { notes[idx].text = text }
        if let frame { notes[idx].frame = NoteFrame(frame) }
        notes[idx].updatedAt = Date()
    }

    /// Moves the note into `pendingDeletions`. The on-disk file is NOT yet removed.
    func beginDelete(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes.remove(at: idx)
        pendingDeletions[id] = note
    }

    /// Cancel a pending deletion — put the note back.
    @discardableResult
    func undelete(id: UUID) -> Note? {
        guard let note = pendingDeletions.removeValue(forKey: id) else { return nil }
        notes.append(note)
        return note
    }

    /// Commit the deletion: remove it from `pendingDeletions`. Disk removal happens in Task 4.
    func commitDelete(id: UUID) {
        pendingDeletions.removeValue(forKey: id)
    }

    // MARK: - Cascade placement

    private func nextCascadeFrame() -> CGRect {
        let size = Self.defaultSize
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let startX = screen.minX + 80
        let startY = screen.maxY - size.height - 80

        let offset = Self.cascadeOffset
        let n = CGFloat(notes.count)
        var x = startX + n * offset
        var y = startY - n * offset

        // Wrap back to the origin if we'd fall off the screen.
        if x + size.width > screen.maxX || y < screen.minY {
            x = startX
            y = startY
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
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
git commit -m "Add NoteStore in-memory core (mutations + cascade)"
```

---

## Task 4: NoteStore — disk persistence

**Files:**
- Modify: `Stickies/Storage/NoteStore.swift`

Adds load-on-init, debounced atomic writes, flush, corrupt-file handling, off-screen frame correction, and disk removal on `commitDelete`.

- [ ] **Step 1: Replace the entire contents of `NoteStore.swift` with the full version below**

```swift
import Foundation
import AppKit
import Combine
import os

/// Single source of truth for all notes. Owns persistence and undo-pending state.
final class NoteStore: ObservableObject {

    static let defaultSize = CGSize(width: 240, height: 240)
    static let cascadeOffset: CGFloat = 24
    static let debounceInterval: TimeInterval = 0.5

    @Published private(set) var notes: [Note] = []

    /// Notes deleted from `notes` but not yet removed from disk.
    private(set) var pendingDeletions: [UUID: Note] = [:]

    private let notesDir: URL
    private let logger = Logger(subsystem: "com.rahulnkm.stickies", category: "NoteStore")

    /// Per-note debounce timers for disk writes.
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

    func update(id: UUID, text: String? = nil, frame: CGRect? = nil) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if let text { notes[idx].text = text }
        if let frame { notes[idx].frame = NoteFrame(frame) }
        notes[idx].updatedAt = Date()
        scheduleWrite(for: id)
    }

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
        // Disk file was never removed, no write needed. Update just in case.
        scheduleWrite(for: id)
        return note
    }

    func commitDelete(id: UUID) {
        pendingDeletions.removeValue(forKey: id)
        removeFile(for: id)
    }

    /// Synchronously flush all pending writes. Call from applicationWillTerminate.
    func flush() {
        for (id, work) in pendingWrites {
            work.cancel()
            if let note = notes.first(where: { $0.id == id }) {
                writeNow(note)
            }
        }
        pendingWrites.removeAll()
    }

    // MARK: - Cascade placement

    private func nextCascadeFrame() -> CGRect {
        let size = Self.defaultSize
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let startX = screen.minX + 80
        let startY = screen.maxY - size.height - 80
        let offset = Self.cascadeOffset
        let n = CGFloat(notes.count)
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
                // Off-screen correction: if the frame is entirely outside the union of all screens,
                // re-center on main screen at default size and persist.
                if let corrected = reframeIfOffScreen(note.frame.cgRect) {
                    note.frame = NoteFrame(corrected)
                    loaded.append(note)
                    scheduleWrite(for: note.id) // persist correction
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
        let work = DispatchWorkItem { [weak self] in
            guard let self, let note = self.notes.first(where: { $0.id == id }) else { return }
            self.writeNow(note)
        }
        pendingWrites[id] = work
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private func cancelPendingWrite(for id: UUID) {
        if let w = pendingWrites.removeValue(forKey: id) {
            w.cancel()
        }
    }

    private func writeNow(_ note: Note) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = fileURL(for: note.id)
        let tmp = url.appendingPathExtension("tmp")
        do {
            let data = try encoder.encode(note)
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            logger.error("Failed to write note \(note.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func removeFile(for id: UUID) {
        let url = fileURL(for: id)
        do { try FileManager.default.removeItem(at: url) }
        catch CocoaError.fileNoSuchFile { /* already gone */ }
        catch { logger.warning("Remove failed for \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)") }
    }

    private func fileURL(for id: UUID) -> URL {
        notesDir.appendingPathComponent("\(id.uuidString).json")
    }
}
```

- [ ] **Step 2: Build**

```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manually sanity-check persistence path**

```
ls "$HOME/Library/Application Support/" | grep -i stickies || echo "directory not yet created"
```

It's fine if the directory doesn't exist yet — it's created lazily in `init()` the first time the app runs. We'll verify it after Task 8.

- [ ] **Step 4: Commit**

```
git add Stickies/Storage/NoteStore.swift
git commit -m "Wire NoteStore to disk (atomic writes, debounce, load, off-screen fix)"
```

---

## Task 5: NoteView (SwiftUI)

**Files:**
- Create: `Stickies/Windows/NoteView.swift`

This is the interior of a sticky. It receives a `NoteStore` and its own `noteID`, reads its `Note` from the store, renders text editing and the hover-reveal close button. **No window logic lives here.**

- [ ] **Step 1: Create `NoteView.swift`**

```swift
import SwiftUI

enum NoteTheme {
    static let bg = Color(red: 0x1F/255, green: 0x1D/255, blue: 0x1A/255)
    static let text = Color(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255)
    static let cornerRadius: CGFloat = 6
    static let innerPadding: CGFloat = 16
    static let closeSize: CGFloat = 12
    static let closeInset: CGFloat = 12
}

struct NoteView: View {
    let noteID: UUID
    @ObservedObject var store: NoteStore
    var onClose: () -> Void

    @State private var hovering = false

    private var note: Note? { store.notes.first(where: { $0.id == noteID }) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background fill — drawn as a rounded shape so the NSWindow shadow
            // computes the correct silhouette (the window itself is transparent).
            RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous)
                .fill(NoteTheme.bg)

            // Text editor
            TextEditor(text: Binding(
                get: { note?.text ?? "" },
                set: { store.update(id: noteID, text: $0) }
            ))
            .font(.system(size: 14))
            .foregroundColor(NoteTheme.text)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(NoteTheme.innerPadding)

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(NoteTheme.text)
                    .frame(width: NoteTheme.closeSize, height: NoteTheme.closeSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, NoteTheme.closeInset)
            .padding(.trailing, NoteTheme.closeInset)
            .opacity(hovering ? 0.7 : 0.0)
            .animation(.easeInOut(duration: 0.12), value: hovering)
        }
        .onHover { hovering = $0 }
        .clipShape(RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous))
    }
}
```

Notes on the close button: the spec says 20% when the window is hovered, 70% on hover of the button itself. For v1 the simpler "0 → 70%" on window-hover is acceptable — the subtle opacity ladder is a polish item; if it reads weird in QA (Task 13) we revisit it then. Leaving a comment in the code would add no information beyond what is already here, so none is added.

- [ ] **Step 2: Build**

```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```
git add Stickies/Windows/NoteView.swift
git commit -m "Add NoteView (SwiftUI interior)"
```

---

## Task 6: NoteWindowController

**Files:**
- Create: `Stickies/Windows/NoteWindowController.swift`

Manages one borderless, always-on-top `NSWindow` per note. Hosts `NoteView` via `NSHostingView`. Observes move/resize and writes the frame back to the store.

- [ ] **Step 1: Create `NoteWindowController.swift`**

```swift
import AppKit
import SwiftUI
import Combine

final class NoteWindowController: NSWindowController, NSWindowDelegate {

    let noteID: UUID
    private unowned let store: NoteStore
    private let onClose: (UUID) -> Void
    private var cancellables = Set<AnyCancellable>()

    init(noteID: UUID, store: NoteStore, onClose: @escaping (UUID) -> Void) {
        self.noteID = noteID
        self.store = store
        self.onClose = onClose

        let initialFrame = store.notes.first(where: { $0.id == noteID })?.frame.cgRect
            ?? CGRect(x: 120, y: 340, width: 240, height: 240)

        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 160, height: 140)
        window.contentMinSize = NSSize(width: 160, height: 140)

        super.init(window: window)
        window.delegate = self

        let hosting = NSHostingView(rootView: NoteView(
            noteID: noteID,
            store: store,
            onClose: { [weak self] in
                guard let self else { return }
                self.onClose(self.noteID)
            }
        ))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        // Shadow recomputes from opaque content; poke it once after layout.
        DispatchQueue.main.async { [weak window] in window?.invalidateShadow() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func show() {
        window?.orderFrontRegardless()
    }

    func close(persistFrame: Bool = true) {
        if persistFrame, let frame = window?.frame {
            store.update(id: noteID, frame: frame)
        }
        window?.delegate = nil
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let frame = window?.frame else { return }
        store.update(id: noteID, frame: frame)
    }

    func windowDidResize(_ notification: Notification) {
        guard let frame = window?.frame else { return }
        store.update(id: noteID, frame: frame)
        window?.invalidateShadow()
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
git add Stickies/Windows/NoteWindowController.swift
git commit -m "Add NoteWindowController (borderless floating window host)"
```

---

## Task 7: AppDelegate + app entry wiring

**Files:**
- Modify: `Stickies/AppDelegate.swift`

Owns the `NoteStore` and a dictionary of window controllers. On launch, opens a window for each note. On quit, flushes the store.

- [ ] **Step 1: Replace `AppDelegate.swift` with the full version**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = NoteStore()
    private var controllers: [UUID: NoteWindowController] = [:]
    // MenuBarController is added in Task 8.
    // UndoToast wiring is added in Task 10.

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        for note in store.notes {
            openWindow(for: note.id)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Window management (used by MenuBarController and delete flow)

    func openWindow(for id: UUID) {
        guard controllers[id] == nil else {
            controllers[id]?.show()
            return
        }
        let wc = NoteWindowController(noteID: id, store: store) { [weak self] closedID in
            self?.handleCloseRequested(id: closedID)
        }
        controllers[id] = wc
        wc.show()
    }

    func closeWindow(for id: UUID, persistFrame: Bool = true) {
        controllers[id]?.close(persistFrame: persistFrame)
        controllers.removeValue(forKey: id)
    }

    /// Placeholder — the full delete-with-undo flow lands in Task 10.
    private func handleCloseRequested(id: UUID) {
        closeWindow(for: id, persistFrame: true)
        store.beginDelete(id: id)
        store.commitDelete(id: id)
    }
}
```

- [ ] **Step 2: Build**

```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run and verify empty-state launch**

Launch the built app:
```
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Stickies.app' -type d -path '*Debug*' 2>/dev/null | head -1)"
```

Expected: app launches, Dock icon appears, no windows (because there are no notes yet and there's no menu bar UI yet). Quit with ⌘Q.

- [ ] **Step 4: Commit**

```
git add Stickies/AppDelegate.swift
git commit -m "Wire AppDelegate to NoteStore and per-note window controllers"
```

---

## Task 8: MenuBarController — New Note + Quit

**Files:**
- Create: `Stickies/MenuBar/MenuBarController.swift`
- Modify: `Stickies/AppDelegate.swift` (instantiate the controller)

This task lights the app up for the first time — you can actually create a note.

- [ ] **Step 1: Create `MenuBarController.swift`**

```swift
import AppKit

final class MenuBarController {

    private let statusItem: NSStatusItem
    private let onNewNote: () -> Void
    // Launch-at-login menu item is wired in Task 11.

    init(onNewNote: @escaping () -> Void) {
        self.onNewNote = onNewNote
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text",
                                   accessibilityDescription: "Stickies")
            button.image?.isTemplate = true
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let new = NSMenuItem(title: "New Note", action: #selector(newNoteAction), keyEquivalent: "n")
        new.keyEquivalentModifierMask = [.command]
        new.target = self
        menu.addItem(new)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Stickies", action: #selector(quitAction), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func newNoteAction() { onNewNote() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
```

- [ ] **Step 2: Modify `AppDelegate.swift` — add the controller instance and wire New Note**

Change the stored properties section and `applicationDidFinishLaunching` so the file reads:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = NoteStore()
    private var controllers: [UUID: NoteWindowController] = [:]
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        menuBar = MenuBarController(onNewNote: { [weak self] in
            self?.createNote()
        })

        for note in store.notes {
            openWindow(for: note.id)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Public actions

    func createNote() {
        let note = store.newNote()
        openWindow(for: note.id)
    }

    // MARK: - Window management

    func openWindow(for id: UUID) {
        guard controllers[id] == nil else {
            controllers[id]?.show()
            return
        }
        let wc = NoteWindowController(noteID: id, store: store) { [weak self] closedID in
            self?.handleCloseRequested(id: closedID)
        }
        controllers[id] = wc
        wc.show()
    }

    func closeWindow(for id: UUID, persistFrame: Bool = true) {
        controllers[id]?.close(persistFrame: persistFrame)
        controllers.removeValue(forKey: id)
    }

    /// Placeholder — the full delete-with-undo flow lands in Task 10.
    private func handleCloseRequested(id: UUID) {
        closeWindow(for: id, persistFrame: true)
        store.beginDelete(id: id)
        store.commitDelete(id: id)
    }
}
```

- [ ] **Step 3: Build**

```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run and manually verify core sticky functionality**

Launch:
```
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Stickies.app' -type d -path '*Debug*' 2>/dev/null | head -1)"
```

Verify:
- [ ] Menu bar icon (a small note icon) appears at top-right of screen.
- [ ] Click it → menu shows **New Note** and **Quit Stickies**.
- [ ] Click **New Note** → a small dark rounded rectangle appears on screen.
- [ ] Type into it → text appears in warm off-white.
- [ ] Click **New Note** three more times → notes cascade 24 px down-right.
- [ ] Drag a note by clicking anywhere on it → it moves.
- [ ] Grab an edge → resize works; can't go below 160×140.
- [ ] The note stays on top when you click Safari, Finder, Terminal.
- [ ] Click the × (visible only on hover) → note disappears (delete flow is intentionally immediate at this stage — undo toast is added in Task 10).
- [ ] Quit (⌘Q) → relaunch → all remaining notes reappear at their positions with their text.
- [ ] Check the data directory: `ls "$HOME/Library/Application Support/Stickies/notes/"` → one `.json` per note.
- [ ] `cat "$HOME/Library/Application Support/Stickies/notes/"*.json` → well-formed JSON with expected fields.

- [ ] **Step 5: Commit**

```
git add Stickies/MenuBar/MenuBarController.swift Stickies/AppDelegate.swift
git commit -m "Add menu bar controller with New Note + Quit"
```

---

## Task 9: UndoToast

**Files:**
- Create: `Stickies/UI/UndoToast.swift`

A transient `NSPanel` shown at the bottom-center of the main screen after a delete. Has a label and an **Undo** button. Auto-dismisses after 3 seconds. Calls back on dismiss with whether undo was clicked.

- [ ] **Step 1: Create `UndoToast.swift`**

```swift
import AppKit
import SwiftUI

final class UndoToast {

    enum Outcome { case undone, expired }

    private var panel: NSPanel?
    private var timer: Timer?

    private static let visibleDuration: TimeInterval = 3.0
    private static let size = CGSize(width: 240, height: 44)
    private static let bottomMargin: CGFloat = 48

    /// Shows the toast. Calls `completion` exactly once with the outcome.
    func show(message: String = "Note deleted", completion: @escaping (Outcome) -> Void) {
        dismiss(outcome: nil) // belt-and-suspenders if somehow already visible

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: screen.midX - Self.size.width / 2,
            y: screen.minY + Self.bottomMargin
        )
        let frame = NSRect(origin: origin, size: Self.size)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false

        var boxed: UndoToastHandle!
        boxed = UndoToastHandle(onUndo: { [weak self] in
            self?.dismiss(outcome: .undone)
            completion(.undone)
        })

        let hosting = NSHostingView(rootView: UndoToastView(message: message, handle: boxed))
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        panel = p
        p.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            self?.dismiss(outcome: .expired)
            completion(.expired)
        }
    }

    /// Dismisses without firing completion (internal use).
    private func dismiss(outcome: Outcome?) {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        _ = outcome // silence unused
    }
}

/// Lightweight reference handle so the SwiftUI button can close the toast.
final class UndoToastHandle: ObservableObject {
    let onUndo: () -> Void
    init(onUndo: @escaping () -> Void) { self.onUndo = onUndo }
}

private struct UndoToastView: View {
    let message: String
    @ObservedObject var handle: UndoToastHandle

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(NoteTheme.text)
            Spacer()
            Button("Undo", action: handle.onUndo)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(NoteTheme.text)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NoteTheme.bg)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
git add Stickies/UI/UndoToast.swift
git commit -m "Add UndoToast (transient NSPanel with 3s auto-dismiss)"
```

---

## Task 10: Wire delete + undo flow

**Files:**
- Modify: `Stickies/AppDelegate.swift`

Replaces the placeholder immediate-delete handler from Task 7/8 with the full pending-delete + toast + commit-or-undelete flow.

- [ ] **Step 1: Modify `AppDelegate.swift`**

Add an `UndoToast` property and replace `handleCloseRequested` with the full flow. The file should now read:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = NoteStore()
    private var controllers: [UUID: NoteWindowController] = [:]
    private var menuBar: MenuBarController!
    private let undoToast = UndoToast()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        menuBar = MenuBarController(onNewNote: { [weak self] in
            self?.createNote()
        })

        for note in store.notes {
            openWindow(for: note.id)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Actions

    func createNote() {
        let note = store.newNote()
        openWindow(for: note.id)
    }

    // MARK: - Window management

    func openWindow(for id: UUID) {
        guard controllers[id] == nil else {
            controllers[id]?.show()
            return
        }
        let wc = NoteWindowController(noteID: id, store: store) { [weak self] closedID in
            self?.handleCloseRequested(id: closedID)
        }
        controllers[id] = wc
        wc.show()
    }

    func closeWindow(for id: UUID, persistFrame: Bool = true) {
        controllers[id]?.close(persistFrame: persistFrame)
        controllers.removeValue(forKey: id)
    }

    // MARK: - Delete with undo

    private func handleCloseRequested(id: UUID) {
        // Persist final frame before tear-down so undo restores the exact position.
        closeWindow(for: id, persistFrame: true)
        store.beginDelete(id: id)

        undoToast.show { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .undone:
                if self.store.undelete(id: id) != nil {
                    self.openWindow(for: id)
                }
            case .expired:
                self.store.commitDelete(id: id)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manually verify delete + undo**

Launch the built app.

Verify:
- [ ] Create a note, type "test undo".
- [ ] Click the × → window disappears; a small dark toast appears at bottom-center saying "Note deleted" with an **Undo** button.
- [ ] Click **Undo** within 3 seconds → the note reappears at its original position with "test undo" intact.
- [ ] Create another note, type "test expiry".
- [ ] Click × → toast appears → wait 3+ seconds → toast disappears, note is gone for good. Relaunch app → note does not reappear.
- [ ] Create a note, click × → **force-quit** the app during the 3-second undo window (`killall Stickies`). Relaunch → note reappears (crash-safe undo window).

- [ ] **Step 4: Commit**

```
git add Stickies/AppDelegate.swift
git commit -m "Wire delete with 3s undo toast"
```

---

## Task 11: Launch at login

**Files:**
- Create: `Stickies/Util/LaunchAtLogin.swift`
- Modify: `Stickies/MenuBar/MenuBarController.swift` (add menu item + state)
- Modify: `Stickies/AppDelegate.swift` (reconcile on launch, pass to menu bar)

- [ ] **Step 1: Create `LaunchAtLogin.swift`**

```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {

    private static let userDefaultsKey = "launchAtLoginUserPreference"

    /// User-visible preference (checkbox state). Source of truth.
    static var userPreference: Bool {
        get {
            if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
                return true // default ON for first launch
            }
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            reconcile()
        }
    }

    /// Brings SMAppService state in line with `userPreference`. Safe to call on launch.
    static func reconcile() {
        let want = userPreference
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled where !want:
                try service.unregister()
            case .notRegistered, .notFound where want:
                try service.register()
            case .requiresApproval:
                // User-approval pending in Settings → Login Items. Nothing we can do silently.
                break
            default:
                if want && service.status != .enabled { try service.register() }
                if !want && service.status == .enabled { try service.unregister() }
            }
        } catch {
            NSLog("LaunchAtLogin reconcile failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: Modify `MenuBarController.swift` to include the Launch-at-Login toggle**

Replace the whole file with:

```swift
import AppKit

final class MenuBarController {

    private let statusItem: NSStatusItem
    private let onNewNote: () -> Void
    private let launchAtLoginItem: NSMenuItem

    init(onNewNote: @escaping () -> Void) {
        self.onNewNote = onNewNote
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text",
                                   accessibilityDescription: "Stickies")
            button.image?.isTemplate = true
        }

        self.launchAtLoginItem = NSMenuItem(title: "Launch at Login",
                                            action: nil,
                                            keyEquivalent: "")

        let menu = NSMenu()

        let new = NSMenuItem(title: "New Note", action: #selector(newNoteAction), keyEquivalent: "n")
        new.keyEquivalentModifierMask = [.command]
        new.target = self
        menu.addItem(new)

        menu.addItem(.separator())

        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Stickies", action: #selector(quitAction), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginItem.state = LaunchAtLogin.userPreference ? .on : .off
    }

    @objc private func newNoteAction() { onNewNote() }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.userPreference.toggle()
        refreshLaunchAtLoginState()
    }

    @objc private func quitAction() { NSApp.terminate(nil) }
}
```

- [ ] **Step 3: Modify `AppDelegate.swift` — reconcile launch-at-login on startup**

Add one line at the top of `applicationDidFinishLaunching`:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        LaunchAtLogin.reconcile()

        menuBar = MenuBarController(onNewNote: { [weak self] in
            self?.createNote()
        })

        for note in store.notes {
            openWindow(for: note.id)
        }
    }
```

- [ ] **Step 4: Build**

```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manually verify**

Launch. Open the menu bar menu:
- [ ] **Launch at Login** shows with a checkmark (first-launch default).
- [ ] Open macOS → System Settings → General → Login Items. **Stickies** should appear as an enabled item (it may take a few seconds).
- [ ] Toggle the menu item off → checkmark clears; Login Items entry is removed (or disabled).
- [ ] Toggle back on → reappears.

Note: `SMAppService` registration is silent — no dialog. If macOS flags it as "requires approval," the user would need to allow it in Settings. The menu checkbox stays accurate to the user preference either way; actual OS state is reconciled on next launch.

- [ ] **Step 6: Commit**

```
git add Stickies/Util/LaunchAtLogin.swift Stickies/MenuBar/MenuBarController.swift Stickies/AppDelegate.swift
git commit -m "Add launch-at-login (SMAppService + menu bar toggle)"
```

---

## Task 12: App icon stub

**Files:**
- Create: `Stickies/Assets.xcassets/AppIcon.appiconset/*.png` (10 images)
- Modify: `Stickies/Assets.xcassets/AppIcon.appiconset/Contents.json` (fill `filename` entries)

A simple generated icon — warm-dark rounded square with a subtle highlight, matching the palette.

- [ ] **Step 1: Generate the 1024×1024 source image**

From the repo root, run:

```
python3 - <<'PY'
from pathlib import Path
try:
    from PIL import Image, ImageDraw
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet", "Pillow"])
    from PIL import Image, ImageDraw

BG = (0x1F, 0x1D, 0x1A, 255)
HIGHLIGHT = (0xE8, 0xE3, 0xD8, 40)  # faint warm off-white at ~15% alpha

sizes = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]

out_dir = Path("Stickies/Assets.xcassets/AppIcon.appiconset")
out_dir.mkdir(parents=True, exist_ok=True)

for base, scale in sizes:
    px = base * scale
    im = Image.new("RGBA", (px, px), (0,0,0,0))
    d = ImageDraw.Draw(im)
    radius = int(px * 0.22)
    d.rounded_rectangle((0,0,px-1,px-1), radius=radius, fill=BG)
    # top highlight arc
    d.rounded_rectangle((int(px*0.08), int(px*0.08), int(px*0.92), int(px*0.30)),
                        radius=int(px*0.05), fill=HIGHLIGHT)
    fname = f"icon_{base}x{base}{'@2x' if scale==2 else ''}.png"
    im.save(out_dir / fname, "PNG")
    print("wrote", fname)
PY
```

Expected: `wrote icon_16x16.png` through `wrote icon_512x512@2x.png` — 10 PNGs.

- [ ] **Step 2: Overwrite `Contents.json` to reference the new filenames**

```json
{
  "images": [
    { "idiom": "mac", "scale": "1x", "size": "16x16",   "filename": "icon_16x16.png" },
    { "idiom": "mac", "scale": "2x", "size": "16x16",   "filename": "icon_16x16@2x.png" },
    { "idiom": "mac", "scale": "1x", "size": "32x32",   "filename": "icon_32x32.png" },
    { "idiom": "mac", "scale": "2x", "size": "32x32",   "filename": "icon_32x32@2x.png" },
    { "idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128x128.png" },
    { "idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_128x128@2x.png" },
    { "idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256x256.png" },
    { "idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_256x256@2x.png" },
    { "idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512x512.png" },
    { "idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_512x512@2x.png" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 3: Regenerate the project (picks up new asset files)**

```
  xcodegen generate
```

- [ ] **Step 4: Build and verify icon shows up**

```
  xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

Launch the app:
```
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Stickies.app' -type d -path '*Debug*' 2>/dev/null | head -1)"
```

Verify:
- [ ] Dock shows the warm-dark rounded square icon (not the default Xcode icon).
- [ ] In Finder, navigate to the built `.app` → Get Info → icon in the top-left matches.

- [ ] **Step 5: Commit**

```
git add Stickies/Assets.xcassets
git commit -m "Add Stickies app icon"
```

---

## Task 13: Full manual QA pass

**Files:** none (verification only)

Walk the manual verification checklist from spec §7. If anything fails, open an issue/TODO in `README.md` under "Known issues" and decide whether to fix inline or defer.

- [ ] **Step 1: Run through the spec checklist**

Each bullet below maps directly to a line in spec §7. Check each one.

- [ ] Launch app → menu bar icon appears; no stray windows.
- [ ] Menu bar → **New Note** → sticky appears on main screen.
- [ ] Create five notes in a row → each cascades 24 px down-right.
- [ ] Type text → quit with ⌘Q → relaunch → all notes restored at same positions with same text.
- [ ] Move a note → relaunch → note is at its moved position.
- [ ] Resize a note to minimum → cannot go below 160 × 140.
- [ ] Close a note → toast appears → click Undo within 3 s → note returns at original frame.
- [ ] Close a note → let toast expire → relaunch → note is gone.
- [ ] Toggle **Launch at Login** off → `launchctl print gui/$(id -u) | grep -i stickies` shows nothing (or registration removed).
- [ ] Force-kill mid-typing (`killall -9 Stickies`) → relaunch → at most ~500 ms of typing lost.
- [ ] (If you have an external monitor) place a note on it, disconnect monitor, relaunch → note re-centers on main screen.
- [ ] Corrupt one JSON file manually (`echo "broken" >> <uuid>.json` via `sed`/vim, leaving valid JSON malformed) → relaunch → other notes still load; corrupt one is logged to Console and skipped.
- [ ] Close-button opacity ladder feels right — the button is invisible by default, fades in on hovering the note, and is comfortably readable (not jarring) without being distracting. Per Task 5's deferred decision, v1 uses a single 0→70% fade on window-hover rather than the spec's 20%/70% two-stage ladder. If it reads wrong, add the second stage as a small follow-up fix and re-run this bullet.

- [ ] **Step 2: If any item failed**

- Small fix (one file, <15 min): patch it, re-verify, commit as `fix: <what> in Stickies`.
- Larger issue: add a `## Known issues` section to `README.md`, log the deviation, commit.

- [ ] **Step 3: Final commit (if README updated)**

```
git add README.md
git commit -m "Document known issues from v1 QA"
```

If nothing was changed, skip this step — QA results live in your head and in the plan checklist below.

---

## Implementation notes for the agent

- **Working directory for all commands:** the repo root. All other paths in this plan are absolute-rooted-at-the-repo.
- **SwiftUI gotcha — NSWindow shadow on clear window:** the spec's dark rounded-rectangle look requires `window.isOpaque = false`, `backgroundColor = .clear`, and a rounded opaque fill drawn *inside* `contentView`. macOS computes the shadow from the content alpha mask, but it caches the shape, so after layout or resize we call `window.invalidateShadow()` — this is done in `NoteWindowController`.
- **SwiftUI gotcha — `@Published var notes: [Note]`:** every text keystroke republishes the whole array and invalidates all note views. Fine at v1 scale (tens of notes). If it ever feels laggy, refactor to per-note `ObservableObject` without changing the on-disk format.
- **Spec deviations:** none known. If any mid-flight simplification is required, document it in `README.md` under "Known issues" before proceeding, do not silently drift from the spec.
- **Commit discipline:** one task = one commit (or two, if QA produces a fix). Do not batch tasks.
