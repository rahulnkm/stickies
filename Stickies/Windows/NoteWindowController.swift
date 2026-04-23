import AppKit
import SwiftUI

final class NoteWindowController: NSWindowController, NSWindowDelegate {

    let noteID: UUID
    private unowned let store: NoteStore
    private let onClose: (UUID) -> Void

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
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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
