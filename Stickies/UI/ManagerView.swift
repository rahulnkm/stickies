import SwiftUI
import AppKit

struct ManagerView: View {
    @ObservedObject var store: NoteStore
    let onToggleVisibility: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @State private var query: String = ""
    @State private var expandedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.4)

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    section(title: "Visible", notes: filtered(store.visibleNotes), emptyText: "No visible notes")
                    section(title: "Hidden",  notes: filtered(store.hiddenNotes),  emptyText: "No hidden notes")
                    Spacer(minLength: 24)
                }
                .padding(.top, 8)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 380, minHeight: 360)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField("Search notes…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func filtered(_ notes: [Note]) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return notes }
        return notes.filter { $0.text.lowercased().contains(q) }
    }

    // MARK: - Section

    @ViewBuilder
    private func section(title: String, notes: [Note], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(title)  ·  \(notes.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if notes.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else {
                ForEach(notes) { note in
                    rowView(for: note)
                    Divider().opacity(0.25).padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(for note: Note) -> some View {
        let isExpanded = expandedID == note.id

        VStack(alignment: .leading, spacing: 0) {
            // Tap area + summary row
            HStack(spacing: 10) {
                Image(systemName: note.isHidden ? "circle" : "circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(note.isHidden ? .secondary : NoteTheme.hideYellow)
                    .frame(width: 12)

                Text(MenuBarController.previewText(note.text))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(Self.relativeDate(note.updatedAt))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button(note.isHidden ? "Show" : "Hide") {
                    onToggleVisibility(note.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedID = isExpanded ? nil : note.id
                }
            }
            .contextMenu {
                Button(note.isHidden ? "Show Note" : "Hide Note") {
                    onToggleVisibility(note.id)
                }
                Divider()
                Button("Delete Forever", role: .destructive) {
                    if expandedID == note.id { expandedID = nil }
                    onDelete(note.id)
                }
            }

            if isExpanded {
                inlineEditor(for: note)
            }
        }
    }

    @ViewBuilder
    private func inlineEditor(for note: Note) -> some View {
        let binding = Binding<String>(
            get: { store.notes.first(where: { $0.id == note.id })?.text ?? "" },
            set: { store.update(id: note.id, text: $0) }
        )

        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: binding)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 280)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Formatting

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
