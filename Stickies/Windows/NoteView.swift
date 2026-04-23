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

    @State private var topBarHovering = false
    @State private var hoverHideTask: DispatchWorkItem?

    private var note: Note? { store.notes.first(where: { $0.id == noteID }) }
    private var currentTint: NoteTintStyle { note?.tintStyle ?? .slate }

    /// Debounced hover handler. Going invisible is delayed by 120ms so the
    /// false→true flip when the cursor moves onto a child button gets
    /// cancelled before it's committed.
    private func handleHover(_ isHovering: Bool) {
        hoverHideTask?.cancel()
        if isHovering {
            topBarHovering = true
        } else {
            let task = DispatchWorkItem { topBarHovering = false }
            hoverHideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Translucent background: native blur + dark tint at the selected opacity.
            BlurView(material: .hudWindow, blendingMode: .behindWindow)
            RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous)
                .fill(NoteTheme.bg.opacity(currentTint.tintOpacity))

            NoteTextEditor(text: Binding(
                get: { note?.text ?? "" },
                set: { store.update(id: noteID, text: $0) }
            ))
            .padding(.top, NoteTheme.topPadding)
            .padding(.horizontal, NoteTheme.innerPadding)
            .padding(.bottom, NoteTheme.innerPadding)

            // Top-bar strip: only this area triggers the hover reveal.
            // Swatches left, close button right. Invisible until hover.
            topBar
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: NoteTheme.topPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous))
        .ignoresSafeArea()
    }

    private var topBar: some View {
        ZStack {
            // Always-rendered transparent layer that catches hover for the strip.
            Color.clear
                .contentShape(Rectangle())
                .onHover(perform: handleHover)

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(NoteTintStyle.allCases, id: \.self) { style in
                        TintSwatch(style: style, isSelected: currentTint == style) {
                            store.update(id: noteID, tintStyle: style)
                        }
                    }
                }
                .padding(.leading, 6)
                .onHover(perform: handleHover)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(NoteTheme.text)
                        .frame(width: NoteTheme.closeSize, height: NoteTheme.closeSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, NoteTheme.closeInset)
                // Keep the close-button hover from firing the strip's "false"
                // path (debounce already handles it, but this is belt-and-braces).
                .onHover(perform: handleHover)
            }
            .opacity(topBarHovering ? 0.9 : 0)
            .allowsHitTesting(topBarHovering)
            .animation(.easeInOut(duration: 0.12), value: topBarHovering)
        }
        .frame(maxWidth: .infinity)
        .frame(height: NoteTheme.topPadding, alignment: .top)
    }
}

private struct TintSwatch: View {
    let style: NoteTintStyle
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(white: style.swatchLightness))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().stroke(NoteTheme.text, lineWidth: isSelected ? 1.0 : 0)
                )
                // Tight horizontal gap (~6pt between circles); vertical padding
                // keeps the hit target tall enough for easy clicks.
                .padding(EdgeInsets(top: 8, leading: 3, bottom: 8, trailing: 3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.rawValue.capitalized)
    }
}

/// Native macOS vibrancy behind the note, so the dark palette reads as a
/// translucent frosted pane over the desktop / windows behind.
private struct BlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = NoteTheme.cornerRadius
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
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
            // Disable ligatures so Geist Mono doesn't collapse `...` into a
            // narrower ellipsis ligature that visually overlaps prior glyphs.
            .ligature: 0,
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
