import SwiftUI

/// Barre flottante en bas du canvas : tous les éléments à ajouter, et le type des liens.
struct CanvasToolbar: View {
    let store: CanvasStore
    @Binding var showsRecorder: Bool
    @Binding var showsImporter: Bool
    @Binding var showsLinkSheet: Bool

    @State private var showsLinkOptions = false
    @AppStorage(Prefs.defaultDirection) private var direction = LinkDirection.forward.rawValue
    @AppStorage(Prefs.linkStyle) private var style = LinkStyle.solid.rawValue
    @AppStorage(Prefs.linkColor) private var color = ItemColor.plain.rawValue

    var body: some View {
        HStack(spacing: 4) {
            // Mode : sélection (flèche) ou main (glisser fait défiler)
            ToolButton(symbol: "cursorarrow", help: String(localized: "Sélectionner et déplacer (V)"), selected: !store.handMode) {
                store.handMode = false
            }
            ToolButton(symbol: "hand.raised", help: String(localized: "Main : glisser pour faire défiler le canvas (H)"), selected: store.handMode) {
                store.handMode = true
            }

            Divider().frame(height: 22).padding(.horizontal, 6)

            ToolButton(symbol: "note.text.badge.plus", help: String(localized: "Nouvelle note (⌥⌘1, ou double-clic sur le fond)")) {
                store.addNote()
            }
            ToolButton(symbol: "mic", help: String(localized: "Enregistrer une note vocale (⌥⌘2)")) {
                showsRecorder = true
            }
            .popover(isPresented: $showsRecorder, arrowEdge: .top) {
                VoiceRecorderView(store: store, isPresented: $showsRecorder)
            }
            ToolButton(symbol: "paperclip", help: String(localized: "Ajouter des images, vidéos ou documents (⌥⌘3). Tu peux aussi les déposer sur le canvas.")) {
                showsImporter = true
            }
            ToolButton(symbol: "link.badge.plus", help: String(localized: "Ajouter un lien web (⌥⌘4)")) {
                showsLinkSheet = true
            }
            ToolButton(symbol: "square.dashed", help: String(localized: "Nouveau conteneur, ou grouper la sélection (⌥⌘5)")) {
                store.addContainer()
            }

            Divider().frame(height: 22).padding(.horizontal, 6)

            // Type des liens : celui du lien sélectionné, sinon celui des prochains liens
            Button {
                showsLinkOptions.toggle()
            } label: {
                HStack(spacing: 6) {
                    LinkSample(direction: currentDirection, style: currentStyle, color: currentColor)
                        .frame(width: 44, height: 16)
                    Image(systemName: "chevron.up")
                        .font(.app(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Type de lien : sens, trait et couleur"))
            .popover(isPresented: $showsLinkOptions, arrowEdge: .top) { linkOptions }

            Divider().frame(height: 22).padding(.horizontal, 6)

            ToolButton(symbol: "minus.magnifyingglass", help: String(localized: "Zoom arrière (⌘−)")) { store.zoomOut() }
            Button {
                store.zoomToActualSize()
            } label: {
                Text(verbatim: "\(Int((store.zoom * 100).rounded())) %")
                    .font(.app(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 46, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Revenir à 100 % (⌘0)"))
            ToolButton(symbol: "plus.magnifyingglass", help: String(localized: "Zoom avant (⌘+)")) { store.zoomIn() }
            ToolButton(symbol: "scope", help: String(localized: "Tout afficher (⌘1)")) { store.fitAll() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Surface.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Surface.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }

    // MARK: - Type de lien

    private var currentDirection: LinkDirection {
        store.selectedLink?.direction ?? LinkDirection(rawValue: direction) ?? .forward
    }

    private var currentStyle: LinkStyle {
        store.selectedLink?.style ?? LinkStyle(rawValue: style) ?? .solid
    }

    private var currentColor: ItemColor {
        store.selectedLink?.color ?? ItemColor(rawValue: color) ?? .plain
    }

    private func setDirection(_ value: LinkDirection) {
        direction = value.rawValue
        if let id = store.selectedConnection { store.updateConnection(id) { $0.direction = value } }
    }

    private func setStyle(_ value: LinkStyle) {
        style = value.rawValue
        if let id = store.selectedConnection { store.updateConnection(id) { $0.style = value } }
    }

    private func setColor(_ value: ItemColor) {
        color = value.rawValue
        if let id = store.selectedConnection { store.updateConnection(id) { $0.color = value } }
    }

    private var linkOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.selectedLink == nil ? String(localized: "Prochains liens") : String(localized: "Lien sélectionné"))
                .font(.app(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "Sens")).font(.app(size: 10.5)).foregroundStyle(.secondary)
                Picker(String(localized: "Sens"), selection: Binding(get: { currentDirection }, set: setDirection)) {
                    ForEach(LinkDirection.allCases, id: \.self) { value in
                        Image(systemName: value.symbol).tag(value).help(value.label)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "Trait")).font(.app(size: 10.5)).foregroundStyle(.secondary)
                Picker(String(localized: "Trait"), selection: Binding(get: { currentStyle }, set: setStyle)) {
                    ForEach(LinkStyle.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "Couleur")).font(.app(size: 10.5)).foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    ForEach(ItemColor.allCases, id: \.self) { value in
                        Button {
                            setColor(value)
                        } label: {
                            Circle()
                                .fill(value.tint ?? Color.secondary)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary, lineWidth: 2)
                                        .padding(-3)
                                        .opacity(value == currentColor ? 1 : 0)
                                )
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                        .help(value.label)
                    }
                }
            }

            Divider()

            if let link = store.selectedLink {
                HStack {
                    Button(link.label.isEmpty ? String(localized: "Ajouter un libellé…") : String(localized: "Modifier le libellé…")) {
                        showsLinkOptions = false
                        store.editingLabelOf = link.id
                    }
                    Button(String(localized: "Inverser le sens")) { store.reverseConnection(link.id) }
                }
            } else {
                Text(String(localized: "Ces réglages s'appliquent aux liens que tu vas tracer. Sélectionne un lien pour le modifier ; double-clique dessus pour lui donner un libellé."))
                    .font(.app(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Bouton rond de la barre flottante
private struct ToolButton: View {
    let symbol: String
    let help: String
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(size: 14))
                .frame(width: 34, height: 32)
                .foregroundStyle(selected ? Color.theme : Color.primary.opacity(hovering ? 1 : 0.72))
                .background(
                    Color.primary.opacity(selected ? 0.09 : hovering ? 0.07 : 0),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Petit dessin d'un lien : trait, flèches et couleur
struct LinkSample: View {
    let direction: LinkDirection
    let style: LinkStyle
    let color: ItemColor

    var body: some View {
        GeometryReader { geo in
            let y = geo.size.height / 2
            let tint = color.tint ?? Color.primary
            let start = CGPoint(x: direction.arrowAtStart ? 8 : 1, y: y)
            let end = CGPoint(x: geo.size.width - (direction.arrowAtEnd ? 8 : 1), y: y)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: start)
                    p.addLine(to: end)
                }
                .stroke(tint, style: style.stroke(lineWidth: 2))
                if direction.arrowAtEnd {
                    ArrowHead(tip: CGPoint(x: geo.size.width, y: y), angle: 0, size: 10).fill(tint)
                }
                if direction.arrowAtStart {
                    ArrowHead(tip: CGPoint(x: 0, y: y), angle: .pi, size: 10).fill(tint)
                }
            }
        }
    }
}

/// Miniature du canvas, en bas à droite : tout le contenu, et le cadre de ce qui est affiché.
/// Cliquer ou glisser dedans déplace la vue.
struct MinimapView: View {
    let store: CanvasStore
    /// Zone représentée, figée pendant qu'on glisse pour que le repère ne bouge pas sous le curseur
    @State private var dragWorld: CGRect?

    private static let size = CGSize(width: 190, height: 128)

    var body: some View {
        let world = dragWorld ?? worldRect
        let scale: CGFloat = min(Self.size.width / world.width, Self.size.height / world.height)
        let originX: CGFloat = (Self.size.width - world.width * scale) / 2 - world.minX * scale
        let originY: CGFloat = (Self.size.height - world.height * scale) / 2 - world.minY * scale
        let layers = store.document.renderOrder(hidden: store.hiddenIDs)
        let visible = store.visibleWorldRect

        Canvas { context, _ in
            func map(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX * scale + originX, y: r.minY * scale + originY, width: r.width * scale, height: r.height * scale)
            }
            for item in layers.containers {
                let tint = item.color.tint ?? Color.secondary
                let rect = map(item.frame)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(tint.opacity(0.12)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(tint.opacity(0.6)), lineWidth: 1)
            }
            for item in layers.items {
                let tint = item.color.tint ?? Color.secondary
                var rect = map(item.frame)
                rect.size.width = max(rect.width, 2)
                rect.size.height = max(rect.height, 2)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(tint.opacity(0.85)))
            }
            let frame = map(visible)
            context.fill(Path(roundedRect: frame, cornerRadius: 2), with: .color(Color.theme.opacity(0.12)))
            context.stroke(Path(roundedRect: frame, cornerRadius: 2), with: .color(Color.theme), lineWidth: 1.5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Surface.panel, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Surface.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragWorld == nil { dragWorld = world }
                    store.center(on: CGPoint(
                        x: (value.location.x - originX) / scale,
                        y: (value.location.y - originY) / scale
                    ))
                }
                .onEnded { _ in dragWorld = nil }
        )
        .help(String(localized: "Miniature : clique ou glisse pour te déplacer"))
    }

    /// Le contenu et la zone affichée, avec une marge
    private var worldRect: CGRect {
        let visible = store.visibleWorldRect
        let content = store.document.bounds() ?? visible
        let rect = content.union(visible).insetBy(dx: -40, dy: -40)
        return rect.width > 0 && rect.height > 0 ? rect : CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}
