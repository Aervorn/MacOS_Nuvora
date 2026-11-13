import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Réglages de Nuvora (⌘,) : affichés dans la fenêtre, à la place du canvas.
struct SettingsView: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Réglages"))
                    .font(.app(size: 16, weight: .semibold))
                Spacer()
                Button(String(localized: "Terminé"), action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            Divider()
            // La largeur disponible décide : Général et Canvas côte à côte, ou une seule colonne si c'est étroit.
            // (Mesurée ici plutôt que devinée par la mise en page : les longs textes d'explication la trompaient.)
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        if geometry.size.width >= 640 {
                            HStack(alignment: .top, spacing: 16) {
                                general
                                canvas
                            }
                        } else {
                            general
                            canvas
                        }
                        updates
                    }
                    .padding(16)
                }
            }
        }
    }

    private var general: some View {
        SettingsPanel(title: String(localized: "Général"), symbol: "gearshape", tint: .blue) { GeneralSettings() }
    }

    private var canvas: some View {
        SettingsPanel(title: String(localized: "Canvas"), symbol: "square.on.square.dashed", tint: .purple) { CanvasSettings() }
    }

    private var updates: some View {
        SettingsPanel(title: String(localized: "Mises à jour"), symbol: "arrow.triangle.2.circlepath", tint: .green) { UpdateSettings() }
    }
}

/// Un groupe de réglages : un titre et un fond très légèrement coloré
private struct SettingsPanel<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.app(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}

