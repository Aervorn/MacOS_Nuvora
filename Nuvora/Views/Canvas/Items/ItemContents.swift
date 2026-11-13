import AppKit
import SwiftUI

// Contenu de chaque type d'élément, dessiné à sa taille sur le canvas (le zoom s'applique ensuite).
// Rien ici ne s'appuie sur une vue AppKit : tout reste net et réactif quand on zoome.

// MARK: - Note

struct NoteContent: View {
    let store: CanvasStore
    let item: CanvasItem
    @State private var hovering = false

    var body: some View {
        Group {
            if store.editingID == item.id {
                // Le texte est affiché par l'éditeur posé par-dessus (CanvasView)
                Color.clear
            } else if item.text.isEmpty {
                Label(String(localized: "Double-clique pour écrire"), systemImage: "pencil")
                    .font(.canvas(size: 13))
                    .foregroundStyle(.tertiary)
            } else {
                // À sa hauteur naturelle : la note s'agrandit pour montrer tout le texte
                MarkdownText(text: item.text) { line in store.toggleTask(item.id, line: line) }
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        let footer: CGFloat = NoteMarkdown.tasks(item.text).isEmpty ? 0 : 24
                        store.noteContentMeasured(item.id, height: height + 28 + footer)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .overlay(alignment: .bottomLeading) { taskCount }
        .overlay(alignment: .topTrailing) { quickActions }
        .card(item.color)
        .onHover { hovering = $0 }
    }

    /// Avancement des tâches de la note : « 2/5 »
    @ViewBuilder
    private var taskCount: some View {
        let tasks = NoteMarkdown.tasks(item.text)
        if !tasks.isEmpty && store.editingID != item.id {
            Label(
                String(tasks.filter(\.done).count) + "/" + String(tasks.count),
                systemImage: "checklist"
            )
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.bottom, 9)
        }
    }

    /// Au survol, en haut à droite : modifier dans la carte, ouvrir l'éditeur complet
    @ViewBuilder
    private var quickActions: some View {
        if hovering && store.editingID != item.id {
            HStack(spacing: 2) {
                quickButton("pencil", String(localized: "Modifier dans la carte")) { store.beginEditing(item.id) }
                quickButton("arrow.up.left.and.arrow.down.right", String(localized: "Ouvrir l'éditeur complet")) {
                    store.openFullEditor(item.id)
                }
            }
            .padding(6)
        }
    }

    private func quickButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.canvas(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Surface.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Mise en forme dans une ligne : **gras**, *italique*, `code`, [liens](https://…)
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// Affichage d'une note en Markdown : titres, listes, tâches à cocher, citations, blocs de code.
struct MarkdownText: View {
    let text: String
    var baseSize: CGFloat = 13
    /// Appelé avec le numéro de ligne d'une tâche quand on clique sur sa case
    var toggle: ((Int) -> Void)?

    var body: some View {
        let blocks = NoteMarkdown.blocks(text)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(block)
            }
        }
        .font(.canvas(size: baseSize))
        .lineSpacing(3)
        .foregroundStyle(Color.primary.opacity(0.78))
    }

    @ViewBuilder
    private func row(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(NoteContent.markdown(text))
                .font(.canvas(size: level == 1 ? baseSize + 3 : level == 2 ? baseSize + 1.5 : baseSize, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 2)
        case let .paragraph(text):
            Text(NoteContent.markdown(text))
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "•").foregroundStyle(.secondary)
                Text(NoteContent.markdown(text))
            }
        case let .task(line, done, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    toggle?(line)
                } label: {
                    CheckBox(done: done, size: baseSize)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                }
                .buttonStyle(.plain)
                .disabled(toggle == nil)
                Text(NoteContent.markdown(text))
                    .strikethrough(done)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
            }
        case let .quote(text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.5)).frame(width: 3)
                Text(NoteContent.markdown(text)).italic().foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case let .code(text):
            Text(verbatim: text)
                .font(.system(size: baseSize - 1.5, design: .monospaced))
                .lineSpacing(4)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Surface.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Surface.border, lineWidth: 1))
        }
    }
}

// MARK: - Conteneur

struct ContainerContent: View {
    let store: CanvasStore
    let item: CanvasItem

