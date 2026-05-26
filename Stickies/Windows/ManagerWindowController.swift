import AppKit
import SwiftUI

final class ManagerWindowController: NSWindowController, NSWindowDelegate {

    var onClosed: (() -> Void)?

    init(store: NoteStore,
         onToggleVisibility: @escaping (UUID) -> Void,
         onDelete: @escaping (UUID) -> Void) {
        let initialFrame = NSRect(x: 200, y: 200, width: 520, height: 640)
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Stickies"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 380, height: 360)
        window.setFrameAutosaveName("StickiesManager")
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let view = ManagerView(
            store: store,
            onToggleVisibility: onToggleVisibility,
            onDelete: onDelete
        )
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}
