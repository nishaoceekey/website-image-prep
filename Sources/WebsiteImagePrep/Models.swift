import AppKit
import Foundation

struct PreparedImage: Identifiable, @unchecked Sendable {
    let id: UUID
    let url: URL
    let originalFilename: String
    let image: NSImage
    let pixelSize: CGSize
    var zoom: Double
    var offsetX: Double
    var offsetY: Double
    var csvFilename: String?

    init(url: URL, image: NSImage, pixelSize: CGSize) {
        id = UUID()
        self.url = url
        originalFilename = url.lastPathComponent
        self.image = image
        self.pixelSize = pixelSize
        zoom = 1
        offsetX = 0
        offsetY = 0
        csvFilename = nil
    }
}

enum NamingStrategy: String, CaseIterable, Identifiable {
    case original = "Keep original names"
    case csv = "Use imported names"
    case sequential = "Sequential names"

    var id: String { rawValue }
}

enum OutputFormat: String, CaseIterable, Identifiable, Hashable {
    case jpeg = "JPEG"
    case png = "PNG"
    case psd = "PSD"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .psd: return "psd"
        }
    }
}

enum ClarityLevel: String, CaseIterable, Identifiable {
    case natural = "Natural"
    case clear = "Clear"
    case extraSharp = "Extra Sharp"

    var id: String { rawValue }

    var sharpness: Double {
        switch self {
        case .natural: return 0
        case .clear: return 0.35
        case .extraSharp: return 0.7
        }
    }
}

enum CanvasPreset: String, CaseIterable, Identifiable {
    case website800 = "Website 800 × 800"
    case square1200 = "Square 1200 × 1200"
    case square1600 = "Square 1600 × 1600"
    case custom = "Custom"

    var id: String { rawValue }

    var dimensions: (Int, Int)? {
        switch self {
        case .website800: return (800, 800)
        case .square1200: return (1200, 1200)
        case .square1600: return (1600, 1600)
        case .custom: return nil
        }
    }
}

struct ExportConfiguration {
    let width: Int
    let height: Int
    let maximumBytes: Int
    let doNotEnlargeSmallImages: Bool
    let namingStrategy: NamingStrategy
    let sequentialPrefix: String
    let outputFormats: Set<OutputFormat>
    let clarityLevel: ClarityLevel
}

struct ExportedFileDetail {
    let filename: String
    let byteCount: Int
    let format: OutputFormat
    let jpegQuality: Double?
}

struct RenameReviewRow: Identifiable {
    let id: UUID
    let imageID: UUID
    let originalFilename: String
    var newFilename: String
}

struct ExportResult {
    let processedImageCount: Int
    let exportedFileCount: Int
    let outputFolder: URL
    let warnings: [String]
    let files: [ExportedFileDetail]
}

enum AppError: LocalizedError {
    case invalidImage(URL)
    case invalidDimensions
    case invalidMaximumSize
    case cannotRender(String)
    case cannotMeetFileSize(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage(let url):
            return "Could not read \(url.lastPathComponent)."
        case .invalidDimensions:
            return "Width and height must be between 1 and 12,000 pixels."
        case .invalidMaximumSize:
            return "The JPEG size limit must be greater than 0 MB."
        case .cannotRender(let filename):
            return "Could not render \(filename)."
        case .cannotMeetFileSize(let filename):
            return "\(filename) cannot fit under the selected size limit while keeping the exact pixel dimensions. Increase the MB limit."
        }
    }
}
