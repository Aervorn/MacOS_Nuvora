import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Un canvas ouvert : son contenu, la vue (zoom, position), la sélection et les gestes en cours.
///
/// Toute modification passe par `perform` (ou une interaction qui se termine par `commit`), qui
/// l'inscrit dans l'historique (⌘Z / ⇧⌘Z) et programme l'enregistrement.
@MainActor
@Observable
final class CanvasStore {
    let id: UUID
    let folderURL: URL
    var assetsURL: URL { folderURL.appending(path: "assets", directoryHint: .isDirectory) }
    private var fileURL: URL { folderURL.appending(path: "canvas.json") }

    // MARK: Contenu

    var document: CanvasDocument

    // MARK: Vue

    var zoom: CGFloat
    var offset: CGPoint
    var viewSize: CGSize = .zero {
        didSet {
            if needsInitialFit, viewSize.width > 0, viewSize.height > 0 {
                needsInitialFit = false
                fitAll()
            }
        }
    }
    @ObservationIgnored private var needsInitialFit: Bool

    var transform: CanvasTransform { CanvasTransform(offset: offset, zoom: zoom) }

    // MARK: Sélection et gestes

    var selection: Set<UUID> = []
    var selectedConnection: UUID?
    /// Note ou conteneur dont on modifie le texte
    private(set) var editingID: UUID?
    /// Rectangle de sélection, en coordonnées de l'écran
    private(set) var marquee: CGRect?
    /// Lien en train d'être tiré : élément de départ et position du curseur (écran)
    private(set) var pendingConnection: (from: UUID, point: CGPoint)?
    /// Élément visé par le lien en cours
    private(set) var connectionTarget: UUID?
    /// Conteneur dans lequel tomberait l'élément déplacé
    private(set) var dropContainer: UUID?
    /// Espace enfoncée : glisser fait défiler le canvas
    var spacePanning = false
    /// Mode main : glisser n'importe où fait défiler le canvas (pratique à la souris)
    var handMode = false
    var isPanning: Bool { spacePanning || handMode }
    var isDropTargeted = false
    /// Fichier montré dans Quick Look
    var quickLookURL: URL?
    /// Lien dont on modifie le libellé, élément dont on modifie l'adresse
    var editingLabelOf: UUID?
    var editingAddressOf: UUID?
    var alertMessage: String?

    // MARK: Enregistrement

    /// Le contenu a changé depuis le dernier enregistrement
    private(set) var hasUnsavedChanges = false
    private(set) var lastSaved: Date?
    private(set) var saveFailed = false

    // MARK: Traitements en cours

    private(set) var transcribing: Set<UUID> = []
    private(set) var transcriptionErrors: [UUID: String] = [:]
    private(set) var fetchingPreviews: Set<UUID> = []

    @ObservationIgnored weak var undoManager: UndoManager?
    /// Appelé quand le contenu a changé (date de modification dans la bibliothèque)
    @ObservationIgnored var onModified: (() -> Void)?

    @ObservationIgnored private var interaction: Interaction?
    @ObservationIgnored private var editSnapshot: CanvasDocument?
    @ObservationIgnored private var pendingSelectOnly: UUID?
    @ObservationIgnored private var marqueeBase: Set<UUID> = []
    @ObservationIgnored private var lastPanTranslation: CGSize = .zero
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var contentChanged = false
    @ObservationIgnored private var cascade = 0

    private enum Interaction {
        case move(start: [UUID: CGPoint], roots: Set<UUID>, primary: UUID, snapshot: CanvasDocument)
        case resize(id: UUID, start: CGRect, snapshot: CanvasDocument)
    }

    init(id: UUID, folderURL: URL, file: CanvasFile) {
        self.id = id
        self.folderURL = folderURL
        document = file.document
        zoom = CGFloat(file.viewport?.zoom ?? 1)
        offset = CGPoint(x: file.viewport?.offsetX ?? 0, y: file.viewport?.offsetY ?? 0)
        needsInitialFit = file.viewport == nil
        try? FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        pruneOrphanAssets()
        pullShared()
    }

    // MARK: - Conteneurs partagés

    /// Dossier des conteneurs partagés, commun à tous les canvas
    var sharedURL: URL {
        folderURL.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Shared", directoryHint: .isDirectory)
    }

    /// À l'ouverture : chaque conteneur partagé reçoit la dernière version de son contenu.
    private func pullShared() {
        var changed = false
        for item in document.items where item.isContainer {
            guard let sharedID = item.sharedID, let file = SharedStore.read(sharedID, in: sharedURL),
                  file.stamp != item.sharedStamp else { continue }
            SharedStore.copyAssets(file.content.referencedAssets, from: SharedStore.assetsURL(in: sharedURL), to: assetsURL)
            document.applyShared(file.content, to: item.id)
            if let i = document.index(of: item.id) { document.items[i].sharedStamp = file.stamp }
            changed = true
        }
        if changed {
            contentChanged = true
            scheduleSave()
        }
    }

    /// À l'enregistrement : le contenu des conteneurs partagés est publié pour les autres canvas.
    private func pushShared() {
        for item in document.items where item.isContainer {
            guard let sharedID = item.sharedID, let content = document.sharedContent(of: item.id) else { continue }
            let stamp = SharedStore.write(content, id: sharedID, in: sharedURL)
            SharedStore.copyAssets(content.referencedAssets, from: assetsURL, to: SharedStore.assetsURL(in: sharedURL))
            if item.sharedStamp != stamp, let i = document.index(of: item.id) {
                document.items[i].sharedStamp = stamp
            }
        }
    }

