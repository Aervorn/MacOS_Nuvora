import Foundation

/// Un dossier de la bibliothèque. Les dossiers peuvent s'imbriquer.
struct LibraryFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID?
    var isExpanded: Bool = true
}

/// Un canvas de la bibliothèque (son contenu est dans son propre dossier sur le disque).
struct CanvasEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var folderID: UUID?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Nombre de cartes, affiché dans la barre latérale (`nil` : pas encore compté)
    var cardCount: Int?
    /// Icône (symbole SF) et couleur choisies pour la barre latérale
    var icon: String?
    var color: ItemColor?
}

/// Fichier `library.json` : l'arborescence des dossiers et la liste des canvas.
struct LibraryIndex: Codable, Equatable, Sendable {
    var version = 1
    var folders: [LibraryFolder] = []
    var canvases: [CanvasEntry] = []

    func folder(_ id: UUID) -> LibraryFolder? { folders.first { $0.id == id } }
    func canvas(_ id: UUID) -> CanvasEntry? { canvases.first { $0.id == id } }

    /// Sous-dossiers directs, triés par nom (`nil` : la racine)
    func subfolders(of parent: UUID?) -> [LibraryFolder] {
        folders.filter { $0.parentID == parent }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Canvas d'un dossier, triés par nom (`nil` : la racine)
    func canvases(in folder: UUID?) -> [CanvasEntry] {
        canvases.filter { $0.folderID == folder }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Le dossier et tous ses sous-dossiers
    func folderTree(_ id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var queue = [id]
        while let current = queue.popLast() {
            for sub in folders where sub.parentID == current && !result.contains(sub.id) {
                result.insert(sub.id)
                queue.append(sub.id)
            }
        }
        return result
    }

    /// Un dossier peut aller dans `parent` s'il n'en est pas un ancêtre (pas de boucle).
    func canMove(folder id: UUID, to parent: UUID?) -> Bool {
        guard let parent else { return true }
        return !folderTree(id).contains(parent)
    }

    /// Chemin d'un dossier, de la racine jusqu'à lui (« Projets › Maison »)
    func path(of folderID: UUID?) -> [LibraryFolder] {
        var result: [LibraryFolder] = []
        var current = folderID
        var seen = Set<UUID>()
        while let id = current, let folder = folder(id), !seen.contains(id) {
            seen.insert(id)
            result.insert(folder, at: 0)
            current = folder.parentID
        }
        return result
    }

    /// Nom libre de la forme « Base », « Base 2 », « Base 3 »… parmi des noms existants
    static func uniqueName(_ base: String, among names: [String]) -> String {
        let taken = Set(names.map { $0.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
