import Foundation

enum XLSXParser {
    enum XLSXError: LocalizedError {
        case invalidWorkbook
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidWorkbook:
                return "The Excel workbook could not be read. Please use an .xlsx file or save it as CSV."
            case .commandFailed(let detail):
                return detail
            }
        }
    }

    static func parse(_ url: URL) throws -> CSVParser.RenameData {
        let listingData = try unzip(arguments: ["-Z1", url.path])
        guard let listing = String(data: listingData, encoding: .utf8) else {
            throw XLSXError.invalidWorkbook
        }
        let sheets = listing
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.range(of: #"^xl/worksheets/sheet[0-9]+\.xml$"#, options: .regularExpression) != nil }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let firstSheet = sheets.first else { throw XLSXError.invalidWorkbook }

        var sharedStrings: [String] = []
        if listing.split(whereSeparator: \.isNewline).contains(where: { $0 == "xl/sharedStrings.xml" }) {
            let data = try unzip(arguments: ["-p", url.path, "xl/sharedStrings.xml"])
            let delegate = SharedStringsDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            guard parser.parse() else { throw parser.parserError ?? XLSXError.invalidWorkbook }
            sharedStrings = delegate.strings
        }

        let sheetData = try unzip(arguments: ["-p", url.path, firstSheet])
        let delegate = SheetDelegate(sharedStrings: sharedStrings)
        let parser = XMLParser(data: sheetData)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? XLSXError.invalidWorkbook }
        return CSVParser.renameData(from: delegate.rows)
    }

    private static func unzip(arguments: [String]) throws -> Data {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8) ?? "The Excel workbook could not be opened."
            throw XLSXError.commandFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }
}

private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var insideString = false
    private var insideText = false
    private var value = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" {
            insideString = true
            value = ""
        } else if elementName == "t", insideString {
            insideText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { value.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" {
            insideText = false
        } else if elementName == "si" {
            strings.append(value)
            insideString = false
        }
    }
}

private final class SheetDelegate: NSObject, XMLParserDelegate {
    let sharedStrings: [String]
    var rows: [[String]] = []

    private var cells: [Int: String] = [:]
    private var currentColumn = 0
    private var currentType = ""
    private var currentValue = ""
    private var insideCell = false
    private var collectingValue = false
    private var collectingInlineText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            cells = [:]
        case "c":
            insideCell = true
            currentType = attributeDict["t"] ?? ""
            currentValue = ""
            if let reference = attributeDict["r"] {
                currentColumn = Self.columnIndex(from: reference)
            }
        case "v":
            collectingValue = insideCell
        case "t":
            collectingInlineText = insideCell
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingValue || collectingInlineText { currentValue.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v":
            collectingValue = false
        case "t":
            collectingInlineText = false
        case "c":
            let value: String
            if currentType == "s", let index = Int(currentValue), sharedStrings.indices.contains(index) {
                value = sharedStrings[index]
            } else {
                value = currentValue
            }
            cells[currentColumn] = value
            currentColumn += 1
            insideCell = false
        case "row":
            if let maximumColumn = cells.keys.max() {
                var row = Array(repeating: "", count: maximumColumn + 1)
                for (column, value) in cells { row[column] = value }
                rows.append(row)
            }
        default:
            break
        }
    }

    private static func columnIndex(from reference: String) -> Int {
        var value = 0
        for scalar in reference.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { break }
            value = value * 26 + Int(scalar.value - 64)
        }
        return max(value - 1, 0)
    }
}
