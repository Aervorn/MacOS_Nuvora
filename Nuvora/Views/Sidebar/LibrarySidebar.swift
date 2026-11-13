import SwiftUI

/// Ce qu'on renomme ou supprime depuis la barre latérale.
enum LibraryTarget: Identifiable, Equatable {
    case canvas(UUID)
    case folder(UUID)

    var id: UUID {
        switch self {
        case let .canvas(id), let .folder(id): id
        }
    }

    /// Texte transporté par le glisser-déposer
    var dragPayload: String {
        switch self {
        case let .canvas(id): "canvas:\(id.uuidString)"
        case let .folder(id): "folder:\(id.uuidString)"
        }
    }

    init?(payload: String) {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "canvas": self = .canvas(id)
        case "folder": self = .folder(id)
        default: return nil
        }
    }
}

/// Barre latérale : titre de l'app, recherche, dossiers (imbriqués) et canvas, conteneurs, version.
/// Réduite, elle devient une barre d'icônes. Glisser un canvas ou un dossier sur un dossier l'y range.
struct LibrarySidebar: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppUpdater.self) private var updater
    @Binding var collapsed: Bool
    @Binding var showsPalette: Bool
    @AppStorage(Prefs.showContainers) private var showsContainers = true
    @State private var renaming: LibraryTarget?
    @State private var renameText = ""
    @State private var deleting: LibraryTarget?
    @State private var pickingIcon: UUID?

    var body: some View {
        Group {
            if collapsed { rail } else { full }
        }
        .background { SidebarBackground().ignoresSafeArea() }
        .sheet(isPresented: Binding(get: { pickingIcon != nil }, set: { if !$0 { pickingIcon = nil } })) {
            if let id = pickingIcon { IconPicker(canvasID: id) }
        }
        .alert(String(localized: "Renommer"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: "Nom"), text: $renameText)
            Button(String(localized: "Renommer")) { commitRename() }
            Button(String(localized: "Annuler"), role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Mettre à la corbeille"), role: .destructive) { commitDelete() }
            Button(String(localized: "Annuler"), role: .cancel) { deleting = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: - Barre complète

    private var full: some View {
        VStack(spacing: 0) {
            // Titre centré, bouton de réduction sur la même ligne
            ZStack {
                Text(verbatim: "Nuvora")
                    .font(.app(size: 14, weight: .semibold))
                HStack {
                    Spacer()
                    SidebarIcon(symbol: "sidebar.left", help: String(localized: "Réduire la barre latérale")) {
                        collapsed = true
                    }
                }
            }
            .padding(.horizontal, 10)
            // Sur la ligne des boutons de la fenêtre
            .frame(height: 30)
            .padding(.bottom, 8)

            searchButton

            tree

            Divider()
            footer
        }
    }

    /// Ressemble à un champ de recherche ; un clic ouvre la palette (⌘K)
    private var searchButton: some View {
        Button {
            showsPalette = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text(String(localized: "Rechercher…"))
                Spacer()
                Text(verbatim: "⌘K")
                    .font(.app(size: 11, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .help(String(localized: "Rechercher un canvas, un contenu ou une commande (⌘K)"))
    }

    private var tree: some View {
        @Bindable var library = library
        return List(selection: $library.selectedCanvasID) {
            Section {
                FolderContents(parent: nil, actions: actions)
            } header: {
                HStack(spacing: 2) {
                    Text(String(localized: "Bibliothèque"))
                        .textCase(.uppercase)
                        .kerning(0.9)
                        .font(.app(size: 10.5, weight: .semibold))
                    Spacer()
                    SidebarIcon(symbol: "folder.badge.plus", help: String(localized: "Nouveau dossier")) {
                        library.createFolder(in: nil)
                    }
                    SidebarIcon(symbol: "plus", help: String(localized: "Nouveau canvas")) {
                        library.createCanvas(in: nil)
                    }
                }
            }

            Section {
                if showsContainers {
                    let containers = library.allContainers()
                    if containers.isEmpty {
                        Text(String(localized: "Aucun conteneur pour l'instant."))
                            .font(.app(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(containers) { container in
                        ContainerRow(container: container)
                    }
                }
            } header: {
                Button {
                    showsContainers.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(String(localized: "Conteneurs"))
                            .textCase(.uppercase)
                            .kerning(0.9)
                            .font(.app(size: 10.5, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.app(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(showsContainers ? 90 : 0))
                            .frame(width: 22, height: 20)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .dropDestination(for: String.self) { payloads, _ in
            return move(payloads, to: nil)
        }
        .contextMenu {
            Button(String(localized: "Nouveau canvas")) { library.createCanvas(in: nil) }
            Button(String(localized: "Nouveau dossier")) { library.createFolder(in: nil) }
        }
    }

    /// Version courante : un clic recherche les mises à jour
    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                updater.checkForUpdates()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(String(localized: "Version \(updater.currentVersion)"))
                }
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(updater.isEnabled
                ? String(localized: "Rechercher les mises à jour…")
                : String(localized: "Désactivées dans les versions de développement."))
            Spacer()
            Button {
                NotificationCenter.default.post(name: .nuvoraSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Réglages (⌘,)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Barre d'icônes

    private var rail: some View {
        VStack(spacing: 8) {
            SidebarIcon(symbol: "sidebar.left", size: 16, help: String(localized: "Afficher la barre latérale")) {
                collapsed = false
            }
            SidebarIcon(symbol: "magnifyingglass", size: 16, help: String(localized: "Rechercher un canvas, un contenu ou une commande (⌘K)")) {
                showsPalette = true
            }
            SidebarIcon(symbol: "plus", size: 16, help: String(localized: "Nouveau canvas")) {
                library.createCanvas(in: library.currentFolderID)
            }
            Spacer()
            SidebarIcon(symbol: "arrow.triangle.2.circlepath", size: 16, help: String(localized: "Rechercher les mises à jour…")) {
                updater.checkForUpdates()
            }
            Button {
                NotificationCenter.default.post(name: .nuvoraSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.app(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Réglages (⌘,)"))
        }
        .padding(.bottom, 10)
        // Sous les boutons de la fenêtre, plus larges que la barre d'icônes
        .padding(.top, 38)
        .frame(maxWidth: .infinity)
    }

    private var actions: SidebarActions {
        SidebarActions(
            rename: { target in
                switch target {
                case let .canvas(id): renameText = library.index.canvas(id)?.name ?? ""
                case let .folder(id): renameText = library.index.folder(id)?.name ?? ""
                }
                renaming = target
            },
            delete: { deleting = $0 },
            move: { payloads, folder in move(payloads, to: folder) },
            pickIcon: { pickingIcon = $0 }
        )
    }

    private func move(_ payloads: [String], to folder: UUID?) -> Bool {
        var moved = false
        for payload in payloads {
            switch LibraryTarget(payload: payload) {
            case let .canvas(id)?:
                library.moveCanvas(id, to: folder)
                moved = true
            case let .folder(id)?:
                guard library.index.canMove(folder: id, to: folder) else { continue }
                library.moveFolder(id, to: folder)
                moved = true
            case nil:
                continue
            }
        }
        return moved
    }

    private func commitRename() {
        switch renaming {
        case let .canvas(id)?: library.renameCanvas(id, to: renameText)
        case let .folder(id)?: library.renameFolder(id, to: renameText)
        case nil: break
        }
        renaming = nil
    }

    private func commitDelete() {
        switch deleting {
        case let .canvas(id)?: library.deleteCanvas(id)
        case let .folder(id)?: library.deleteFolder(id)
        case nil: break
        }
        deleting = nil
    }

    private var deleteTitle: String {
        switch deleting {
        case let .canvas(id)?:
            String(localized: "Mettre « \(library.index.canvas(id)?.name ?? "") » à la corbeille ?")
        case let .folder(id)?:
            String(localized: "Supprimer le dossier « \(library.index.folder(id)?.name ?? "") » ?")
        case nil: ""
        }
    }

    private var deleteMessage: String {
        switch deleting {
        case let .folder(id)?:
            let count = library.canvasCount(inFolderTree: id)
            if count == 0 { return String(localized: "Le dossier est vide.") }
            if count == 1 { return String(localized: "Le canvas qu'il contient ira à la corbeille de macOS.") }
            return String(localized: "Les \(String(count)) canvas qu'il contient iront à la corbeille de macOS.")
        default:
            return String(localized: "Tu pourras le récupérer depuis la corbeille de macOS.")
        }
    }
}

/// Actions demandées par les lignes de la barre latérale.
struct SidebarActions {
    var rename: (LibraryTarget) -> Void
    var delete: (LibraryTarget) -> Void
    var move: ([String], UUID?) -> Bool
    var pickIcon: (UUID) -> Void
}

/// Sous-dossiers puis canvas d'un dossier (`nil` : la racine).
private struct FolderContents: View {
    @Environment(LibraryStore.self) private var library
    let parent: UUID?
    let actions: SidebarActions

    var body: some View {
        ForEach(library.index.subfolders(of: parent)) { folder in
            FolderNode(folder: folder, actions: actions)
        }
        ForEach(library.index.canvases(in: parent)) { canvas in
            CanvasRow(canvas: canvas, showsPath: false, actions: actions)
        }
    }
}

private struct FolderNode: View {
    @Environment(LibraryStore.self) private var library
    let folder: LibraryFolder
    let actions: SidebarActions
    @State private var isTargeted = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { library.index.folder(folder.id)?.isExpanded ?? true },
            set: { library.setExpanded(folder.id, $0) }
        )) {
            FolderContents(parent: folder.id, actions: actions)
        } label: {
            // Pas d'icône : seulement le chevron (vers la droite replié, vers le bas déplié)
            HStack {
                Text(folder.name)
                Spacer(minLength: 4)
                Text(verbatim: String(library.canvasCount(inFolderTree: folder.id)))
                    .font(.app(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                SidebarIcon(symbol: "plus", size: 11, help: String(localized: "Nouveau canvas dans ce dossier")) {
                    library.createCanvas(in: folder.id)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .background(isTargeted ? Color.theme.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .draggable(LibraryTarget.folder(folder.id).dragPayload)
                .dropDestination(for: String.self) { payloads, _ in
                    return actions.move(payloads, folder.id)
                } isTargeted: { isTargeted = $0 }
                .contextMenu {
                    Button(String(localized: "Nouveau canvas ici")) { library.createCanvas(in: folder.id) }
                    Button(String(localized: "Nouveau sous-dossier")) { library.createFolder(in: folder.id) }
                    Divider()
                    Button(String(localized: "Renommer…")) { actions.rename(.folder(folder.id)) }
                    MoveMenu(target: .folder(folder.id), current: folder.parentID, actions: actions)
                    Divider()
                    Button(String(localized: "Supprimer le dossier…"), role: .destructive) { actions.delete(.folder(folder.id)) }
                }
        }
    }
}

private struct CanvasRow: View {
    @Environment(LibraryStore.self) private var library
    let canvas: CanvasEntry
    let showsPath: Bool
    let actions: SidebarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Label {
                    Text(canvas.name)
                } icon: {
                    CanvasIconView(icon: canvas.icon, color: canvas.color)
                }
                Spacer(minLength: 4)
                if let count = canvas.cardCount {
                    Text(verbatim: String(count))
                        .font(.app(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            if showsPath {
                let path = library.index.path(of: canvas.folderID).map(\.name).joined(separator: " › ")
                if !path.isEmpty {
                    Text(path)
                        .font(.app(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
            }
        }
        .tag(canvas.id)
        .draggable(LibraryTarget.canvas(canvas.id).dragPayload)
        .contextMenu {
            Button(String(localized: "Renommer…")) { actions.rename(.canvas(canvas.id)) }
            Button(String(localized: "Dupliquer")) { library.duplicateCanvas(canvas.id) }
            Button(String(localized: "Choisir une icône…")) { actions.pickIcon(canvas.id) }
            MoveMenu(target: .canvas(canvas.id), current: canvas.folderID, actions: actions)
            Divider()
            Button(String(localized: "Mettre à la corbeille…"), role: .destructive) { actions.delete(.canvas(canvas.id)) }
        }
    }
}

/// Sous-menu « Déplacer vers » : la racine et tous les dossiers possibles.
private struct MoveMenu: View {
    @Environment(LibraryStore.self) private var library
    let target: LibraryTarget
    let current: UUID?
    let actions: SidebarActions

    var body: some View {
        Menu(String(localized: "Déplacer vers")) {
            Button(String(localized: "Bibliothèque (racine)")) { _ = actions.move([target.dragPayload], nil) }
                .disabled(current == nil)
            Divider()
            ForEach(destinations) { entry in
                Button(entry.title) { _ = actions.move([target.dragPayload], entry.id) }
                    .disabled(entry.id == current)
            }
        }
        .disabled(destinations.isEmpty && current == nil)
    }

    private struct Destination: Identifiable {
        let id: UUID
        let title: String
    }

    private var destinations: [Destination] {
        library.index.folders
            .filter { folder in
                if case let .folder(id) = target { return library.index.canMove(folder: id, to: folder.id) }
                return true
            }
            .map { Destination(id: $0.id, title: library.index.path(of: $0.id).map(\.name).joined(separator: " › ")) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// Petit bouton à icône de la barre latérale
struct SidebarIcon: View {
    let symbol: String
    var size: CGFloat = 13
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(size: size))
                .foregroundStyle(.secondary)
                .frame(width: size + 14, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Un conteneur dans la liste « Conteneurs » : un clic ouvre son canvas et cadre la vue dessus.
private struct ContainerRow: View {
    @Environment(LibraryStore.self) private var library
    let container: LibraryStore.ContainerRef

    var body: some View {
        Button {
            library.show(container)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: container.sharedID == nil ? "square.dashed" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(container.title.isEmpty ? String(localized: "Sans titre") : container.title)
                        .lineLimit(1)
                    Text(container.canvasCount > 1
                        ? String(localized: "Synchronisé dans \(String(container.canvasCount)) canvas")
                        : container.canvasName)
                        .font(.app(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(verbatim: String(container.count))
                    .font(.app(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { library.show(container) } label: {
                Label(String(localized: "Afficher"), systemImage: "scope")
            }
            Divider()
            Button { library.insert(container, linked: true) } label: {
                Label(String(localized: "Ajouter à ce canvas (synchronisé)"), systemImage: "arrow.triangle.2.circlepath")
            }
            Button { library.insert(container, linked: false) } label: {
                Label(String(localized: "Ajouter une copie indépendante"), systemImage: "plus.square.on.square")
            }
        }
        .disabled(library.openCanvas == nil)
    }
}
