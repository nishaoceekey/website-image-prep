import Foundation

enum CSVParser {
    struct RenameData {
        var mapping: [String: String]
        var orderedNames: [String]
    }

    static func parse(_ text: String) -> RenameData {
        renameData(from: parseRows(text))
    }

    static func renameData(from inputRows: [[String]]) -> RenameData {
        var rows = inputRows
            .map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { row in row.contains { !$0.isEmpty } }

        guard !rows.isEmpty else {
            return RenameData(mapping: [:], orderedNames: [])
        }

        var originalIndex = 0
        var renamedIndex = rows[0].count > 1 ? 1 : 0

        if looksLikeHeader(rows[0]) {
            let header = rows.removeFirst().map { $0.lowercased() }
            originalIndex = header.firstIndex(where: {
                $0.contains("original") || $0.contains("source") || $0 == "file" || $0 == "filename"
            }) ?? 0
            renamedIndex = header.firstIndex(where: {
                $0.contains("new") || $0.contains("rename") || $0.contains("output") || $0.contains("product")
            }) ?? min(1, max(0, header.count - 1))
        }

        var mapping: [String: String] = [:]
        var orderedNames: [String] = []

        for row in rows {
            guard !row.isEmpty else { continue }
            if row.count == 1 {
                if let name = cleanOutputName(row[0]) {
                    orderedNames.append(name)
                }
                continue
            }

            guard originalIndex < row.count, renamedIndex < row.count,
                  let output = cleanOutputName(row[renamedIndex]) else { continue }

            let original = normalizedLookupName(row[originalIndex])
            if !original.isEmpty {
                mapping[original] = output
                mapping[(original as NSString).deletingPathExtension.lowercased()] = output
            }
            orderedNames.append(output)
        }

        return RenameData(mapping: mapping, orderedNames: orderedNames)
    }

    static func normalizedLookupName(_ value: String) -> String {
        URL(fileURLWithPath: value).lastPathComponent.lowercased()
    }

    static func cleanOutputName(_ value: String) -> String? {
        var name = URL(fileURLWithPath: value).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        name = name.components(separatedBy: invalid).joined(separator: "-")
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !name.isEmpty else { return nil }

        let ext = (name as NSString).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "psd"].contains(ext) {
            name = (name as NSString).deletingPathExtension
        }
        return name + ".jpg"
    }

    private static func looksLikeHeader(_ row: [String]) -> Bool {
        let joined = row.joined(separator: " ").lowercased()
        return ["original", "source", "filename", "new", "rename", "output"].contains {
            joined.contains($0)
        }
    }

    private static func parseRows(_ text: String) -> [[String]] {
        let sampleLine = text.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? ""
        let commaCount = sampleLine.filter { $0 == "," }.count
        let tabCount = sampleLine.filter { $0 == "\t" }.count
        let semicolonCount = sampleLine.filter { $0 == ";" }.count
        let delimiter: Character
        if tabCount > commaCount, tabCount >= semicolonCount {
            delimiter = "\t"
        } else if semicolonCount > commaCount {
            delimiter = ";"
        } else {
            delimiter = ","
        }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if insideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if character == delimiter, !insideQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !insideQuotes {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