/// Sous-groupe d'un panneau : un petit titre, des réglages, une explication
private struct SettingsGroup<Content: View>: View {
    var title: String = ""
    var footer: String = ""
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { SectionTitle(title: title) }
            content
            if !footer.isEmpty {
                Text(footer)
                    .font(.app(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GeneralSettings: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage(Prefs.appearance) private var appearance = AppAppearance.system
    @State private var language = AppLanguage.current
    @State private var languageChanged = false
    @AppStorage(Prefs.theme) private var theme = AppTheme.system.rawValue
    @AppStorage(Prefs.uiFont) private var uiFont = ""
    @AppStorage(Prefs.canvasFont) private var canvasFont = ""
    @AppStorage(Prefs.fileManagerMode) private var fileManagerMode = "auto"
    @AppStorage(Prefs.fileManagerPath) private var fileManagerPath = ""

    /// Choisit l'app qui remplace le Finder
    private func chooseFileManager() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileManagerPath = url.path
        fileManagerMode = "custom"
    }

    private var fileManagerSummary: String {
        switch fileManagerMode {
        case "finder":
            return String(localized: "Les fichiers s'affichent dans le Finder.")
        case "custom":
            let name = fileManagerPath.isEmpty ? "—" : FileManagerApp.name(of: URL(fileURLWithPath: fileManagerPath))
            return String(localized: "Les fichiers s'affichent dans \(name).")
        default:
            if let url = FileManagerApp.detected {
                return String(localized: "Remplaçant du Finder détecté : \(FileManagerApp.name(of: url)).")
            }
            return String(localized: "Aucun remplaçant du Finder détecté : les fichiers s'affichent dans le Finder.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: String(localized: "Apparence")) {
                Picker(String(localized: "Apparence"), selection: $appearance) {
                    Text(String(localized: "Automatique")).tag(AppAppearance.system)
                    Text(String(localized: "Clair")).tag(AppAppearance.light)
                    Text(String(localized: "Sombre")).tag(AppAppearance.dark)
                }
                .fixedSize()
                Picker(String(localized: "Thème de couleur"), selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .fixedSize()
                Picker(String(localized: "Langue"), selection: $language) {
                    Text(String(localized: "Langue du système")).tag(AppLanguage.system)
                    Text(verbatim: "Français").tag("fr")
                    Text(verbatim: "English").tag("en")
                }
                .fixedSize()
                if languageChanged {
                    HStack {
                        Text(String(localized: "La nouvelle langue s'appliquera au prochain lancement."))
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Relancer Nuvora")) { AppLanguage.relaunch() }
                    }
                }
            }

            SettingsGroup(
                title: String(localized: "Polices"),
                footer: String(localized: "La police du canvas s'applique aux notes, aux titres des conteneurs et aux libellés des liens.")
            ) {
                Picker(String(localized: "Police de l'interface"), selection: $uiFont) {
                    Text(String(localized: "Police de macOS")).tag("")
                    Divider()
                    ForEach(AppFonts.families, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .fixedSize()
                Picker(String(localized: "Police du canvas"), selection: $canvasFont) {
                    Text(String(localized: "Police de macOS")).tag("")
                    Divider()
                    ForEach(AppFonts.families, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .fixedSize()
            }

            SettingsGroup(title: String(localized: "Gestionnaire de fichiers"), footer: fileManagerSummary) {
                HStack {
                    Picker(String(localized: "Afficher les fichiers dans"), selection: $fileManagerMode) {
                        Text(String(localized: "Automatique")).tag("auto")
                        Text(verbatim: "Finder").tag("finder")
                        Text(String(localized: "Une autre app")).tag("custom")
                    }
                    .fixedSize()
                    if fileManagerMode == "custom" {
                        Button(String(localized: "Choisir…")) { chooseFileManager() }
                    }
                }
            }

            SettingsGroup(
                title: String(localized: "Données"),
                footer: String(localized: "Tes canvas et leurs fichiers sont enregistrés ici, et nulle part ailleurs. Time Machine les sauvegarde avec le reste de ton Mac.")
            ) {
                Text(library.rootURL.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(FileManagerApp.revealLabel) { library.revealInFinder() }
            }
        }
        .onChange(of: appearance) { _, value in AppAppearance.apply(value) }
        .onChange(of: language) { _, value in
            AppLanguage.set(value)
            languageChanged = true
        }
    }
}

private struct CanvasSettings: View {
    @AppStorage(Prefs.gridStyle) private var gridStyle = GridStyle.dots.rawValue
    @AppStorage(Prefs.snapToGrid) private var snapToGrid = false
    @AppStorage(Prefs.defaultDirection) private var direction = LinkDirection.forward.rawValue
    @AppStorage(Prefs.autoTranscribe) private var autoTranscribe = true
    @AppStorage(Prefs.transcriptionLocale) private var transcriptionLocale = "system"
    @AppStorage(Prefs.fetchLinkPreviews) private var fetchPreviews = true
    @AppStorage(Prefs.showMinimap) private var showMinimap = true
    @AppStorage(Prefs.autosaveMinutes) private var autosave = Prefs.autosaveContinuous

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(
                title: String(localized: "Enregistrement"),
                footer: String(localized: "⌘S enregistre à tout moment. Dans tous les cas, le canvas est enregistré quand tu en changes et quand tu quittes Nuvora.")
            ) {
                Picker(String(localized: "Enregistrement automatique"), selection: $autosave) {
                    Text(String(localized: "En continu")).tag(Prefs.autosaveContinuous)
                    Text(String(localized: "Toutes les minutes")).tag(1)
                    ForEach([2, 5, 10, 15, 30], id: \.self) { minutes in
                        Text(String(localized: "Toutes les \(String(minutes)) minutes")).tag(minutes)
                    }
                    Text(String(localized: "Désactivé")).tag(Prefs.autosaveOff)
                }
                .fixedSize()
            }

            SettingsGroup(title: String(localized: "Affichage")) {
                Picker(String(localized: "Fond"), selection: $gridStyle) {
                    ForEach(GridStyle.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .fixedSize()
                Toggle(String(localized: "Aligner les éléments sur la grille"), isOn: $snapToGrid)
                Toggle(String(localized: "Afficher la miniature du canvas"), isOn: $showMinimap)
                Picker(String(localized: "Sens des nouveaux liens"), selection: $direction) {
                    ForEach(LinkDirection.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
                .fixedSize()
            }

            SettingsGroup(
                title: String(localized: "Notes vocales"),
                footer: String(localized: "La transcription se fait sur ton Mac : l'audio n'est jamais envoyé en ligne. Si la langue n'est pas encore téléchargée, active la dictée dans Réglages Système › Clavier.")
            ) {
                Toggle(String(localized: "Transcrire automatiquement les notes vocales"), isOn: $autoTranscribe)
                Picker(String(localized: "Langue de transcription"), selection: $transcriptionLocale) {
                    Text(String(localized: "Langue du système")).tag("system")
                    Text(verbatim: "Français").tag("fr-FR")
                    Text(verbatim: "English (US)").tag("en-US")
                    Text(verbatim: "English (UK)").tag("en-GB")
                }
                .fixedSize()
            }

            SettingsGroup(
                title: String(localized: "Liens web"),
                footer: String(localized: "Nuvora lit le titre, l'image et l'icône de la page directement sur le site, une seule fois, puis les garde avec le canvas. Désactivé, aucun lien n'est ouvert sans toi.")
            ) {
                Toggle(String(localized: "Récupérer l'aperçu des pages web"), isOn: $fetchPreviews)
            }
        }
    }
}

private struct UpdateSettings: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        VStack(alignment: .leading, spacing: 12) {
            if updater.isEnabled {
                Toggle(String(localized: "Rechercher automatiquement les mises à jour"), isOn: $updater.automaticallyChecksForUpdates)
                HStack {
                    Button(String(localized: "Rechercher maintenant")) { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    if let date = updater.lastCheck {
                        Text(String(localized: "Dernière recherche : \(date.formatted(date: .abbreviated, time: .shortened))"))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(String(localized: "Désactivées dans les versions de développement."))
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "Version \(updater.currentVersion)"))
                .foregroundStyle(.secondary)
        }
    }
}

extension LinkDirection {
    var label: String {
        switch self {
        case .none: String(localized: "Sans flèche")
        case .forward: String(localized: "Vers la cible →")
        case .backward: String(localized: "Vers la source ←")
        case .both: String(localized: "Dans les deux sens ↔")
        }
    }
}
