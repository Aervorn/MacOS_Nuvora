import AppKit
import AVFoundation
import Foundation
import ImageIO
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Informations sur les fichiers importés.
enum MediaProbe {
    static func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    /// Taille en pixels d'une image, orientation EXIF comprise
    static func imageSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    static func pdfPageCount(_ url: URL) -> Int? {
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        return PDFDocument(url: url)?.pageCount
    }

    /// Durée et taille d'une vidéo (ou durée seule pour un son)
    static func av(_ url: URL) async -> (duration: Double?, size: CGSize?) {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration).seconds
        var size: CGSize?
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let r = CGRect(origin: .zero, size: natural).applying(transform)
            size = CGSize(width: abs(r.width), height: abs(r.height))
        }
        return (duration.flatMap { $0.isFinite ? $0 : nil }, size)
    }

    /// Taille d'affichage d'un média sur le canvas (côté le plus long : `longest`)
    static func displaySize(for pixels: CGSize?, longest: CGFloat = 360) -> CGSize {
        guard let p = pixels, p.width > 0, p.height > 0 else { return CGSize(width: longest, height: longest * 0.5625) }
        let scale = min(1, longest / max(p.width, p.height))
        let w = max(80, p.width * scale), h = max(60, p.height * scale)
        return CGSize(width: w.rounded(), height: h.rounded())
    }
}

/// Image collée ou déposée depuis une autre app : enregistrée telle quelle si c'est du PNG, JPEG, GIF ou HEIC,
/// sinon convertie en PNG.
enum ImageData {
    static func normalized(_ data: Data) -> (data: Data, ext: String)? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source) as String?,
           let utType = UTType(type), let ext = utType.preferredFilenameExtension,
           [UTType.png, .jpeg, .gif, .heic, .webP].contains(where: { utType.conforms(to: $0) }) {
            return (data, ext)
        }
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return (png, "png")
    }
}

/// Miniatures (images réduites, première page des documents, image d'une vidéo), gardées en mémoire.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()

    private init() { cache.countLimit = 300 }

    /// Image réduite (les grandes photos ne sont jamais chargées en entier)
    func image(_ url: URL, maxPixel: Int = 1400) async -> NSImage? {
        let key = "img:\(url.path):\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let cg: CGImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }

    /// Aperçu Quick Look d'un fichier (PDF, Word, Excel, PowerPoint, Keynote, vidéo…)
    func preview(_ url: URL, size: CGSize) async -> NSImage? {
        let key = "ql:\(url.path):\(Int(size.width))x\(Int(size.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = rep.nsImage
        cache.setObject(image, forKey: key)
        return image
    }

    /// Image d'une vidéo, prise à une seconde (ou au début si elle est plus courte)
    func videoFrame(_ url: URL) async -> NSImage? {
        let key = "video:\(url.path)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        let cg: CGImage?
        if let result = try? await generator.image(at: time) {
            cg = result.image
        } else {
            cg = try? await generator.image(at: .zero).image
        }
        guard let cg else { return await preview(url, size: CGSize(width: 400, height: 300)) }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }

    func icon(for url: URL) -> NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Lecture des échantillons d'un fichier audio, pour dessiner sa forme d'onde.
enum WaveformReader {
    static func bars(for url: URL, count: Int = 64) async -> [Float]? {
        await Task.detached(priority: .utility) { () -> [Float]? in
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            let format = file.processingFormat
            let frames = AVAudioFrameCount(min(file.length, Int64(format.sampleRate * 60 * 30)))
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
            do { try file.read(into: buffer) } catch { return nil }
            guard let channel = buffer.floatChannelData?[0] else { return nil }
            let length = Int(buffer.frameLength)
            // Un échantillon sur `stride` suffit pour une forme d'onde
            let stride = max(1, length / 8000)
            var samples: [Float] = []
            samples.reserveCapacity(length / stride + 1)
            var i = 0
            while i < length {
                samples.append(channel[i])
                i += stride
            }
            return Waveform.bars(from: samples, count: count)
        }.value
    }
}
