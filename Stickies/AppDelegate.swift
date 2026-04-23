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
