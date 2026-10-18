import AppKit
import Combine
import SwiftUI

/// Titled `NSWindow` subclass that hides its title bar for a sticky-note look
/// while preserving NSWindow's native edge-resize and drag handling. Plain
/// `.borderless` windows lose both.
final class KeyableStickyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class NoteWindowController: NSWindowController, NSWindowDelegate {

    let noteID: UUID
    private unowned let store: NoteStore
    private let onHide: (UUID) -> Void
    private var tintObserver: AnyCancellable?

    init(noteID: UUID, store: NoteStore, onHide: @escaping (UUID) -> Void) {
        self.noteID = noteID
        self.store = store
        self.onHide = onHide

        let initialFrame = store.notes.first(where: { $0.id == noteID })?.frame.cgRect
            ?? CGRect(x: 120, y: 340, width: 240, height: 240)

        let window = KeyableStickyWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        // Always-on-top over other apps. Floating-level windows still show up
        // in Mission Control on macOS 13+ (grouped at the bottom).
        window.level = .floating
        // Stays on the space it was created in — do NOT set .canJoinAllSpaces.
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.minSize = NSSize(width: 160, height: 140)
        window.contentMinSize = NSSize(width: 160, height: 140)

        super.init(window: window)
        window.delegate = self

        let hosting = NSHostingView(rootView: NoteView(
            noteID: noteID,
            store: store,
            onHide: { [weak self] in
                guard let self else { return }
                self.onHide(self.noteID)
            }
        ))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        // Pin the window light or dark to match the note's tint, so the AppKit
        // text view's dynamic colours follow the surface, not the system.
        tintObserver = store.$notes
            .map { $0.first(where: { $0.id == noteID })?.tintStyle ?? .slate }
            .removeDuplicates()
            .sink { [weak window] tint in window?.appearance = tint.appearance }

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
