import AppKit
import Foundation
import ImageIO

enum SelfTest {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @MainActor
    static func run() throws {
        try runStage("CSV", testCSV)
        try runStage("Excel", testExcel)
        try runStage("pre-image import", testPreImageImport)
        try runStage("screenshot OCR", testScreenshotRecognition)
        try runStage("image encoding", testJPEG)
        try runStage("export naming", testExportNaming)
    }

    private static func runStage(_ name: String, _ test: () throws -> Void) throws {
        do {
            try test()
        } catch {
            let nsError = error as NSError
            throw Failure(message: "\(name) check failed: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription) — \(nsError.userInfo)")
        }
    }

    private static func testCSV() throws {
        let csv = "original_filename,new_filename\n\"IMG, 001.png\",\"blue bottle\"\nIMG_002.png,side-view.jpg\n"
        let parsed = CSVParser.parse(csv)
        try require(parsed.mapping["img, 001.png"] == "blue bottle.jpg", "CSV quoted-name mapping failed")
        try require(parsed.mapping["img_002.png"] == "side-view.jpg", "CSV two-column mapping failed")

        let ordered = CSVParser.parse("first product\nsecond product.jpg\n")
        try require(ordered.orderedNames == ["first product.jpg", "second product.jpg"], "CSV row-order mapping failed")

        let tsv = CSVParser.parse("original_filename\tnew_filename\nIMG_003.png\ttab-product\n")
        try require(tsv.mapping["img_003.png"] == "tab-product.jpg", "TSV mapping failed")

        let semicolonCSV = CSVParser.parse("original_filename;new_filename\nIMG_004.png;semicolon-product\n")
        try require(semicolonCSV.mapping["img_004.png"] == "semicolon-product.jpg", "Semicolon CSV mapping failed")
    }

