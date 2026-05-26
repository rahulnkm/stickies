import AppKit
import os

final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let store: NoteStore
    private let onNewNote: () -> Void
    private let onToggleVisibility: (UUID) -> Void
    private let onOpenManager: () -> Void
    private let launchAtLoginItem: NSMenuItem
    private static let logger = Logger(subsystem: "com.rahulnkm.stickies", category: "MenuBar")

    private static let previewLimit = 32
    private static let hiddenRowCap = 8

    init(store: NoteStore,
         onNewNote: @escaping () -> Void,
         onToggleVisibility: @escaping (UUID) -> Void,
         onOpenManager: @escaping () -> Void) {
        self.store = store
        self.onNewNote = onNewNote
        self.onToggleVisibility = onToggleVisibility
        self.onOpenManager = onOpenManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "note.text",
                                accessibilityDescription: "Stickies")
            if let image {
                button.image = image
                button.image?.isTemplate = true
            } else {
                button.title = "●"
                Self.logger.warning("SF Symbol 'note.text' returned nil; using text fallback")
            }
        } else {
            Self.logger.error("statusItem.button is nil — status item will not render")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    // MARK: - Menu construction

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let new = NSMenuItem(title: "New Note", action: #selector(newNoteAction), keyEquivalent: "n")
        new.keyEquivalentModifierMask = [.command]
        new.target = self
        menu.addItem(new)

        menu.addItem(.separator())

        let visible = store.visibleNotes
        let hidden = store.hiddenNotes

        addSection(title: "Visible (\(visible.count))", to: menu)
        if visible.isEmpty {
            menu.addItem(disabledItem("  (none — ⌘N to add one)"))
        } else {
            for note in visible {
                menu.addItem(row(for: note, isHidden: false))
            }
        }

        menu.addItem(.separator())

        addSection(title: "Hidden (\(hidden.count))", to: menu)
        if hidden.isEmpty {
            menu.addItem(disabledItem("  (none)"))
        } else {
            for note in hidden.prefix(Self.hiddenRowCap) {
                menu.addItem(row(for: note, isHidden: true))
            }
            if hidden.count > Self.hiddenRowCap {
                let more = NSMenuItem(
                    title: "  … \(hidden.count - Self.hiddenRowCap) more — open Manager",
                    action: #selector(openManagerAction),
                    keyEquivalent: ""
                )
                more.target = self
                menu.addItem(more)
            }
        }

        menu.addItem(.separator())

        let mgr = NSMenuItem(title: "Open Manager…", action: #selector(openManagerAction), keyEquivalent: "n")
        mgr.keyEquivalentModifierMask = [.command, .shift]
        mgr.target = self
        menu.addItem(mgr)

        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginItem.target = self
        launchAtLoginItem.state = LaunchAtLogin.userPreference ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Stickies", action: #selector(quitAction), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
    }

    private func addSection(title: String, to menu: NSMenu) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(header)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func row(for note: Note, isHidden: Bool) -> NSMenuItem {
        let bullet = isHidden ? "○" : "●"
        let preview = Self.previewText(note.text)
        let item = NSMenuItem(
            title: "  \(bullet)  \(preview)",
            action: #selector(toggleRowAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = note.id
        return item
    }

    static func previewText(_ raw: String) -> String {
        let firstLine = raw.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Untitled" }
        if trimmed.count > previewLimit {
            let cut = trimmed.prefix(previewLimit)
            return "\(cut)…"
        }
        return trimmed
    }

    // MARK: - Actions

    @objc private func newNoteAction() { onNewNote() }

    @objc private func openManagerAction() { onOpenManager() }

    @objc private func toggleRowAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onToggleVisibility(id)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.userPreference.toggle()
        launchAtLoginItem.state = LaunchAtLogin.userPreference ? .on : .off
    }

    @objc private func quitAction() { NSApp.terminate(nil) }
}
