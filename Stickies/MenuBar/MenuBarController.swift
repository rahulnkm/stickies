import AppKit
import os

final class MenuBarController {

    private let statusItem: NSStatusItem
    private let onNewNote: () -> Void
    private let launchAtLoginItem: NSMenuItem
    private static let logger = Logger(subsystem: "com.rahulnkm.stickies", category: "MenuBar")

    init(onNewNote: @escaping () -> Void) {
        self.onNewNote = onNewNote
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.logger.notice("MenuBarController init: statusItem created, length=\(self.statusItem.length)")

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "note.text",
                                accessibilityDescription: "Stickies")
            if let image {
                button.image = image
                button.image?.isTemplate = true
                Self.logger.notice("Status item image set (SF Symbol note.text)")
            } else {
                // Fallback: SF Symbol unavailable — ensure the status item has a visible label
                // so it doesn't collapse to zero width.
                button.title = "●"
                Self.logger.warning("SF Symbol 'note.text' returned nil; using text fallback")
            }
        } else {
            Self.logger.error("statusItem.button is nil — status item will not render")
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
