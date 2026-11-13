import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Icône d'un canvas : un symbole (teinté), un emoji ou une image personnelle.
/// `icon` vaut le nom d'un symbole SF, « emoji:😀 » ou « file:nom.png ».
struct CanvasIconView: View {
    let icon: String?
    let color: ItemColor?
    var size: CGFloat = 13

    var body: some View {
        Group {
            if let emoji = CanvasIcons.emoji(icon) {
                Text(verbatim: emoji).font(.app(size: size))
            } else if let name = CanvasIcons.fileName(icon), let image = IconStore.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size + 3, height: size + 3)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: CanvasIcons.symbol(icon))
                    .font(.app(size: size))
                    .foregroundStyle(color?.tint ?? Color.secondary)
            }
        }
        .frame(width: size + 7, height: size + 5)
    }
}

/// Icônes proposées pour les canvas
enum CanvasIcons {
    static let defaultSymbol = "rectangle.3.group"

    static func emoji(_ icon: String?) -> String? {
        guard let icon, icon.hasPrefix("emoji:") else { return nil }
        return String(icon.dropFirst(6))
    }

    static func fileName(_ icon: String?) -> String? {
        guard let icon, icon.hasPrefix("file:") else { return nil }
        return String(icon.dropFirst(5))
    }

    /// Symbole SF à afficher (celui par défaut pour un emoji ou une image)
    static func symbol(_ icon: String?) -> String {
        guard let icon, !icon.isEmpty, !icon.contains(":") else { return defaultSymbol }
        return icon
    }

    static let symbols: [String] = [
        "rectangle.3.group", "lightbulb", "star", "heart", "book", "books.vertical", "briefcase", "house",
        "hammer", "wrench.and.screwdriver", "paintpalette", "paintbrush", "pencil", "music.note", "guitars",
        "camera", "film", "tv", "headphones", "mic", "gamecontroller", "puzzlepiece", "airplane", "car",
        "bicycle", "tram", "map", "globe", "mountain.2", "tent", "leaf", "pawprint", "sun.max", "moon",
        "cloud", "bolt", "flame", "drop", "snowflake", "flag", "target", "trophy", "medal", "graduationcap",
        "brain", "person", "person.2", "figure.walk", "figure.run", "dumbbell", "cross.case", "pills",
        "fork.knife", "cup.and.saucer", "wineglass", "birthday.cake", "gift", "cart", "creditcard",
        "banknote", "chart.bar", "chart.pie", "building.2", "building.columns", "folder", "doc.text",
        "newspaper", "list.bullet", "checklist", "calendar", "clock", "bell", "bookmark", "tag", "envelope",
        "message", "phone", "gearshape", "cpu", "desktopcomputer", "laptopcomputer", "iphone", "server.rack",
        "network", "wifi", "lock", "key", "shield", "sparkles", "wand.and.stars", "scissors", "printer",
        "archivebox", "shippingbox", "trash", "eye", "hand.thumbsup", "face.smiling", "theatermasks",
    ]

    static let emojis: [String] = [
        "💡", "⭐️", "❤️", "🔥", "✨", "🎯", "🚀", "🧠", "📚", "📖", "📝", "✏️", "📌", "📎", "🗂️", "📁",
        "🗓️", "⏰", "✅", "❓", "⚠️", "🔒", "🔑", "🛠️", "⚙️", "🧰", "🔧", "🧪", "🔬", "💻", "🖥️", "📱",
        "🌐", "📡", "🔌", "🎨", "🖌️", "🎬", "🎥", "📷", "🎵", "🎸", "🎹", "🎧", "🎤", "🎮", "🧩", "🎲",
        "🏠", "🏡", "🏢", "🏗️", "🛋️", "🛏️", "🚗", "🚲", "✈️", "🚆", "⛵️", "🗺️", "🧭", "🏔️", "🏖️", "⛺️",
        "🌳", "🌱", "🌸", "🌻", "🍀", "☀️", "🌙", "⛅️", "🌧️", "❄️", "🌊", "🐶", "🐱", "🐦", "🐝", "🦋",
        "🍎", "🍋", "🥑", "🍞", "🧀", "🍕", "🍣", "🍰", "☕️", "🍷", "🍺", "🛒", "🎁", "🎉", "🎂", "🎄",
        "💼", "💰", "💳", "📈", "📊", "🏦", "🧾", "✉️", "💬", "📞", "🤝", "👥", "👨‍👩‍👧‍👦", "👶", "🧒", "🧑‍💻",
        "🏃", "🚴", "🏋️", "🧘", "⚽️", "🏀", "🎾", "🏆", "🥇", "🩺", "💊", "🧬", "🧳", "🎓", "🏷️", "🔖",
    ]
}

/// Choix de l'icône d'un canvas : symboles teintés, emoji, ou une image à soi.
struct IconPicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let canvasID: UUID
    @State private var customEmoji = ""

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 12)

    var body: some View {
        let entry = library.index.canvas(canvasID)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                CanvasIconView(icon: entry?.icon, color: entry?.color, size: 22)
                Text(entry?.name ?? "")
                    .font(.app(size: 13, weight: .semibold))
                Spacer()
                Button(String(localized: "Icône par défaut")) {
                    library.setIcon(canvasID, icon: nil)
                    library.setColor(canvasID, color: nil)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    title(String(localized: "Symboles"))
                    ColorDots(current: entry?.color ?? .plain) { value in
                        library.setColor(canvasID, color: value == .plain ? nil : value)
                    }
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(CanvasIcons.symbols, id: \.self) { symbol in
                            cell(selected: entry?.icon == symbol) {
                                library.setIcon(canvasID, icon: symbol)
                            } label: {
                                Image(systemName: symbol)
                                    .font(.app(size: 16))
                                    .foregroundStyle(entry?.color?.tint ?? Color.primary)
                            }
                        }
                    }

                    title(String(localized: "Emoji"))
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(CanvasIcons.emojis, id: \.self) { emoji in
                            cell(selected: entry?.icon == "emoji:" + emoji) {
                                library.setIcon(canvasID, icon: "emoji:" + emoji)
                            } label: {
                                Text(verbatim: emoji).font(.app(size: 19))
                            }
                        }
                    }
                    HStack {
                        TextField(String(localized: "Un autre emoji"), text: $customEmoji)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .onChange(of: customEmoji) { _, value in
                                // Le dernier caractère saisi devient l'icône
                                guard let last = value.last, !last.isWhitespace else { return }
                                library.setIcon(canvasID, icon: "emoji:" + String(last))
                            }
                        Button(String(localized: "Tous les emoji…")) {
                            NSApp.orderFrontCharacterPalette(nil)
                        }
                        Text(String(localized: "Clique dans le champ, puis choisis un emoji."))
                            .font(.app(size: 10.5))
                            .foregroundStyle(.secondary)
                    }

                    title(String(localized: "Image personnelle"))
                    HStack {
                        Button(String(localized: "Choisir une image…")) { chooseImage() }
                        Text(String(localized: "PNG, JPEG ou SVG. L'image est copiée dans le dossier de Nuvora."))
                            .font(.app(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 6)
            }

            HStack {
                Spacer()
                Button(String(localized: "Terminé")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 560)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private func cell<Content: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .frame(width: 32, height: 32)
                .background(selected ? Color.theme.opacity(0.22) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let name = IconStore.importImage(url) else { return }
        library.setIcon(canvasID, icon: "file:" + name)
    }
}