    /// Ajoute un conteneur venu d'un autre canvas : synchronisé (`sharedID`) ou copie indépendante.
    func insertContainer(_ content: SharedContent, sharedID: UUID?, stamp: String?, assetsFrom source: URL) {
        if let sharedID, let existing = document.items.first(where: { $0.sharedID == sharedID }) {
            focus(existing.id)
            return
        }
        SharedStore.copyAssets(content.referencedAssets, from: source, to: assetsURL)
        let size = CGSize(width: content.width, height: content.height)
        var box = CanvasItem(
            kind: .container, frame: CGRect(origin: nextPosition(for: size, at: nil), size: size),
            zIndex: document.maxZ + 1, color: content.color, text: content.title
        )
        box.sharedID = sharedID
        box.sharedStamp = stamp
        perform(String(localized: "Insérer un conteneur")) { doc in
            doc.items.append(box)
            doc.applyShared(content, to: box.id)
        }
        focus(box.id)
    }

    /// Ce conteneur ne suit plus les autres canvas (son contenu reste).
    func detachShared(_ id: UUID) {
        perform(String(localized: "Ne plus synchroniser")) { doc in
            guard let i = doc.index(of: id) else { return }
            doc.items[i].sharedID = nil
            doc.items[i].sharedStamp = nil
        }
    }

    func assetURL(_ name: String?) -> URL? { name.map { assetsURL.appending(path: $0) } }

    // MARK: - Enregistrement

    private func documentChanged() {
        contentChanged = true
        hasUnsavedChanges = true
        scheduleSave()
    }

