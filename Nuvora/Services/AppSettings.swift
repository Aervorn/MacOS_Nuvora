import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Clés des préférences de Nuvora.
enum Prefs {
    static let appearance = "appearance"
    static let gridStyle = "canvas.gridStyle"
    static let snapToGrid = "canvas.snapToGrid"
    static let defaultDirection = "canvas.defaultDirection"
    static let autoTranscribe = "voice.autoTranscribe"
    static let transcriptionLocale = "voice.transcriptionLocale"
    static let fetchLinkPreviews = "links.fetchPreviews"
    static let lastCanvas = "library.lastCanvas"
    static let theme = "appearance.theme"
    /// Polices : nom de la famille, vide pour la police de macOS
    static let uiFont = "appearance.uiFont"
    static let canvasFont = "appearance.canvasFont"
    static let sidebarCollapsed = "sidebar.collapsed"
    static let showContainers = "sidebar.showContainers"
    static let showInspector = "canvas.showInspector"
    /// Gestionnaire de fichiers : "auto", "finder" ou "custom" (avec le chemin de l'app)
    static let fileManagerMode = "files.managerMode"
    static let fileManagerPath = "files.managerPath"
    static let linkStyle = "canvas.linkStyle"
    static let linkColor = "canvas.linkColor"
    static let showMinimap = "canvas.showMinimap"
    /// Enregistrement automatique : 0 = en continu, -1 = désactivé, sinon un intervalle en minutes
    static let autosaveMinutes = "save.autosaveMinutes"
    static let autosaveContinuous = 0
    static let autosaveOff = -1

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    static var snapsToGrid: Bool { bool(snapToGrid, default: false) }
    static var autoTranscribes: Bool { bool(autoTranscribe, default: true) }
    static var fetchesLinkPreviews: Bool { bool(fetchLinkPreviews, default: true) }

    static var linkDirection: LinkDirection {
        UserDefaults.standard.string(forKey: defaultDirection).flatMap(LinkDirection.init(rawValue:)) ?? .forward
    }

    static var newLinkStyle: LinkStyle {
        UserDefaults.standard.string(forKey: linkStyle).flatMap(LinkStyle.init(rawValue:)) ?? .solid
    }

    static var newLinkColor: ItemColor {
        UserDefaults.standard.string(forKey: linkColor).flatMap(ItemColor.init(rawValue:)) ?? .plain
    }

    static var autosave: Int { UserDefaults.standard.object(forKey: autosaveMinutes) as? Int ?? autosaveContinuous }

    /// Pas de la grille, en points du canvas
    static let gridStep: CGFloat = 20
}

/// Fond du canvas.
enum GridStyle: String, CaseIterable, Identifiable {
    case dots, lines, plain
    var id: Self { self }

    var label: String {
        switch self {
        case .dots: String(localized: "Points")
        case .lines: String(localized: "Quadrillage")
        case .plain: String(localized: "Uni")
        }
    }
}

/// Apparence de l'app : celle de macOS, ou forcée en clair / sombre (comme dans Octopus).
enum AppAppearance {
    static let system = "system"
    static let light = "light"
    static let dark = "dark"

    @MainActor
    static func apply(_ value: String? = nil) {
        let v = value ?? UserDefaults.standard.string(forKey: Prefs.appearance) ?? system
        switch v {
        case light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: NSApplication.shared.appearance = nil // suit macOS
        }
    }
}

/// Langue de l'interface. Par défaut, celle de macOS ; on peut la forcer
/// (équivaut au réglage par app de Réglages Système › Langue et région).
enum AppLanguage {
    static let system = "system"
    private static let key = "AppleLanguages"

