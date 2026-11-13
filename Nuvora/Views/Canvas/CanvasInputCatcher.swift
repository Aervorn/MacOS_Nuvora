import AppKit
import SwiftUI

/// Capte, au-dessus du canvas, ce que SwiftUI ne fournit pas directement : défilement à deux doigts
/// ou à la molette, pincement, double tape à deux doigts et raccourcis clavier sans ⌘.
/// Transparente aux clics (`hitTest` renvoie nil) : les gestes SwiftUI continuent de fonctionner.
struct CanvasInputCatcher: NSViewRepresentable {
    let store: CanvasStore

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.store = store
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.store = store
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.removeMonitor()
    }
}

/// Transporte un NSEvent hors de `MainActor.assumeIsolated` (qui exige un résultat Sendable)
private struct EventBox: @unchecked Sendable {
    let event: NSEvent?
}

final class CatcherView: NSView {
    weak var store: CanvasStore?
    private var monitor: Any?
    /// Le dernier clic a eu lieu sur le canvas : les touches lui reviennent
    private var canvasHasFocus = true

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .magnify, .smartMagnify, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            // Le moniteur est toujours appelé sur le fil principal ; NSEvent n'est pas Sendable, d'où la boîte
            let result = MainActor.assumeIsolated { () -> EventBox in
                guard let self else { return EventBox(event: event) }
                return EventBox(event: self.handle(event))
            }
            return result.event
        }
    }

    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// Un champ de texte a le clavier (note en cours de modification, recherche, réglages…)
    private var isTyping: Bool { window?.firstResponder is NSText }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let store, event.window === window else { return event }
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            canvasHasFocus = bounds.contains(location(of: event))
            // Pendant la modification d'une note, le champ de texte garde le clavier (barre de mise en forme)
            if canvasHasFocus, !isTyping, store.editingID == nil, store.fullEditorID == nil {
                // Les flèches et Suppr ne doivent plus aller à la barre latérale
                window?.makeFirstResponder(nil)
            }
            return event

        case .scrollWheel:
            let p = location(of: event)
            guard bounds.contains(p), !isInsideEditor(p, store: store) else { return event }
            if store.fullEditorID != nil, store.fullEditorFrame.contains(p) { return event }
            if event.modifierFlags.contains(.command) {
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
                store.setZoom(store.zoom * exp(delta * 0.01), around: p)
            } else {
                let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                store.pan(by: CGSize(width: event.scrollingDeltaX * factor, height: event.scrollingDeltaY * factor))
            }
            return nil

        case .magnify:
            let p = location(of: event)
            guard bounds.contains(p) else { return event }
            store.setZoom(store.zoom * (1 + event.magnification), around: p)
            return nil

        case .smartMagnify:
            let p = location(of: event)
            guard bounds.contains(p) else { return event }
            store.smartZoom(at: p)
            return nil

        case .keyDown:
            return keyDown(event, store: store)

        case .keyUp:
            if event.keyCode == Key.space, store.spacePanning {
                store.spacePanning = false
                NSCursor.arrow.set()
                return nil
            }
            return event

        default:
            return event
        }
    }

    private func isInsideEditor(_ p: CGPoint, store: CanvasStore) -> Bool {
        guard let id = store.editingID, let item = store.document.item(id) else { return false }
        return store.transform.toScreen(item.frame).contains(p)
    }

    private enum Key {
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    private func keyDown(_ event: NSEvent, store: CanvasStore) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Pendant la modification d'une note : Échap ou ⌘↩ la termine
        if isTyping {
            if store.fullEditorID != nil, event.keyCode == Key.escape {
                store.closeFullEditor()
                window?.makeFirstResponder(nil)
                return nil
            }
            if store.editingID != nil,
               event.keyCode == Key.escape || (flags.contains(.command) && event.keyCode == Key.returnKey) {
                store.endEditing()
                window?.makeFirstResponder(nil)
                return nil
            }
            return event
        }
        // Éditeur complet ouvert : Échap le ferme, les autres touches ne touchent pas au canvas
        if store.fullEditorID != nil {
            guard event.keyCode == Key.escape, window?.attachedSheet == nil else { return event }
            store.closeFullEditor()
            return nil
        }
        guard canvasHasFocus, window?.attachedSheet == nil else { return event }

        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a":
                store.selectAll()
                return nil
            case "v":
                store.paste()
                return nil
            default:
                return event
            }
        }

        if flags.subtracting([.capsLock, .numericPad, .function]).isEmpty {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "h":
                store.handMode = true
                return nil
            case "v":
                store.handMode = false
                return nil
            default:
                break
            }
        }

        let step: CGFloat = flags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case Key.space:
            if !event.isARepeat {
                store.spacePanning = true
                NSCursor.openHand.set()
            }
            return nil
        case Key.delete, Key.forwardDelete:
            guard !store.selection.isEmpty || store.selectedConnection != nil else { return event }
            store.deleteSelection()
            return nil
        case Key.escape:
            store.escape()
            return nil
        case Key.returnKey, Key.enter:
            guard store.selection.count == 1, let id = store.selection.first else { return event }
            store.activate(id)
            return nil
        case Key.left: store.nudge(dx: -step, dy: 0); return store.selection.isEmpty ? event : nil
        case Key.right: store.nudge(dx: step, dy: 0); return store.selection.isEmpty ? event : nil
        case Key.up: store.nudge(dx: 0, dy: -step); return store.selection.isEmpty ? event : nil
        case Key.down: store.nudge(dx: 0, dy: step); return store.selection.isEmpty ? event : nil
        default:
            return event
        }
    }
}
