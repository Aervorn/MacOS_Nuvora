import SwiftUI
import UniformTypeIdentifiers

/// La surface infinie : fond, conteneurs, liens, éléments, puis ce qui se dessine par-dessus
/// (lien en cours, rectangle de sélection, éditeur de texte).
struct CanvasView: View {
    static let space = "canvas"

    @Bindable var store: CanvasStore
    @AppStorage(Prefs.gridStyle) private var gridStyle = GridStyle.dots.rawValue

    var body: some View {
        GeometryReader { geo in
            let t = store.transform
            let layers = store.visibleLayers()
            ZStack(alignment: .topLeading) {
                GridBackground(style: GridStyle(rawValue: gridStyle) ?? .dots, transform: t)
                    .contentShape(Rectangle())
                    .gesture(backgroundDrag)
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2, coordinateSpace: .named(Self.space)).onEnded { value in
                            store.addNote(at: t.toWorld(value.location))
                        }
                    )
                    .simultaneousGesture(TapGesture().onEnded { store.clearSelection() })

                ForEach(layers.containers) { item in
                    ItemView(store: store, item: item).placed(item.frame, t)
                }

                ConnectionsLayer(store: store, transform: t)

                ForEach(layers.items) { item in
                    ItemView(store: store, item: item).placed(item.frame, t)
                }

                pendingConnection(t)
                marquee
                editor(t)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
            .clipped()
            .background(CanvasInputCatcher(store: store))
            .overlay {
                if store.isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.theme, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL, .url, .image, .plainText], isTargeted: $store.isDropTargeted) { providers, location in
                store.drop(providers, at: location)
            }
            .onAppear { store.viewSize = geo.size }
            .onChange(of: geo.size) { _, size in store.viewSize = size }
        }
    }

    private var backgroundDrag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                store.backgroundDrag(start: value.startLocation, location: value.location, translation: value.translation)
            }
            .onEnded { _ in store.endBackgroundDrag() }
    }

    /// Lien en train d'être tiré, en pointillés
    @ViewBuilder
    private func pendingConnection(_ t: CanvasTransform) -> some View {
        if let pending = store.pendingConnection, let source = store.document.item(pending.from) {
            let target = store.connectionTarget.flatMap { store.document.item($0) }.map { t.toScreen($0.frame) }
                ?? CGRect(origin: pending.point, size: .zero)
            let curve = ConnectionCurve(from: t.toScreen(source.frame), to: target)
            ZStack(alignment: .topLeading) {
                CurveShape(curve: curve)
                    .stroke(Prefs.newLinkColor.tint ?? Color.theme, style: Prefs.newLinkStyle.stroke(lineWidth: 2))
                    .opacity(0.8)
                if Prefs.linkDirection.arrowAtEnd {
                    ArrowHead(tip: curve.end, angle: curve.endAngle, size: 16).fill(Prefs.newLinkColor.tint ?? Color.theme)
                }
                if Prefs.linkDirection.arrowAtStart {
                    ArrowHead(tip: curve.start, angle: curve.startAngle, size: 16).fill(Prefs.newLinkColor.tint ?? Color.theme)
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var marquee: some View {
        if let rect = store.marquee {
            Rectangle()
                .fill(Color.theme.opacity(0.08))
                .overlay(Rectangle().strokeBorder(Color.theme.opacity(0.8), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    /// Éditeur du texte d'une note ou du titre d'un conteneur, posé à l'écran (pas agrandi par le zoom,
    /// pour que la saisie reste nette) avec une police à l'échelle.
    @ViewBuilder
    private func editor(_ t: CanvasTransform) -> some View {
        if let id = store.editingID, let item = store.document.item(id) {
            let rect = t.toScreen(item.frame)
            if item.kind == .note {
                NoteEditor(store: store, id: id, zoom: t.zoom)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                MarkdownToolbar(text: store.textBinding(id)) { store.endEditing() }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Surface.panel, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Surface.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .fixedSize()
                    .offset(x: max(4, rect.minX), y: max(4, rect.minY - 40))
            } else {
                TitleEditor(store: store, id: id, zoom: t.zoom)
                    .frame(width: max(40, rect.width - 80 * t.zoom), height: CanvasItem.containerHeaderHeight * t.zoom)
                    .offset(x: rect.minX + 38 * t.zoom, y: rect.minY)
            }
        }
    }
}

private extension View {
    /// Place une vue dessinée en coordonnées du canvas à sa position à l'écran
    func placed(_ frame: CGRect, _ t: CanvasTransform) -> some View {
        self
            .scaleEffect(t.zoom, anchor: .topLeading)
            .offset(x: frame.minX * t.zoom + t.offset.x, y: frame.minY * t.zoom + t.offset.y)
    }
}

private struct NoteEditor: View {
    let store: CanvasStore
    let id: UUID
    let zoom: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: store.textBinding(id))
            .font(.canvas(size: 13 * zoom))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 9 * zoom)
            .padding(.vertical, 14 * zoom)
            .focused($focused)
            .onAppear { focused = true }
    }
}

private struct TitleEditor: View {
    let store: CanvasStore
    let id: UUID
    let zoom: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        TextField(String(localized: "Titre du conteneur"), text: store.textBinding(id))
            .textFieldStyle(.plain)
            .font(.canvas(size: 11 * zoom, weight: .semibold))
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit { store.endEditing() }
    }
}
