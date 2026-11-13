import CoreGraphics
import Foundation
import Testing

@Suite("Géométrie")
struct GeometryTests {
    @Test func curveLeavesFromFacingSides() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 50)
        let right = CGRect(x: 300, y: 0, width: 100, height: 50)
        let c = ConnectionCurve(from: a, to: right)
        #expect(c.start == CGPoint(x: 100, y: 25))
        #expect(c.end == CGPoint(x: 300, y: 25))
        #expect(abs(c.endAngle) < 0.001) // arrive vers la droite

        let below = CGRect(x: 0, y: 400, width: 100, height: 50)
        let v = ConnectionCurve(from: a, to: below)
        #expect(v.start == CGPoint(x: 50, y: 50))
        #expect(v.end == CGPoint(x: 50, y: 400))
        #expect(abs(v.endAngle - .pi / 2) < 0.001)
        #expect(v.point(at: 0) == v.start)
        #expect(v.point(at: 1) == v.end)
    }

    @Test func transformRoundTrip() {
        let t = CanvasTransform(offset: CGPoint(x: 40, y: -20), zoom: 2)
        let p = CGPoint(x: 13, y: 7)
        #expect(t.toWorld(t.toScreen(p)) == p)
        let r = CGRect(x: 1, y: 2, width: 30, height: 40)
        #expect(t.toWorld(t.toScreen(r)) == r)
    }

    @Test func zoomKeepsAnchorUnderCursor() {
        let t = CanvasTransform(offset: CGPoint(x: 10, y: 10), zoom: 1)
        let anchor = CGPoint(x: 200, y: 150)
        let world = t.toWorld(anchor)
        let z = t.zoomed(to: 2.5, around: anchor)
        let back = z.toScreen(world)
        #expect(abs(back.x - anchor.x) < 0.0001 && abs(back.y - anchor.y) < 0.0001)
        #expect(t.zoomed(to: 100, around: anchor).zoom == Viewport.maxZoom)
        #expect(t.zoomed(to: 0, around: anchor).zoom == Viewport.minZoom)
    }

    @Test func fittingCentersContent() {
        let rect = CGRect(x: 1000, y: 1000, width: 400, height: 200)
        let t = CanvasTransform.fitting(rect, in: CGSize(width: 1000, height: 800))
        let center = t.toScreen(CGPoint(x: rect.midX, y: rect.midY))
        #expect(abs(center.x - 500) < 0.001 && abs(center.y - 400) < 0.001)
        #expect(t.zoom <= 1)
    }

    @Test func snapping() {
        #expect(CGFloat(29).snapped(to: 20) == 20)
        #expect(CGFloat(31).snapped(to: 20) == 40)
    }
}

@Suite("Bibliothèque")
struct LibraryIndexTests {
    @Test func foldersCannotMoveIntoThemselves() {
        var index = LibraryIndex()
        let root = LibraryFolder(name: "Projets")
        let child = LibraryFolder(name: "Maison", parentID: root.id)
        let grandChild = LibraryFolder(name: "Cuisine", parentID: child.id)
        index.folders = [root, child, grandChild]
        #expect(!index.canMove(folder: root.id, to: grandChild.id))
        #expect(!index.canMove(folder: root.id, to: root.id))
        #expect(index.canMove(folder: grandChild.id, to: nil))
        #expect(index.canMove(folder: grandChild.id, to: root.id))
        #expect(index.path(of: grandChild.id).map(\.name) == ["Projets", "Maison", "Cuisine"])
        #expect(index.folderTree(root.id) == [root.id, child.id, grandChild.id])
    }

    @Test func sortedByName() {
        var index = LibraryIndex()
        index.canvases = [CanvasEntry(name: "b10"), CanvasEntry(name: "b2"), CanvasEntry(name: "A")]
        #expect(index.canvases(in: nil).map(\.name) == ["A", "b2", "b10"])
    }

    @Test func uniqueNames() {
        #expect(LibraryIndex.uniqueName("Canvas", among: []) == "Canvas")
        #expect(LibraryIndex.uniqueName("Canvas", among: ["canvas", "Canvas 2"]) == "Canvas 3")
    }
}

@Suite("Outils")
struct HelperTests {
    @Test func webAddresses() {
        #expect(WebAddress.parse("https://apple.com/fr")?.absoluteString == "https://apple.com/fr")
        #expect(WebAddress.parse("  apple.com ")?.absoluteString == "https://apple.com")
        #expect(WebAddress.parse("www.exemple.fr/page?x=1")?.host == "www.exemple.fr")
        #expect(WebAddress.parse("bonjour") == nil)
        #expect(WebAddress.parse("deux mots.fr") == nil)
        #expect(WebAddress.parse("ftp://exemple.fr") == nil)
        #expect(WebAddress.parse("mailto:a@b.fr") == nil)
        #expect(WebAddress.displayHost(URL(string: "https://www.apple.com/x")!) == "apple.com")
    }

