import AppKit
import Foundation
import Observation

/// La bibliothèque : dossiers et canvas, enregistrés dans `~/Library/Application Support/Nuvora`.
///
/// ```
/// Nuvora/
/// ├── library.json            dossiers et liste des canvas
/// └── Canvases/<id>/
///     ├── canvas.json         éléments, liens, position de la vue
///     └── assets/             fichiers importés, notes vocales, aperçus des liens
/// ```
/// Tout reste en local : pas de compte, pas de synchronisation, pas de télémétrie.
@MainActor
@Observable
final class LibraryStore {
    private(set) var index = LibraryIndex()

    /// Canvas affiché
    var selectedCanvasID: UUID? {
        didSet {
            guard selectedCanvasID != oldValue else { return }
            UserDefaults.standard.set(selectedCanvasID?.uuidString, forKey: Prefs.lastCanvas)
        }
    }

    /// Canvas ouvert (un seul à la fois)
    private(set) var openCanvas: CanvasStore?
    /// Le canvas sélectionné n'a pas pu être lu : on ne l'ouvre pas, pour ne jamais écraser son fichier.
    private(set) var openError: String?

    let rootURL: URL
    var canvasesURL: URL { rootURL.appending(path: "Canvases", directoryHint: .isDirectory) }
    private var indexURL: URL { rootURL.appending(path: "library.json") }

