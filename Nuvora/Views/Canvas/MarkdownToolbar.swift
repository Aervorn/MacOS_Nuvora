import SwiftUI

/// Barre de mise en forme Markdown : agit sur le texte sélectionné de la note en cours de modification.
struct MarkdownToolbar: View {
    /// Texte de la note en cours de modification
    @Binding var text: String
    /// Bouton « Terminer » à droite (modification dans la carte)
    var done: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MarkdownFormat.allCases, id: \.self) { format in
                Button {
                    format.apply { text = $0 }
                } label: {
                    Image(systemName: format.symbol)
                        .font(.app(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(format.label)
            }
            if let done {
                Divider().frame(height: 14).padding(.horizontal, 4)
                Button(action: done) {
                    Image(systemName: "checkmark")
                        .font(.app(size: 12, weight: .semibold))
                        .foregroundStyle(Color.theme)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Terminer (⌘↩)"))
            }
        }
    }
}