    /// "system", "fr" ou "en"
    static var current: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        guard let first = (domain[key] as? [String])?.first else { return system }
        return first.hasPrefix("fr") ? "fr" : first.hasPrefix("en") ? "en" : system
    }

    static func set(_ code: String) {
        if code == system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([code], forKey: key)
        }
    }

    /// Relance l'app pour appliquer la nouvelle langue
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Thème de couleur : la teinte des boutons, de la sélection et du fond, en plus du mode clair ou sombre.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, aurora, ocean, forest, sunset, rose, graphite
    var id: Self { self }

    var label: String {
        switch self {
        case .system: String(localized: "Couleur de macOS")
        case .aurora: String(localized: "Aurore")
        case .ocean: String(localized: "Océan")
        case .forest: String(localized: "Forêt")
        case .sunset: String(localized: "Crépuscule")
        case .rose: String(localized: "Rose")
        case .graphite: String(localized: "Graphite")
        }
    }

    /// Teinte du thème (`nil` : la couleur d'accentuation de macOS)
    var accent: Color? {
        switch self {
        case .system: nil
        case .aurora: Color(red: 0.42, green: 0.30, blue: 0.96)
        case .ocean: Color(red: 0.07, green: 0.60, blue: 0.78)
        case .forest: Color(red: 0.20, green: 0.62, blue: 0.42)
        case .sunset: Color(red: 0.93, green: 0.47, blue: 0.18)
        case .rose: Color(red: 0.90, green: 0.33, blue: 0.55)
        case .graphite: Color(red: 0.45, green: 0.48, blue: 0.54)
        }
    }

    static var current: AppTheme {
        UserDefaults.standard.string(forKey: Prefs.theme).flatMap(AppTheme.init(rawValue:)) ?? .system
    }
}

extension Color {
    /// Teinte du thème choisi. L'interface est reconstruite quand le thème change (voir ContentView).
    static var theme: Color { AppTheme.current.accent ?? .accentColor }
}

/// L'app qui montre les fichiers : le Finder, ou celle qui le remplace (Bloom, Path Finder, ForkLift…).
enum FileManagerApp {
    private static let finderID = "com.apple.finder"

    /// App à utiliser (`nil` : le Finder)
    static var appURL: URL? {
        switch UserDefaults.standard.string(forKey: Prefs.fileManagerMode) ?? "auto" {
        case "finder":
            return nil
        case "custom":
            guard let path = UserDefaults.standard.string(forKey: Prefs.fileManagerPath), !path.isEmpty,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        default:
            return detected
        }
    }

    /// Remplaçant du Finder déclaré dans macOS : le réglage global `NSFileViewer`, sinon l'app qui ouvre les dossiers.
    static var detected: URL? {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        if let id = global["NSFileViewer"] as? String, id != finderID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return url
        }
        if let url = NSWorkspace.shared.urlForApplication(toOpen: .folder),
           Bundle(url: url)?.bundleIdentifier != finderID {
            return url
        }
        return nil
    }

    static func name(of url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// « Afficher dans le Finder » ou « Afficher dans Bloom »
    static var revealLabel: String {
        guard let url = appURL else { return String(localized: "Afficher dans le Finder") }
        return String(localized: "Afficher dans \(name(of: url))")
    }

    /// Montre un fichier ou un dossier. Le Finder le sélectionne ; une autre app ouvre le dossier qui le contient.
    @MainActor
    static func reveal(_ url: URL) {
        guard let app = appURL else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }
}

/// Couleurs des surfaces de Nuvora : neutres, sourdes, avec des bordures fines plutôt que des ombres.
enum Surface {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func gray(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Fond du canvas
    static let canvas = dynamic(light: gray(0.965, 0.962, 0.955), dark: gray(0.086, 0.090, 0.098))
    /// Barres latérales, panneaux flottants
    static let panel = dynamic(light: gray(0.940, 0.937, 0.930), dark: gray(0.112, 0.116, 0.126))
    /// Cartes posées sur le canvas
    static let card = dynamic(light: gray(1, 1, 1), dark: gray(0.150, 0.155, 0.168))
    /// Bordure fine
    static let border = dynamic(
        light: NSColor(white: 0, alpha: 0.11),
        dark: NSColor(white: 1, alpha: 0.10)
    )
}

/// Bouton discret : texte secondaire, sans fond
struct QuietButtonStyle: ButtonStyle {
    var color: Color = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Bouton au contour fin
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Surface.border, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Case à cocher dessinée : contour fin, pleine quand elle est cochée
struct CheckBox: View {
    let done: Bool
    var size: CGFloat = 13

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26)
                .fill(done ? Color.theme : Color.clear)
            RoundedRectangle(cornerRadius: size * 0.26)
                .strokeBorder(done ? Color.theme : Color.secondary.opacity(0.7), lineWidth: 1.2)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Polices de l'interface et du canvas, choisies dans les réglages.
enum AppFonts {
    static var ui: String { UserDefaults.standard.string(forKey: Prefs.uiFont) ?? "" }
    static var canvas: String { UserDefaults.standard.string(forKey: Prefs.canvasFont) ?? "" }