    private var tint: Color { item.color.tint ?? Color.secondary }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    store.toggleCollapse(item.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.canvas(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                        .rotationEffect(.degrees(item.collapsed ? 0 : 90))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.collapsed ? String(localized: "Développer") : String(localized: "Réduire"))

                if store.editingID == item.id {
                    Color.clear.frame(height: 20)
                } else {
                    Text(item.text.isEmpty ? String(localized: "Sans titre") : item.text)
                        .textCase(.uppercase)
                        .kerning(0.9)
                        .font(.canvas(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if item.sharedID != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.canvas(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .help(String(localized: "Conteneur synchronisé avec d'autres canvas"))
                }
                if item.collapsed {
                    CollapsedSummary(document: store.document, containerID: item.id)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: CanvasItem.containerHeaderHeight)

            if !item.collapsed { Spacer(minLength: 0) }
        }
        .background {
            ZStack {
                // Réduit, le conteneur devient une carte pleine ; développé, il laisse voir le canvas
                if item.collapsed { RoundedRectangle(cornerRadius: 14).fill(Surface.card) }
                RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.05))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tint.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: item.collapsed ? [] : [4, 4]))
        )
    }
}

/// Résumé d'un conteneur réduit : nombre d'éléments et icônes de leurs types
private struct CollapsedSummary: View {
    let document: CanvasDocument
    let containerID: UUID

    var body: some View {
        let contents = document.descendants(of: containerID).compactMap { document.item($0) }
        let kinds = ItemKind.allCases.filter { kind in contents.contains { $0.kind == kind } }
        HStack(spacing: 5) {
            ForEach(kinds, id: \.self) { Image(systemName: $0.symbol).font(.canvas(size: 11)) }
            Text(contents.count == 1 ? String(localized: "1 élément") : String(localized: "\(String(contents.count)) éléments"))
                .font(.canvas(size: 12))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }
}

extension ItemKind {
    var symbol: String {
        switch self {
        case .note: "note.text"
        case .voice: "waveform"
        case .image: "photo"
        case .video: "film"
        case .document: "doc"
        case .link: "link"
        case .container: "square.dashed"
        }
    }
}

// MARK: - Note vocale

struct VoiceContent: View {
    let store: CanvasStore
    let item: CanvasItem

    private var playback: AudioPlayback { AudioPlayback.shared }
    private var isCurrent: Bool { playback.currentID == item.id }
    private var isPlaying: Bool { isCurrent && playback.isPlaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    store.activate(item.id)
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.canvas(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(item.color.tint ?? .theme))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.originalName ?? String(localized: "Note vocale"))
                        .font(.canvas(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(timeLabel)
                        .font(.canvas(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if store.transcribing.contains(item.id) {
                    ProgressView().controlSize(.small)
                        .help(String(localized: "Transcription…"))
                }
            }

            WaveformBars(bars: item.waveform ?? [], progress: isCurrent ? playback.progress : 0, tint: item.color.tint ?? .theme)
                .frame(height: 30)
                .contentShape(Rectangle())
                .overlay {
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let url = store.assetURL(item.asset), geo.size.width > 0 else { return }
                                AudioPlayback.shared.seek(item.id, url: url, to: location.x / geo.size.width)
                            }
                    }
                }

            transcript
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(item.color)
    }

    private var timeLabel: String {
        let total = item.media?.duration ?? 0
        if isCurrent { return "\(Format.duration(playback.currentTime)) / \(Format.duration(total))" }
        return Format.duration(total)
    }

    @ViewBuilder
    private var transcript: some View {
        if let text = item.transcript {
            Text(text)
                .font(.canvas(size: 12))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
        } else if let error = store.transcriptionErrors[item.id] {
            Text(error)
                .font(.canvas(size: 11))
                .foregroundStyle(.secondary)
        } else if !store.transcribing.contains(item.id) {
            Button(String(localized: "Transcrire")) { store.transcribe(item.id) }
                .controlSize(.small)
        }
    }
}

/// Forme d'onde en barres ; la partie déjà lue est colorée
struct WaveformBars: View {
    let bars: [Float]
    let progress: Double
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let values = bars.isEmpty ? Array(repeating: Float(0.15), count: 48) : bars
            let count = CGFloat(values.count)
            let slot = size.width / count
            let barWidth = max(1, slot * 0.6)
            for (i, value) in values.enumerated() {
                let h = max(2, CGFloat(value) * size.height)
                let x = CGFloat(i) * slot + (slot - barWidth) / 2
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                let played = (CGFloat(i) + 0.5) / count <= CGFloat(progress)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(played ? tint : Color.secondary.opacity(0.45))
                )
            }
        }
    }
}

// MARK: - Image

struct ImageContent: View {
    let store: CanvasStore
    let item: CanvasItem
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: item.frame.width, height: item.frame.height)
                    .clipped()
            } else {
                Surface.card
                Image(systemName: "photo").font(.canvas(size: 28)).foregroundStyle(.tertiary)
            }
        }
        .overlay(alignment: .topLeading) { MediaName(name: item.originalName) }
        .card(.plain, radius: 10)
        .task(id: item.asset) {
            guard let url = store.assetURL(item.asset) else { return }
            image = await Thumbnails.shared.image(url)
        }
    }
}