    /// Programme l'enregistrement selon le réglage : en continu (peu après la dernière modification),
    /// toutes les X minutes, ou jamais (⌘S, changement de canvas et fermeture seulement).
    private func scheduleSave() {
        let mode = Prefs.autosave
        if mode == Prefs.autosaveOff {
            saveTask?.cancel()
            saveTask = nil
            return
        }
        if mode == Prefs.autosaveContinuous {
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.saveNow()
            }
            return
        }
        // Intervalle : un seul enregistrement programmé à la fois, à partir de la première modification
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(mode * 60))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Enregistre tout de suite (⌘S, changement de canvas, fermeture).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        pushShared()
        let file = CanvasFile(
            document: document,
            viewport: Viewport(offsetX: offset.x, offsetY: offset.y, zoom: zoom)
        )
        do {
            let data = try JSONEncoder.nuvora.encode(file)
            try data.write(to: fileURL, options: .atomic)
            saveFailed = false
            hasUnsavedChanges = false
            lastSaved = Date()
            if contentChanged {
                contentChanged = false
                onModified?()
            }
        } catch {
            saveFailed = true
            NSLog("Nuvora: canvas non enregistré : \(error)")
        }
    }

    /// L'app passe à l'arrière-plan : on enregistre, sauf si l'enregistrement automatique est désactivé.
    func saveIfAutosaving() {
        guard Prefs.autosave != Prefs.autosaveOff else { return }
        saveNow()
    }

    /// Le canvas va être supprimé : rien à enregistrer.
    func discardPendingSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    /// Fichiers que plus aucun élément n'utilise (après une suppression, au lancement suivant)
    private func pruneOrphanAssets() {
        let used = document.referencedAssets
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: assetsURL.path) else { return }
        for name in files where !used.contains(name) && !name.hasPrefix(".") {
            try? FileManager.default.removeItem(at: assetsURL.appending(path: name))
        }
    }

    // MARK: - Historique

    /// Modifie le contenu et inscrit le changement dans l'historique.
    func perform(_ actionName: String, _ change: (inout CanvasDocument) -> Void) {
        let before = document
        change(&document)
        guard document != before else { return }
        registerUndo(restoring: before, actionName: actionName)
        documentChanged()
    }

    /// Modifie un élément sans passer par l'historique (aperçus, transcriptions, durées…).
    func updateSilently(_ id: UUID, _ change: (inout CanvasItem) -> Void) {
        guard let i = document.index(of: id) else { return }
        change(&document.items[i])
        documentChanged()
    }

    private func registerUndo(restoring old: CanvasDocument, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let current = store.document
                store.endEditing(commit: false)
                store.document = old
                store.registerUndo(restoring: current, actionName: actionName)
                store.cleanSelection()
                store.documentChanged()
            }
        }
        undoManager.setActionName(actionName)
    }

    private func cleanSelection() {
        let ids = Set(document.items.map(\.id))
        selection = selection.intersection(ids)
        if let link = selectedConnection, !document.connections.contains(where: { $0.id == link }) {
            selectedConnection = nil
        }
    }

    // MARK: - Vue

    /// Rectangle visible, en coordonnées du canvas
    var visibleWorldRect: CGRect { transform.toWorld(CGRect(origin: .zero, size: viewSize)) }

    /// Centre de la vue, en coordonnées du canvas
    var viewCenter: CGPoint { transform.toWorld(CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)) }

    func pan(by delta: CGSize) {
        offset.x += delta.width
        offset.y += delta.height
        scheduleSave()
    }

    func setZoom(_ value: CGFloat, around anchor: CGPoint? = nil) {
        let t = transform.zoomed(to: value, around: anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        zoom = t.zoom
        offset = t.offset
        scheduleSave()
    }

    /// Centre la vue sur un point du canvas (clic dans la miniature)
    func center(on point: CGPoint) {
        offset = CGPoint(x: viewSize.width / 2 - point.x * zoom, y: viewSize.height / 2 - point.y * zoom)
        scheduleSave()
    }

    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }
    func zoomToActualSize() { setZoom(1) }

    /// Affiche tout le contenu (ou la sélection)
    func fitAll() {
        guard viewSize.width > 0 else { needsInitialFit = true; return }
        let target = selection.isEmpty ? document.bounds() : document.bounds(of: selection)
        guard let rect = target else {
            zoom = 1
            offset = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
            return
        }
        let t = CanvasTransform.fitting(rect, in: viewSize)
        zoom = t.zoom
        offset = t.offset
        scheduleSave()
    }

    /// Double tape à deux doigts : tout afficher, ou revenir à 100 %
    func smartZoom(at point: CGPoint) {
        if abs(zoom - 1) < 0.01 { fitAll() } else { setZoom(1, around: point) }
    }

    // MARK: - Ce qui est affiché

    var hiddenIDs: Set<UUID> { document.hiddenIDs }

    /// Éléments à dessiner (ceux qui sont dans la vue), conteneurs à part
    func visibleLayers() -> (containers: [CanvasItem], items: [CanvasItem]) {
        let area = visibleWorldRect.insetBy(dx: -200 / zoom, dy: -200 / zoom)
        let order = document.renderOrder(hidden: hiddenIDs)
        return (order.containers.filter { $0.frame.intersects(area) }, order.items.filter { $0.frame.intersects(area) })
    }

    /// Lien à dessiner, avec les cadres de ses extrémités visibles
    struct VisibleConnection: Identifiable {
        var link: Connection
        var from: CGRect
        var to: CGRect
        var id: UUID { link.id }
    }

    /// Liens à dessiner (un élément masqué est remplacé par son conteneur réduit)
    func visibleConnections() -> [VisibleConnection] {
        let hidden = hiddenIDs
        let lookup = document.indexByID
        var seen = Set<String>()
        var result: [VisibleConnection] = []
        for link in document.connections {
            let a = document.visibleEndpoint(for: link.from, hidden: hidden)
            let b = document.visibleEndpoint(for: link.to, hidden: hidden)
            guard a != b, !hidden.contains(a), !hidden.contains(b),
                  let ia = lookup[a], let ib = lookup[b] else { continue }
            // Plusieurs liens repliés sur le même conteneur : un seul trait
            if a != link.from || b != link.to {
                let key = [a.uuidString, b.uuidString].sorted().joined()
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            result.append(VisibleConnection(link: link, from: document.items[ia].frame, to: document.items[ib].frame))
        }
        return result
    }

    /// Élément sous un point de l'écran (le plus haut), hors exclusions
    func hitItem(atScreen point: CGPoint, excluding excluded: Set<UUID> = []) -> UUID? {
        let p = transform.toWorld(point)
        let order = document.renderOrder(hidden: hiddenIDs)
        if let item = order.items.reversed().first(where: { !excluded.contains($0.id) && $0.frame.contains(p) }) {
            return item.id
        }
        return order.containers.reversed().first(where: { !excluded.contains($0.id) && $0.frame.contains(p) })?.id
    }

    // MARK: - Sélection

    func selectAll() {
        let hidden = hiddenIDs
        selection = Set(document.items.filter { !hidden.contains($0.id) }.map(\.id))
        selectedConnection = nil
    }

    func clearSelection() {
        endEditing()
        selection = []
        selectedConnection = nil
    }

    func selectConnection(_ id: UUID) {
        endEditing()
        selection = []
        selectedConnection = id
    }

    /// Échap : fin de la modification, puis désélection
    func escape() {
        if editingID != nil { endEditing() } else { clearSelection() }
    }

    // MARK: - Déplacer

    /// Clic sur un élément (au moment où le bouton s'enfonce)
    func pressItem(_ id: UUID, extend: Bool) {
        if let editingID, editingID != id { endEditing() }
        selectedConnection = nil
        pendingSelectOnly = nil
        if extend {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if !selection.contains(id) {
            selection = [id]
        } else {
            // Déjà sélectionné avec d'autres : on ne garde que lui au relâchement, s'il n'a pas bougé
            pendingSelectOnly = id
        }
    }

    func dragItem(_ id: UUID, translation: CGSize) {
        if interaction == nil {
            guard selection.contains(id) else { return }
            let roots = document.topLevel(of: selection)
            var moving = roots
            for root in roots { moving.formUnion(document.descendants(of: root)) }
            var start: [UUID: CGPoint] = [:]
            for item in document.items where moving.contains(item.id) { start[item.id] = item.frame.origin }
            interaction = .move(start: start, roots: roots, primary: id, snapshot: document)
        }
        guard case let .move(start, roots, primary, _) = interaction, let primaryStart = start[primary] else { return }
        var dx = translation.width / zoom
        var dy = translation.height / zoom
        if Prefs.snapsToGrid {
            dx = (primaryStart.x + dx).snapped(to: Prefs.gridStep) - primaryStart.x
            dy = (primaryStart.y + dy).snapped(to: Prefs.gridStep) - primaryStart.y
        }
        let lookup = document.indexByID
        for (itemID, origin) in start {
            guard let i = lookup[itemID] else { continue }
            document.items[i].frame.origin = CGPoint(x: origin.x + dx, y: origin.y + dy)
        }
        // Conteneur visé : celui sous le centre de l'élément tiré
        if let i = lookup[primary], roots.contains(primary) {
            let f = document.items[i].frame
            dropContainer = document.innermostContainer(
                containing: CGPoint(x: f.midX, y: f.midY), excluding: Set(start.keys), hidden: hiddenIDs
            )
        }
    }

    /// Fin du clic ou du déplacement
    func releaseItem(_ id: UUID, moved: Bool) {
        if case let .move(_, roots, _, snapshot) = interaction, moved {
            document.recomputeParents(for: roots)
            for root in roots { document.growContainers(toFit: root) }
            if document != snapshot {
                registerUndo(restoring: snapshot, actionName: String(localized: "Déplacer"))
                documentChanged()
            }
        } else if !moved, pendingSelectOnly == id {
            selection = [id]
        }
        interaction = nil
        dropContainer = nil
        pendingSelectOnly = nil
    }

    /// Flèches du clavier : décale la sélection d'un point (dix avec Maj)
    func nudge(dx: CGFloat, dy: CGFloat) {
        guard !selection.isEmpty else { return }
        let roots = document.topLevel(of: selection)
        var moving = roots
        for root in roots { moving.formUnion(document.descendants(of: root)) }
        perform(String(localized: "Déplacer")) { doc in
            for i in doc.items.indices where moving.contains(doc.items[i].id) {
                doc.items[i].frame = doc.items[i].frame.offsetBy(dx: dx, dy: dy)
            }
            doc.recomputeParents(for: roots)
            for root in roots { doc.growContainers(toFit: root) }
        }
    }

    // MARK: - Redimensionner

    /// Bord ou coin tiré : -1 (gauche / haut), 0 ou 1 (droite / bas) sur chaque axe
    struct ResizeEdge: Equatable {
        var dx: Int
        var dy: Int
    }

    func resizeItem(_ id: UUID, translation: CGSize, edge: ResizeEdge = ResizeEdge(dx: 1, dy: 1)) {
        if interaction == nil {
            guard let item = document.item(id) else { return }
            interaction = .resize(id: id, start: item.frame, snapshot: document)
        }
        guard case let .resize(itemID, start, snapshot) = interaction, let i = document.index(of: itemID) else { return }
        let item = document.items[i]
        let minimum = item.minimumSize
        var w: CGFloat = start.width
        var h: CGFloat = start.height
        if edge.dx != 0 { w = max(minimum.width, start.width + CGFloat(edge.dx) * translation.width / zoom) }
        if edge.dy != 0 { h = max(minimum.height, start.height + CGFloat(edge.dy) * translation.height / zoom) }
        if Prefs.snapsToGrid {
            if edge.dx > 0 { w = max(minimum.width, (start.minX + w).snapped(to: Prefs.gridStep) - start.minX) }
            if edge.dy > 0 { h = max(minimum.height, (start.minY + h).snapped(to: Prefs.gridStep) - start.minY) }
        }
        if item.keepsAspectRatio, start.width > 0, start.height > 0 {
            let ratio: CGFloat = start.height / start.width
            if edge.dx != 0 { h = max(minimum.height, w * ratio) } else { w = max(minimum.width, h / ratio) }
        }
        if item.isContainer && item.collapsed { h = CanvasItem.containerHeaderHeight }
        // Une note ne devient jamais plus petite que son texte
        if item.kind == .note, let needed = noteHeights[itemID] { h = max(h, needed) }
        let x: CGFloat = edge.dx < 0 ? start.maxX - w : start.minX
        let y: CGFloat = edge.dy < 0 ? start.maxY - h : start.minY
        document.items[i].frame = CGRect(x: x, y: y, width: w, height: h)
        // Les conteneurs qui l'englobent repartent de leur taille de départ, puis s'agrandissent s'il déborde
        for ancestorID in document.ancestors(of: itemID) {
            if let a = document.index(of: ancestorID), let original = snapshot.item(ancestorID) {
                document.items[a].frame = original.frame
            }
        }
        document.growContainers(toFit: itemID)
    }

    /// Hauteur dont chaque note a besoin pour montrer tout son texte (mesurée à l'affichage)
    @ObservationIgnored private var noteHeights: [UUID: CGFloat] = [:]

    /// La hauteur du texte d'une note a changé : la note s'agrandit pour tout montrer.
    func noteContentMeasured(_ id: UUID, height: CGFloat) {
        let needed = min(height.rounded(.up), 1400)
        noteHeights[id] = needed
        guard interaction == nil, let item = document.item(id), item.kind == .note, needed > item.frame.height + 0.5 else { return }
        guard let i = document.index(of: id) else { return }
        document.items[i].frame.size.height = needed
        document.growContainers(toFit: id)
        documentChanged()
    }

    func endResize() {
        if case let .resize(itemID, _, snapshot) = interaction {
            document.refreshMembership(ofContainer: itemID)
            if document != snapshot {
                registerUndo(restoring: snapshot, actionName: String(localized: "Redimensionner"))
                documentChanged()
            }
        }
        interaction = nil
    }

    // MARK: - Relier

    func dragConnection(from id: UUID, to point: CGPoint) {
        endEditing()
        pendingConnection = (id, point)
        var excluded: Set<UUID> = [id]
        excluded.formUnion(document.ancestors(of: id))
        connectionTarget = hitItem(atScreen: point, excluding: excluded)
    }

    func endConnection() {
        if let pending = pendingConnection, let target = connectionTarget {
            connect(pending.from, target)
        }
        pendingConnection = nil
        connectionTarget = nil
    }

    /// Relie les deux éléments sélectionnés
    func connectSelection() {
        guard selection.count == 2 else { return }
        let ids = document.items.filter { selection.contains($0.id) }.sorted { $0.frame.minX < $1.frame.minX }.map(\.id)
        connect(ids[0], ids[1])
    }

    /// Crée un lien avec le sens, le trait et la couleur choisis dans la barre d'outils, et le sélectionne.
    private func connect(_ from: UUID, _ to: UUID) {
        let direction = Prefs.linkDirection, style = Prefs.newLinkStyle, color = Prefs.newLinkColor
        var created: UUID?
        perform(String(localized: "Relier")) { doc in
            guard let link = doc.connect(from, to, direction: direction),
                  let i = doc.connections.firstIndex(where: { $0.id == link.id }) else { return }
            doc.connections[i].style = style
            doc.connections[i].color = color
            created = link.id
        }
        if let created {
            selection = []
            selectedConnection = created
        }
    }

    /// Lien sélectionné
    var selectedLink: Connection? {
        selectedConnection.flatMap { id in document.connections.first { $0.id == id } }
    }

    func updateConnection(_ id: UUID, _ change: @escaping (inout Connection) -> Void) {
        perform(String(localized: "Modifier le lien")) { doc in
            if let i = doc.connections.firstIndex(where: { $0.id == id }) { change(&doc.connections[i]) }
        }
    }

    func reverseConnection(_ id: UUID) {
        updateConnection(id) { link in swap(&link.from, &link.to) }
    }

    func deleteConnection(_ id: UUID) {
        perform(String(localized: "Supprimer le lien")) { $0.connections.removeAll { $0.id == id } }
        if selectedConnection == id { selectedConnection = nil }
    }

    // MARK: - Sélection au rectangle et défilement à la souris

    func backgroundDrag(start: CGPoint, location: CGPoint, translation: CGSize) {
        if isPanning {
            panDrag(translation)
            return
        }
        if marquee == nil {
            endEditing()
            selectedConnection = nil
            marqueeBase = NSEvent.modifierFlags.contains(.shift) ? selection : []
        }
        let rect = CGRect(
            x: min(start.x, location.x), y: min(start.y, location.y),
            width: abs(location.x - start.x), height: abs(location.y - start.y)
        )
        marquee = rect
        let world = transform.toWorld(rect)
        let hidden = hiddenIDs
        let hits = document.items.filter { item in
            guard !hidden.contains(item.id) else { return false }
            // Un conteneur doit être entièrement dans le rectangle, sinon on le prendrait à chaque fois
            return item.isContainer ? world.contains(item.frame) : world.intersects(item.frame)
        }
        selection = marqueeBase.union(hits.map(\.id))
    }

    /// Glisser avec Espace enfoncée : fait défiler le canvas
    func panDrag(_ translation: CGSize) {
        pan(by: CGSize(width: translation.width - lastPanTranslation.width, height: translation.height - lastPanTranslation.height))
        lastPanTranslation = translation
    }

    func endBackgroundDrag() {
        marquee = nil
        lastPanTranslation = .zero
    }

    // MARK: - Modifier le texte

    func beginEditing(_ id: UUID) {
        guard let item = document.item(id), item.kind == .note || item.kind == .container else { return }
        if editingID != nil { endEditing() }
        editSnapshot = document
        selection = [id]
        editingID = id
    }

    // MARK: Éditeur complet

    /// Note ouverte dans l'éditeur complet (fenêtre flottante)
    private(set) var fullEditorID: UUID?
    /// Emplacement de l'éditeur complet sur le canvas (pour que le défilement lui revienne)
    @ObservationIgnored var fullEditorFrame: CGRect = .zero
    @ObservationIgnored private var fullEditorSnapshot: CanvasDocument?
    /// Élément qu'on renomme (conteneur, image, vidéo, document, note vocale, lien)
    var renamingContainer: UUID?

    /// Nom actuel d'un élément, proposé dans la boîte « Renommer »
    func currentName(of id: UUID) -> String {
        guard let item = document.item(id) else { return "" }
        switch item.kind {
        case .container, .link, .note: return item.text
        case .image, .video, .document, .voice: return item.originalName ?? ""
        }
    }

    func openFullEditor(_ id: UUID) {
        guard document.item(id)?.kind == .note else { return }
        endEditing()
        closeFullEditor()
        fullEditorSnapshot = document
        selection = [id]
        selectedConnection = nil
        fullEditorID = id
    }

    /// Nouvelle note, ouverte directement dans l'éditeur complet
    func newNoteInFullEditor() {
        endEditing()
        closeFullEditor()
        let before = document
        let size = CGSize(width: 260, height: 160)
        let item = CanvasItem(kind: .note, frame: snappedFrame(nextPosition(for: size, at: nil), size), zIndex: document.maxZ + 1)
        document.items.append(item)
        document.recomputeParents(for: [item.id])
        selection = [item.id]
        selectedConnection = nil
        fullEditorSnapshot = before
        fullEditorID = item.id
    }

    func closeFullEditor() {
        guard let id = fullEditorID else { return }
        fullEditorID = nil
        guard let snapshot = fullEditorSnapshot else { return }
        fullEditorSnapshot = nil
        commitTextEdit(id, since: snapshot)
    }

    func renameContainer(_ id: UUID, to title: String) {
        perform(String(localized: "Renommer")) { doc in
            guard let i = doc.index(of: id) else { return }
            switch doc.items[i].kind {
            case .container, .link, .note:
                doc.items[i].text = title
            case .image, .video, .document, .voice:
                // Un nom vide rend à l'élément son nom par défaut
                doc.items[i].originalName = title.isEmpty ? nil : title
            }
        }
    }

    /// Fin de la modification d'un texte. Une note neuve laissée vide disparaît.
    func endEditing(commit: Bool = true) {
        guard let id = editingID else { return }
        editingID = nil
        guard let snapshot = editSnapshot else { return }
        editSnapshot = nil
        guard commit else { return }
        commitTextEdit(id, since: snapshot)
    }

    private func commitTextEdit(_ id: UUID, since snapshot: CanvasDocument) {
        if let item = document.item(id), item.kind == .note,
           item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, snapshot.item(id) == nil {
            document.items.removeAll { $0.id == id }
            selection.remove(id)
        }
        if document != snapshot {
            let name = snapshot.item(id) == nil ? String(localized: "Nouvelle note") : String(localized: "Modifier le texte")
            registerUndo(restoring: snapshot, actionName: name)
            documentChanged()
        }
    }

    func textBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.document.item(id)?.text ?? "" },
            set: { [weak self] value in
                guard let self, let i = self.document.index(of: id) else { return }
                self.document.items[i].text = value
                self.scheduleSave()
            }
        )
    }

    /// Coche ou décoche une tâche d'une note
    func toggleTask(_ id: UUID, line: Int) {
        perform(String(localized: "Cocher une tâche")) { doc in
            guard let i = doc.index(of: id) else { return }
            doc.items[i].text = NoteMarkdown.toggleTask(in: doc.items[i].text, line: line)
        }
    }

    /// Sélectionne un élément et centre la vue dessus, sans changer le zoom
    func reveal(_ id: UUID) {
        guard let item = document.item(id) else { return }
        endEditing()
        selection = [id]
        selectedConnection = nil
        center(on: CGPoint(x: item.frame.midX, y: item.frame.midY))
    }

    /// Sélectionne un élément et cadre la vue dessus
    func focus(_ id: UUID) {
        guard document.item(id) != nil else { return }
        endEditing()
        selection = [id]
        selectedConnection = nil
        fitAll()
    }

    /// Double-clic sur un élément
    func activate(_ id: UUID) {
        guard let item = document.item(id) else { return }
        switch item.kind {
        case .note, .container: beginEditing(id)
        case .voice: if let url = assetURL(item.asset) { AudioPlayback.shared.toggle(id, url: url) }
        case .image, .video, .document: quickLookURL = assetURL(item.asset)
        case .link: openLink(id)
        }
    }

    // MARK: - Création

    /// Point où poser un nouvel élément : le centre de la vue, décalé un peu à chaque fois
    private func nextPosition(for size: CGSize, at point: CGPoint?) -> CGPoint {
        if let point { return CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2) }
        cascade = (cascade + 1) % 8
        let c = viewCenter
        let shift = CGFloat(cascade) * 24
        return CGPoint(x: c.x - size.width / 2 + shift, y: c.y - size.height / 2 + shift)
    }

    private func snappedFrame(_ origin: CGPoint, _ size: CGSize) -> CGRect {
        guard Prefs.snapsToGrid else { return CGRect(origin: origin, size: size) }
        return CGRect(
            x: origin.x.snapped(to: Prefs.gridStep), y: origin.y.snapped(to: Prefs.gridStep),
            width: size.width, height: size.height
        )
    }

    /// Ajoute un élément (rangé dans le conteneur où il tombe) et le sélectionne.
    @discardableResult
    private func insert(_ item: CanvasItem, actionName: String) -> UUID {
        var item = item
        item.zIndex = document.maxZ + 1
        perform(actionName) { doc in
            doc.items.append(item)
            doc.recomputeParents(for: [item.id])
            doc.growContainers(toFit: item.id)
        }
        endEditing()
        selection = [item.id]
        selectedConnection = nil
        return item.id
    }

    /// Nouvelle note, prête à écrire. Sans texte, elle disparaît en quittant la modification.
    func addNote(at point: CGPoint? = nil, text: String = "") {
        endEditing()
        let size = CGSize(width: 240, height: 160)
        let before = document
        let item = CanvasItem(kind: .note, frame: snappedFrame(nextPosition(for: size, at: point), size), zIndex: document.maxZ + 1, text: text)
        document.items.append(item)
        document.recomputeParents(for: [item.id])
        selection = [item.id]
        selectedConnection = nil
        if text.isEmpty {
            editSnapshot = before
            editingID = item.id
        } else {
            registerUndo(restoring: before, actionName: String(localized: "Nouvelle note"))
            documentChanged()
        }
    }

    func addContainer(at point: CGPoint? = nil) {
        if selection.count > 0 && point == nil {
            groupSelection()
            return
        }
        let size = CGSize(width: 480, height: 320)
        let item = CanvasItem(kind: .container, frame: snappedFrame(nextPosition(for: size, at: point), size), text: String(localized: "Conteneur"))
        insert(item, actionName: String(localized: "Nouveau conteneur"))
    }

    func groupSelection() {
        guard !selection.isEmpty else { return }
        var newID: UUID?
        let ids = selection
        perform(String(localized: "Grouper")) { newID = $0.group(ids, title: String(localized: "Conteneur")) }
        if let newID { selection = [newID] }
    }

    func ungroup(_ id: UUID) {
        let children = Set(document.children(of: id).map(\.id))
        perform(String(localized: "Dégrouper")) { $0.ungroup(id) }
        selection = children
    }

    func ungroupSelection() {
        for id in selection where document.item(id)?.isContainer == true { ungroup(id) }
    }

    func toggleCollapse(_ id: UUID) {
        endEditing()
        perform(String(localized: "Réduire ou développer")) { $0.toggleCollapse(id) }
    }

    // MARK: - Liens web

    func addLink(_ url: URL, at point: CGPoint? = nil) {
        let fetch = Prefs.fetchesLinkPreviews
        let size = CGSize(width: 300, height: fetch ? 250 : 96)
        let item = CanvasItem(kind: .link, frame: snappedFrame(nextPosition(for: size, at: point), size), url: url.absoluteString)
        let id = insert(item, actionName: String(localized: "Nouveau lien"))
        if fetch { refreshPreview(id) }
    }

    func setAddress(_ id: UUID, _ raw: String) {
        guard let url = WebAddress.parse(raw) else {
            alertMessage = String(localized: "Ce n'est pas une adresse web valide.")
            return
        }
        perform(String(localized: "Modifier l'adresse")) { doc in
            if let i = doc.index(of: id) {
                doc.items[i].url = url.absoluteString
                doc.items[i].preview = nil
            }
        }
        if Prefs.fetchesLinkPreviews { refreshPreview(id) }
    }

    func refreshPreview(_ id: UUID) {
        guard let raw = document.item(id)?.url, let url = URL(string: raw), !fetchingPreviews.contains(id) else { return }
        fetchingPreviews.insert(id)
        Task {
            let result = await LinkPreviewFetcher.fetch(url)
            fetchingPreviews.remove(id)
            guard let current = document.item(id), current.url == raw else { return }
            var preview = LinkPreview(fetchedAt: Date())
            if let result {
                preview.title = result.title
                if let data = result.image { preview.imageAsset = writeAsset(data, ext: "png") }
                if let data = result.icon { preview.iconAsset = writeAsset(data, ext: "png") }
            } else {
                preview.failed = true
            }
            let hasImage = preview.imageAsset != nil
            updateSilently(id) { item in
                item.preview = preview
                // Carte plus basse sans image, tant qu'on ne l'a pas redimensionnée
                if !hasImage && item.frame.height == 250 && item.frame.width == 300 { item.frame.size.height = 96 }
                if hasImage && item.frame.height == 96 && item.frame.width == 300 { item.frame.size.height = 250 }
            }
        }
    }

    func openLink(_ id: UUID) {
        guard let raw = document.item(id)?.url, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Fichiers

    private func writeAsset(_ data: Data, ext: String) -> String? {
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try data.write(to: assetsURL.appending(path: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Importe des fichiers : ils sont copiés dans le canvas, qui reste ainsi complet même si l'original bouge.
    func importFiles(_ urls: [URL], at point: CGPoint? = nil) {
        let files = urls.filter { !$0.hasDirectoryPath }
        guard !files.isEmpty else { return }
        let destination = assetsURL
        Task {
            var placed = 0
            for url in files {
                let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension.lowercased()
                let name = "\(UUID().uuidString).\(ext)"
                let target = destination.appending(path: name)
                let copied: Bool = await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return (try? FileManager.default.copyItem(at: url, to: target)) != nil
                }.value
                guard copied else { continue }
                let spot = point.map { CGPoint(x: $0.x + CGFloat(placed) * 28, y: $0.y + CGFloat(placed) * 28) }
                addFileItem(asset: name, originalName: url.lastPathComponent, at: spot)
                placed += 1
            }
        }
    }

    /// Image collée ou déposée depuis une autre app
    func addImageData(_ data: Data, at point: CGPoint? = nil) {
        guard let normalized = ImageData.normalized(data), let name = writeAsset(normalized.data, ext: normalized.ext) else { return }
        addFileItem(asset: name, originalName: nil, at: point)
    }

    private func addFileItem(asset: String, originalName: String?, at point: CGPoint?) {
        let url = assetsURL.appending(path: asset)
        let kind = FileClassifier.kind(forExtension: url.pathExtension)
        var media = MediaInfo(fileSize: MediaProbe.fileSize(url))
        let size: CGSize
        switch kind {
        case .image:
            let pixels = MediaProbe.imageSize(url)
            media.pixelWidth = pixels.map { Double($0.width) }
            media.pixelHeight = pixels.map { Double($0.height) }
            size = MediaProbe.displaySize(for: pixels)
        case .video: size = CGSize(width: 360, height: 203)
        case .voice: size = CGSize(width: 300, height: 150)
        default:
            media.pageCount = MediaProbe.pdfPageCount(url)
            size = CGSize(width: 220, height: 280)
        }
        let item = CanvasItem(
            kind: kind, frame: snappedFrame(nextPosition(for: size, at: point), size),
            asset: asset, originalName: originalName, media: media
        )
        let actionName: String
        switch kind {
        case .image: actionName = String(localized: "Nouvelle image")
        case .video: actionName = String(localized: "Nouvelle vidéo")
        case .voice: actionName = String(localized: "Nouvelle note vocale")
        default: actionName = String(localized: "Nouveau document")
        }
        let id = insert(item, actionName: actionName)
        enrich(id)
    }

    /// Note vocale tout juste enregistrée (le fichier est déjà dans `assets`)
    func addRecording(asset: String, duration: TimeInterval) {
        let size = CGSize(width: 300, height: 150)
        let item = CanvasItem(
            kind: .voice, frame: snappedFrame(nextPosition(for: size, at: nil), size), asset: asset,
            media: MediaInfo(duration: duration, fileSize: MediaProbe.fileSize(assetsURL.appending(path: asset)))
        )
        let id = insert(item, actionName: String(localized: "Nouvelle note vocale"))
        enrich(id)
    }

    /// Complète un élément importé : durée, taille d'une vidéo, forme d'onde, transcription.
    private func enrich(_ id: UUID) {
        guard let item = document.item(id), let url = assetURL(item.asset) else { return }
        switch item.kind {
        case .video:
            Task {
                let info = await MediaProbe.av(url)
                updateSilently(id) { item in
                    item.media?.duration = info.duration
                    if let size = info.size {
                        item.media?.pixelWidth = Double(size.width)
                        item.media?.pixelHeight = Double(size.height)
                        let display = MediaProbe.displaySize(for: size)
                        item.frame.size.height = (item.frame.width * display.height / display.width).rounded()
                    }
                }
            }
        case .voice:
            Task {
                if item.media?.duration == nil {
                    let info = await MediaProbe.av(url)
                    updateSilently(id) { $0.media?.duration = info.duration }
                }
                let bars = await WaveformReader.bars(for: url)
                updateSilently(id) { $0.waveform = bars }
                if Prefs.autoTranscribes { transcribe(id) }
            }
        default:
            break
        }
    }

    func transcribe(_ id: UUID) {
        guard let url = assetURL(document.item(id)?.asset), !transcribing.contains(id) else { return }
        transcribing.insert(id)
        transcriptionErrors[id] = nil
        Task {
            do {
                let text = try await Transcriber.transcribe(url)
                updateSilently(id) { $0.transcript = text }
            } catch {
                transcriptionErrors[id] = error.localizedDescription
            }
            transcribing.remove(id)
        }
    }

    // MARK: - Coller et déposer

    /// ⌘V sur le canvas : fichiers, image, adresse web ou texte du presse-papiers
    func paste() {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            importFiles(urls)
        } else if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
            addImageData(data)
        } else if let string = board.string(forType: .string) {
            if let url = WebAddress.parse(string) {
                addLink(url)
            } else if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addNote(text: string)
            }
        }
    }

    /// Dépôt depuis le Finder ou une autre app, au point indiqué (écran)
    func drop(_ providers: [NSItemProvider], at screenPoint: CGPoint) -> Bool {
        let point = transform.toWorld(screenPoint)
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in self.importFiles([url], at: point) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.scheme?.hasPrefix("http") == true else { return }
                    Task { @MainActor in self.addLink(url, at: point) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in self.addImageData(data, at: point) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string else { return }
                    Task { @MainActor in
                        if let url = WebAddress.parse(string) { self.addLink(url, at: point) } else { self.addNote(at: point, text: string) }
                    }
                }
            }
        }
        return handled
    }

    // MARK: - Actions sur la sélection

    /// Éléments visés par une action du menu contextuel : la sélection si l'élément en fait partie, sinon lui seul
    func targets(for id: UUID) -> Set<UUID> { selection.contains(id) ? selection : [id] }

    func deleteSelection() {
        if let link = selectedConnection {
            deleteConnection(link)
            return
        }
        delete(selection)
    }

    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        endEditing()
        if let open = fullEditorID, ids.contains(open) {
            fullEditorID = nil
            fullEditorSnapshot = nil
        }
        AudioPlayback.shared.stopIfPlaying(ids)
        perform(String(localized: "Supprimer")) { $0.remove(ids) }
        selection.subtract(ids)
        cleanSelection()
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        var copies: Set<UUID> = []
        let ids = selection
        perform(String(localized: "Dupliquer")) { copies = $0.duplicate(ids) }
        selection = copies
    }

    func setColor(_ color: ItemColor, for ids: Set<UUID>) {
        perform(String(localized: "Couleur")) { doc in
            for i in doc.items.indices where ids.contains(doc.items[i].id) { doc.items[i].color = color }
        }
    }

    func bringToFront(_ ids: Set<UUID>) { perform(String(localized: "Premier plan")) { $0.bringToFront(ids) } }
    func sendToBack(_ ids: Set<UUID>) { perform(String(localized: "Arrière-plan")) { $0.sendToBack(ids) } }

    func revealInFinder(_ id: UUID) {
        guard let url = assetURL(document.item(id)?.asset) else { return }
        FileManagerApp.reveal(url)
    }

    func openFile(_ id: UUID) {
        guard let url = assetURL(document.item(id)?.asset) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Enregistre une copie du fichier d'origine ailleurs
    func exportFile(_ id: UUID) {
        guard let item = document.item(id), let url = assetURL(item.asset) else { return }
        let panel = NSSavePanel()
        // Un élément renommé garde l'extension de son fichier
        var name = item.originalName ?? url.lastPathComponent
        if (name as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty { name += "." + url.pathExtension }
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.copyItem(at: url, to: target) } catch { alertMessage = error.localizedDescription }
    }
}

/// Canvas au premier plan, pour les commandes des menus.
struct CanvasStoreKey: FocusedValueKey {
    typealias Value = CanvasStore
}

extension FocusedValues {
    var canvasStore: CanvasStore? {
        get { self[CanvasStoreKey.self] }
        set { self[CanvasStoreKey.self] = newValue }
    }
}
