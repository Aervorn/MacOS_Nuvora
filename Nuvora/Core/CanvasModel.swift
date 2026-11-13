import CoreGraphics
import Foundation

/// Nature d'un élément posé sur un canvas.
enum ItemKind: String, Codable, CaseIterable, Sendable {
    case note, voice, image, video, document, link, container
}

/// Teinte d'un élément ou d'un lien (traduite en couleur par l'interface).
enum ItemColor: String, Codable, CaseIterable, Sendable {
    case plain, yellow, orange, red, pink, purple, blue, teal, green, gray
}

/// Sens d'un lien entre deux éléments.
enum LinkDirection: String, Codable, CaseIterable, Sendable {
    /// Sans flèche
    case none
    /// De la source vers la cible
    case forward
    /// De la cible vers la source
    case backward
    /// Dans les deux sens
    case both

    var arrowAtEnd: Bool { self == .forward || self == .both }
    var arrowAtStart: Bool { self == .backward || self == .both }
}

enum LinkStyle: String, Codable, CaseIterable, Sendable {
    /// Trait plein, tirets, pointillés
    case solid, dashed, dotted
}

/// Informations sur un fichier importé (image, vidéo, audio, document).
struct MediaInfo: Codable, Equatable, Sendable {
    var pixelWidth: Double?
    var pixelHeight: Double?
    /// Durée en secondes (audio, vidéo)
    var duration: Double?
    /// Taille du fichier en octets
    var fileSize: Int64?
    /// Nombre de pages (PDF)
    var pageCount: Int?
}

/// Aperçu d'une page web, récupéré une fois puis gardé avec le canvas.
struct LinkPreview: Codable, Equatable, Sendable {
    var title: String?
    /// Image de la page, enregistrée dans les fichiers du canvas
    var imageAsset: String?
    /// Icône du site, enregistrée dans les fichiers du canvas
    var iconAsset: String?
    var fetchedAt: Date?
    /// La dernière récupération a échoué
    var failed: Bool = false
}

