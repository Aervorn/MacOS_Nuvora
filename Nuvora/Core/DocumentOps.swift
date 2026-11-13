import CoreGraphics
import Foundation

/// Opérations sur le contenu d'un canvas, sans interface (testées).
extension CanvasDocument {
    // MARK: - Recherche

    func index(of id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    func item(_ id: UUID) -> CanvasItem? { items.first { $0.id == id } }

    /// Dictionnaire id → position dans `items`
    var indexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
    }

    /// Enfants directs d'un conteneur
    func children(of id: UUID) -> [CanvasItem] { items.filter { $0.parentID == id } }

    /// Tous les éléments contenus, à toutes les profondeurs
    func descendants(of id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = [id]
        let byParent = Dictionary(grouping: items.filter { $0.parentID != nil }, by: { $0.parentID! })
        while let current = queue.popLast() {
            for child in byParent[current] ?? [] where !result.contains(child.id) && child.id != id {
                result.insert(child.id)
                queue.append(child.id)
            }
        }
        return result
    }

    /// Conteneurs qui englobent l'élément, du plus proche au plus lointain
    func ancestors(of id: UUID) -> [UUID] {
        let lookup = indexByID
        var result: [UUID] = []
        var current = lookup[id].flatMap { items[$0].parentID }
        while let parent = current, !result.contains(parent), parent != id {
            result.append(parent)
            current = lookup[parent].flatMap { items[$0].parentID }
        }
        return result
    }

    func depth(of id: UUID) -> Int { ancestors(of: id).count }

    /// Éléments masqués parce qu'un de leurs conteneurs est réduit
    var hiddenIDs: Set<UUID> {
        var hidden = Set<UUID>()
        for item in items where item.isContainer && item.collapsed {
            hidden.formUnion(descendants(of: item.id))
        }
        return hidden
    }

    /// Élément affiché à la place d'un élément masqué : son conteneur réduit le plus extérieur.
    func visibleEndpoint(for id: UUID, hidden: Set<UUID>) -> UUID {
        guard hidden.contains(id) else { return id }
        return ancestors(of: id).last { !hidden.contains($0) } ?? id
    }

    /// Ordre d'affichage : les conteneurs d'abord (du plus extérieur au plus intérieur), puis les autres éléments.
    func renderOrder(hidden: Set<UUID>) -> (containers: [CanvasItem], items: [CanvasItem]) {
        let visible = items.filter { !hidden.contains($0.id) }
        let ranked: [(item: CanvasItem, depth: Int)] = visible.filter(\.isContainer).map { container in
            (item: container, depth: depth(of: container.id))
        }
        let sorted = ranked.sorted { (a, b) -> Bool in
            if a.depth != b.depth { return a.depth < b.depth }
            return a.item.zIndex < b.item.zIndex
        }
        let containers: [CanvasItem] = sorted.map { $0.item }
        let others = visible.filter { !$0.isContainer }.sorted { $0.zIndex < $1.zIndex }
        return (containers, others)
    }

    var maxZ: Double { items.map(\.zIndex).max() ?? 0 }
    var minZ: Double { items.map(\.zIndex).min() ?? 0 }

    /// Rectangle qui englobe les éléments donnés (tous les éléments visibles si `nil`)
    func bounds(of ids: Set<UUID>? = nil) -> CGRect? {
        let hidden = hiddenIDs
        let frames = items.filter { ids?.contains($0.id) ?? !hidden.contains($0.id) }.map(\.frame)
        guard var rect = frames.first else { return nil }
        for f in frames.dropFirst() { rect = rect.union(f) }
        return rect
    }

    // MARK: - Conteneurs

    /// Conteneur le plus intérieur (développé, visible) qui contient le point, hors exclusions.
    func innermostContainer(containing point: CGPoint, excluding excluded: Set<UUID>, hidden: Set<UUID>) -> UUID? {
        items
            .filter { $0.isContainer && !$0.collapsed && !excluded.contains($0.id) && !hidden.contains($0.id) }
            .filter { $0.frame.contains(point) }
            .max { (a: CanvasItem, b: CanvasItem) -> Bool in
                let da: Int = depth(of: a.id)
                let db: Int = depth(of: b.id)
                if da != db { return da < db }
                // À profondeur égale : le plus petit l'emporte
                let areaA: CGFloat = a.frame.width * a.frame.height
                let areaB: CGFloat = b.frame.width * b.frame.height
                return areaA > areaB
            }?.id
    }

