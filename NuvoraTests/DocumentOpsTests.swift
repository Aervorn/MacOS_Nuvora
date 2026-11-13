import CoreGraphics
import Foundation
import Testing

@Suite("Contenu d'un canvas")
struct DocumentOpsTests {
    private func note(_ x: CGFloat, _ y: CGFloat, w: CGFloat = 100, h: CGFloat = 60) -> CanvasItem {
        CanvasItem(kind: .note, frame: CGRect(x: x, y: y, width: w, height: h))
    }

    private func container(_ x: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat) -> CanvasItem {
        CanvasItem(kind: .container, frame: CGRect(x: x, y: y, width: w, height: h))
    }

    @Test func groupPlacesItemsInsideAContainer() throws {
        var doc = CanvasDocument()
        let a = note(0, 0), b = note(200, 100)
        doc.items = [a, b]
        // Appel mutant hors de la macro : #require capture son expression comme une valeur immuable
        let grouped = doc.group([a.id, b.id], title: "Groupe")
        let id = try #require(grouped)
        let box = try #require(doc.item(id))
        #expect(box.isContainer)
        #expect(box.frame.contains(a.frame))
        #expect(box.frame.contains(b.frame))
        #expect(doc.item(a.id)?.parentID == id)
        #expect(doc.descendants(of: id) == [a.id, b.id])
    }

    @Test func collapsingHidesContentAndRedirectsLinks() throws {
        var doc = CanvasDocument()
        let inside = note(20, 60), outside = note(600, 60)
        var box = container(0, 0, w: 300, h: 300)
        box.text = "Boîte"
        doc.items = [box, inside, outside]
        doc.recomputeParents(for: [inside.id, outside.id])
        #expect(doc.item(inside.id)?.parentID == box.id)
        #expect(doc.item(outside.id)?.parentID == nil)
        doc.connect(inside.id, outside.id, direction: .forward)

        doc.toggleCollapse(box.id)
        let collapsed = try #require(doc.item(box.id))
        #expect(collapsed.collapsed)
        #expect(collapsed.frame.height == CanvasItem.containerHeaderHeight)
        #expect(collapsed.expandedHeight == 300)
        let hidden = doc.hiddenIDs
        #expect(hidden == [inside.id])
        #expect(doc.visibleEndpoint(for: inside.id, hidden: hidden) == box.id)

        doc.toggleCollapse(box.id)
        #expect(doc.item(box.id)?.frame.height == 300)
        #expect(doc.hiddenIDs.isEmpty)
    }

    @Test func nestedContainersPickTheInnermost() {
        var doc = CanvasDocument()
        let outer = container(0, 0, w: 800, h: 800)
        let inner = container(100, 100, w: 300, h: 300)
        let item = note(150, 150)
        doc.items = [outer, inner, item]
        doc.recomputeParents(for: [inner.id, item.id])
        #expect(doc.item(inner.id)?.parentID == outer.id)
        #expect(doc.item(item.id)?.parentID == inner.id)
        #expect(doc.ancestors(of: item.id) == [inner.id, outer.id])
        let order = doc.renderOrder(hidden: [])
        #expect(order.containers.map(\.id) == [outer.id, inner.id])
    }

    @Test func aContainerNeverContainsItself() {
        var doc = CanvasDocument()
        let outer = container(0, 0, w: 800, h: 800)
        var inner = container(100, 100, w: 300, h: 300)
        inner.parentID = outer.id
        doc.items = [outer, inner]
        // On pose le grand conteneur sur le petit : il ne peut pas entrer dans son propre contenu
        doc.items[0].frame.origin = CGPoint(x: 150, y: 150)
        doc.recomputeParents(for: [outer.id])
        #expect(doc.item(outer.id)?.parentID == nil)
    }

    @Test func removingAContainerRemovesItsContentAndLinks() {
        var doc = CanvasDocument()
        let box = container(0, 0, w: 300, h: 300)
        let inside = note(20, 60), other = note(600, 0)
        doc.items = [box, inside, other]
        doc.recomputeParents(for: [inside.id])
        doc.connect(inside.id, other.id, direction: .both)
        doc.remove([box.id])
        #expect(doc.items.map(\.id) == [other.id])
        #expect(doc.connections.isEmpty)
    }