/// Un élément du canvas. Une seule structure pour tous les types : chaque type n'utilise
/// que les champs qui le concernent (plus simple à modifier et à enregistrer qu'une énumération).
struct CanvasItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: ItemKind
    /// Position et taille, en coordonnées du canvas (indépendantes du zoom)
    var frame: CGRect
    /// Conteneur qui contient l'élément
    var parentID: UUID?
    var zIndex: Double
    var color: ItemColor
    /// Texte d'une note, titre d'un conteneur, titre personnalisé d'un lien
    var text: String
    /// Fichier dans le dossier `assets` du canvas
    var asset: String?
    /// Nom d'origine d'un fichier importé
    var originalName: String?
    /// Adresse d'un lien web
    var url: String?
    var preview: LinkPreview?
    var media: MediaInfo?
    /// Transcription d'une note vocale
    var transcript: String?
    /// Forme d'onde d'une note vocale (valeurs entre 0 et 1)
    var waveform: [Float]?
    /// Conteneur réduit : son contenu est masqué
    var collapsed: Bool
    /// Hauteur du conteneur développé, gardée pendant qu'il est réduit
    var expandedHeight: Double?
    /// Conteneur partagé entre plusieurs canvas : identifiant commun à toutes ses occurrences
    var sharedID: UUID?
    /// Version du contenu partagé que cette occurrence a reçue ou envoyée
    var sharedStamp: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: ItemKind,
        frame: CGRect,
        parentID: UUID? = nil,
        zIndex: Double = 0,
        color: ItemColor = .plain,
        text: String = "",
        asset: String? = nil,
        originalName: String? = nil,
        url: String? = nil,
        preview: LinkPreview? = nil,
        media: MediaInfo? = nil,
        transcript: String? = nil,
        waveform: [Float]? = nil,
        collapsed: Bool = false,
        expandedHeight: Double? = nil,
        sharedID: UUID? = nil,
        sharedStamp: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.parentID = parentID
        self.zIndex = zIndex
        self.color = color
        self.text = text
        self.asset = asset
        self.originalName = originalName
        self.url = url
        self.preview = preview
        self.media = media
        self.transcript = transcript
        self.waveform = waveform
        self.collapsed = collapsed
        self.expandedHeight = expandedHeight
        self.sharedID = sharedID
        self.sharedStamp = sharedStamp
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, frame, parentID, zIndex, color, text, asset, originalName, url
        case preview, media, transcript, waveform, collapsed, expandedHeight, createdAt, sharedID, sharedStamp
    }

    /// Lecture tolérante : un champ absent (fichier d'une version plus ancienne) prend sa valeur par défaut.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decode(ItemKind.self, forKey: .kind)) ?? .note
        frame = try c.decode(CGRect.self, forKey: .frame)
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        zIndex = try c.decodeIfPresent(Double.self, forKey: .zIndex) ?? 0
        color = (try? c.decode(ItemColor.self, forKey: .color)) ?? .plain
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        asset = try c.decodeIfPresent(String.self, forKey: .asset)
        originalName = try c.decodeIfPresent(String.self, forKey: .originalName)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        preview = try c.decodeIfPresent(LinkPreview.self, forKey: .preview)
        media = try c.decodeIfPresent(MediaInfo.self, forKey: .media)
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript)
        waveform = try c.decodeIfPresent([Float].self, forKey: .waveform)
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        expandedHeight = try c.decodeIfPresent(Double.self, forKey: .expandedHeight)
        sharedID = try c.decodeIfPresent(UUID.self, forKey: .sharedID)
        sharedStamp = try c.decodeIfPresent(String.self, forKey: .sharedStamp)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var isContainer: Bool { kind == .container }

    /// Fichiers du canvas utilisés par l'élément
    var referencedAssets: [String] {
        [asset, preview?.imageAsset, preview?.iconAsset].compactMap { $0 }
    }

    /// Taille minimale quand on redimensionne
    var minimumSize: CGSize {
        switch kind {
        case .note: CGSize(width: 120, height: 60)
        case .voice: CGSize(width: 220, height: 110)
        case .image, .video: CGSize(width: 80, height: 60)
        case .document: CGSize(width: 160, height: 120)
        case .link: CGSize(width: 200, height: 90)
        case .container: CGSize(width: 200, height: Self.containerHeaderHeight)
        }
    }

    /// Les images et les vidéos gardent leurs proportions quand on les redimensionne
    var keepsAspectRatio: Bool { kind == .image || kind == .video }

    static let containerHeaderHeight: CGFloat = 44
}

/// Lien entre deux éléments.
struct Connection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var from: UUID
    var to: UUID
    var direction: LinkDirection
    var style: LinkStyle
    var color: ItemColor
    var label: String

    init(
        id: UUID = UUID(),
        from: UUID,
        to: UUID,
        direction: LinkDirection = .forward,
        style: LinkStyle = .solid,
        color: ItemColor = .plain,
        label: String = ""
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.direction = direction
        self.style = style
        self.color = color
        self.label = label
    }

    private enum CodingKeys: String, CodingKey { case id, from, to, direction, style, color, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        from = try c.decode(UUID.self, forKey: .from)
        to = try c.decode(UUID.self, forKey: .to)
        direction = (try? c.decode(LinkDirection.self, forKey: .direction)) ?? .forward
        style = (try? c.decode(LinkStyle.self, forKey: .style)) ?? .solid
        color = (try? c.decode(ItemColor.self, forKey: .color)) ?? .plain
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

/// Position de la vue sur le canvas : point écran = point canvas × zoom + offset.
struct Viewport: Codable, Equatable, Sendable {
    var offsetX: Double
    var offsetY: Double
    var zoom: Double

    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 4
}

/// Contenu d'un canvas : ses éléments et leurs liens.
struct CanvasDocument: Codable, Equatable, Sendable {
    var items: [CanvasItem] = []
    var connections: [Connection] = []
}

/// Fichier `canvas.json` d'un canvas.
struct CanvasFile: Codable, Sendable {
    static let currentVersion = 1

    var version: Int = CanvasFile.currentVersion
    var document: CanvasDocument
    /// `nil` : jamais ouvert, la vue s'ajustera au contenu
    var viewport: Viewport?
}
