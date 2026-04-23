import AppKit
import SwiftUI

final class UndoToast {

    enum Outcome { case undone, expired }

    private var panel: NSPanel?
    private var timer: Timer?
    private var activeCompletion: ((Outcome) -> Void)?

    private static let visibleDuration: TimeInterval = 3.0
    private static let size = CGSize(width: 240, height: 44)
    private static let bottomMargin: CGFloat = 48

    /// Shows the toast. Calls `completion` exactly once with the outcome.
    /// If another toast is active, the prior completion is resolved as `.expired`
    /// (committing the prior deletion) before this one is shown.
    func show(message: String = "Note deleted", completion: @escaping (Outcome) -> Void) {
        // Resolve any previously-active toast as expired so its deletion commits.
        if let prior = activeCompletion {
            activeCompletion = nil
            dismissPanel()
            prior(.expired)
        }

        activeCompletion = completion

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

        let handle = UndoToastHandle(onUndo: { [weak self] in
            self?.fire(.undone)
        })

        let hosting = NSHostingView(rootView: UndoToastView(message: message, handle: handle))
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        panel = p
        p.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            self?.fire(.expired)
        }
    }

    /// Invoke the active completion exactly once with the given outcome, then clean up.
    private func fire(_ outcome: Outcome) {
        guard let completion = activeCompletion else { return }
        activeCompletion = nil
        dismissPanel()
        completion(outcome)
    }

    private func dismissPanel() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
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