    /// Range chaque élément donné dans le conteneur où se trouve son centre (ou le sort de tout conteneur).
    mutating func recomputeParents(for ids: Set<UUID>) {
        let hidden = hiddenIDs
        for id in ids {
            guard let i = index(of: id), !hidden.contains(id) else { continue }
            var excluded = descendants(of: id)
            excluded.insert(id)
            let center = CGPoint(x: items[i].frame.midX, y: items[i].frame.midY)
            items[i].parentID = innermostContainer(containing: center, excluding: excluded, hidden: hidden)
        }
    }

    /// Après le redimensionnement d'un conteneur : il accueille les éléments voisins qui sont maintenant
    /// dedans, et laisse sortir ceux qui n'y sont plus.
    mutating func refreshMembership(ofContainer id: UUID) {
        guard let container = item(id), container.isContainer, !container.collapsed else { return }
        let hidden = hiddenIDs
        var excluded = descendants(of: id)
        excluded.insert(id)
        excluded.formUnion(ancestors(of: id))
        let neighbours = items.filter {
            !excluded.contains($0.id) && !hidden.contains($0.id) && $0.parentID == container.parentID
                && container.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        let leaving = children(of: id).filter {
            !container.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        recomputeParents(for: Set(neighbours.map(\.id) + leaving.map(\.id)))
    }

    /// Agrandit les conteneurs qui englobent l'élément pour qu'il n'en déborde pas,
    /// en remontant jusqu'au conteneur le plus extérieur.
    mutating func growContainers(toFit id: UUID, padding: CGFloat = 16) {
        var current = id
        for ancestorID in ancestors(of: id) {
            guard let ci = index(of: ancestorID), let child = item(current), !items[ci].collapsed else { break }
            let container = items[ci].frame
            let minX: CGFloat = min(container.minX, child.frame.minX - padding)
            let minY: CGFloat = min(container.minY, child.frame.minY - padding - CanvasItem.containerHeaderHeight)
            let maxX: CGFloat = max(container.maxX, child.frame.maxX + padding)
            let maxY: CGFloat = max(container.maxY, child.frame.maxY + padding)
            let grown = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            if grown == container { break }
            items[ci].frame = grown
            current = ancestorID
        }
    }

    /// Nombre de conteneurs et de cartes (tous les autres éléments)
    var containerCount: Int { items.filter(\.isContainer).count }
    var cardCount: Int { items.count - containerCount }

    /// Tout le texte du canvas, pour la recherche : notes, titres, transcriptions, noms de fichiers,
    /// adresses et titres des liens web, libellés des liens.
    var searchText: String {
        var parts: [String] = []
        for item in items {
            parts.append(item.text)
            if let value = item.transcript { parts.append(value) }
            if let value = item.originalName { parts.append(value) }
            if let value = item.url { parts.append(value) }
            if let value = item.preview?.title { parts.append(value) }
        }
        for link in connections where !link.label.isEmpty { parts.append(link.label) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Réduit ou développe un conteneur. La position du contenu ne change pas.
    mutating func toggleCollapse(_ id: UUID) {
        guard let i = index(of: id), items[i].isContainer else { return }
        if items[i].collapsed {
            items[i].frame.size.height = max(items[i].expandedHeight ?? 240, CanvasItem.containerHeaderHeight)
            items[i].collapsed = false
        } else {
            items[i].expandedHeight = items[i].frame.height
            items[i].frame.size.height = CanvasItem.containerHeaderHeight
            items[i].collapsed = true
        }
    }

    /// Crée un conteneur autour des éléments donnés. Renvoie son identifiant.
    @discardableResult
    mutating func group(_ ids: Set<UUID>, title: String, padding: CGFloat = 24) -> UUID? {
        let roots = topLevel(of: ids)
        guard let bounds = bounds(of: roots) else { return nil }
        let parents = Set(roots.compactMap { item($0)?.parentID })
        let commonParent = parents.count == 1 && roots.allSatisfy({ item($0)?.parentID != nil }) ? parents.first : nil
        let frame = CGRect(
            x: bounds.minX - padding,
            y: bounds.minY - padding - CanvasItem.containerHeaderHeight,
            width: bounds.width + padding * 2,
            height: bounds.height + padding * 2 + CanvasItem.containerHeaderHeight
        )
        let container = CanvasItem(kind: .container, frame: frame, parentID: commonParent, zIndex: maxZ + 1, text: title)
        items.append(container)
        for id in roots { if let i = index(of: id) { items[i].parentID = container.id } }
        return container.id
    }

    /// Supprime un conteneur en gardant son contenu.
    mutating func ungroup(_ id: UUID) {
        guard let container = item(id), container.isContainer else { return }
        if container.collapsed { toggleCollapse(id) }
        for i in items.indices where items[i].parentID == id { items[i].parentID = container.parentID }
        items.removeAll { $0.id == id }
        connections.removeAll { $0.from == id || $0.to == id }
    }

    /// Éléments de la liste qui ne sont pas déjà contenus dans un autre élément de la liste.
    func topLevel(of ids: Set<UUID>) -> Set<UUID> {
        ids.filter { id in !ancestors(of: id).contains(where: ids.contains) }
    }

    // MARK: - Modifications

    /// Supprime des éléments, leur contenu et leurs liens.
    mutating func remove(_ ids: Set<UUID>) {
        var all = ids
        for id in ids { all.formUnion(descendants(of: id)) }
        items.removeAll { all.contains($0.id) }
        connections.removeAll { all.contains($0.from) || all.contains($0.to) }
    }

    /// Duplique des éléments (avec leur contenu et les liens entre eux), décalés. Renvoie les nouveaux identifiants
    /// des éléments de premier niveau.
    mutating func duplicate(_ ids: Set<UUID>, offset: CGSize = CGSize(width: 24, height: 24)) -> Set<UUID> {
        let roots = topLevel(of: ids)
        var all = roots
        for id in roots { all.formUnion(descendants(of: id)) }
        var mapping: [UUID: UUID] = [:]
        for id in all { mapping[id] = UUID() }
        let top = maxZ
        var copies: [CanvasItem] = []
        for original in items where all.contains(original.id) {
            var copy = original
            copy.id = mapping[original.id]!
            copy.frame = original.frame.offsetBy(dx: offset.width, dy: offset.height)
            copy.parentID = original.parentID.flatMap { mapping[$0] } ?? original.parentID
            copy.zIndex = top + 1 + original.zIndex - minZ
            copy.createdAt = Date()
            copies.append(copy)
        }
        items.append(contentsOf: copies)
        for link in connections where all.contains(link.from) && all.contains(link.to) {
            var copy = link
            copy.id = UUID()
            copy.from = mapping[link.from]!
            copy.to = mapping[link.to]!
            connections.append(copy)
        }
        return Set(roots.compactMap { mapping[$0] })
    }

    mutating func bringToFront(_ ids: Set<UUID>) {
        var z = maxZ
        for i in items.indices where ids.contains(items[i].id) {
            z += 1
            items[i].zIndex = z
        }
    }

    mutating func sendToBack(_ ids: Set<UUID>) {
        var z = minZ
        for i in items.indices.reversed() where ids.contains(items[i].id) {
            z -= 1
            items[i].zIndex = z
        }
    }

    /// Relie deux éléments. Pas de doublon ni de lien d'un élément vers lui-même. Renvoie le lien créé.
    @discardableResult
    mutating func connect(_ from: UUID, _ to: UUID, direction: LinkDirection) -> Connection? {
        guard from != to, item(from) != nil, item(to) != nil else { return nil }
        if connections.contains(where: { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) }) {
            return nil
        }
        let link = Connection(from: from, to: to, direction: direction)
        connections.append(link)
        return link
    }

    /// Fichiers référencés par au moins un élément
    var referencedAssets: Set<String> { Set(items.flatMap(\.referencedAssets)) }
}