    private static func testExcel() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebsiteImagePrep-XLSX-\(UUID().uuidString)")
        let workbookRoot = temporaryRoot.appendingPathComponent("contents")
        let worksheetFolder = workbookRoot.appendingPathComponent("xl/worksheets")
        let workbookURL = temporaryRoot.appendingPathComponent("rename-list.xlsx")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        try FileManager.default.createDirectory(at: worksheetFolder, withIntermediateDirectories: true)
        let sharedStrings = """
        <?xml version="1.0" encoding="UTF-8"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4">
          <si><t>original_filename</t></si><si><t>new_filename</t></si>
          <si><t>IMG_001.png</t></si><si><t>excel-product</t></si>
        </sst>
        """
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
          <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
          <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" t="s"><v>3</v></c></row>
        </sheetData></worksheet>
        """
        try Data(sharedStrings.utf8).write(to: workbookRoot.appendingPathComponent("xl/sharedStrings.xml"))
        try Data(sheet.utf8).write(to: worksheetFolder.appendingPathComponent("sheet1.xml"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", workbookURL.path, "."]
        process.currentDirectoryURL = workbookRoot
        try process.run()
        process.waitUntilExit()
        try require(process.terminationStatus == 0, "Could not create Excel test workbook")

        let parsed = try XLSXParser.parse(workbookURL)
        try require(parsed.mapping["img_001.png"] == "excel-product.jpg", "Excel rename mapping failed")
    }

    @MainActor
    private static func testPreImageImport() throws {
        let model = AppModel()
        let data = CSVParser.parse("queued-name-one\nqueued-name-two\n")
        model.prepareRenameReview(data, source: "CSV")
        try require(model.images.isEmpty, "Pre-image import unexpectedly added an image")
        try require(model.csvStatus == "Names imported from CSV — add images to review", "Pre-image import status was missing")
        try require(!model.showingRenameReview, "Review opened before images were available")

        let source = makeImage(width: 20, height: 20, color: .systemBlue)
        model.images = [PreparedImage(
            url: URL(fileURLWithPath: "/tmp/queued-image.png"),
            image: source,
            pixelSize: CGSize(width: 20, height: 20)
        )]
        model.applyPendingRenameReviewIfPossible()
        try require(model.showingRenameReview, "Queued names were not presented after images arrived")
        try require(model.renameReviewRows.first?.newFilename == "queued-name-one.jpg", "Queued name did not match the first image")
    }

    private static func testScreenshotRecognition() throws {
        let image = NSImage(size: NSSize(width: 1400, height: 500), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 76, weight: .medium),
                .foregroundColor: NSColor.black
            ]
            NSString(string: "product-one.jpg").draw(at: NSPoint(x: 60, y: 310), withAttributes: attributes)
            NSString(string: "product-two.jpg").draw(at: NSPoint(x: 60, y: 130), withAttributes: attributes)
            return true
        }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw Failure(message: "Could not create screenshot OCR test image")
        }
        let rows = try ScreenshotNameReader.recognizeRows(in: cgImage)
        let combined = rows.flatMap { $0 }.joined(separator: " ").lowercased()
        try require(combined.contains("product"), "Screenshot name recognition failed")
    }

    private static func testJPEG() throws {
        let source = makeImage(width: 400, height: 200, color: .systemBlue)
        let item = PreparedImage(
            url: URL(fileURLWithPath: "/tmp/sample.png"),
            image: source,
            pixelSize: CGSize(width: 400, height: 200)
        )
        guard let data = ExportService.jpegData(
            for: item,
            width: 800,
            height: 800,
            maximumBytes: 2_000_000,
            doNotEnlarge: false
        ), let rep = NSBitmapImageRep(data: data) else {
            throw Failure(message: "JPEG encoding failed")
        }
        try require(data.count <= 2_000_000, "JPEG exceeded its size limit")
        try require(rep.pixelsWide == 800 && rep.pixelsHigh == 800, "JPEG dimensions were not exact")
        guard let fullQuality = ExportService.jpegEncoding(from: rep, maximumBytes: 2_000_000) else {
            throw Failure(message: "Maximum-quality JPEG encoding failed")
        }
        try require(fullQuality.quality == 1.0, "JPEG did not use 100% quality when it fit under the limit")

        guard let bitmap = ExportService.render(item, width: 800, height: 800, doNotEnlarge: false),
              let png = ExportService.pngData(from: bitmap),
              let psd = ExportService.psdData(from: bitmap) else {
            throw Failure(message: "PNG or PSD encoding failed")
        }
        try verifyDimensions(data: png, width: 800, height: 800, label: "PNG")
        try verifyDimensions(data: psd, width: 800, height: 800, label: "PSD")
        try require(String(data: psd.prefix(4), encoding: .ascii) == "8BPS", "PSD signature was invalid")
    }

    private static func testExportNaming() throws {
        let source = makeImage(width: 20, height: 20, color: .systemRed)
        var first = PreparedImage(url: URL(fileURLWithPath: "/tmp/a.png"), image: source, pixelSize: CGSize(width: 20, height: 20))
        var second = PreparedImage(url: URL(fileURLWithPath: "/tmp/b.png"), image: source, pixelSize: CGSize(width: 20, height: 20))
        first.csvFilename = "same.jpg"
        second.csvFilename = "same.jpg"

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WebsiteImagePrep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try ExportService.export(
            images: [first, second],
            to: folder,
            configuration: ExportConfiguration(
                width: 50,
                height: 50,
                maximumBytes: 100_000,
                doNotEnlargeSmallImages: false,
                namingStrategy: .csv,
                sequentialPrefix: "image",
                outputFormats: [.jpeg],
                clarityLevel: .clear
            ),
            progress: { _, _ in }
        )
        try require(result.processedImageCount == 2, "Batch image count was incorrect")
        try require(result.exportedFileCount == 2, "Batch export file count was incorrect")
        try require(FileManager.default.fileExists(atPath: folder.appendingPathComponent("same.jpg").path), "First export was missing")
        try require(FileManager.default.fileExists(atPath: folder.appendingPathComponent("same-2.jpg").path), "Duplicate-name protection failed")
    }

    private static func makeImage(width: Int, height: Int, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private static func verifyDimensions(data: Data, width: Int, height: Int, label: String) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw Failure(message: "\(label) could not be read back")
        }
        try require(pixelWidth.intValue == width && pixelHeight.intValue == height, "\(label) dimensions were not exact")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }
}
