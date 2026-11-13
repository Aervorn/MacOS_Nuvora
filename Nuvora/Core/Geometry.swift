import CoreGraphics
import Foundation

/// Courbe d'un lien entre deux rectangles : une Bézier cubique qui part du côté de la source
/// tourné vers la cible, et arrive sur le côté de la cible tourné vers la source.
struct ConnectionCurve: Equatable, Sendable {
    var start: CGPoint
    var control1: CGPoint
    var control2: CGPoint
    var end: CGPoint

    init(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }

    init(from a: CGRect, to b: CGRect) {
        let dx = b.midX - a.midX
        let dy = b.midY - a.midY
        if abs(dx) >= abs(dy) {
            let right = dx >= 0
            start = CGPoint(x: right ? a.maxX : a.minX, y: a.midY)
            end = CGPoint(x: right ? b.minX : b.maxX, y: b.midY)
            let k = max(abs(end.x - start.x) * 0.5, 30)
            control1 = CGPoint(x: start.x + (right ? k : -k), y: start.y)
            control2 = CGPoint(x: end.x + (right ? -k : k), y: end.y)
        } else {
            let down = dy >= 0
            start = CGPoint(x: a.midX, y: down ? a.maxY : a.minY)
            end = CGPoint(x: b.midX, y: down ? b.minY : b.maxY)
            let k = max(abs(end.y - start.y) * 0.5, 30)
            control1 = CGPoint(x: start.x, y: start.y + (down ? k : -k))
            control2 = CGPoint(x: end.x, y: end.y + (down ? -k : k))
        }
    }

    /// Point de la courbe à t (entre 0 et 1)
    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }

    /// Angle (radians) de la courbe en arrivant sur la cible
    var endAngle: CGFloat { Self.angle(from: control2 == end ? start : control2, to: end) }

    /// Angle (radians) de la courbe en arrivant sur la source, quand on la parcourt à l'envers
    var startAngle: CGFloat { Self.angle(from: control1 == start ? end : control1, to: start) }

    static func angle(from a: CGPoint, to b: CGPoint) -> CGFloat { atan2(b.y - a.y, b.x - a.x) }

    /// Distance approximative d'un point à la courbe (échantillonnage)
    func distance(to p: CGPoint, samples: Int = 32) -> CGFloat {
        (0...samples).map { i -> CGFloat in
            let q = point(at: CGFloat(i) / CGFloat(samples))
            return hypot(q.x - p.x, q.y - p.y)
        }.min() ?? .infinity
    }
}

/// Conversions entre coordonnées du canvas et de l'écran.
struct CanvasTransform: Equatable, Sendable {
    var offset: CGPoint
    var zoom: CGFloat

    func toScreen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + offset.x, y: p.y * zoom + offset.y) }

    func toWorld(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - offset.x) / zoom, y: (p.y - offset.y) / zoom) }

    func toScreen(_ r: CGRect) -> CGRect {
        CGRect(origin: toScreen(r.origin), size: CGSize(width: r.width * zoom, height: r.height * zoom))
    }

    func toWorld(_ r: CGRect) -> CGRect {
        CGRect(origin: toWorld(r.origin), size: CGSize(width: r.width / zoom, height: r.height / zoom))
    }

    /// Zoom autour d'un point de l'écran, qui reste sous le curseur.
    func zoomed(to newZoom: CGFloat, around anchor: CGPoint) -> CanvasTransform {
        let z = min(max(newZoom, Viewport.minZoom), Viewport.maxZoom)
        let ratio = z / zoom
        return CanvasTransform(
            offset: CGPoint(x: anchor.x - (anchor.x - offset.x) * ratio, y: anchor.y - (anchor.y - offset.y) * ratio),
            zoom: z
        )
    }

    /// Cadre qui affiche tout le rectangle dans la vue, avec une marge.
    static func fitting(_ rect: CGRect, in size: CGSize, margin: CGFloat = 60, maxZoom: CGFloat = 1) -> CanvasTransform {
        guard rect.width > 0, rect.height > 0, size.width > margin * 2, size.height > margin * 2 else {
            return CanvasTransform(offset: .zero, zoom: 1)
        }
        let z = min(
            max(min((size.width - margin * 2) / rect.width, (size.height - margin * 2) / rect.height), Viewport.minZoom),
            maxZoom
        )
        return CanvasTransform(
            offset: CGPoint(x: size.width / 2 - rect.midX * z, y: size.height / 2 - rect.midY * z),
            zoom: z
        )
    }
}

extension CGFloat {
    /// Arrondi au multiple le plus proche (magnétisme de la grille)
    func snapped(to step: CGFloat) -> CGFloat { step > 0 ? (self / step).rounded() * step : self }
}
