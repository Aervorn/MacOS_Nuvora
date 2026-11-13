import CoreGraphics
import Foundation

/// Contenu d'un conteneur partagé entre plusieurs canvas, indépendant de sa position :
/// les éléments sont placés par rapport au coin du conteneur.
struct SharedContent: Codable, Equatable, Sendable {
    var title: String
    var color: ItemColor
    var width: Double
    /// Hauteur du conteneur développé
    var height: Double
    /// Éléments contenus ; `parentID` vaut `nil` pour ceux posés directement dans le conteneur
    var items: [CanvasItem]
    /// Liens entre les éléments contenus
    var connections: [Connection]

    var referencedAssets: Set<String> { Set(items.flatMap(\.referencedAssets)) }
}

/// Fichier `Shared/<identifiant>.json` : la dernière version du contenu d'un conteneur partagé.
/// Chaque canvas l'écrit quand il est enregistré et le relit quand il est ouvert.
struct SharedFile: Codable, Sendable {
    var stamp: String
    var content: SharedContent
}

extension CanvasDocument {
    /// Contenu d'un conteneur, prêt à être partagé ou copié.
    func sharedContent(of id: UUID) -> SharedContent? {
        guard let container = item(id), container.isContainer else { return nil }
        let inside = descendants(of: id)
        let origin = container.frame.origin
        func rounded(_ value: CGFloat) -> CGFloat { (value * 100).rounded() / 100 }

        var contents = items.filter { inside.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
        for i in contents.indices {
            let frame = contents[i].frame
            contents[i].frame = CGRect(
                x: rounded(frame.minX - origin.x), y: rounded(frame.minY - origin.y),
                width: rounded(frame.width), height: rounded(frame.height)
            )
            if contents[i].parentID == id { contents[i].parentID = nil }
        }
        let links = connections
            .filter { inside.contains($0.from) && inside.contains($0.to) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let height = container.collapsed ? (container.expandedHeight ?? Double(container.frame.height)) : Double(container.frame.height)
        return SharedContent(
            title: container.text, color: container.color,
            width: Double(rounded(container.frame.width)), height: Double(rounded(CGFloat(height))),
            items: contents, connections: links
        )
    }

    /// Remplace le contenu d'un conteneur par un contenu partagé (la position du conteneur ne change pas).
    /// Les liens venus de l'extérieur vers des éléments qui existent toujours sont gardés.
    mutating func applyShared(_ content: SharedContent, to id: UUID) {
        guard index(of: id) != nil else { return }
        let old = descendants(of: id)
        let kept = Set(content.items.map(\.id))
        items.removeAll { old.contains($0.id) || (kept.contains($0.id) && $0.id != id) }
        connections.removeAll { link in
            let fromOld = old.contains(link.from), toOld = old.contains(link.to)
            if fromOld && toOld { return true }
            if fromOld && !kept.contains(link.from) { return true }
            if toOld && !kept.contains(link.to) { return true }
            return false
        }
        guard let ci = index(of: id) else { return }
        items[ci].text = content.title
        items[ci].color = content.color
        items[ci].frame.size.width = content.width
        if items[ci].collapsed {
            items[ci].expandedHeight = content.height
        } else {
            items[ci].frame.size.height = content.height
        }
        let origin = items[ci].frame.origin
        for var item in content.items {
            item.frame = item.frame.offsetBy(dx: origin.x, dy: origin.y)
            if item.parentID == nil { item.parentID = id }
            items.append(item)
        }
        connections.append(contentsOf: content.connections)
    }
}

extension SharedContent {
    /// Copie indépendante : mêmes éléments, nouveaux identifiants, plus aucun partage.
    func detachedCopy() -> SharedContent {
        var mapping: [UUID: UUID] = [:]
        for item in items { mapping[item.id] = UUID() }
        var copy = self
        for i in copy.items.indices {
            copy.items[i].id = mapping[items[i].id] ?? UUID()
            copy.items[i].parentID = items[i].parentID.flatMap { mapping[$0] }
            copy.items[i].sharedID = nil
            copy.items[i].sharedStamp = nil
            copy.items[i].createdAt = Date()
        }
        copy.connections = connections.compactMap { link in
            guard let from = mapping[link.from], let to = mapping[link.to] else { return nil }
            var result = link
            result.id = UUID()
            result.from = from
            result.to = to
            return result
        }
        return copy
    }
}
