import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Un canvas ouvert, avec sa barre d'outils et ses fenêtres (lien, note vocale, libellés…).
struct CanvasScreen: View {
    @Bindable var store: CanvasStore
    @Environment(LibraryStore.self) private var library
    @Environment(\.undoManager) private var undoManager

    @State private var showsRecorder = false
    @State private var showsImporter = false
    @State private var showsLinkSheet = false
    @State private var labelText = ""
    @State private var addressText = ""
    @State private var containerTitle = ""
    @AppStorage(Prefs.showMinimap) private var showsMinimap = true
    @AppStorage(Prefs.showInspector) private var showsInspector = false

    var body: some View {
        canvasArea
            .navigationTitle(library.index.canvas(store.id)?.name ?? "Nuvora")
            .focusedSceneValue(\.canvasStore, store)
            .onAppear { store.undoManager = undoManager }
            .onChange(of: undoManager) { _, manager in store.undoManager = manager }
            .onDisappear {
                store.endEditing()
                store.saveNow()
                AudioPlayback.shared.stop()
            }
            .quickLookPreview($store.quickLookURL)
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result { store.importFiles(urls) }
            }
            .sheet(isPresented: $showsLinkSheet) {
                AddLinkSheet { url in store.addLink(url) }
            }
            .alert(String(localized: "Libellé du lien"), isPresented: Binding(
                get: { store.editingLabelOf != nil },
                set: { if !$0 { store.editingLabelOf = nil } }
            )) {
                TextField(String(localized: "Libellé"), text: $labelText)
                Button(String(localized: "Valider")) {
                    if let id = store.editingLabelOf {
                        let text = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.updateConnection(id) { $0.label = text }
                    }
                    store.editingLabelOf = nil
                }
                Button(String(localized: "Annuler"), role: .cancel) { store.editingLabelOf = nil }
            } message: {
                Text(String(localized: "Laisse vide pour retirer le libellé."))
            }
            .alert(String(localized: "Renommer"), isPresented: Binding(
                get: { store.renamingContainer != nil },
                set: { if !$0 { store.renamingContainer = nil } }
            )) {
                TextField(String(localized: "Nom"), text: $containerTitle)
                Button(String(localized: "Renommer")) {
                    if let id = store.renamingContainer {
                        store.renameContainer(id, to: containerTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    store.renamingContainer = nil
                }
                Button(String(localized: "Annuler"), role: .cancel) { store.renamingContainer = nil }
            }
            .onChange(of: store.renamingContainer) { _, id in
                containerTitle = id.map { store.currentName(of: $0) } ?? ""
            }
            .alert(String(localized: "Adresse du lien"), isPresented: Binding(
                get: { store.editingAddressOf != nil },
                set: { if !$0 { store.editingAddressOf = nil } }
            )) {
                TextField(String(localized: "https://…"), text: $addressText)
                Button(String(localized: "Valider")) {
                    if let id = store.editingAddressOf { store.setAddress(id, addressText) }
                    store.editingAddressOf = nil
                }
                Button(String(localized: "Annuler"), role: .cancel) { store.editingAddressOf = nil }
            }
            .alert(store.alertMessage ?? "", isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.alertMessage = nil } }
            )) {
                Button(String(localized: "OK")) { store.alertMessage = nil }
            }
            .onChange(of: store.editingLabelOf) { _, id in
                labelText = id.flatMap { id in store.document.connections.first { $0.id == id }?.label } ?? ""
            }
            .onChange(of: store.editingAddressOf) { _, id in
                addressText = id.flatMap { store.document.item($0)?.url } ?? ""
            }
            .onReceive(NotificationCenter.default.publisher(for: .nuvoraRecordVoice)) { _ in showsRecorder = true }
            .onReceive(NotificationCenter.default.publisher(for: .nuvoraImportFile)) { _ in showsImporter = true }
            .onReceive(NotificationCenter.default.publisher(for: .nuvoraAddLink)) { _ in showsLinkSheet = true }
    }

    /// L'en-tête, puis le canvas et, à droite, le panneau de détails
    private var canvasArea: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                surface
                if showsInspector {
                    Divider()
                    InspectorView(store: store)
                        .frame(width: 290)
                        .background { SidebarBackground() }
                }
            }
        }
    }

    /// Le canvas, avec la miniature en bas à droite et la barre flottante en bas
    private var surface: some View {
        CanvasView(store: store)
            .overlay(alignment: .bottomTrailing) {
                if showsMinimap {
                    // Dans le coin, au niveau de la barre flottante ; remontée quand la place manque
                    MinimapView(store: store)
                        .padding(.trailing, 14)
                        .padding(.bottom, store.viewSize.width > 1180 ? 14 : 70)
                }
            }
            .overlay(alignment: .topLeading) {
                if let id = store.fullEditorID {
                    FullNoteEditor(store: store, id: id)
                        .id(id)
                }
            }
            .overlay(alignment: .bottom) {
                CanvasToolbar(
                    store: store, showsRecorder: $showsRecorder,
                    showsImporter: $showsImporter, showsLinkSheet: $showsLinkSheet
                )
                .padding(.bottom, 14)
            }
    }

    /// En-tête : nom du canvas, compteurs, état de l'enregistrement, couleur de la sélection, panneau de détails
    private var header: some View {
        HStack(spacing: 10) {
            Text(library.index.canvas(store.id)?.name ?? "")
                .font(.app(size: 14, weight: .semibold))
                .lineLimit(1)
            Text(countsLine)
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 5) {
                Circle().fill(saveColor).frame(width: 5, height: 5)
                Text(saveStatus)
                    .font(.app(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !store.selection.isEmpty {
                Divider().frame(height: 18)
                ColorDots(current: selectionColor, size: 12) { store.setColor($0, for: store.selection) }
            }
            Spacer(minLength: 8)
            Button {
                store.newNoteInFullEditor()
            } label: {
                Label(String(localized: "Nouvelle note"), systemImage: "plus")
            }
            .buttonStyle(OutlineButtonStyle())
            .help(String(localized: "Nouvelle note, ouverte dans l'éditeur complet"))
            Button {
                showsInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.app(size: 15))
                    .foregroundStyle(showsInspector ? Color.theme : Color.secondary)
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Afficher ou masquer les détails"))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    /// Couleur commune aux éléments sélectionnés (`nil` s'ils diffèrent)
    private var selectionColor: ItemColor? {
        let colors = Set(store.selection.compactMap { store.document.item($0)?.color })
        return colors.count == 1 ? colors.first : nil
    }

    /// « 7 cartes · 2 conteneurs »
    private var countsLine: String {
        let containers = store.document.containerCount
        let cards = store.document.cardCount
        let parts = [
            cards == 1 ? String(localized: "1 carte") : String(localized: "\(String(cards)) cartes"),
            containers == 1 ? String(localized: "1 conteneur") : String(localized: "\(String(containers)) conteneurs"),
        ]
        return parts.joined(separator: " · ")
    }

    private var saveColor: Color {
        if store.saveFailed { return ItemColor.red.tint ?? .red }
        return (store.hasUnsavedChanges ? ItemColor.orange.tint : ItemColor.green.tint) ?? .green
    }

    private var saveStatus: String {
        if store.saveFailed { return String(localized: "Échec de l'enregistrement") }
        if store.hasUnsavedChanges { return String(localized: "Modifications non enregistrées") }
        if let date = store.lastSaved {
            return String(localized: "Enregistré à \(date.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "Enregistré")
    }
}

/// Fenêtre « Ajouter un lien » : le presse-papiers est proposé s'il contient une adresse.
private struct AddLinkSheet: View {
    let add: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var url: URL? { WebAddress.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Ajouter un lien web"))
                .font(.app(size: 13, weight: .semibold))
            TextField(String(localized: "https://exemple.fr"), text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
                .frame(width: 380)
            if !text.isEmpty && url == nil {
                Text(String(localized: "Ce n'est pas une adresse web valide."))
                    .font(.app(size: 10.5))
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Annuler"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Ajouter"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(url == nil)
            }
        }
        .padding(20)
        .onAppear {
            if let clip = NSPasteboard.general.string(forType: .string), WebAddress.parse(clip) != nil {
                text = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            focused = true
        }
    }

    private func submit() {
        guard let url else { return }
        add(url)
        dismiss()
    }
}

/// Enregistrement d'une note vocale : démarre dès l'ouverture, « Terminer » l'ajoute au canvas.
struct VoiceRecorderView: View {
    let store: CanvasStore
    @Binding var isPresented: Bool
    @State private var recorder = AudioRecorder()
    @State private var asset: String?
    @State private var error: String?
    @State private var finished = false

    var body: some View {
        VStack(spacing: 14) {
            Text(String(localized: "Note vocale"))
                .font(.app(size: 13, weight: .semibold))

            if let error {
                Label(error, systemImage: "mic.slash")
                    .font(.app(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 280)
                Button(String(localized: "Ouvrir les réglages du micro")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(Color.red.opacity(0.75))
                            .frame(width: 4, height: max(3, CGFloat(level) * 44))
                    }
                }
                .frame(height: 48)
                .animation(.linear(duration: 0.05), value: recorder.levels)

                Text(Format.duration(recorder.elapsed))
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 10) {
                    Button(String(localized: "Annuler"), role: .cancel) {
                        recorder.cancel()
                        finished = true
                        isPresented = false
                    }
                    Button {
                        finish()
                    } label: {
                        Label(String(localized: "Terminer"), systemImage: "stop.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
                    .disabled(!recorder.isRecording)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 300)
        .task {
            let name = "\(UUID().uuidString).m4a"
            asset = name
            do {
                try await recorder.start(to: store.assetsURL.appending(path: name))
            } catch let failure {
                error = failure.localizedDescription
            }
        }
        // Fermé autrement (clic à côté, Échap) : l'enregistrement n'est pas perdu
        .onDisappear { if !finished && recorder.isRecording { finish() } }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let duration = recorder.stop()
        if let asset, duration > 0.3 {
            store.addRecording(asset: asset, duration: duration)
        } else if let asset {
            try? FileManager.default.removeItem(at: store.assetsURL.appending(path: asset))
        }
        isPresented = false
    }
}
