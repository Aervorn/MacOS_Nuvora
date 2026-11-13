import Foundation
import UniformTypeIdentifiers

/// Lecture d'une adresse web saisie ou collée.
enum WebAddress {
    /// `https://exemple.fr`, `exemple.fr/page` ou `www.exemple.fr` → URL http(s). `nil` si ce n'est pas une adresse.
    static func parse(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
            return url
        }
        // Sans schéma : il faut au moins un nom de domaine avec un point
        let hostPart = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        guard hostPart.contains("."), !hostPart.hasPrefix("."), !hostPart.hasSuffix("."),
              hostPart.range(of: #"^[A-Za-z0-9.\-]+(:\d+)?$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://" + text), url.host != nil
        else { return nil }
        return url
    }

    /// Nom d'hôte sans « www. », pour l'affichage
    static func displayHost(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Type d'élément à créer pour un fichier importé.
enum FileClassifier {
    static func kind(forExtension ext: String) -> ItemKind {
        guard let type = UTType(filenameExtension: ext.lowercased()) else { return .document }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .voice }
        return .document
    }
}

/// Forme d'onde : réduit une suite d'échantillons audio à `count` barres entre 0 et 1.
enum Waveform {
    static func bars(from samples: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
        let bucket = max(1, samples.count / count)
        var bars: [Float] = []
        bars.reserveCapacity(count)
        for i in 0..<count {
            let start = i * samples.count / count
            let end = min(samples.count, max(start + 1, start + bucket))
            guard start < samples.count else { bars.append(0); continue }
            var sum: Float = 0
            for s in samples[start..<end] { sum += s * s }
            bars.append((sum / Float(end - start)).squareRoot())
        }
        let peak = bars.max() ?? 0
        guard peak > 0 else { return bars }
        // Normalisé, avec un plancher pour que les silences restent visibles
        return bars.map { max(0.06, min(1, $0 / peak)) }
    }
}

/// Mise en forme des durées et des tailles.
enum Format {
    /// 75 → « 1:15 », 3725 → « 1:02:05 »
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
