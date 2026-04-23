import AppKit

final class MenuBarController {

    private let statusItem: NSStatusItem
    private let onNewNote: () -> Void
    private let launchAtLoginItem: NSMenuItem

    init(onNewNote: @escaping () -> Void) {
        self.onNewNote = onNewNote
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text",
                                   accessibilityDescription: "Stickies")
            button.image?.isTemplate = true
        }

        self.launchAtLoginItem = NSMenuItem(title: "Launch at Login",
                                            action: nil,
                                            keyEquivalent: "")

        let menu = NSMenu()

        let new = NSMenuItem(title: "New Note", action: #selector(newNoteAction), keyEquivalent: "n")
        new.keyEquivalentModifierMask = [.command]
        new.target = self
        menu.addItem(new)

        menu.addItem(.separator())

        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Stickies", action: #selector(quitAction), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginItem.state = LaunchAtLogin.userPreference ? .on : .off
    }

    @objc private func newNoteAction() { onNewNote() }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.userPreference.toggle()
        refreshLaunchAtLoginState()
    }

    @objc private func quitAction() { NSApp.terminate(nil) }
}
