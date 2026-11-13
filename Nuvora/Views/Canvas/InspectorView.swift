import AppKit
import SwiftUI

extension ItemKind {
    var label: String {
        switch self {
        case .note: String(localized: "Note")
        case .voice: String(localized: "Note vocale")
        case .image: String(localized: "Image")
        case .video: String(localized: "Vidéo")
        case .document: String(localized: "Document")
        case .link: String(localized: "Lien web")
        case .container: String(localized: "Conteneur")
        }
    }
}

extension CanvasItem {
    /// Titre court d'un élément, pour les listes et le panneau de détails
    var displayTitle: String {
        switch kind {
        case .note:
            let title = NoteMarkdown.title(text)
            return title.isEmpty ? kind.label : title
        case .container:
            return text.isEmpty ? String(localized: "Sans titre") : text
        case .link:
            if !text.isEmpty { return text }
            if let title = preview?.title, !title.isEmpty { return title }
            return url.flatMap(URL.init(string:)).map(WebAddress.displayHost) ?? kind.label
        case .voice, .image, .video, .document:
            return originalName ?? kind.label
        }
    }
}

/// Rangée de pastilles pour choisir une couleur
struct ColorDots: View {
    let current: ItemColor?
    var size: CGFloat = 16
    let choose: (ItemColor) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ItemColor.allCases, id: \.self) { value in
                Button {
                    choose(value)
                } label: {
                    Circle()
                        .fill(value.tint ?? Color.secondary.opacity(0.35))
                        .frame(width: size, height: size)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5)
                                .padding(-3)
                                .opacity(value == current ? 1 : 0)
                        )
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(value.label)
            }
        }
    }
}

/// Titre de section en petites capitales, avec un compteur à droite
struct SectionTitle: View {
    let title: String
    var trailing: String = ""

