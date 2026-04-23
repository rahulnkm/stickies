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
