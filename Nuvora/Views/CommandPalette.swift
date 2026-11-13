import SwiftUI

/// Palette flottante (⌘K) : cherche dans les canvas (nom et contenu) et les conteneurs, et lance les commandes.
struct CommandPalette: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppUpdater.self) private var updater
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    struct Entry: Identifiable {
        let id: String
        let title: String
        var subtitle: String = ""
        let symbol: String
        var shortcut: String = ""
        let run: () -> Void
    }

    var body: some View {
        let entries = self.entries
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.app(size: 17))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Rechercher un canvas, un contenu ou une commande…"), text: $query)
                        .textFieldStyle(.plain)
                        .font(.app(size: 17))
                        .focused($focused)
                        .onSubmit { run(entries) }
                        .onKeyPress(.downArrow) {
                            highlighted = min(highlighted + 1, max(entries.count - 1, 0))
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            highlighted = max(highlighted - 1, 0)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            isPresented = false
                            return .handled
                        }
                    KeyCap(text: "esc")
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                ScrollView {
                    VStack(spacing: 2) {
                        if entries.isEmpty {
                            Text(String(localized: "Aucun résultat."))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 18)
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { position, entry in
                            row(entry, isHighlighted: position == highlighted)
                                .onHover { inside in if inside { highlighted = position } }
                                .onTapGesture {
                                    highlighted = position
                                    run(entries)
                                }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 340)

                Divider()

                HStack(spacing: 6) {
                    KeyCap(text: "↑")
                    KeyCap(text: "↓")
                    Text(String(localized: "naviguer"))
                    KeyCap(text: "↩").padding(.leading, 8)
                    Text(String(localized: "ouvrir"))
                    Spacer()
                    Text(library.index.canvases.count == 1
                         ? String(localized: "1 canvas")
                         : String(localized: "\(String(library.index.canvases.count)) canvas"))
                }
                .font(.app(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 34)
            }
            .frame(width: 580)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
            .padding(.top, 70)
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    private func row(_ entry: Entry, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol)
                .frame(width: 22)
                .foregroundStyle(isHighlighted ? Color.theme : Color.secondary)
            Text(entry.title)
                .lineLimit(1)
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.app(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !entry.shortcut.isEmpty { KeyCap(text: entry.shortcut) }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(isHighlighted ? Color.theme.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func run(_ entries: [Entry]) {
        guard entries.indices.contains(highlighted) else { return }
        isPresented = false
        entries[highlighted].run()
    }

    // MARK: - Contenu

    private var entries: [Entry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = commands.filter { text.isEmpty || $0.title.localizedStandardContains(text) }

        let canvases: [CanvasEntry] = text.isEmpty
            ? Array(library.index.canvases.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8))
            : library.search(text)
        for canvas in canvases {
            let path = library.index.path(of: canvas.folderID).map(\.name).joined(separator: " › ")
            result.append(Entry(
                id: "canvas-" + canvas.id.uuidString, title: canvas.name, subtitle: path,
                symbol: CanvasIcons.symbol(canvas.icon)
            ) { library.selectedCanvasID = canvas.id })
        }

        if !text.isEmpty {
            for container in library.allContainers() where container.title.localizedStandardContains(text) {
                result.append(Entry(
                    id: "container-" + container.id.uuidString, title: container.title,
                    subtitle: container.canvasName, symbol: "square.dashed"
                ) { library.show(container) })
            }
        }
        return result
    }

    private var commands: [Entry] {
        var list: [Entry] = []
        let store = library.openCanvas
        if let store {
            list.append(Entry(id: "note", title: String(localized: "Nouvelle note"), symbol: "note.text.badge.plus", shortcut: "⌥⌘1") {
                store.addNote()
            })
        }
        list.append(Entry(id: "canvas", title: String(localized: "Nouveau canvas"), symbol: "plus.rectangle", shortcut: "⌘N") {
            library.createCanvas(in: library.currentFolderID)
        })
        list.append(Entry(id: "folder", title: String(localized: "Nouveau dossier"), symbol: "folder.badge.plus", shortcut: "⇧⌘N") {
            library.createFolder(in: nil)
        })
        if let store {
            list.append(Entry(id: "fit", title: String(localized: "Tout afficher"), symbol: "scope", shortcut: "⌘1") {
                store.fitAll()
            })
            list.append(Entry(
                id: "hand",
                title: store.handMode ? String(localized: "Mode sélection") : String(localized: "Mode main"),
                symbol: store.handMode ? "cursorarrow" : "hand.raised",
                shortcut: store.handMode ? "V" : "H"
            ) { store.handMode.toggle() })
            list.append(Entry(id: "details", title: String(localized: "Afficher ou masquer les détails"), symbol: "sidebar.right") {
                let shown = UserDefaults.standard.bool(forKey: Prefs.showInspector)
                UserDefaults.standard.set(!shown, forKey: Prefs.showInspector)
            })
        }
        list.append(Entry(id: "settings", title: String(localized: "Réglages…"), symbol: "gearshape", shortcut: "⌘,") {
            NotificationCenter.default.post(name: .nuvoraSettings, object: nil)
        })
        list.append(Entry(id: "updates", title: String(localized: "Rechercher les mises à jour…"), symbol: "arrow.triangle.2.circlepath") {
            updater.checkForUpdates()
        })
        return list
    }
}

/// Touche de clavier dessinée
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.app(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 1))
    }
}
