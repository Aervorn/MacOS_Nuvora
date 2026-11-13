import AppKit
import SwiftUI

/// Fenêtre principale : la barre latérale à gauche, le canvas ouvert à droite, sous une barre de titre masquée
/// pour que l'ensemble ne fasse qu'un. La palette de recherche (⌘K) se pose par-dessus.
struct ContentView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage(Prefs.sidebarCollapsed) private var collapsed = false
    @AppStorage(Prefs.theme) private var theme = AppTheme.system.rawValue
    @AppStorage(Prefs.uiFont) private var uiFont = ""
    @AppStorage(Prefs.canvasFont) private var canvasFont = ""
    @State private var showsPalette = false
    @State private var showsSettings = false

    var body: some View {
        layout
            .overlay {
                if showsPalette {
                    CommandPalette(isPresented: $showsPalette)
                }
            }
            .tint(Color.theme)
            .font(.app(size: 13))
            // Changer de thème ou de police reconstruit l'interface
            .id(theme + "|" + uiFont + "|" + canvasFont)
            .task(id: library.selectedCanvasID) { library.openSelected() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                library.openCanvas?.saveIfAutosaving()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nuvoraPalette)) { _ in
                showsPalette.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nuvoraSettings)) { _ in
                showsSettings.toggle()
            }
            .onChange(of: library.selectedCanvasID) { _, _ in showsSettings = false }
    }

    private var layout: some View {
        HStack(spacing: 0) {
            LibrarySidebar(collapsed: $collapsed, showsPalette: $showsPalette)
                .frame(width: collapsed ? 52 : 250)
            Divider().ignoresSafeArea()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Surface.canvas.ignoresSafeArea())
        // Tout monte jusqu'en haut de la fenêtre, sur la ligne des boutons rouge, jaune et vert
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private var detail: some View {
        if showsSettings {
            SettingsView { showsSettings = false }
        } else if let store = library.openCanvas {
            CanvasScreen(store: store)
                .id(store.id)
        } else if let error = library.openError {
            ContentUnavailableView {
                Label(String(localized: "Ce canvas ne peut pas être ouvert"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button(FileManagerApp.revealLabel) { library.revealInFinder() }
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "Aucun canvas"), systemImage: "rectangle.3.group")
            } description: {
                Text(String(localized: "Crée un canvas pour commencer."))
            } actions: {
                Button(String(localized: "Nouveau canvas")) { library.createCanvas() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
