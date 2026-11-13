import AppKit
import SwiftUI

/// Fenêtre « À propos de Nuvora », dans le même style que celles de Flux, Vestora et Octopus.
struct AboutView: View {
    static let windowID = "about"
    static let repositoryURL = URL(string: "https://github.com/Aervorn/MacOS_Nuvora")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.top, 8)

            Text(verbatim: "Nuvora")
                .font(.app(size: 26, weight: .bold))
                .padding(.top, 6)
            Text(version)
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            Text(String(localized: "Des canvas infinis pour tes idées : notes, notes vocales, images, vidéos, documents et liens, reliés entre eux."))
                .font(.app(size: 12))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            // 100 % local : mis en avant, comme Mole dans Octopus
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.laptopcomputer").foregroundStyle(.tint)
                    Text(String(localized: "100 % local")).fontWeight(.semibold)
                }
                Text(String(localized: "Pas de compte, pas de télémétrie, pas de cloud. Tes canvas restent sur ton Mac."))
                    .font(.app(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 16)

            Divider().padding(.vertical, 16)

            VStack(spacing: 6) {
                Text(String(localized: "Créé par Aervorn, avec l'aide de Claude."))
                Text("Mises à jour : [Sparkle](https://sparkle-project.org) (MIT)")
                Text(String(localized: "Aperçus des documents : Quick Look · Transcription : reconnaissance vocale de macOS, sur le Mac."))
                    .padding(.top, 4)
            }
            .font(.app(size: 10.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Link(destination: Self.repositoryURL) {
                Label(String(localized: "Code source sur GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .font(.app(size: 12))
            .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .frame(width: 380)
    }
}

/// Entrée « À propos de Nuvora » du menu de l'application.
struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(String(localized: "À propos de Nuvora")) { openWindow(id: AboutView.windowID) }
    }
}
