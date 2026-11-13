import Foundation

/// Un bloc d'une note écrite en Markdown.
enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    /// Tâche à cocher ; `line` est le numéro de sa ligne dans le texte de la note
    case task(line: Int, done: Bool, text: String)
    case quote(String)
    case code(String)
}

/// Lecture du Markdown d'une note : titres, listes, tâches à cocher, citations et blocs de code.
/// La mise en forme dans une ligne (gras, italique, code, liens) est laissée à AttributedString.
enum NoteMarkdown {
    static func blocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        let lines = text.components(separatedBy: "\n")
        for (number, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty {
                flush()
                continue
            }
            if let task = parseTask(line) {
                flush()
                blocks.append(.task(line: number, done: task.done, text: task.text))
            } else if let heading = parseHeading(line) {
                flush()
                blocks.append(.heading(level: heading.level, text: heading.text))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// « - [ ] texte » ou « - [x] texte »
    static func parseTask(_ line: String) -> (done: Bool, text: String)? {
        for marker in ["- [", "* ["] where line.hasPrefix(marker) {
            let rest = line.dropFirst(marker.count)
            guard let state = rest.first, rest.dropFirst().hasPrefix("]") else { return nil }
            guard state == " " || state == "x" || state == "X" else { return nil }
            let text = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return (state != " ", text)
        }
        return nil
    }

    static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6, line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces))
    }

    /// Coche ou décoche la tâche de la ligne donnée.
    static func toggleTask(in text: String, line: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return text }
        let current = lines[line]
        if let range = current.range(of: "[ ]") {
            lines[line] = current.replacingCharacters(in: range, with: "[x]")
        } else if let range = current.range(of: "[x]") ?? current.range(of: "[X]") {
            lines[line] = current.replacingCharacters(in: range, with: "[ ]")
        }
        return lines.joined(separator: "\n")
    }

    /// Ajoute la marque au début de chaque ligne non vide, ou la retire si toutes la portent déjà.
    static func togglePrefix(_ prefix: String, in block: String) -> String {
        let lines = block.components(separatedBy: "\n")
        let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allMarked = !filled.isEmpty && filled.allSatisfy { $0.hasPrefix(prefix) }
        // Une ligne seule et vide reçoit quand même la marque (on commence une liste)
        let single = lines.count == 1
        return lines.map { line -> String in
            if allMarked { return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line }
            if line.trimmingCharacters(in: .whitespaces).isEmpty && !single { return line }
            return prefix + line
        }.joined(separator: "\n")
    }

    /// Une mise en forme à appliquer à la sélection
    enum Edit: Equatable {
        /// Marque de part et d'autre de la sélection (gras, italique, code)
        case wrap(String)
        /// Marque au début de chaque ligne touchée (titre, liste, tâche, citation)
        case linePrefix(String)
        /// Lien : [sélection](https://)
        case link
    }

    /// Applique une mise en forme. Renvoie le nouveau texte et la sélection à rétablir.
    /// `placeholder` remplace une sélection vide.
    static func apply(_ edit: Edit, to text: String, selection: NSRange, placeholder: String) -> (text: String, selection: NSRange) {
        let source = text as NSString
        guard selection.location != NSNotFound, NSMaxRange(selection) <= source.length else { return (text, selection) }
        let selected = source.substring(with: selection)
        func length(_ string: String) -> Int { (string as NSString).length }

        switch edit {
        case let .wrap(marker):
            let inner = selected.isEmpty ? placeholder : selected
            let result = source.replacingCharacters(in: selection, with: marker + inner + marker)
            return (result, NSRange(location: selection.location + length(marker), length: length(inner)))
        case let .linePrefix(prefix):
            var lines = source.lineRange(for: selection)
            if source.substring(with: lines).hasSuffix("\n") { lines.length -= 1 }
            let replaced = togglePrefix(prefix, in: source.substring(with: lines))
            let result = source.replacingCharacters(in: lines, with: replaced)
            return (result, NSRange(location: lines.location, length: length(replaced)))
        case .link:
            let title = selected.isEmpty ? placeholder : selected
            let address = "https://"
            let result = source.replacingCharacters(in: selection, with: "[" + title + "](" + address + ")")
            return (result, NSRange(location: selection.location + length(title) + 3, length: length(address)))
        }
    }

    /// Tâches d'une note : (ligne, cochée, texte)
    static func tasks(_ text: String) -> [(line: Int, done: Bool, text: String)] {
        blocks(text).compactMap { block in
            if case let .task(line, done, text) = block { return (line, done, text) }
            return nil
        }
    }

    /// Première ligne lisible d'une note, sans les marques de Markdown (pour les titres et les listes)
    static func title(_ text: String) -> String {
        for block in blocks(text) {
            switch block {
            case let .heading(_, text), let .paragraph(text), let .bullet(text), let .quote(text), let .code(text):
                let first = text.components(separatedBy: "\n").first ?? text
                let plain = first.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
                if !plain.isEmpty { return plain }
            case let .task(_, _, text):
                if !text.isEmpty { return text }
            }
        }
        return ""
    }
}
