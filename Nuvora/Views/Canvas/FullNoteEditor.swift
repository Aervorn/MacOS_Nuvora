import AppKit
import SwiftUI

/// Fond commun aux deux barres latérales et aux panneaux flottants
struct SidebarBackground: View {
    var body: some View { Surface.panel }
}

/// Éditeur complet d'une note : une fenêtre flottante, à déplacer par son en-tête, avec le texte brut
/// (Markdown) d'un côté et son rendu de l'autre.
struct FullNoteEditor: View {
    let store: CanvasStore
    let id: UUID

    @State private var showsPreview = false
    @State private var origin: CGPoint?
    @State private var dragStart: CGPoint?
    @FocusState private var focused: Bool

    private var size: CGSize {
        CGSize(width: 460, height: max(320, min(600, store.viewSize.height - 110)))
    }

    private var position: CGPoint {
        origin ?? CGPoint(x: max(12, store.viewSize.width - size.width - 16), y: 14)
    }

    var body: some View {
        if let item = store.document.item(id) {
            panel(item)
                .frame(width: size.width, height: size.height)
                .background { SidebarBackground() }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
                .offset(x: position.x, y: position.y)
                .onAppear {
                    store.fullEditorFrame = CGRect(origin: position, size: size)
                    focused = true
                }
                .onChange(of: position) { _, value in store.fullEditorFrame = CGRect(origin: value, size: size) }
                .onDisappear { store.fullEditorFrame = .zero }
                .onExitCommand { store.closeFullEditor() }
        }
    }

    /// Glisser l'en-tête déplace la fenêtre, sans la laisser sortir du canvas
    private var move: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? position
                if dragStart == nil { dragStart = start }
                let maxX = max(0, store.viewSize.width - size.width)
                let maxY = max(0, store.viewSize.height - 60)
                origin = CGPoint(
                    x: min(max(start.x + value.translation.width, 0), maxX),
                    y: min(max(start.y + value.translation.height, 0), maxY)
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private func panel(_ item: CanvasItem) -> some View {
        let tasks = NoteMarkdown.tasks(item.text)
        return VStack(alignment: .leading, spacing: 0) {
            // En-tête : sert de poignée
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(item.color.tint ?? Color.secondary).frame(width: 8, height: 8)
                    Text(item.kind.label + " · " + item.createdAt.formatted(date: .long, time: .omitted))
                        .font(.app(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.closeFullEditor()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.app(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Fermer (Échap)"))
                }
                Text(item.displayTitle)
                    .font(.app(size: 20, weight: .bold))
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(move)

            HStack {
                Picker(String(localized: "Affichage"), selection: $showsPreview) {
                    Label(String(localized: "Code Markdown"), systemImage: "chevron.left.forwardslash.chevron.right").tag(false)
                    Label(String(localized: "Aperçu"), systemImage: "eye").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if !tasks.isEmpty {
                    Label(String(tasks.filter(\.done).count) + "/" + String(tasks.count), systemImage: "checklist")
                        .font(.app(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if !showsPreview {
                MarkdownToolbar(text: store.textBinding(id))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Divider()

            if showsPreview {
                ScrollView {
                    MarkdownText(text: item.text) { line in store.toggleTask(id, line: line) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                TextEditor(text: store.textBinding(id))
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
            }

            Divider()

            HStack(spacing: 14) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                } label: {
                    Label(String(localized: "Copier le Markdown"), systemImage: "doc.on.doc")
                }
                Button {
                    store.closeFullEditor()
                    store.selection = [id]
                    store.duplicateSelection()
                } label: {
                    Label(String(localized: "Dupliquer"), systemImage: "plus.square.on.square")
                }
                Spacer()
                Button(role: .destructive) {
                    store.delete([id])
                } label: {
                    Label(String(localized: "Supprimer"), systemImage: "trash")
                }
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .font(.app(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
    }
}