/// Nom d'une image ou d'une vidéo, posé dans son coin
struct MediaName: View {
    let name: String?

    var body: some View {
        if let name, !name.isEmpty {
            Text(name)
                .font(.canvas(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Surface.panel.opacity(0.9), in: Capsule())
                .padding(7)
        }
    }
}

// MARK: - Vidéo

struct VideoContent: View {
    let store: CanvasStore
    let item: CanvasItem
    @State private var frame: NSImage?

    var body: some View {
        ZStack {
            Color.black
            if let frame {
                Image(nsImage: frame)
                    .resizable()
                    .scaledToFill()
                    .frame(width: item.frame.width, height: item.frame.height)
                    .clipped()
            }
            Button {
                store.activate(item.id)
            } label: {
                Image(systemName: "play.fill")
                    .font(.canvas(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Lire dans Aperçu rapide"))
        }
        .overlay(alignment: .bottomTrailing) {
            if let duration = item.media?.duration {
                Text(Format.duration(duration))
                    .font(.canvas(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(8)
            }
        }
        .overlay(alignment: .topLeading) { MediaName(name: item.originalName) }
        .card(.plain, radius: 10)
        .task(id: item.asset) {
            guard let url = store.assetURL(item.asset) else { return }
            frame = await Thumbnails.shared.videoFrame(url)
        }
    }
}

// MARK: - Document

struct DocumentContent: View {
    let store: CanvasStore
    let item: CanvasItem
    @State private var preview: NSImage?

    private var url: URL? { store.assetURL(item.asset) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Surface.canvas
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else if let url {
                    Image(nsImage: Thumbnails.shared.icon(for: url))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()

            HStack(spacing: 8) {
                if let url {
                    Image(nsImage: Thumbnails.shared.icon(for: url))
                        .resizable()
                        .frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.originalName ?? url?.lastPathComponent ?? "")
                        .font(.canvas(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(details)
                        .font(.canvas(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .card(item.color)
        .task(id: "\(item.asset ?? "")-\(Int(item.frame.width))") {
            guard let url else { return }
            let width = max(160, item.frame.width)
            preview = await Thumbnails.shared.preview(url, size: CGSize(width: width, height: width * 1.3))
        }
    }

    private var details: String {
        var parts: [String] = []
        if let ext = url?.pathExtension, !ext.isEmpty { parts.append(ext.uppercased()) }
        if let pages = item.media?.pageCount {
            parts.append(pages == 1 ? String(localized: "1 page") : String(localized: "\(String(pages)) pages"))
        }
        if let size = item.media?.fileSize { parts.append(Format.fileSize(size)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Lien web

struct LinkContent: View {
    let store: CanvasStore
    let item: CanvasItem
    @State private var image: NSImage?
    @State private var icon: NSImage?

    private var url: URL? { item.url.flatMap(URL.init(string:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: item.frame.width, height: max(0, item.frame.height - 86))
                    .clipped()
            } else if store.fetchingPreviews.contains(item.id) && item.frame.height > 150 {
                ZStack {
                    Color.secondary.opacity(0.08)
                    ProgressView().controlSize(.small)
                }
                .frame(height: max(0, item.frame.height - 86))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let icon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "globe").font(.canvas(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(url.map(WebAddress.displayHost) ?? (item.url ?? ""))
                        .font(.canvas(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        store.openLink(item.id)
                    } label: {
                        Image(systemName: "arrow.up.right.square").font(.canvas(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Ouvrir dans le navigateur"))
                }
                Text(title)
                    .font(.canvas(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            Spacer(minLength: 0)
        }
        .card(item.color)
        .task(id: "\(item.preview?.imageAsset ?? "")|\(item.preview?.iconAsset ?? "")") {
            if let imageURL = store.assetURL(item.preview?.imageAsset) {
                image = await Thumbnails.shared.image(imageURL, maxPixel: 900)
            } else {
                image = nil
            }
            if let iconURL = store.assetURL(item.preview?.iconAsset) {
                icon = await Thumbnails.shared.image(iconURL, maxPixel: 64)
            } else {
                icon = nil
            }
        }
    }

    private var title: String {
        if !item.text.isEmpty { return item.text }
        if let t = item.preview?.title, !t.isEmpty { return t }
        if store.fetchingPreviews.contains(item.id) { return String(localized: "Chargement de l'aperçu…") }
        return item.url ?? ""
    }
}