    @Test func ungroupKeepsTheContent() {
        var doc = CanvasDocument()
        let a = note(0, 0)
        doc.items = [a]
        let id = doc.group([a.id], title: "G")!
        doc.ungroup(id)
        #expect(doc.items.map(\.id) == [a.id])
        #expect(doc.item(a.id)?.parentID == nil)
    }

    @Test func duplicateCopiesContentAndInternalLinks() {
        var doc = CanvasDocument()
        let a = note(0, 0), b = note(200, 0), c = note(400, 0)
        doc.items = [a, b, c]
        doc.connect(a.id, b.id, direction: .forward)
        doc.connect(b.id, c.id, direction: .forward)
        let copies = doc.duplicate([a.id, b.id])
        #expect(copies.count == 2)
        #expect(doc.items.count == 5)
        // Seul le lien entre a et b est copié (c n'est pas dupliqué)
        #expect(doc.connections.count == 3)
        let copyLinks = doc.connections.filter { copies.contains($0.from) && copies.contains($0.to) }
        #expect(copyLinks.count == 1)
    }

    @Test func noDuplicateOrSelfLinks() {
        var doc = CanvasDocument()
        let a = note(0, 0), b = note(200, 0)
        doc.items = [a, b]
        let first = doc.connect(a.id, b.id, direction: .forward)
        let reversed = doc.connect(b.id, a.id, direction: .forward)
        let selfLink = doc.connect(a.id, a.id, direction: .forward)
        #expect(first != nil)
        #expect(reversed == nil)
        #expect(selfLink == nil)
        #expect(doc.connections.count == 1)
    }

    @Test func zOrder() {
        var doc = CanvasDocument()
        var a = note(0, 0), b = note(0, 0)
        a.zIndex = 1
        b.zIndex = 2
        doc.items = [a, b]
        doc.bringToFront([a.id])
        #expect(doc.item(a.id)!.zIndex > doc.item(b.id)!.zIndex)
        doc.sendToBack([a.id])
        #expect(doc.item(a.id)!.zIndex < doc.item(b.id)!.zIndex)
    }

    @Test func resizedContainerAdoptsNeighbours() {
        var doc = CanvasDocument()
        let box = container(0, 0, w: 200, h: 200)
        let later = note(300, 50)
        doc.items = [box, later]
        doc.items[0].frame.size.width = 500
        doc.refreshMembership(ofContainer: box.id)
        #expect(doc.item(later.id)?.parentID == box.id)
        doc.items[0].frame.size.width = 200
        doc.refreshMembership(ofContainer: box.id)
        #expect(doc.item(later.id)?.parentID == nil)
    }

    @Test func resizedChildGrowsItsContainers() {
        var doc = CanvasDocument()
        let outer = container(0, 0, w: 400, h: 400)
        let inner = container(20, 60, w: 200, h: 200)
        let item = note(40, 120)
        doc.items = [outer, inner, item]
        doc.recomputeParents(for: [inner.id, item.id])
        // L'élément déborde à droite du petit conteneur, puis du grand
        doc.items[2].frame.size.width = 500
        doc.growContainers(toFit: item.id, padding: 16)
        #expect(doc.item(inner.id)?.frame.maxX == 556)
        #expect(doc.item(outer.id)?.frame.maxX == 572)
        #expect(doc.item(outer.id)?.frame.height == 400)
        // Vers la gauche et le haut aussi (élément déplacé près du bord)
        doc.items[2].frame.origin = CGPoint(x: -30, y: 40)
        doc.growContainers(toFit: item.id, padding: 16)
        #expect(doc.item(inner.id)?.frame.minX == -46)
        #expect(doc.item(inner.id)?.frame.minY == -20)
        #expect(doc.item(outer.id)?.frame.minX == -62)
        // Rien ne bouge quand l'élément tient déjà dedans
        let before = doc
        doc.growContainers(toFit: item.id, padding: 16)
        #expect(doc == before)
    }

