import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var images: [PreparedImage] = []
    @Published var selectedID: UUID?
    @Published var canvasWidth = 800
    @Published var canvasHeight = 800
    @Published var dimensionsLinked = true
    @Published var preset: CanvasPreset = .website800
    @Published var maximumMB = 2.0
    @Published var outputFormats: Set<OutputFormat> = [.jpeg]
    @Published var clarityLevel: ClarityLevel = .clear
    @Published var doNotEnlargeSmallImages = false
    @Published var namingStrategy: NamingStrategy = .original
    @Published var sequentialPrefix = "product"
    @Published var outputFolder: URL?
    @Published var csvStatus: String?
    @Published var isReadingNames = false
    @Published var renameReviewRows: [RenameReviewRow] = []
    @Published var renameReviewSource = ""
    @Published var showingRenameReview = false
    @Published var isExporting = false
    @Published var exportProgress = 0.0
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var showingAlert = false

    private static let supportedExtensions = Set(["png", "jpg", "jpeg", "psd", "tif", "tiff", "heic", "heif", "webp", "gif", "bmp"])
    private static let namingExtensions = Set(["csv", "tsv", "txt", "xlsx", "xls"])
    private var pendingRenameData: CSVParser.RenameData?
    private var pendingRenameSource = ""
    private var pendingReviewWorkItem: DispatchWorkItem?

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return images.firstIndex { $0.id == selectedID }
    }

    var selectedImage: PreparedImage? {
        guard let selectedIndex else { return nil }
        return images[selectedIndex]
    }

    var selectedImageBinding: Binding<PreparedImage>? {
        guard let id = selectedID, images.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                guard let self, let index = self.images.firstIndex(where: { $0.id == id }) else {
                    fatalError("Selected image no longer exists")
                }
                return self.images[index]
            },
            set: { [weak self] newValue in
                guard let self, let index = self.images.firstIndex(where: { $0.id == id }) else { return }
                self.images[index] = newValue
            }
        )
    }

    var matchedRenameCount: Int {
        images.filter { $0.csvFilename != nil }.count
    }

    var exportFileCount: Int {
        images.count * outputFormats.count
    }

    var outputFormatSummary: String {
        OutputFormat.allCases
            .filter { outputFormats.contains($0) }
            .map(\.rawValue)
            .joined(separator: " + ")
    }

    var selectedClarityMessage: String? {
        guard let item = selectedImage else { return nil }
        let sourceWidth = max(item.pixelSize.width, 1)
        let sourceHeight = max(item.pixelSize.height, 1)
        var scale = min(CGFloat(canvasWidth) / sourceWidth, CGFloat(canvasHeight) / sourceHeight)
        if doNotEnlargeSmallImages { scale = min(scale, 1) }
        scale *= CGFloat(item.zoom)

        if scale > 1.05 {
            return "Clarity warning: this image is enlarged to \(Int((scale * 100).rounded()))%. Enlarging cannot create missing detail."
        }
        if scale < 0.5 {
            return "Clarity note: this image is reduced to \(Int((scale * 100).rounded()))%. Very small text may soften at \(canvasWidth) × \(canvasHeight) px."
        }
        return "Clarity check: source resolution is suitable for this output size."
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Choose Images or Folders"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    func addURLs(_ urls: [URL]) {
        let fileURLs = expandedImageURLs(urls)
        let existing = Set(images.map { $0.url.standardizedFileURL.path })
        var additions: [PreparedImage] = []
        var failed: [String] = []

        for url in fileURLs where !existing.contains(url.standardizedFileURL.path) {
            if let item = loadImage(url) {
                additions.append(item)
            } else {
                failed.append(url.lastPathComponent)
            }
        }

        images.append(contentsOf: additions)
        if selectedID == nil {
            selectedID = images.first?.id
        }
        if outputFolder == nil, let first = images.first {
            outputFolder = first.url.deletingLastPathComponent().appendingPathComponent("Website Images", isDirectory: true)
        }
        if !failed.isEmpty {
            showAlert(title: "Some files were skipped", message: failed.joined(separator: "\n"))
        }
        if !additions.isEmpty {
            schedulePendingRenameReview()
        }
    }

    func handleIncomingURLs(_ urls: [URL]) {
        let namingFiles = urls.filter {
            Self.namingExtensions.contains($0.pathExtension.lowercased())
        }
        let imageFilesAndFolders = urls.filter {
            !Self.namingExtensions.contains($0.pathExtension.lowercased())
        }

        if !imageFilesAndFolders.isEmpty {
            addURLs(imageFilesAndFolders)
        }
        if let namingFile = namingFiles.first {
            importRenameSource(namingFile)
        }
        if namingFiles.count > 1 {
            showAlert(
                title: "One naming file imported",
                message: "Only one CSV, TSV, text, or Excel naming file can be active at a time. \(namingFiles[0].lastPathComponent) was imported."
            )
        }
    }

    func remove(_ id: UUID) {
        images.removeAll { $0.id == id }
        if selectedID == id { selectedID = images.first?.id }
    }

    func clearAll() {
        pendingReviewWorkItem?.cancel()
        pendingReviewWorkItem = nil
        pendingRenameData = nil
        pendingRenameSource = ""
        images.removeAll()
        selectedID = nil
        csvStatus = nil
    }

    func setCanvasWidth(_ newValue: Int) {
        let value = min(max(newValue, 1), 12_000)
        if dimensionsLinked, canvasWidth > 0 {
            let ratio = Double(canvasHeight) / Double(canvasWidth)
            canvasHeight = min(max(Int((Double(value) * ratio).rounded()), 1), 12_000)
        }
        canvasWidth = value
        preset = matchingPreset() ?? .custom
    }

    func setCanvasHeight(_ newValue: Int) {
        let value = min(max(newValue, 1), 12_000)
        if dimensionsLinked, canvasHeight > 0 {
            let ratio = Double(canvasWidth) / Double(canvasHeight)
            canvasWidth = min(max(Int((Double(value) * ratio).rounded()), 1), 12_000)
        }
        canvasHeight = value
        preset = matchingPreset() ?? .custom
    }

    func applyPreset(_ newPreset: CanvasPreset) {
        preset = newPreset
        if let dimensions = newPreset.dimensions {
            canvasWidth = dimensions.0
            canvasHeight = dimensions.1
        }
    }

    func setOutputFormat(_ format: OutputFormat, enabled: Bool) {
        if enabled {
            outputFormats.insert(format)
        } else if outputFormats.count > 1 {
            outputFormats.remove(format)
        }
    }

    func displayCSVFilename(for item: PreparedImage) -> String? {
        guard let csvFilename = item.csvFilename else { return nil }
        let stem = (csvFilename as NSString).deletingPathExtension
        let extensions = OutputFormat.allCases
            .filter { outputFormats.contains($0) }
            .map(\.fileExtension)
        if extensions.count == 1, let ext = extensions.first {
            return "\(stem).\(ext)"
        }
        return "\(stem).{\(extensions.joined(separator: ","))}"
    }

    func chooseRenameFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Rename CSV or Excel File"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        var contentTypes: [UTType] = [.commaSeparatedText, .plainText]
        if let tsvType = UTType(filenameExtension: "tsv") {
            contentTypes.append(tsvType)
        }
        if let excelType = UTType(filenameExtension: "xlsx") {
            contentTypes.append(excelType)
        }
        if let legacyExcelType = UTType(filenameExtension: "xls") {
            contentTypes.append(legacyExcelType)
        }
        panel.allowedContentTypes = contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }

        importRenameSource(url)
    }

    func chooseCSV() {
        chooseRenameFile()
    }

    func importRenameSource(_ url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(fileExtension) {
            guard let image = NSImage(contentsOf: url) else {
                showAlert(title: "Could not read screenshot", message: "Choose a clear PNG, JPG, HEIC, or TIFF screenshot.")
                return
            }
            recognizeNames(in: image, source: "screenshot")
            return
        }

        if fileExtension == "xls" {
            showAlert(
                title: "Older Excel format",
                message: "Please open the .xls file in Excel and save it as .xlsx or CSV, then import it again."
            )
            return
        }

        isReadingNames = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data: CSVParser.RenameData
                let source: String
                if fileExtension == "xlsx" {
                    data = try XLSXParser.parse(url)
                    source = "Excel"
                } else {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    data = CSVParser.parse(text)
                    switch fileExtension {
                    case "tsv": source = "TSV"
                    case "txt": source = "text file"
                    default: source = "CSV"
                    }
                }
                DispatchQueue.main.async {
                    self.isReadingNames = false
                    self.prepareRenameReview(data, source: source)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isReadingNames = false
                    self.showAlert(title: "Could not import names", message: error.localizedDescription)
                }
            }
        }
    }

    func pasteNamingScreenshot() {
        let pasteboard = NSPasteboard.general
        let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        guard let data, let image = NSImage(data: data) else {
            showAlert(
                title: "No screenshot found",
                message: "Copy a screenshot to the clipboard, then click Paste Screenshot again."
            )
            return
        }
        recognizeNames(in: image, source: "pasted screenshot")
    }

    func recognizeNames(in image: NSImage, source: String) {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            showAlert(title: "Could not read screenshot", message: ScreenshotNameReader.RecognitionError.invalidImage.localizedDescription)
            return
        }
        isReadingNames = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let rows = try ScreenshotNameReader.recognizeRows(in: cgImage)
                let data = CSVParser.renameData(from: rows)
                DispatchQueue.main.async {
                    self.isReadingNames = false
                    self.prepareRenameReview(data, source: source)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isReadingNames = false
                    self.showAlert(title: "Could not read names", message: error.localizedDescription)
                }
            }
        }
    }

    func prepareRenameReview(_ data: CSVParser.RenameData, source: String) {
        guard !images.isEmpty else {
            pendingRenameData = data
            pendingRenameSource = source
            namingStrategy = .csv
            csvStatus = "Names imported from \(source) — add images to review"
            return
        }

        pendingRenameData = nil
        pendingRenameSource = ""
        var rows: [RenameReviewRow] = []
        for (index, image) in images.enumerated() {
            let full = CSVParser.normalizedLookupName(image.originalFilename)
            let base = (full as NSString).deletingPathExtension.lowercased()
            let proposed: String
            if let mapped = data.mapping[full] ?? data.mapping[base] {
                proposed = mapped
            } else if data.mapping.isEmpty, index < data.orderedNames.count {
                proposed = data.orderedNames[index]
            } else {
                proposed = ""
            }
            rows.append(RenameReviewRow(
                id: UUID(),
                imageID: image.id,
                originalFilename: image.originalFilename,
                newFilename: proposed
            ))
        }

        guard rows.contains(where: { !$0.newFilename.isEmpty }) else {
            showAlert(title: "No names found", message: "The \(source) did not contain any usable filenames.")
            return
        }
        renameReviewRows = rows
        renameReviewSource = source
        showingRenameReview = true
    }

    private func schedulePendingRenameReview() {
        guard pendingRenameData != nil else { return }
        pendingReviewWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyPendingRenameReviewIfPossible()
        }
        pendingReviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func applyPendingRenameReviewIfPossible() {
        guard let data = pendingRenameData, !images.isEmpty else { return }
        let source = pendingRenameSource
        pendingRenameData = nil
        pendingRenameSource = ""
        prepareRenameReview(data, source: source)
    }

    func applyRenameReview() {
        for row in renameReviewRows {
            guard let imageIndex = images.firstIndex(where: { $0.id == row.imageID }) else { continue }
            images[imageIndex].csvFilename = CSVParser.cleanOutputName(row.newFilename)
        }
        namingStrategy = .csv
        csvStatus = "\(matchedRenameCount) of \(images.count) names applied from \(renameReviewSource)"
        showingRenameReview = false
    }

    func cancelRenameReview() {
        showingRenameReview = false
        renameReviewRows = []
    }

    func applyRenameData(_ data: CSVParser.RenameData) {
        for index in images.indices {
            let full = CSVParser.normalizedLookupName(images[index].originalFilename)
            let base = (full as NSString).deletingPathExtension.lowercased()
            if let match = data.mapping[full] ?? data.mapping[base] {
                images[index].csvFilename = match
            } else if data.mapping.isEmpty, index < data.orderedNames.count {
                images[index].csvFilename = data.orderedNames[index]
            } else {
                images[index].csvFilename = nil
            }
        }
        csvStatus = "\(matchedRenameCount) of \(images.count) names matched"
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return }
        outputFolder = panel.url
    }

    func exportImages() {
        guard !images.isEmpty else {
            showAlert(title: "Add images first", message: "Drop images into the app or click Add Images.")
            return
        }
        guard (1...12_000).contains(canvasWidth), (1...12_000).contains(canvasHeight) else {
            showAlert(title: "Invalid canvas size", message: AppError.invalidDimensions.localizedDescription)
            return
        }
        guard !outputFormats.contains(.jpeg) || maximumMB > 0 else {
            showAlert(title: "Invalid JPEG limit", message: AppError.invalidMaximumSize.localizedDescription)
            return
        }
        guard let outputFolder else {
            chooseOutputFolder()
            guard self.outputFolder != nil else { return }
            exportImages()
            return
        }

        let snapshot = images
        let configuration = ExportConfiguration(
            width: canvasWidth,
            height: canvasHeight,
            maximumBytes: Int(maximumMB * 1_000_000),
            doNotEnlargeSmallImages: doNotEnlargeSmallImages,
            namingStrategy: namingStrategy,
            sequentialPrefix: sequentialPrefix,
            outputFormats: outputFormats,
            clarityLevel: clarityLevel
        )
        isExporting = true
        exportProgress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try ExportService.export(
                    images: snapshot,
                    to: outputFolder,
                    configuration: configuration
                ) { completed, total in
                    DispatchQueue.main.async {
                        self.exportProgress = Double(completed) / Double(max(total, 1))
                    }
                }
                DispatchQueue.main.async {
                    self.isExporting = false
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .file
                    let fileLines = result.files.prefix(8).map { file in
                        let size = formatter.string(fromByteCount: Int64(file.byteCount))
                        if let quality = file.jpegQuality {
                            return "\(file.filename): \(size), JPEG quality \(Int((quality * 100).rounded()))%"
                        }
                        return "\(file.filename): \(size)"
                    }
                    let extraCount = max(result.files.count - fileLines.count, 0)
                    let extraLine = extraCount > 0 ? "\n…and \(extraCount) more files" : ""
                    let maximumQualityBelowLimit = result.files.contains { file in
                        file.format == .jpeg &&
                        (file.jpegQuality ?? 0) >= 0.999 &&
                        file.byteCount < Int(Double(configuration.maximumBytes) * 0.9)
                    }
                    let qualityNote = maximumQualityBelowLimit
                        ? "\n\nMaximum JPEG quality was reached. A file can be much smaller than the MB limit when the canvas is small; adding empty bytes would not improve clarity."
                        : ""
                    let warningText = result.warnings.isEmpty ? "" : "\n\n" + result.warnings.joined(separator: "\n")
                    self.showAlert(
                        title: "Export complete",
                        message: "\(result.exportedFileCount) files from \(result.processedImageCount) images were saved to:\n\(result.outputFolder.path)\n\n\(fileLines.joined(separator: "\n"))\(extraLine)\(qualityNote)\(warningText)"
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showAlert(title: "Export stopped", message: error.localizedDescription)
                }
            }
        }
    }

    func revealOutputFolder() {
        guard let outputFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputFolder])
    }

    private func matchingPreset() -> CanvasPreset? {
        CanvasPreset.allCases.first { preset in
            guard let dimensions = preset.dimensions else { return false }
            return dimensions.0 == canvasWidth && dimensions.1 == canvasHeight
        }
    }

    private func expandedImageURLs(_ urls: [URL]) -> [URL] {
        var output: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let child as URL in enumerator where Self.supportedExtensions.contains(child.pathExtension.lowercased()) {
                        output.append(child)
                    }
                }
            } else if Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                output.append(url)
            }
        }
        return output.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func loadImage(_ url: URL) -> PreparedImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var pixelSize = image.size
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            if [5, 6, 7, 8].contains(orientation) {
                pixelSize = CGSize(width: height.doubleValue, height: width.doubleValue)
            } else {
                pixelSize = CGSize(width: width.doubleValue, height: height.doubleValue)
            }
        }
        return PreparedImage(url: url, image: image, pixelSize: pixelSize)
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}
