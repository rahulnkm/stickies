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

    /// Notes deleted from `notes` but not yet removed from disk.
    private(set) var pendingDeletions: [UUID: Note] = [:]

    /// In-memory cache of rich bodies, lazily filled on first body(for:) call.
    private var bodies: [UUID: NSAttributedString] = [:]

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

    /// Synchronously flush all pending writes. Call from applicationWillTerminate.
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
            let url = rtfdURL(for: id)
            if let wrapper = try? FileWrapper(url: url, options: []),
               let body = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) {
                return NoteStore.upgradeAttachments(in: body)
            }
            logger.warning("RTFD load failed for \(id.uuidString, privacy: .public); falling back to plain text")
        }
        return NSAttributedString(string: note.text)
    }

    /// Replaces plain NSTextAttachment instances with FitWidthImageAttachment so
    /// loaded RTFD images participate in width-fit layout. RTFD decode produces
    /// base-class attachments; we promote each one in place.
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
            _ = try FileManager.default.replaceItemAt(jsonURL, withItemAt: tmp)
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