    var body: some View {
        HStack {
            Text(title)
                .textCase(.uppercase)
                .kerning(0.9)
            Spacer()
            if !trailing.isEmpty {
                Text(verbatim: trailing).monospacedDigit()
            }
        }
        .font(.app(size: 10.5, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}

/// Panneau de détails, à droite du canvas : l'élément sélectionné, ses actions, ses tâches,
/// les canvas où il apparaît, ses fils, parents et frères, et la zone de danger.
struct InspectorView: View {
    let store: CanvasStore
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle(title: String(localized: "Détails"))
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let link = store.selectedLink {
            linkDetails(link)
        } else if store.selection.count == 1, let id = store.selection.first, let item = store.document.item(id) {
            itemDetails(item)
        } else if store.selection.count > 1 {
            Text(String(localized: "\(String(store.selection.count)) éléments sélectionnés"))
                .font(.app(size: 15, weight: .semibold))
            HStack(spacing: 12) {
                Button { store.groupSelection() } label: {
                    Label(String(localized: "Grouper"), systemImage: "square.dashed")
                }
                .buttonStyle(OutlineButtonStyle())
                Button { store.duplicateSelection() } label: {
                    Label(String(localized: "Dupliquer"), systemImage: "plus.square.on.square")
                }
                .buttonStyle(QuietButtonStyle())
            }
            .controlSize(.small)
            section(String(localized: "Zone de danger")) {
                Button(role: .destructive) { store.deleteSelection() } label: {
                    Label(String(localized: "Supprimer la sélection"), systemImage: "trash")
                }
                .buttonStyle(QuietButtonStyle(color: Color(red: 0.88, green: 0.45, blue: 0.42)))
            }
        } else {
            Text(String(localized: "Rien n'est sélectionné"))
                .font(.app(size: 15, weight: .semibold))
            Text(String(localized: "Clique sur un élément ou un lien pour voir ses détails, ses tâches et ses liens."))
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, trailing: String = "", @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(title: title, trailing: trailing)
            body()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 12.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Élément

    @ViewBuilder
    private func itemDetails(_ item: CanvasItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(item.color.tint ?? Color.secondary).frame(width: 7, height: 7)
                Text(item.kind.label)
                    .textCase(.uppercase)
                    .kerning(0.9)
                    .font(.app(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(item.displayTitle)
                .font(.app(size: 14, weight: .semibold))
                .lineLimit(3)
            Text(String(localized: "Créé le \(item.createdAt.formatted(date: .long, time: .shortened))"))
                .font(.app(size: 10.5))
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 12) {
            Button { primaryAction(item) } label: {
                Label(primaryLabel(item), systemImage: primarySymbol(item))
            }
            .buttonStyle(OutlineButtonStyle())
            Button { store.duplicateSelection() } label: {
                Label(String(localized: "Dupliquer"), systemImage: "plus.square.on.square")
            }
            .buttonStyle(QuietButtonStyle())
            if item.kind != .note && item.kind != .container {
                Button { store.renamingContainer = item.id } label: {
                    Label(String(localized: "Renommer"), systemImage: "pencil")
                }
                .buttonStyle(QuietButtonStyle())
            }
            if item.kind == .note {
                Button { copy(item.text) } label: {
                    Label(String(localized: "Copier MD"), systemImage: "doc.on.doc")
                }
                .buttonStyle(QuietButtonStyle())
                .help(String(localized: "Copier le Markdown"))
            }
        }
        .controlSize(.small)
        .lineLimit(1)

        specifics(item)
        boards(for: item)
        relations(of: item)

        section(String(localized: "Zone de danger")) {
            Button { copy(item.id.uuidString) } label: {
                Label(String(localized: "Copier l'identifiant"), systemImage: "doc.on.doc")
            }
            .buttonStyle(OutlineButtonStyle())
            .controlSize(.small)
            Button(role: .destructive) { store.delete([item.id]) } label: {
                Label(String(localized: "Supprimer"), systemImage: "trash")
            }
            .buttonStyle(QuietButtonStyle(color: Color(red: 0.88, green: 0.45, blue: 0.42)))
        }
    }

    private func primaryAction(_ item: CanvasItem) {
        switch item.kind {
        case .note: store.openFullEditor(item.id)
        case .container: store.renamingContainer = item.id
        default: store.activate(item.id)
        }
    }

    private func primaryLabel(_ item: CanvasItem) -> String {
        switch item.kind {
        case .note: String(localized: "Modifier")
        case .container: String(localized: "Renommer")
        case .voice: String(localized: "Lire")
        case .image, .video, .document: String(localized: "Aperçu rapide")
        case .link: String(localized: "Ouvrir")
        }
    }

    private func primarySymbol(_ item: CanvasItem) -> String {
        switch item.kind {
        case .note, .container: "pencil"
        case .voice: "play.fill"
        case .image, .video, .document: "eye"
        case .link: "safari"
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Ce qui dépend du type : tâches d'une note, contenu d'un conteneur, fichier, transcription, adresse
    @ViewBuilder
    private func specifics(_ item: CanvasItem) -> some View {
        switch item.kind {
        case .note:
            let tasks = NoteMarkdown.tasks(item.text)
            if !tasks.isEmpty {
                section(String(localized: "Tâches"), trailing: String(tasks.filter(\.done).count) + "/" + String(tasks.count)) {
                    ForEach(tasks, id: \.line) { task in
                        Button {
                            store.toggleTask(item.id, line: task.line)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                CheckBox(done: task.done)
                                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                                Text(NoteContent.markdown(task.text))
                                    .font(.app(size: 13))
                                    .strikethrough(task.done)
                                    .foregroundStyle(task.done ? Color.secondary : Color.primary.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .container:
            let count = store.document.descendants(of: item.id).count
            section(String(localized: "Contenu"), trailing: String(count)) {
                Button { store.toggleCollapse(item.id) } label: {
                    Label(
                        item.collapsed ? String(localized: "Développer") : String(localized: "Réduire"),
                        systemImage: item.collapsed ? "chevron.down" : "chevron.right"
                    )
                }
                .buttonStyle(QuietButtonStyle())
                .controlSize(.small)
                if item.sharedID != nil {
                    Button { store.detachShared(item.id) } label: {
                        Label(String(localized: "Ne plus synchroniser"), systemImage: "link.badge.plus")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .controlSize(.small)
                }
            }
        case .voice:
            fileSection(item)
            if let transcript = item.transcript {
                section(String(localized: "Transcription")) {
                    Text(transcript)
                        .font(.app(size: 12))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .image, .video, .document:
            fileSection(item)
        case .link:
            section(String(localized: "Adresse")) {
                Text(item.url ?? "")
                    .font(.app(size: 12))
                    .textSelection(.enabled)
                    .lineLimit(4)
                Button { store.editingAddressOf = item.id } label: {
                    Label(String(localized: "Modifier l'adresse…"), systemImage: "pencil")
                }
                .buttonStyle(QuietButtonStyle())
                .controlSize(.small)
            }
        }
    }

    private func fileSection(_ item: CanvasItem) -> some View {
        section(String(localized: "Fichier")) {
            let facts = fileFacts(item)
            if !facts.isEmpty {
                Text(facts)
                    .font(.app(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button { store.revealInFinder(item.id) } label: {
                Label(FileManagerApp.revealLabel, systemImage: "folder")
            }
            .buttonStyle(QuietButtonStyle())
            .controlSize(.small)
        }
    }

    private func fileFacts(_ item: CanvasItem) -> String {
        var parts: [String] = []
        if let asset = item.asset, let ext = asset.split(separator: ".").last { parts.append(ext.uppercased()) }
        if let w = item.media?.pixelWidth, let h = item.media?.pixelHeight { parts.append("\(Int(w)) × \(Int(h))") }
        if let duration = item.media?.duration { parts.append(Format.duration(duration)) }
        if let pages = item.media?.pageCount {
            parts.append(pages == 1 ? String(localized: "1 page") : String(localized: "\(String(pages)) pages"))
        }
        if let size = item.media?.fileSize { parts.append(Format.fileSize(size)) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Canvas où l'élément apparaît

    /// Un élément n'est sur plusieurs canvas que s'il est (dans) un conteneur synchronisé
    @ViewBuilder
    private func boards(for item: CanvasItem) -> some View {
        let sharedID = item.sharedID ?? store.document.ancestors(of: item.id).compactMap { store.document.item($0)?.sharedID }.first
        let shared: [CanvasEntry] = sharedID.map { library.canvases(sharing: $0) } ?? []
        let current: [CanvasEntry] = library.index.canvas(store.id).map { [$0] } ?? []
        let canvases = shared.isEmpty ? current : shared
        section(String(localized: "Sur les canvas"), trailing: String(canvases.count)) {
            ForEach(canvases) { canvas in
                row(title: canvas.name, symbol: canvas.id == store.id ? "checkmark" : "arrow.up.right.square") {
                    if canvas.id != store.id { library.selectedCanvasID = canvas.id }
                }
            }
        }
    }

    // MARK: - Fils, parents, frères

    private struct Relation: Identifiable {
        let id: String
        let other: UUID
        let title: String
        let label: String
    }

    /// Fils : au bout d'une flèche qui part de l'élément. Parents : à l'origine d'une flèche qui y arrive.
    /// Frères : reliés par un trait sans flèche. Un lien à double flèche compte dans les fils et les parents.
    @ViewBuilder
    private func relations(of item: CanvasItem) -> some View {
        let all = relationLists(of: item)
        relationSection(String(localized: "Fils"), all.children, empty: String(localized: "Aucune flèche ne part de cet élément."))
        relationSection(String(localized: "Parents"), all.parents, empty: String(localized: "Aucune flèche n'arrive sur cet élément."))
        relationSection(String(localized: "Frères"), all.siblings, empty: String(localized: "Aucun lien sans flèche."))
    }

    private func relationLists(of item: CanvasItem) -> (children: [Relation], parents: [Relation], siblings: [Relation]) {
        var children: [Relation] = []
        var parents: [Relation] = []
        var siblings: [Relation] = []
        for link in store.document.connections where link.from == item.id || link.to == item.id {
            let outgoing = link.from == item.id
            let otherID = outgoing ? link.to : link.from
            let relation = Relation(
                id: link.id.uuidString, other: otherID,
                title: store.document.item(otherID)?.displayTitle ?? "", label: link.label
            )
            switch link.direction {
            case .none:
                siblings.append(relation)
            case .both:
                children.append(relation)
                parents.append(relation)
            case .forward:
                if outgoing { children.append(relation) } else { parents.append(relation) }
            case .backward:
                if outgoing { parents.append(relation) } else { children.append(relation) }
            }
        }
        return (children, parents, siblings)
    }

    private func relationSection(_ title: String, _ relations: [Relation], empty: String) -> some View {
        section(title, trailing: String(relations.count)) {
            if relations.isEmpty { hint(empty) }
            ForEach(relations) { relation in
                row(title: relation.title, subtitle: relation.label, symbol: "scope") {
                    store.reveal(relation.other)
                }
            }
        }
    }

    /// Ligne cliquable : un titre, un libellé éventuel, une icône à droite
    private func row(title: String, subtitle: String = "", symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.app(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.app(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .font(.app(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lien

    @ViewBuilder
    private func linkDetails(_ link: Connection) -> some View {
        let from = store.document.item(link.from)?.displayTitle ?? ""
        let to = store.document.item(link.to)?.displayTitle ?? ""
        VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "Lien"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.app(size: 10.5, weight: .semibold))
                .foregroundStyle(link.color.tint ?? Color.secondary)
            Text(link.label.isEmpty ? String(localized: "Sans libellé") : link.label)
                .font(.app(size: 15, weight: .semibold))
            Text(verbatim: from + "  " + link.direction.arrowText + "  " + to)
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        section(String(localized: "Sens")) {
            Picker(String(localized: "Sens"), selection: Binding(
                get: { link.direction },
                set: { value in store.updateConnection(link.id) { $0.direction = value } }
            )) {
                ForEach(LinkDirection.allCases, id: \.self) { Image(systemName: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        section(String(localized: "Trait")) {
            Picker(String(localized: "Trait"), selection: Binding(
                get: { link.style },
                set: { value in store.updateConnection(link.id) { $0.style = value } }
            )) {
                ForEach(LinkStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        section(String(localized: "Couleur")) {
            ColorDots(current: link.color) { value in store.updateConnection(link.id) { $0.color = value } }
        }
        HStack {
            Button(link.label.isEmpty ? String(localized: "Ajouter un libellé…") : String(localized: "Modifier le libellé…")) {
                store.editingLabelOf = link.id
            }
            Button(String(localized: "Supprimer"), role: .destructive) { store.deleteConnection(link.id) }
        }
        .controlSize(.small)
    }
}

extension LinkDirection {
    var arrowText: String {
        switch self {
        case .none: "—"
        case .forward: "→"
        case .backward: "←"
        case .both: "↔"
        }
    }
}
