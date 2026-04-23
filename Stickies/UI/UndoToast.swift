import AppKit
import SwiftUI

final class UndoToast {

    enum Outcome { case undone, expired }

    private var panel: NSPanel?
    private var timer: Timer?

    private static let visibleDuration: TimeInterval = 3.0
    private static let size = CGSize(width: 240, height: 44)
    private static let bottomMargin: CGFloat = 48

    /// Shows the toast. Calls `completion` exactly once with the outcome.
    func show(message: String = "Note deleted", completion: @escaping (Outcome) -> Void) {
        dismiss(outcome: nil) // belt-and-suspenders if somehow already visible

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: screen.midX - Self.size.width / 2,
            y: screen.minY + Self.bottomMargin
        )
        let frame = NSRect(origin: origin, size: Self.size)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false

        var boxed: UndoToastHandle!
        boxed = UndoToastHandle(onUndo: { [weak self] in
            self?.dismiss(outcome: .undone)
            completion(.undone)
        })

        let hosting = NSHostingView(rootView: UndoToastView(message: message, handle: boxed))
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        panel = p
        p.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            self?.dismiss(outcome: .expired)
            completion(.expired)
        }
    }

    /// Dismisses without firing completion (internal use).
    private func dismiss(outcome: Outcome?) {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        _ = outcome // silence unused
    }
}

/// Lightweight reference handle so the SwiftUI button can close the toast.
final class UndoToastHandle: ObservableObject {
    let onUndo: () -> Void
    init(onUndo: @escaping () -> Void) { self.onUndo = onUndo }
}

private struct UndoToastView: View {
    let message: String
    @ObservedObject var handle: UndoToastHandle

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(NoteTheme.text)
            Spacer()
            Button("Undo", action: handle.onUndo)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(NoteTheme.text)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NoteTheme.bg)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
