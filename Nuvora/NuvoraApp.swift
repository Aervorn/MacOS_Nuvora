import SwiftUI

@main
struct NuvoraApp: App {
    static let mainWindowID = "main"

    /// Vrai quand l'app sert d'hôte aux tests : ni Sparkle, ni vraie bibliothèque.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryStore()
    @State private var updater = AppUpdater()

    var body: some Scene {
        Window("Nuvora", id: Self.mainWindowID) {
            ContentView()
                .frame(minWidth: 960, minHeight: 600)
                .environment(library)
                .environment(updater)
                .task {
                    AppAppearance.apply()
                    appDelegate.library = library
                }
        }
        // Barre de titre masquée : la barre latérale et l'en-tête du canvas montent jusqu'en haut de la fenêtre
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
                Button(String(localized: "Rechercher les mises à jour…")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            // ⌘, affiche les réglages dans la fenêtre, à la place du canvas
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Réglages…")) {
                    NotificationCenter.default.post(name: .nuvoraSettings, object: nil)
                }
                .keyboardShortcut(",")
            }
            LibraryCommands(library: library)
            CanvasCommands()
        }

        Window(String(localized: "À propos de Nuvora"), id: AboutView.windowID) {
            AboutView()
                .tint(Color.theme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Enregistre le canvas ouvert avant de quitter.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var library: LibraryStore?

    func applicationWillTerminate(_ notification: Notification) {
        library?.saveAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Menu Fichier : nouveaux canvas et dossiers.
struct LibraryCommands: Commands {
    let library: LibraryStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "Nouveau canvas")) {
                library.createCanvas(in: library.currentFolderID)
            }
            .keyboardShortcut("n")
            Button(String(localized: "Nouveau dossier")) {
                library.createFolder(in: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(String(localized: "Rechercher et commandes…")) {
                NotificationCenter.default.post(name: .nuvoraPalette, object: nil)
            }
            .keyboardShortcut("k")
        }
    }
}

/// Menus Insertion, Canvas et Présentation : ils agissent sur le canvas affiché.
struct CanvasCommands: Commands {
    @FocusedValue(\.canvasStore) private var store

    var body: some Commands {
        CommandMenu(String(localized: "Insertion")) {
            Button(String(localized: "Note")) { store?.addNote() }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(store == nil)
            Button(String(localized: "Note vocale…")) {
                NotificationCenter.default.post(name: .nuvoraRecordVoice, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(store == nil)
            Button(String(localized: "Fichier…")) {
                NotificationCenter.default.post(name: .nuvoraImportFile, object: nil)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
                .disabled(store == nil)
            Button(String(localized: "Lien web…")) {
                NotificationCenter.default.post(name: .nuvoraAddLink, object: nil)
            }
            .keyboardShortcut("4", modifiers: [.command, .option])
                .disabled(store == nil)
            Button(String(localized: "Conteneur")) { store?.addContainer() }
                .keyboardShortcut("5", modifiers: [.command, .option])
                .disabled(store == nil)
        }

        CommandMenu(String(localized: "Canvas")) {
            Button(String(localized: "Dupliquer")) { store?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(store?.selection.isEmpty ?? true)
            Button(String(localized: "Grouper dans un conteneur")) { store?.groupSelection() }
                .keyboardShortcut("g")
                .disabled(store?.selection.isEmpty ?? true)
            Button(String(localized: "Dégrouper")) { store?.ungroupSelection() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(store?.selection.isEmpty ?? true)
            Button(String(localized: "Relier les deux éléments")) { store?.connectSelection() }
                .keyboardShortcut("l")
                .disabled(store?.selection.count != 2)
            Divider()
            Button(String(localized: "Premier plan")) { if let s = store { s.bringToFront(s.selection) } }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(store?.selection.isEmpty ?? true)
            Button(String(localized: "Arrière-plan")) { if let s = store { s.sendToBack(s.selection) } }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(store?.selection.isEmpty ?? true)
        }

        CommandGroup(replacing: .saveItem) {
            Button(String(localized: "Enregistrer")) { store?.saveNow() }
                .keyboardShortcut("s")
                .disabled(store == nil)
        }

        CommandGroup(before: .toolbar) {
            Button(String(localized: "Zoom avant")) { store?.zoomIn() }
                .keyboardShortcut("+")
            Button(String(localized: "Zoom arrière")) { store?.zoomOut() }
                .keyboardShortcut("-")
            Button(String(localized: "Taille réelle")) { store?.zoomToActualSize() }
                .keyboardShortcut("0")
            Button(String(localized: "Tout afficher")) { store?.fitAll() }
                .keyboardShortcut("1")
            Divider()
        }
    }
}

extension Notification.Name {
    static let nuvoraRecordVoice = Notification.Name("nuvora.recordVoice")
    static let nuvoraImportFile = Notification.Name("nuvora.importFile")
    static let nuvoraAddLink = Notification.Name("nuvora.addLink")
    static let nuvoraPalette = Notification.Name("nuvora.palette")
    static let nuvoraSettings = Notification.Name("nuvora.settings")
}
