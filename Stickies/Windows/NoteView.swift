import SwiftUI
import AppKit

enum NoteTheme {
    static let bg = Color(red: 0x1F/255, green: 0x1D/255, blue: 0x1A/255)
    static let text = Color(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255)
    static let nsBg = NSColor(red: 0x1F/255, green: 0x1D/255, blue: 0x1A/255, alpha: 1)
    static let nsText = NSColor(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255, alpha: 1)
    static let cornerRadius: CGFloat = 6
    static let innerPadding: CGFloat = 16
    static let topPadding: CGFloat = 30   // extra room so hover-reveal × doesn't collide with the first line
    static let closeSize: CGFloat = 12
    static let closeInset: CGFloat = 12
    static let fontSize: CGFloat = 13
    static let lineHeightMultiple: CGFloat = 1.0
    static let tracking: CGFloat = 0

    /// Geist Mono, bundled via `ATSApplicationFontsPath` in Info.plist.
    /// Falls back to the system monospaced font if it fails to register.
    static func font(size: CGFloat = fontSize) -> NSFont {
        NSFont(name: "GeistMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

struct NoteView: View {
    let noteID: UUID
    @ObservedObject var store: NoteStore
    var onClose: () -> Void

    @State private var hovering = false

    private var note: Note? { store.notes.first(where: { $0.id == noteID }) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous)
                .fill(NoteTheme.bg)

            NoteTextEditor(text: Binding(
                get: { note?.text ?? "" },
                set: { store.update(id: noteID, text: $0) }
            ))
            .padding(.top, NoteTheme.topPadding)
            .padding(.horizontal, NoteTheme.innerPadding)
            .padding(.bottom, NoteTheme.innerPadding)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(NoteTheme.text)
                    .frame(width: NoteTheme.closeSize, height: NoteTheme.closeSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, NoteTheme.closeInset)
            .padding(.trailing, NoteTheme.closeInset)
            .opacity(hovering ? 0.7 : 0.0)
            .animation(.easeInOut(duration: 0.12), value: hovering)
        }
        .onHover { hovering = $0 }
        .clipShape(RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous))
        .ignoresSafeArea()
    }
}

/// Direct NSTextView wrapper so we can zero out its internal insets and apply
/// the spec's line-height and tracking. `TextEditor` adds ~5pt of lineFragmentPadding
/// and cannot express either attribute, which made the padding look loose.
private struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = NoteTheme.nsText
        tv.insertionPointColor = NoteTheme.nsText
        tv.font = NoteTheme.font()
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.delegate = context.coordinator
        tv.typingAttributes = Self.typingAttributes()

        tv.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: Self.typingAttributes())
        )

        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let ranges = tv.selectedRanges
            tv.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: Self.typingAttributes())
            )
            tv.selectedRanges = ranges
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func typingAttributes() -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = NoteTheme.lineHeightMultiple
        return [
            .font: NoteTheme.font(),
            .foregroundColor: NoteTheme.nsText,
            .paragraphStyle: para,
            .kern: NoteTheme.tracking,
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        init(_ parent: NoteTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if parent.text != tv.string {
                parent.text = tv.string
            }
        }
    }
}
