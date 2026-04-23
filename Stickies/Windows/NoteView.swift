import SwiftUI

enum NoteTheme {
    static let bg = Color(red: 0x1F/255, green: 0x1D/255, blue: 0x1A/255)
    static let text = Color(red: 0xE8/255, green: 0xE3/255, blue: 0xD8/255)
    static let cornerRadius: CGFloat = 6
    static let innerPadding: CGFloat = 16
    static let closeSize: CGFloat = 12
    static let closeInset: CGFloat = 12
}

struct NoteView: View {
    let noteID: UUID
    @ObservedObject var store: NoteStore
    var onClose: () -> Void

    @State private var hovering = false

    private var note: Note? { store.notes.first(where: { $0.id == noteID }) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background fill — drawn as a rounded shape so the NSWindow shadow
            // computes the correct silhouette (the window itself is transparent).
            RoundedRectangle(cornerRadius: NoteTheme.cornerRadius, style: .continuous)
                .fill(NoteTheme.bg)

            // Text editor
            TextEditor(text: Binding(
                get: { note?.text ?? "" },
                set: { store.update(id: noteID, text: $0) }
            ))
            .font(.system(size: 14))
            .foregroundColor(NoteTheme.text)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(NoteTheme.innerPadding)

            // Close button
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
    }
}