    @Test func sharedContainerRoundTrip() throws {
        // Canvas A : un conteneur avec deux notes reliées
        var a = CanvasDocument()
        let boxA = container(100, 100, w: 300, h: 300)
        let n1 = note(120, 160), n2 = note(120, 260)
        a.items = [boxA, n1, n2]
        a.recomputeParents(for: [n1.id, n2.id])
        a.connect(n1.id, n2.id, direction: .forward)
        let content = try #require(a.sharedContent(of: boxA.id))
        #expect(content.items.count == 2)
        #expect(content.items.first { $0.id == n1.id }?.frame.origin == CGPoint(x: 20, y: 60))
        #expect(content.items.allSatisfy { $0.parentID == nil })

        // Canvas B : le même conteneur ailleurs, avec un ancien contenu et un lien venu de l'extérieur
        var b = CanvasDocument()
        let boxB = container(1000, 500, w: 200, h: 200)
        var stale = note(1010, 560)
        stale.parentID = boxB.id
        var keptOld = n1
        keptOld.frame.origin = CGPoint(x: 1020, y: 560)
        keptOld.parentID = boxB.id
        let outside = note(2000, 0)
        b.items = [boxB, stale, keptOld, outside]
        b.connect(outside.id, n1.id, direction: .forward)
        b.connect(outside.id, stale.id, direction: .forward)

        b.applyShared(content, to: boxB.id)
        #expect(b.item(stale.id) == nil)
        #expect(b.item(n1.id)?.frame.origin == CGPoint(x: 1020, y: 560))
        #expect(b.item(n2.id)?.parentID == boxB.id)
        #expect(b.item(boxB.id)?.frame.size == CGSize(width: 300, height: 300))
        // Le lien extérieur vers n1 reste, celui vers l'ancienne note disparaît, le lien interne arrive
        #expect(b.connections.count == 2)
        // Le contenu relu depuis B est identique à celui de A
        #expect(b.sharedContent(of: boxB.id) == content)

        // Copie indépendante : nouveaux identifiants, liens internes conservés
        let copy = content.detachedCopy()
        #expect(Set(copy.items.map(\.id)).isDisjoint(with: Set(content.items.map(\.id))))
        #expect(copy.connections.count == 1)
    }

    @Test func countsAndSearchText() {
        var doc = CanvasDocument()
        var a = note(0, 0)
        a.text = "Idée de cuisine"
        var voice = CanvasItem(kind: .voice, frame: CGRect(x: 0, y: 100, width: 100, height: 60))
        voice.transcript = "penser au plan de travail"
        doc.items = [container(0, 0, w: 300, h: 300), a, voice]
        doc.connections = [Connection(from: a.id, to: voice.id, label: "dépend de")]
        #expect(doc.containerCount == 1)
        #expect(doc.cardCount == 2)
        #expect(doc.searchText.contains("cuisine"))
        #expect(doc.searchText.contains("plan de travail"))
        #expect(doc.searchText.contains("dépend de"))
    }

    @Test func fileRoundTripAndTolerantDecoding() throws {
        var doc = CanvasDocument()
        var item = note(10, 20)
        item.text = "Bonjour"
        item.waveform = [0.1, 0.5]
        doc.items = [item]
        doc.connections = [Connection(from: item.id, to: item.id, label: "x")]
        let file = CanvasFile(document: doc, viewport: Viewport(offsetX: 1, offsetY: 2, zoom: 1.5))
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(CanvasFile.self, from: data)
        #expect(decoded.document == doc)
        #expect(decoded.viewport?.zoom == 1.5)

        // Fichier minimal (champs absents) : valeurs par défaut
        let minimal = #"{"id":"\#(UUID().uuidString)","frame":[[0,0],[10,10]]}"#
        let partial = try JSONDecoder().decode(CanvasItem.self, from: Data(minimal.utf8))
        #expect(partial.kind == .note)
        #expect(partial.color == .plain)
        #expect(!partial.collapsed)
    }
}
