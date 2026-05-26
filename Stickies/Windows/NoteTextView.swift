import AppKit
import UniformTypeIdentifiers

final class NoteTextView: NSTextView {

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        let item = NSMenuItem(title: "Add Image…", action: #selector(addImageFromPicker), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func addImageFromPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Insert"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        insertImage(image)
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        if let image = NoteTextView.imageFromPasteboard(NSPasteboard.general) {
            insertImage(image)
            return
        }
        super.paste(sender)
    }

    // MARK: - Drag

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let images = NoteTextView.allImagesFromPasteboard(pb)
        if !images.isEmpty {
            let dropPoint = convert(sender.draggingLocation, from: nil)
            let charIndex = characterIndexForInsertion(at: dropPoint)
            insertImages(images, at: charIndex)
            return true
        }
        if NoteTextView.pasteboardHasOnlyNonImageContent(pb) {
            return false
        }
        return super.performDragOperation(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if !NoteTextView.allImagesFromPasteboard(pb).isEmpty { return .copy }
        if NoteTextView.pasteboardHasOnlyNonImageContent(pb) { return [] }
        return super.draggingEntered(sender)
    }

    // MARK: - Insertion

    func insertImage(_ image: NSImage) {
        insertImages([image], at: selectedRange().location)
    }

    private func insertImages(_ images: [NSImage], at insertionIndex: Int) {
        guard let storage = textStorage else { return }
        let typing = typingAttributes
        let toInsert = NSMutableAttributedString()
        for (i, image) in images.enumerated() {
            let att = FitWidthImageAttachment()
            att.image = image
            if i > 0 { toInsert.append(NSAttributedString(string: "\n", attributes: typing)) }
            toInsert.append(NSAttributedString(attachment: att))
        }
        // Trailing newline so the next keystroke lands on the line below the image.
        toInsert.append(NSAttributedString(string: "\n", attributes: typing))

        let safeIndex = min(insertionIndex, storage.length)
        let range = NSRange(location: safeIndex, length: 0)
        guard shouldChangeText(in: range, replacementString: toInsert.string) else { return }
        storage.replaceCharacters(in: range, with: toInsert)
        didChangeText()
        setSelectedRange(NSRange(location: safeIndex + toInsert.length, length: 0))
    }

    // MARK: - Pasteboard helpers

    static func imageFromPasteboard(_ pb: NSPasteboard) -> NSImage? {
        return allImagesFromPasteboard(pb).first
    }

    static func allImagesFromPasteboard(_ pb: NSPasteboard) -> [NSImage] {
        var out: [NSImage] = []
        // 1) File URLs that point at image files (drag from Finder).
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                guard let type = UTType(filenameExtension: url.pathExtension.lowercased()),
                      type.conforms(to: .image) else { continue }
                if let image = NSImage(contentsOf: url) { out.append(image) }
            }
        }
        if !out.isEmpty { return out }
        // 2) Direct image objects (clipboard screenshots, drag from browsers).
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage] {
            out.append(contentsOf: images)
        }
        return out
    }

    /// True iff the pasteboard has typed content but none of it is an image, a
    /// file URL, or a plain string. Used to refuse PDF/RTF/etc. drops rather
    /// than letting super embed them as inline previews.
    static func pasteboardHasOnlyNonImageContent(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types, !types.isEmpty else { return false }
        let imageHints: Set<String> = [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
            "public.image",
            "public.jpeg",
            "public.heic",
        ]
        let hasImageHint = types.contains(where: { imageHints.contains($0.rawValue) })
        let hasFileURL = types.contains(.fileURL)
        let hasPlainString = types.contains(.string)
        return !hasImageHint && !hasFileURL && !hasPlainString
    }
}
