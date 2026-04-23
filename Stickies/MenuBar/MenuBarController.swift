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
