import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = NoteStore()
    private var controllers: [UUID: NoteWindowController] = [:]
    private var menuBar: MenuBarController!
    private var manager: ManagerWindowController?
    private let undoToast = UndoToast()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        LaunchAtLogin.reconcile()

        menuBar = MenuBarController(
            store: store,
            onNewNote: { [weak self] in self?.createNote() },
            onToggleVisibility: { [weak self] id in self?.toggleVisibility(id: id) },
            onOpenManager: { [weak self] in self?.openManager() }
        )

        for note in store.visibleNotes {
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

    func toggleVisibility(id: UUID) {
        guard let note = store.notes.first(where: { $0.id == id }) else { return }
        if note.isHidden {
            showNote(id: id)
        } else {
            hideNote(id: id)
        }
    }

    func hideNote(id: UUID) {
        // Persist final frame before tear-down so Show restores the exact position.
        controllers[id]?.close(persistFrame: true)
        controllers.removeValue(forKey: id)
        store.hide(id: id)
    }

    func showNote(id: UUID) {
        store.unhide(id: id)
        openWindow(for: id)
    }

    func deleteForever(id: UUID) {
        // Close any open window, mark deletion, fire undo toast.
        controllers[id]?.close(persistFrame: true)
        controllers.removeValue(forKey: id)
        store.beginDelete(id: id)

        undoToast.show(message: "Note deleted") { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .undone:
                if let restored = self.store.undelete(id: id) {
                    if !restored.isHidden {
                        self.openWindow(for: id)
                    }
                }
            case .expired:
                self.store.commitDelete(id: id)
            }
        }
    }

    func openManager() {
        if let manager {
            manager.show()
            return
        }
        let mgr = ManagerWindowController(
            store: store,
            onToggleVisibility: { [weak self] id in self?.toggleVisibility(id: id) },
            onDelete: { [weak self] id in self?.deleteForever(id: id) }
        )
        manager = mgr
        mgr.onClosed = { [weak self] in self?.manager = nil }
        mgr.show()
    }

    // MARK: - Window management

    func openWindow(for id: UUID) {
        guard controllers[id] == nil else {
            controllers[id]?.show()
            return
        }
        let wc = NoteWindowController(noteID: id, store: store) { [weak self] hiddenID in
            self?.hideNote(id: hiddenID)
        }
        controllers[id] = wc
        wc.show()
    }

    func closeWindow(for id: UUID, persistFrame: Bool = true) {
        controllers[id]?.close(persistFrame: persistFrame)
        controllers.removeValue(forKey: id)
    }
}
