import AppKit
import SwiftUI

/// Un élément du canvas : son contenu, le cadre de sélection, les poignées (taille et lien)
/// et les gestes (déplacer, double-clic, menu contextuel).
///
/// La vue est dessinée à sa taille sur le canvas puis agrandie ou réduite avec le zoom ;
/// les poignées gardent la même taille à l'écran.
struct ItemView: View {
    let store: CanvasStore
    let item: CanvasItem

    @State private var hovering = false
    @State private var handleHovering = false
    @State private var pressed = false
    @State private var moved = false

    private var zoom: CGFloat { store.zoom }
    private var isSelected: Bool { store.selection.contains(item.id) }
    private var isEditing: Bool { store.editingID == item.id }
    private var isHighlighted: Bool { store.connectionTarget == item.id || store.dropContainer == item.id }
    private var radius: CGFloat { item.isContainer ? 14 : 10 }

    var body: some View {
        content
            .frame(width: item.frame.width, height: item.frame.height)
            .overlay {
                if isSelected || isHighlighted {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Color.theme.opacity(isHighlighted && !isSelected ? 0.7 : 1), lineWidth: 1.5 / zoom)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isSelected && !isEditing && store.selection.count == 1 {
                    ResizeHandles(store: store, id: item.id, zoom: zoom)
                }
            }
            // Un « + » au milieu de chaque côté pour tirer un lien
            .overlay(alignment: .trailing) { connectHandle(x: 11, y: 0) }
            .overlay(alignment: .leading) { connectHandle(x: -11, y: 0) }
            .overlay(alignment: .top) { connectHandle(x: 0, y: -11) }
            .overlay(alignment: .bottom) { connectHandle(x: 0, y: 11) }
            .onHover { hovering = $0 }
            .gesture(moveGesture, including: isEditing ? .subviews : .all)
            .simultaneousGesture(doubleClick, including: isEditing ? .subviews : .all)
            .contextMenu { ItemMenu(store: store, item: item) }
    }

    @ViewBuilder
    private func connectHandle(x: CGFloat, y: CGFloat) -> some View {
        if showsConnectHandle {
            ConnectHandle(store: store, id: item.id, zoom: zoom, hovering: $handleHovering)
                .offset(x: x / zoom, y: y / zoom)
        }
    }

    private var showsConnectHandle: Bool {
        if isEditing { return false }
        // Pendant qu'on tire un lien, seule la poignée de départ reste (sinon le geste s'interromprait)
        if let pending = store.pendingConnection { return pending.from == item.id }
        return hovering || handleHovering
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .note: NoteContent(store: store, item: item)
        case .container: ContainerContent(store: store, item: item)
        case .voice: VoiceContent(store: store, item: item)
        case .image: ImageContent(store: store, item: item)
        case .video: VideoContent(store: store, item: item)
        case .document: DocumentContent(store: store, item: item)
        case .link: LinkContent(store: store, item: item)
        }
    }

    /// Double-clic : ouvre l'élément. Dans le corps d'un conteneur, crée une note à cet endroit.
    private var doubleClick: some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .named(CanvasView.space)).onEnded { value in
            let point = store.transform.toWorld(value.location)
            if item.isContainer && !item.collapsed && point.y - item.frame.minY > CanvasItem.containerHeaderHeight {
                store.addNote(at: point)
            } else {
                store.activate(item.id)
            }
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(CanvasView.space))
            .onChanged { value in
                if store.isPanning {
                    store.panDrag(value.translation)
                    return
                }
                if !pressed {
                    pressed = true
                    moved = false
                    let flags = NSEvent.modifierFlags
                    store.pressItem(item.id, extend: flags.contains(.shift) || flags.contains(.command))
                }
                if !moved && hypot(value.translation.width, value.translation.height) > 3 { moved = true }
                if moved { store.dragItem(item.id, translation: value.translation) }
            }
            .onEnded { _ in
                if store.isPanning || !pressed {
                    store.endBackgroundDrag()
                } else {
                    store.releaseItem(item.id, moved: moved)
                }
                pressed = false
                moved = false
            }
    }
}

/// Poignées de redimensionnement : les quatre coins (visibles) et les quatre côtés (invisibles, le long du bord)
private struct ResizeHandles: View {
    let store: CanvasStore
    let id: UUID
    let zoom: CGFloat