    @Test func fileKinds() {
        #expect(FileClassifier.kind(forExtension: "JPG") == .image)
        #expect(FileClassifier.kind(forExtension: "png") == .image)
        #expect(FileClassifier.kind(forExtension: "mov") == .video)
        #expect(FileClassifier.kind(forExtension: "mp4") == .video)
        #expect(FileClassifier.kind(forExtension: "m4a") == .voice)
        #expect(FileClassifier.kind(forExtension: "pdf") == .document)
        #expect(FileClassifier.kind(forExtension: "xlsx") == .document)
        #expect(FileClassifier.kind(forExtension: "inconnu") == .document)
    }

    @Test func waveformBars() {
        let samples = (0..<1000).map { Float(sin(Double($0) / 10)) * ($0 < 500 ? 0.2 : 1) }
        let bars = Waveform.bars(from: samples, count: 10)
        #expect(bars.count == 10)
        #expect(bars.max() == 1)
        #expect(bars[0] < bars[9])
        #expect(Waveform.bars(from: [], count: 4) == [0, 0, 0, 0])
    }

    @Test func durations() {
        #expect(Format.duration(0) == "0:00")
        #expect(Format.duration(75) == "1:15")
        #expect(Format.duration(3725) == "1:02:05")
    }
}

@Suite("Markdown des notes")
struct NoteMarkdownTests {
    private let sample = """
    # Titre
    Un paragraphe
    sur deux lignes

    - [ ] À faire
    - [x] Fait
    - puce
    > citation
    ```
    code  ici
    ```
    """

    @Test func blocks() {
        let blocks = NoteMarkdown.blocks(sample)
        #expect(blocks == [
            .heading(level: 1, text: "Titre"),
            .paragraph("Un paragraphe\nsur deux lignes"),
            .task(line: 4, done: false, text: "À faire"),
            .task(line: 5, done: true, text: "Fait"),
            .bullet("puce"),
            .quote("citation"),
            .code("code  ici"),
        ])
        #expect(NoteMarkdown.title(sample) == "Titre")
    }

    @Test func toggleTask() {
        let once = NoteMarkdown.toggleTask(in: sample, line: 4)
        #expect(NoteMarkdown.tasks(once).map(\.done) == [true, true])
        let twice = NoteMarkdown.toggleTask(in: once, line: 4)
        #expect(twice == sample)
        #expect(NoteMarkdown.toggleTask(in: sample, line: 99) == sample)
    }

    @Test func notATask() {
        #expect(NoteMarkdown.parseTask("- [y] non") == nil)
        #expect(NoteMarkdown.parseTask("- simple puce") == nil)
        #expect(NoteMarkdown.parseHeading("#pas un titre") == nil)
    }
}

@Suite("Mise en forme Markdown")
struct MarkdownFormatTests {
    @Test func togglePrefix() {
        #expect(NoteMarkdown.togglePrefix("- ", in: "un\ndeux") == "- un\n- deux")
        #expect(NoteMarkdown.togglePrefix("- ", in: "- un\n- deux") == "un\ndeux")
        #expect(NoteMarkdown.togglePrefix("- [ ] ", in: "un\n\ndeux") == "- [ ] un\n\n- [ ] deux")
        #expect(NoteMarkdown.togglePrefix("## ", in: "") == "## ")
        // Une seule ligne déjà marquée sur deux : on marque celle qui manque
        #expect(NoteMarkdown.togglePrefix("> ", in: "> un\ndeux") == "> > un\n> deux")
    }
}

@Suite("Mise en forme de la sélection")
struct MarkdownEditTests {
    @Test func wrapSelection() {
        let result = NoteMarkdown.apply(.wrap("*"), to: "Une ligne\nDeux", selection: NSRange(location: 0, length: 9), placeholder: "texte")
        #expect(result.text == "*Une ligne*\nDeux")
        #expect(result.selection == NSRange(location: 1, length: 9))
    }

    @Test func wrapEmptySelectionUsesPlaceholder() {
        let result = NoteMarkdown.apply(.wrap("**"), to: "ab", selection: NSRange(location: 1, length: 0), placeholder: "texte")
        #expect(result.text == "a**texte**b")
        #expect(result.selection == NSRange(location: 3, length: 5))
    }

    @Test func prefixOnSeveralLines() {
        let result = NoteMarkdown.apply(.linePrefix("- "), to: "un\ndeux\ntrois", selection: NSRange(location: 1, length: 5), placeholder: "")
        #expect(result.text == "- un\n- deux\ntrois")
        #expect(result.selection == NSRange(location: 0, length: 11))
    }

    @Test func link() {
        let result = NoteMarkdown.apply(.link, to: "voir ici", selection: NSRange(location: 5, length: 3), placeholder: "texte")
        #expect(result.text == "voir [ici](https://)")
        #expect(result.selection == NSRange(location: 11, length: 8))
    }

    @Test func outOfRangeSelectionChangesNothing() {
        let result = NoteMarkdown.apply(.wrap("*"), to: "ab", selection: NSRange(location: 5, length: 2), placeholder: "x")
        #expect(result.text == "ab")
    }
}
