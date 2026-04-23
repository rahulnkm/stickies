import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = NoteStore()
    private var controllers: [UUID: NoteWindowController] = [:]
    private var menuBar: MenuBarController!
    private let undoToast = UndoToast()

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
