import AppKit
import Foundation

/// Fichiers des conteneurs partagés (`Nuvora/Shared`) : un fichier par conteneur, et les fichiers qu'il utilise.
enum SharedStore {
    static func fileURL(_ id: UUID, in directory: URL) -> URL { directory.appending(path: "\(id.uuidString).json") }
    static func assetsURL(in directory: URL) -> URL { directory.appending(path: "assets", directoryHint: .isDirectory) }

    static func read(_ id: UUID, in directory: URL) -> SharedFile? {
        guard let data = try? Data(contentsOf: fileURL(id, in: directory)) else { return nil }
        return try? JSONDecoder.nuvora.decode(SharedFile.self, from: data)
    }

    /// Enregistre le contenu s'il a changé. Renvoie la version (inchangée si le contenu est le même).
    @discardableResult
    static func write(_ content: SharedContent, id: UUID, in directory: URL) -> String {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try? JSONEncoder.nuvora.encode(content)
        if let existing = read(id, in: directory), let previous = try? JSONEncoder.nuvora.encode(existing.content), previous == encoded {
            return existing.stamp
        }
        let file = SharedFile(stamp: UUID().uuidString, content: content)
        if let data = try? JSONEncoder.nuvora.encode(file) {
            try? data.write(to: fileURL(id, in: directory), options: .atomic)
        }
        return file.stamp
    }

    /// Copie les fichiers qui manquent à l'arrivée.
    static func copyAssets(_ names: Set<String>, from source: URL, to destination: URL) {
        guard !names.isEmpty, source != destination else { return }
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in names {
            let target = destination.appending(path: name)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try? FileManager.default.copyItem(at: source.appending(path: name), to: target)
        }
    }
}

/// Icônes personnelles des canvas (`Nuvora/Icons`).
@MainActor
enum IconStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Nuvora", directoryHint: .isDirectory)
            .appending(path: "Icons", directoryHint: .isDirectory)
    }

    private static var cache: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let image = NSImage(contentsOf: directory.appending(path: name)) else { return nil }
        cache[name] = image
        return image
    }

    /// Copie une image choisie par l'utilisateur. Renvoie son nom dans le dossier des icônes.
    static func importImage(_ url: URL) -> String? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: url, to: directory.appending(path: name))
            return name
        } catch {
            return nil
        }
    }
}
