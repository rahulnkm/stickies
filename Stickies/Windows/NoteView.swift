import SwiftUI
import AppKit

enum NoteTheme {
    static let bg = Color(red: 0x2C/255, green: 0x2A/255, blue: 0x33/255)
    static let text = Color(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255)
    static let nsBg = NSColor(red: 0x2C/255, green: 0x2A/255, blue: 0x33/255, alpha: 1)
    static let nsText = NSColor(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255, alpha: 1)
    static let cornerRadius: CGFloat = 6
    static let innerPadding: CGFloat = 16
    static let topPadding: CGFloat = 30   // extra room so hover-reveal button doesn't collide with the first line
    static let hideSize: CGFloat = 8
    static let hideInset: CGFloat = 12
    /// macOS yellow stoplight color (approx).
    static let hideYellow = Color(red: 0xFE/255, green: 0xBC/255, blue: 0x2E/255)
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
    var onHide: () -> Void

    @State private var topBarHovering = false
    @State private var hideButtonHovering = false
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

            NoteTextEditor(
                initialBody: store.body(for: noteID),
                onChange: { newBody in
                    store.update(id: noteID, body: newBody)
                }
            )
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

                Button(action: onHide) {
                    ZStack {
                        Circle()
                            .fill(NoteTheme.hideYellow)
                            .frame(width: NoteTheme.hideSize, height: NoteTheme.hideSize)
                        if hideButtonHovering {
                            // Stoplight-style minus glyph appears on hover, mirroring macOS.
                            Rectangle()
                                .fill(Color.black.opacity(0.55))
                                .frame(width: 4, height: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, NoteTheme.hideInset)
                .onHover { hovering in
                    hideButtonHovering = hovering
                    handleHover(hovering)
                }
                .help("Hide note")
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

/// Rich-text editor wrapper. Takes an initial NSAttributedString and reports
/// changes via callback rather than a SwiftUI Binding — NSAttributedString
/// equality is expensive and a Binding would fight the in-flight text view.
private struct NoteTextEditor: NSViewRepresentable {
    let initialBody: NSAttributedString
    let onChange: (NSAttributedString) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()

        let tv = NoteTextView(frame: .zero)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0

        tv.isRichText = true
        tv.importsGraphics = true
        tv.allowsImageEditing = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = NoteTheme.nsText
        tv.insertionPointColor = NoteTheme.nsText
        tv.font = NoteTheme.font()
        tv.textContainerInset = .zero
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.typingAttributes = Self.typingAttributes()
        tv.delegate = context.coordinator

        // Seed the body, then force default font/color across the whole range.
        // - Plain-text bodies arrive with no attributes (Helvetica 12 black fallback).
        // - RTFD-decoded bodies may carry whatever attributes the write-time editor
        //   produced. Either way, the note's identity is Geist Mono + the off-white
        //   palette; flatten everything to that.
        tv.textStorage?.setAttributedString(initialBody)
        if let storage = tv.textStorage, storage.length > 0 {
            storage.addAttributes(Self.typingAttributes(),
                                  range: NSRange(location: 0, length: storage.length))
        }

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Don't push body changes back into the text view (NSTextView owns the
        // in-flight body), but DO keep the text view's width pinned to the
        // scroll view's clip-view width. Without this the document view can
        // grow wider than the visible area when a large image is inserted,
        // producing horizontal overflow inside the sticky.
        guard let tv = scroll.documentView as? NoteTextView else { return }
        let targetWidth = scroll.contentView.bounds.width
        guard targetWidth > 0, tv.frame.width != targetWidth else { return }
        tv.setFrameSize(NSSize(width: targetWidth, height: tv.frame.height))
        tv.textContainer?.containerSize = NSSize(width: targetWidth,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: tv.textStorage?.length ?? 0),
            actualCharacterRange: nil
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

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
        let onChange: (NSAttributedString) -> Void
        init(onChange: @escaping (NSAttributedString) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            onChange(NSAttributedString(attributedString: storage))
        }
    }
}
