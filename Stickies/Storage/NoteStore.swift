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
