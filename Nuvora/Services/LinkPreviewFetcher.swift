import AppKit
import Foundation
import LinkPresentation
import UniformTypeIdentifiers

/// Aperçu d'une page web avec LinkPresentation (le framework d'Apple) : Nuvora lit la page directement,
/// sans passer par un service tiers. Le titre, l'image et l'icône sont gardés avec le canvas.
@MainActor
enum LinkPreviewFetcher {
    struct Result {
        var title: String?
        var image: Data?
        var icon: Data?
        /// Adresse finale, après les redirections
        var url: URL?
    }

    static func fetch(_ url: URL) async -> Result? {
        let provider = LPMetadataProvider()
        provider.timeout = 15
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }
        async let image = load(metadata.imageProvider)
        async let icon = load(metadata.iconProvider)
        return Result(title: metadata.title, image: await image, icon: await icon, url: metadata.url)
    }

    private static func load(_ provider: NSItemProvider?) async -> Data? {
        guard let provider, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        // Image ramenée à une taille raisonnable, en PNG ou JPEG
        guard let data, let image = NSImage(data: data) else { return nil }
        return downsized(image, maxSide: 900)
    }

    private static func downsized(_ image: NSImage, maxSide: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        let size = CGSize(width: max(1, (w * scale).rounded()), height: max(1, (h * scale).rounded()))
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        guard let out = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: out)
        return rep.representation(using: .png, properties: [:])
    }
}
