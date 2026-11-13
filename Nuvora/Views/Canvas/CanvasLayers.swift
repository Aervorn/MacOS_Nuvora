import SwiftUI

/// Fond du canvas : points, quadrillage ou uni. Le pas suit le zoom (doublé quand il devient trop serré).
struct GridBackground: View {
    let style: GridStyle
    let transform: CanvasTransform

    var body: some View {
        Canvas { context, size in
            guard style != .plain else { return }
            var step = Prefs.gridStep * transform.zoom
            while step < 14 { step *= 2 }
            let startX = transform.offset.x.truncatingRemainder(dividingBy: step) - step
            let startY = transform.offset.y.truncatingRemainder(dividingBy: step) - step
            let color = Color.primary.opacity(style == .dots ? 0.11 : 0.05)
            var path = Path()
            switch style {
            case .dots:
                let r: CGFloat = max(0.8, min(1.6, transform.zoom * 1.2))
                var y = startY
                while y < size.height + step {
                    var x = startX
                    while x < size.width + step {
                        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                        x += step
                    }
                    y += step
                }
                context.fill(path, with: .color(color))
            case .lines:
                var x = startX
                while x < size.width + step {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y = startY
                while y < size.height + step {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
            case .plain:
                break
            }
        }
        .background(Surface.canvas)
    }
}

extension ItemColor {
    /// Couleur d'accent, volontairement sourde (`nil` : neutre)
    var tint: Color? {
        switch self {
        case .plain: nil
        case .yellow: Color(red: 0.85, green: 0.72, blue: 0.36)
        case .orange: Color(red: 0.86, green: 0.58, blue: 0.37)
        case .red: Color(red: 0.84, green: 0.43, blue: 0.41)
        case .pink: Color(red: 0.83, green: 0.48, blue: 0.63)
        case .purple: Color(red: 0.63, green: 0.54, blue: 0.87)
        case .blue: Color(red: 0.43, green: 0.61, blue: 0.88)
        case .teal: Color(red: 0.37, green: 0.70, blue: 0.72)
        case .green: Color(red: 0.46, green: 0.72, blue: 0.53)
        case .gray: Color(red: 0.58, green: 0.60, blue: 0.63)
        }
    }

    var label: String {
        switch self {
        case .plain: String(localized: "Neutre")
        case .yellow: String(localized: "Jaune")
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Rouge")
        case .pink: String(localized: "Rose")
        case .purple: String(localized: "Violet")
        case .blue: String(localized: "Bleu")
        case .teal: String(localized: "Sarcelle")
        case .green: String(localized: "Vert")
        case .gray: String(localized: "Gris")
        }
    }
}

/// Les liens entre éléments, dessinés en coordonnées de l'écran (sous les éléments, au-dessus des conteneurs).
struct ConnectionsLayer: View {
    let store: CanvasStore
    let transform: CanvasTransform

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(store.visibleConnections()) { entry in
                ConnectionView(
                    store: store,
                    link: entry.link,
                    curve: ConnectionCurve(from: transform.toScreen(entry.from), to: transform.toScreen(entry.to)),
                    zoom: transform.zoom,
                    isSelected: store.selectedConnection == entry.link.id
                )
            }
        }
    }
}

/// Courbe de Bézier d'un lien, pour SwiftUI
struct CurveShape: Shape {
    let curve: ConnectionCurve

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: curve.start)
            p.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2)
        }
    }
}

/// Pointe de flèche, posée sur `tip` et orientée selon `angle`
struct ArrowHead: Shape {
    let tip: CGPoint
    let angle: CGFloat
    let size: CGFloat

    func path(in rect: CGRect) -> Path {
        let back = CGPoint(x: tip.x - cos(angle) * size, y: tip.y - sin(angle) * size)
        let spread = size * 0.36
        let left = CGPoint(x: back.x + cos(angle + .pi / 2) * spread, y: back.y + sin(angle + .pi / 2) * spread)
        let right = CGPoint(x: back.x + cos(angle - .pi / 2) * spread, y: back.y + sin(angle - .pi / 2) * spread)
        return Path { p in
            p.move(to: tip)
            p.addLine(to: left)
            p.addLine(to: right)
            p.closeSubpath()
        }
    }
}

private struct ConnectionView: View {
    let store: CanvasStore
    let link: Connection
    let curve: ConnectionCurve
    let zoom: CGFloat
    let isSelected: Bool

    private var color: Color { isSelected ? .theme : (link.color.tint ?? Color.primary.opacity(0.5)) }
    private var lineWidth: CGFloat { max(1, min(3, 1.6 * zoom)) * (isSelected ? 1.3 : 1) }
    private var arrowSize: CGFloat { max(10, min(22, 14 * zoom)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CurveShape(curve: curve)
                .stroke(color, style: link.style.stroke(lineWidth: lineWidth))
            if link.direction.arrowAtEnd {
                ArrowHead(tip: curve.end, angle: curve.endAngle, size: arrowSize).fill(color)
            }
            if link.direction.arrowAtStart {
                ArrowHead(tip: curve.start, angle: curve.startAngle, size: arrowSize).fill(color)
            }
            if !link.label.isEmpty {
                Text(link.label)
                    .font(.canvas(size: 12 * zoom, weight: .medium))
                    .padding(.horizontal, 8 * zoom)
                    .padding(.vertical, 3 * zoom)
                    .foregroundStyle(.secondary)
                    .background(Surface.canvas, in: Capsule())
                    .fixedSize()
                    .position(curve.point(at: 0.5))
            }
        }
        .contentShape(CurveShape(curve: curve).stroke(style: StrokeStyle(lineWidth: max(14, lineWidth + 10))))
        .onTapGesture(count: 2) { store.editingLabelOf = link.id }
        .onTapGesture { store.selectConnection(link.id) }
        .contextMenu { ConnectionMenu(store: store, link: link) }
    }
}

extension LinkStyle {
    var label: String {
        switch self {
        case .solid: String(localized: "Plein")
        case .dashed: String(localized: "Tirets")
        case .dotted: String(localized: "Pointillés")
        }
    }

    /// Trait du lien : plein, tirets, ou points ronds
    func stroke(lineWidth: CGFloat) -> StrokeStyle {
        switch self {
        case .solid: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        case .dashed: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [lineWidth * 4, lineWidth * 3.5])
        case .dotted: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [0.01, lineWidth * 2.6])
        }
    }
}

extension LinkDirection {
    var symbol: String {
        switch self {
        case .none: "minus"
        case .forward: "arrow.right"
        case .backward: "arrow.left"
        case .both: "arrow.left.arrow.right"
        }
    }
}

/// Menu contextuel d'un lien
struct ConnectionMenu: View {
    let store: CanvasStore
    let link: Connection

    var body: some View {
        Picker(String(localized: "Sens"), selection: Binding(
            get: { link.direction },
            set: { value in store.updateConnection(link.id) { $0.direction = value } }
        )) {
            ForEach(LinkDirection.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Button(String(localized: "Inverser le sens")) { store.reverseConnection(link.id) }
        Picker(String(localized: "Trait"), selection: Binding(
            get: { link.style },
            set: { value in store.updateConnection(link.id) { $0.style = value } }
        )) {
            ForEach(LinkStyle.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Picker(String(localized: "Couleur"), selection: Binding(
            get: { link.color },
            set: { value in store.updateConnection(link.id) { $0.color = value } }
        )) {
            ForEach(ItemColor.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Button(String(localized: "Modifier le libellé…")) { store.editingLabelOf = link.id }
        Divider()
        Button(String(localized: "Supprimer le lien"), role: .destructive) { store.deleteConnection(link.id) }
    }
}