    /// Familles de polices installées sur le Mac
    static var families: [String] { NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") } }

    static func font(_ family: String, size: CGFloat, weight: Font.Weight) -> Font {
        family.isEmpty ? .system(size: size, weight: weight) : .custom(family, fixedSize: size).weight(weight)
    }
}

extension Font {
    /// Police de l'interface (barres latérales, en-tête, panneaux). L'interface est reconstruite quand elle change.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AppFonts.font(AppFonts.ui, size: size, weight: weight)
    }

    /// Police du contenu du canvas (notes, titres des conteneurs, libellés des liens)
    static func canvas(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AppFonts.font(AppFonts.canvas, size: size, weight: weight)
    }
}

/// Mise en forme Markdown appliquée au champ de texte qui a le clavier (note en cours de modification).
@MainActor
enum MarkdownFormat: CaseIterable {
    case bold, italic, code, heading, bullet, task, quote, link

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .heading: "textformat.size"
        case .bullet: "list.bullet"
        case .task: "checklist"
        case .quote: "text.quote"
        case .link: "link"
        }
    }

    var label: String {
        switch self {
        case .bold: String(localized: "Gras")
        case .italic: String(localized: "Italique")
        case .code: String(localized: "Code")
        case .heading: String(localized: "Titre")
        case .bullet: String(localized: "Liste à puces")
        case .task: String(localized: "Tâche à cocher")
        case .quote: String(localized: "Citation")
        case .link: String(localized: "Lien")
        }
    }

    private var edit: NoteMarkdown.Edit {
        switch self {
        case .bold: .wrap("**")
        case .italic: .wrap("*")
        case .code: .wrap("`")
        case .heading: .linePrefix("## ")
        case .bullet: .linePrefix("- ")
        case .task: .linePrefix("- [ ] ")
        case .quote: .linePrefix("> ")
        case .link: .link
        }
    }

    /// Champ de texte de la note en cours de modification : celui qui a le clavier, sinon le champ
    /// modifiable de la fenêtre (un clic sur la barre peut lui avoir retiré le clavier ; sa sélection reste).
    private static func editingTextView() -> NSTextView? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return nil }
        if let focused = window.firstResponder as? NSTextView, focused.isEditable, !focused.isFieldEditor {
            return focused
        }
        var pending: [NSView] = window.contentView.map { [$0] } ?? []
        while let view = pending.popLast() {
            if let textView = view as? NSTextView, textView.isEditable, !textView.isFieldEditor, !textView.isHidden {
                return textView
            }
            pending.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Applique la mise en forme à la sélection de la note en cours de modification.
    /// La sélection est lue dans le champ de texte ; le nouveau texte est écrit dans la note par `setText`
    /// (le champ se met à jour tout seul), puis la sélection est rétablie.
    func apply(setText: (String) -> Void) {
        guard let textView = Self.editingTextView() else {
            NSSound.beep()
            return
        }
        let result = NoteMarkdown.apply(
            edit, to: textView.string, selection: textView.selectedRange(), placeholder: String(localized: "texte")
        )
        guard result.text != textView.string else { return }
        setText(result.text)
        // Après la mise à jour du champ par SwiftUI
        Task { @MainActor in
            textView.window?.makeFirstResponder(textView)
            let length = (textView.string as NSString).length
            if NSMaxRange(result.selection) <= length { textView.setSelectedRange(result.selection) }
        }
    }
}