    init(rootURL: URL? = nil) {
        let base = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Nuvora", directoryHint: .isDirectory)
        self.rootURL = base
        try? FileManager.default.createDirectory(at: canvasesURL, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Lecture et écriture

    private func load() {
        if let data = try? Data(contentsOf: indexURL), let decoded = try? JSONDecoder.nuvora.decode(LibraryIndex.self, from: data) {
            index = decoded
            // Canvas dont le dossier a disparu : retirés de la liste
            index.canvases.removeAll { !FileManager.default.fileExists(atPath: canvasFileURL($0.id).path) }
        } else if FileManager.default.fileExists(atPath: indexURL.path) {
            // Fichier illisible : on le met de côté plutôt que de l'écraser
            let aside = rootURL.appending(path: "library-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: indexURL, to: aside)
            index = LibraryIndex()
        }
        if index.canvases.isEmpty && index.folders.isEmpty {
            createWelcomeCanvas()
        }
        let last = UserDefaults.standard.string(forKey: Prefs.lastCanvas).flatMap(UUID.init(uuidString:))
        selectedCanvasID = last.flatMap { index.canvas($0)?.id } ?? index.canvases.first?.id
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder.nuvora.encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("Nuvora: library.json non enregistré : \(error)")
        }
    }

    func canvasFolderURL(_ id: UUID) -> URL { canvasesURL.appending(path: id.uuidString, directoryHint: .isDirectory) }
    func canvasFileURL(_ id: UUID) -> URL { canvasFolderURL(id).appending(path: "canvas.json") }

    // MARK: - Ouverture

    /// Ouvre le canvas sélectionné (et enregistre celui qu'on quitte).
    func openSelected() {
        guard openCanvas?.id != selectedCanvasID else { return }
        openCanvas?.saveNow()
        openCanvas = nil
        openError = nil
        guard let id = selectedCanvasID, index.canvas(id) != nil else { return }
        do {
            let data = try Data(contentsOf: canvasFileURL(id))
            let file = try JSONDecoder.nuvora.decode(CanvasFile.self, from: data)
            let store = CanvasStore(id: id, folderURL: canvasFolderURL(id), file: file)
            store.onModified = { [weak self] in self?.touch(id) }
            openCanvas = store
            if let focus = pendingFocus {
                pendingFocus = nil
                store.focus(focus)
            }
            // Canvas d'avant le comptage des cartes
            if let i = index.canvases.firstIndex(where: { $0.id == id }), index.canvases[i].cardCount != file.document.cardCount {
                index.canvases[i].cardCount = file.document.cardCount
                saveIndex()
            }
        } catch {
            openError = error.localizedDescription
        }
    }

    /// Enregistre tout avant de quitter.
    func saveAll() {
        openCanvas?.saveNow()
        saveIndex()
    }

    private func touch(_ id: UUID) {
        guard let i = index.canvases.firstIndex(where: { $0.id == id }) else { return }
        index.canvases[i].modifiedAt = Date()
        if let open = openCanvas, open.id == id { index.canvases[i].cardCount = open.document.cardCount }
        saveIndex()
    }

    // MARK: - Recherche et conteneurs

    /// Un conteneur d'un canvas, pour la liste « Conteneurs » de la barre latérale
    struct ContainerRef: Identifiable {
        let id: UUID
        let canvasID: UUID
        let canvasName: String
        let title: String
        let count: Int
        /// Identifiant commun quand le conteneur est synchronisé entre plusieurs canvas
        var sharedID: UUID?
        /// Nombre de canvas où il apparaît
        var canvasCount = 1
    }

    private struct Summary {
        var stamp: Date
        var text: String
        var containers: [(id: UUID, title: String, count: Int, sharedID: UUID?)]
    }

    /// Résumé de chaque canvas déjà lu, tant que le canvas n'a pas été modifié
    @ObservationIgnored private var summaries: [UUID: Summary] = [:]
    /// Conteneur à sélectionner à l'ouverture du prochain canvas
    @ObservationIgnored private var pendingFocus: UUID?

    private func summarize(_ document: CanvasDocument, stamp: Date) -> Summary {
        let containers = document.items.filter(\.isContainer).map { item in
            (id: item.id, title: item.text, count: document.descendants(of: item.id).count, sharedID: item.sharedID)
        }
        return Summary(stamp: stamp, text: document.searchText, containers: containers)
    }

    private func summary(of entry: CanvasEntry) -> Summary {
        if let open = openCanvas, open.id == entry.id { return summarize(open.document, stamp: entry.modifiedAt) }
        if let hit = summaries[entry.id], hit.stamp == entry.modifiedAt { return hit }
        var result = Summary(stamp: entry.modifiedAt, text: "", containers: [])
        if let data = try? Data(contentsOf: canvasFileURL(entry.id)),
           let file = try? JSONDecoder.nuvora.decode(CanvasFile.self, from: data) {
            result = summarize(file.document, stamp: entry.modifiedAt)
        }
        summaries[entry.id] = result
        return result
    }

    /// Canvas dont le nom ou le contenu (notes, transcriptions, noms de fichiers, liens, libellés) contient le texte.
    func search(_ query: String) -> [CanvasEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return index.canvases
            .filter { $0.name.localizedStandardContains(text) || summary(of: $0).text.localizedStandardContains(text) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Tous les conteneurs de tous les canvas, triés par titre
    func allContainers() -> [ContainerRef] {
        var result: [ContainerRef] = []
        var sharedPosition: [UUID: Int] = [:]
        // Le canvas ouvert d'abord : un conteneur synchronisé y renvoie de préférence
        let entries = index.canvases.filter { $0.id == selectedCanvasID } + index.canvases.filter { $0.id != selectedCanvasID }
        for entry in entries {
            for container in summary(of: entry).containers {
                // Un conteneur synchronisé n'apparaît qu'une fois, avec le nombre de canvas qui le montrent
                if let sharedID = container.sharedID, let position = sharedPosition[sharedID] {
                    result[position].canvasCount += 1
                    continue
                }
                if let sharedID = container.sharedID { sharedPosition[sharedID] = result.count }
                result.append(ContainerRef(
                    id: container.id, canvasID: entry.id, canvasName: entry.name,
                    title: container.title, count: container.count, sharedID: container.sharedID
                ))
            }
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Canvas qui montrent un conteneur synchronisé
    func canvases(sharing sharedID: UUID) -> [CanvasEntry] {
        index.canvases
            .filter { entry in summary(of: entry).containers.contains { $0.sharedID == sharedID } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Ouvre le canvas d'un conteneur et cadre la vue dessus.
    func show(_ container: ContainerRef) {
        if let open = openCanvas, open.id == container.canvasID {
            open.focus(container.id)
        } else {
            pendingFocus = container.id
            selectedCanvasID = container.canvasID
        }
    }

    var sharedURL: URL { rootURL.appending(path: "Shared", directoryHint: .isDirectory) }

    /// Ajoute un conteneur d'un autre canvas au canvas ouvert : synchronisé avec l'original, ou copie indépendante.
    func insert(_ container: ContainerRef, linked: Bool) {
        guard let target = openCanvas else { return }
        if container.canvasID == target.id {
            if linked {
                target.focus(container.id)
            } else {
                target.selection = [container.id]
                target.duplicateSelection()
            }
            return
        }
        let sourceURL = canvasFileURL(container.canvasID)
        let sourceAssets = canvasFolderURL(container.canvasID).appending(path: "assets", directoryHint: .isDirectory)
        guard let data = try? Data(contentsOf: sourceURL),
              var file = try? JSONDecoder.nuvora.decode(CanvasFile.self, from: data),
              let i = file.document.index(of: container.id),
              var content = file.document.sharedContent(of: container.id)
        else { return }

        guard linked else {
            target.insertContainer(content.detachedCopy(), sharedID: nil, stamp: nil, assetsFrom: sourceAssets)
            return
        }
        // Déjà partagé : la version publiée fait foi. Sinon, le conteneur d'origine devient partagé.
        let sharedID = file.document.items[i].sharedID ?? UUID()
        let stamp: String
        if let published = SharedStore.read(sharedID, in: sharedURL) {
            content = published.content
            stamp = published.stamp
        } else {
            stamp = SharedStore.write(content, id: sharedID, in: sharedURL)
        }
        SharedStore.copyAssets(content.referencedAssets, from: sourceAssets, to: SharedStore.assetsURL(in: sharedURL))
        if file.document.items[i].sharedID == nil {
            file.document.items[i].sharedID = sharedID
            file.document.items[i].sharedStamp = stamp
            if let updated = try? JSONEncoder.nuvora.encode(file) {
                try? updated.write(to: sourceURL, options: .atomic)
            }
            summaries[container.canvasID] = nil
        }
        target.insertContainer(content, sharedID: sharedID, stamp: stamp, assetsFrom: SharedStore.assetsURL(in: sharedURL))
    }

    func setIcon(_ id: UUID, icon: String?) {
        guard let i = index.canvases.firstIndex(where: { $0.id == id }) else { return }
        index.canvases[i].icon = icon
        saveIndex()
    }

    func setColor(_ id: UUID, color: ItemColor?) {
        guard let i = index.canvases.firstIndex(where: { $0.id == id }) else { return }
        index.canvases[i].color = color
        saveIndex()
    }

    // MARK: - Canvas

    /// Dossier où créer un nouveau canvas : celui du canvas affiché.
    var currentFolderID: UUID? { selectedCanvasID.flatMap { index.canvas($0)?.folderID } }

    @discardableResult
    func createCanvas(name: String? = nil, in folder: UUID? = nil, document: CanvasDocument = CanvasDocument()) -> UUID {
        let base = name ?? String(localized: "Nouveau canvas")
        let unique = LibraryIndex.uniqueName(base, among: index.canvases(in: folder).map(\.name))
        var entry = CanvasEntry(name: unique, folderID: folder)
        entry.cardCount = document.cardCount
        let folderURL = canvasFolderURL(entry.id)
        try? FileManager.default.createDirectory(at: folderURL.appending(path: "assets"), withIntermediateDirectories: true)
        let file = CanvasFile(document: document, viewport: nil)
        if let data = try? JSONEncoder.nuvora.encode(file) {
            try? data.write(to: canvasFileURL(entry.id), options: .atomic)
        }
        index.canvases.append(entry)
        if let folder { setExpanded(folder, true) }
        saveIndex()
        selectedCanvasID = entry.id
        return entry.id
    }

    func renameCanvas(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = index.canvases.firstIndex(where: { $0.id == id }) else { return }
        index.canvases[i].name = trimmed
        saveIndex()
    }

    func moveCanvas(_ id: UUID, to folder: UUID?) {
        guard let i = index.canvases.firstIndex(where: { $0.id == id }), index.canvases[i].folderID != folder else { return }
        index.canvases[i].folderID = folder
        if let folder { setExpanded(folder, true) }
        saveIndex()
    }

    func duplicateCanvas(_ id: UUID) {
        guard let entry = index.canvas(id) else { return }
        if openCanvas?.id == id { openCanvas?.saveNow() }
        var copy = CanvasEntry(
            name: LibraryIndex.uniqueName(
                String(localized: "\(entry.name) (copie)"),
                among: index.canvases(in: entry.folderID).map(\.name)
            ),
            folderID: entry.folderID
        )
        copy.cardCount = entry.cardCount
        do {
            try FileManager.default.copyItem(at: canvasFolderURL(id), to: canvasFolderURL(copy.id))
            index.canvases.append(copy)
            saveIndex()
            selectedCanvasID = copy.id
        } catch {
            NSLog("Nuvora: copie impossible : \(error)")
        }
    }

    /// Met le canvas à la corbeille de macOS (récupérable depuis le Finder).
    func deleteCanvas(_ id: UUID) {
        if openCanvas?.id == id {
            openCanvas?.discardPendingSave()
            openCanvas = nil
        }
        try? FileManager.default.trashItem(at: canvasFolderURL(id), resultingItemURL: nil)
        index.canvases.removeAll { $0.id == id }
        saveIndex()
        if selectedCanvasID == id { selectedCanvasID = index.canvases.first?.id }
    }

    // MARK: - Dossiers

    @discardableResult
    func createFolder(name: String? = nil, in parent: UUID? = nil) -> UUID {
        let base = name ?? String(localized: "Nouveau dossier")
        let folder = LibraryFolder(
            name: LibraryIndex.uniqueName(base, among: index.subfolders(of: parent).map(\.name)),
            parentID: parent
        )
        index.folders.append(folder)
        if let parent { setExpanded(parent, true) }
        saveIndex()
        return folder.id
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = index.folders.firstIndex(where: { $0.id == id }) else { return }
        index.folders[i].name = trimmed
        saveIndex()
    }

    func moveFolder(_ id: UUID, to parent: UUID?) {
        guard id != parent, index.canMove(folder: id, to: parent),
              let i = index.folders.firstIndex(where: { $0.id == id }), index.folders[i].parentID != parent
        else { return }
        index.folders[i].parentID = parent
        if let parent { setExpanded(parent, true) }
        saveIndex()
    }

    func setExpanded(_ id: UUID, _ expanded: Bool) {
        guard let i = index.folders.firstIndex(where: { $0.id == id }), index.folders[i].isExpanded != expanded else { return }
        index.folders[i].isExpanded = expanded
        saveIndex()
    }

    /// Nombre de canvas dans un dossier et ses sous-dossiers
    func canvasCount(inFolderTree id: UUID) -> Int {
        let tree = index.folderTree(id)
        return index.canvases.filter { $0.folderID.map(tree.contains) ?? false }.count
    }

    /// Supprime un dossier, ses sous-dossiers et leurs canvas (mis à la corbeille).
    func deleteFolder(_ id: UUID) {
        let tree = index.folderTree(id)
        for canvas in index.canvases where canvas.folderID.map(tree.contains) ?? false {
            deleteCanvas(canvas.id)
        }
        index.folders.removeAll { tree.contains($0.id) }
        saveIndex()
    }

    func revealInFinder() {
        FileManagerApp.reveal(rootURL)
    }

    // MARK: - Premier lancement

    /// Canvas d'accueil, qui montre ce qu'on peut faire.
    private func createWelcomeCanvas() {
        var doc = CanvasDocument()
        func note(_ text: String, _ x: CGFloat, _ y: CGFloat, _ color: ItemColor, w: CGFloat = 250, h: CGFloat = 130) -> UUID {
            let item = CanvasItem(kind: .note, frame: CGRect(x: x, y: y, width: w, height: h), zIndex: doc.maxZ + 1, color: color, text: text)
            doc.items.append(item)
            return item.id
        }
        let hello = note(
            String(localized: "**Bienvenue dans Nuvora**\n\nUn canvas infini, 100 % local : pas de compte, pas de télémétrie. Tout reste sur ton Mac."),
            0, 0, .purple, w: 300, h: 150
        )
        let create = note(
            String(localized: "**Créer**\n\nDouble-clique sur le fond pour une note. Dépose ici des images, vidéos, documents ou liens, ou colle-les avec ⌘V."),
            400, -80, .yellow
        )
        let link = note(
            String(localized: "**Relier**\n\nSurvole un élément et tire son **+** vers un autre. Clic droit sur un lien pour changer son sens ou son style."),
            400, 110, .blue
        )
        let move = note(
            String(localized: "**Naviguer**\n\nDeux doigts pour te déplacer, pincer ou ⌘ + molette pour zoomer, Espace + glisser pour faire défiler. ⌘1 affiche tout."),
            -10, 230, .green, w: 300, h: 140
        )
        doc.connect(hello, create, direction: .forward)
        doc.connect(hello, link, direction: .forward)
        doc.connect(hello, move, direction: .forward)
        doc.group([create, link], title: String(localized: "Pour commencer"))
        createCanvas(name: String(localized: "Bienvenue"), document: doc)
    }
}

extension JSONEncoder {
    static var nuvora: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var nuvora: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