    var body: some View {
        ZStack {
            side(dx: 0, dy: -1, alignment: .top, position: .top)
            side(dx: 0, dy: 1, alignment: .bottom, position: .bottom)
            side(dx: -1, dy: 0, alignment: .leading, position: .left)
            side(dx: 1, dy: 0, alignment: .trailing, position: .right)
            corner(dx: -1, dy: -1, alignment: .topLeading, position: .topLeft)
            corner(dx: 1, dy: -1, alignment: .topTrailing, position: .topRight)
            corner(dx: -1, dy: 1, alignment: .bottomLeading, position: .bottomLeft)
            corner(dx: 1, dy: 1, alignment: .bottomTrailing, position: .bottomRight)
        }
    }

    private func drag(dx: Int, dy: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(CanvasView.space))
            .onChanged { store.resizeItem(id, translation: $0.translation, edge: CanvasStore.ResizeEdge(dx: dx, dy: dy)) }
            .onEnded { _ in store.endResize() }
    }

    private func cursor(_ position: NSCursor.FrameResizePosition, inside: Bool) {
        if inside {
            NSCursor.frameResize(position: position, directions: .all).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// Bande le long d'un côté, à cheval sur le bord, marquée d'un petit trait en son milieu
    private func side(dx: Int, dy: Int, alignment: Alignment, position: NSCursor.FrameResizePosition) -> some View {
        let thickness: CGFloat = 10 / zoom
        let mark = Capsule()
            .fill(Color.theme)
            .frame(width: (dx == 0 ? 24 : 3) / zoom, height: (dy == 0 ? 24 : 3) / zoom)
        return Color.clear
            .frame(width: dx == 0 ? nil : thickness, height: dy == 0 ? nil : thickness)
            .overlay(mark)
            .contentShape(Rectangle())
            .onHover { cursor(position, inside: $0) }
            .gesture(drag(dx: dx, dy: dy))
            .padding(dx == 0 ? .horizontal : .vertical, 14 / zoom)
            .offset(x: CGFloat(dx) * thickness / 2, y: CGFloat(dy) * thickness / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// Petit rond posé sur un coin
    private func corner(dx: Int, dy: Int, alignment: Alignment, position: NSCursor.FrameResizePosition) -> some View {
        let size: CGFloat = 8 / zoom
        let inset: CGFloat = 6 / zoom
        return Circle()
            .fill(Color.theme)
            .frame(width: size, height: size)
            .padding(inset)
            .contentShape(Rectangle())
            .onHover { cursor(position, inside: $0) }
            .gesture(drag(dx: dx, dy: dy))
            .offset(x: CGFloat(dx) * (inset + size / 2), y: CGFloat(dy) * (inset + size / 2))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// Point d'accroche au milieu d'un côté : le tirer vers un autre élément crée un lien
private struct ConnectHandle: View {
    let store: CanvasStore
    let id: UUID
    let zoom: CGFloat
    @Binding var hovering: Bool
    @State private var over = false

    var body: some View {
        let size = (over ? 12 : 8) / zoom
        Circle()
            .fill(over ? Color.theme : Surface.card)
            .overlay(Circle().strokeBorder(Color.theme, lineWidth: 1.5 / zoom))
            .frame(width: size, height: size)
            .frame(width: 22 / zoom, height: 22 / zoom)
            .contentShape(Circle())
            .onHover { inside in
                over = inside
                hovering = inside
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(CanvasView.space))
                    .onChanged { store.dragConnection(from: id, to: $0.location) }
                    .onEnded { _ in store.endConnection() }
            )
            .help(String(localized: "Tirer vers un autre élément pour les relier"))
    }
}

/// Fond commun des cartes (notes, médias, documents, liens)
struct CardStyle: ViewModifier {
    let color: ItemColor
    var radius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius).fill(Surface.card)
                    if let tint = color.tint {
                        RoundedRectangle(cornerRadius: radius).fill(tint.opacity(0.10))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(color.tint?.opacity(0.55) ?? Surface.border, lineWidth: 1)
            )
    }
}

extension View {
    func card(_ color: ItemColor, radius: CGFloat = 12) -> some View { modifier(CardStyle(color: color, radius: radius)) }
}

/// Menu contextuel d'un élément (il agit sur toute la sélection quand l'élément en fait partie)
struct ItemMenu: View {
    let store: CanvasStore
    let item: CanvasItem

    private var targets: Set<UUID> { store.targets(for: item.id) }

    var body: some View {
        Section(item.displayTitle) {
            specific
        }
        Section {
            Picker(selection: Binding(get: { item.color }, set: { store.setColor($0, for: targets) })) {
                ForEach(ItemColor.allCases, id: \.self) { Text($0.label).tag($0) }
            } label: {
                Label(String(localized: "Couleur"), systemImage: "paintpalette")
            }
            if targets.count == 2 {
                Button { store.connectSelection() } label: {
                    Label(String(localized: "Relier les deux éléments"), systemImage: "arrow.right")
                }
            }
            if !item.isContainer || targets.count > 1 {
                Button {
                    store.selection = targets
                    store.groupSelection()
                } label: {
                    Label(String(localized: "Grouper dans un conteneur"), systemImage: "square.dashed")
                }
            }
            Button {
                store.selection = targets
                store.duplicateSelection()
            } label: {
                Label(String(localized: "Dupliquer"), systemImage: "plus.square.on.square")
            }
            Button { store.bringToFront(targets) } label: {
                Label(String(localized: "Premier plan"), systemImage: "square.3.layers.3d.top.filled")
            }
            Button { store.sendToBack(targets) } label: {
                Label(String(localized: "Arrière-plan"), systemImage: "square.3.layers.3d.bottom.filled")
            }
        }
        Section {
            Button(role: .destructive) { store.delete(targets) } label: {
                Label(String(localized: "Supprimer"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var specific: some View {
        switch item.kind {
        case .note:
            Button { store.beginEditing(item.id) } label: {
                Label(String(localized: "Modifier dans la carte"), systemImage: "pencil")
            }
            Button { store.openFullEditor(item.id) } label: {
                Label(String(localized: "Ouvrir l'éditeur complet"), systemImage: "rectangle.and.pencil.and.ellipsis")
            }
            Button { copy(item.text) } label: {
                Label(String(localized: "Copier le Markdown"), systemImage: "doc.on.doc")
            }
        case .container:
            Button { store.toggleCollapse(item.id) } label: {
                Label(
                    item.collapsed ? String(localized: "Développer") : String(localized: "Réduire"),
                    systemImage: item.collapsed ? "chevron.down" : "chevron.right"
                )
            }
            Button { store.renamingContainer = item.id } label: {
                Label(String(localized: "Renommer…"), systemImage: "pencil")
            }
            Button { store.ungroup(item.id) } label: {
                Label(String(localized: "Dégrouper"), systemImage: "square.dashed")
            }
            if item.sharedID != nil {
                Button { store.detachShared(item.id) } label: {
                    Label(String(localized: "Ne plus synchroniser"), systemImage: "link.badge.plus")
                }
            }
        case .voice:
            Button { store.activate(item.id) } label: {
                Label(String(localized: "Lire ou mettre en pause"), systemImage: "playpause")
            }
            Button { store.transcribe(item.id) } label: {
                Label(
                    item.transcript == nil ? String(localized: "Transcrire") : String(localized: "Transcrire à nouveau"),
                    systemImage: "text.bubble"
                )
            }
            .disabled(store.transcribing.contains(item.id))
            if let transcript = item.transcript {
                Button { copy(transcript) } label: {
                    Label(String(localized: "Copier la transcription"), systemImage: "doc.on.doc")
                }
                Button {
                    store.addNote(at: CGPoint(x: item.frame.maxX + 150, y: item.frame.midY), text: transcript)
                } label: {
                    Label(String(localized: "Créer une note avec la transcription"), systemImage: "note.text.badge.plus")
                }
            }
            fileActions
        case .image, .video, .document:
            Button { store.activate(item.id) } label: {
                Label(String(localized: "Aperçu rapide"), systemImage: "eye")
            }
            Button { store.openFile(item.id) } label: {
                Label(String(localized: "Ouvrir avec l'app par défaut"), systemImage: "arrow.up.forward.app")
            }
            fileActions
        case .link:
            Button { store.openLink(item.id) } label: {
                Label(String(localized: "Ouvrir dans le navigateur"), systemImage: "safari")
            }
            Button { copy(item.url ?? "") } label: {
                Label(String(localized: "Copier l'adresse"), systemImage: "doc.on.doc")
            }
            Button { store.renamingContainer = item.id } label: {
                Label(String(localized: "Renommer…"), systemImage: "pencil")
            }
            Button { store.editingAddressOf = item.id } label: {
                Label(String(localized: "Modifier l'adresse…"), systemImage: "link")
            }
            Button { store.refreshPreview(item.id) } label: {
                Label(String(localized: "Actualiser l'aperçu"), systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var fileActions: some View {
        Button { store.renamingContainer = item.id } label: {
            Label(String(localized: "Renommer…"), systemImage: "pencil")
        }
        Button { store.revealInFinder(item.id) } label: {
            Label(FileManagerApp.revealLabel, systemImage: "folder")
        }
        Button { store.exportFile(item.id) } label: {
            Label(String(localized: "Enregistrer une copie…"), systemImage: "square.and.arrow.down")
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
