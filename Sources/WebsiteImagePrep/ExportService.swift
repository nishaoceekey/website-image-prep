import AppKit
import CoreImage
import Foundation
import ImageIO

enum ExportService {
    struct JPEGEncoding {
        let data: Data
        let quality: Double
    }

    static func export(
        images: [PreparedImage],
        to folder: URL,
        configuration: ExportConfiguration,
        progress: @escaping (Int, Int) -> Void
    ) throws -> ExportResult {
        guard (1...12_000).contains(configuration.width),
              (1...12_000).contains(configuration.height) else {
            throw AppError.invalidDimensions
        }
        guard !configuration.outputFormats.contains(.jpeg) || configuration.maximumBytes > 0 else {
            throw AppError.invalidMaximumSize
        }
        guard !configuration.outputFormats.isEmpty else {
            throw AppError.cannotRender("No output format selected")
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var usedNames = Set<String>()
        var warnings: [String] = []
        var exportedFileCount = 0
        var exportedFiles: [ExportedFileDetail] = []

        for (index, item) in images.enumerated() {
            var capturedError: Error?
            autoreleasepool {
                do {
                    guard let bitmap = render(
                        item,
                        width: configuration.width,
                        height: configuration.height,
                        doNotEnlarge: configuration.doNotEnlargeSmallImages,
                        clarityLevel: configuration.clarityLevel
                    ) else {
                        throw AppError.cannotRender(item.originalFilename)
                    }

                    for format in OutputFormat.allCases where configuration.outputFormats.contains(format) {
                        let desiredName = filename(
                            for: item,
                            index: index,
                            format: format,
                            configuration: configuration
                        )
                        let uniqueName = uniqueFilename(desiredName, in: folder, usedNames: &usedNames)
                        if uniqueName != desiredName {
                            warnings.append("Existing or duplicate name \(desiredName) was exported as \(uniqueName).")
                        }

                        let data: Data?
                        var jpegQuality: Double?
                        switch format {
                        case .jpeg:
                            let encoding = jpegEncoding(from: bitmap, maximumBytes: configuration.maximumBytes)
                            data = encoding?.data
                            jpegQuality = encoding?.quality
                        case .png:
                            data = bitmap.representation(using: .png, properties: [:])
                        case .psd:
                            data = imageData(from: bitmap, typeIdentifier: "com.adobe.photoshop-image")
                        }

                        guard let data else {
                            if format == .jpeg {
                                throw AppError.cannotMeetFileSize(uniqueName)
                            }
                            throw AppError.cannotRender(uniqueName)
                        }
                        try data.write(to: folder.appendingPathComponent(uniqueName), options: .atomic)
                        exportedFileCount += 1
                        exportedFiles.append(ExportedFileDetail(
                            filename: uniqueName,
                            byteCount: data.count,
                            format: format,
                            jpegQuality: jpegQuality
                        ))
                    }
                } catch {
                    capturedError = error
                }
            }

            if let error = capturedError {
                throw error
            }
            progress(index + 1, images.count)
        }

        return ExportResult(
            processedImageCount: images.count,
            exportedFileCount: exportedFileCount,
            outputFolder: folder,
            warnings: warnings,
            files: exportedFiles
        )
    }

    static func jpegData(
        for item: PreparedImage,
        width: Int,
        height: Int,
        maximumBytes: Int,
        doNotEnlarge: Bool
    ) -> Data? {
        guard let bitmap = render(item, width: width, height: height, doNotEnlarge: doNotEnlarge) else {
            return nil
        }

        return jpegData(from: bitmap, maximumBytes: maximumBytes)
    }

    static func jpegData(from bitmap: NSBitmapImageRep, maximumBytes: Int) -> Data? {
        jpegEncoding(from: bitmap, maximumBytes: maximumBytes)?.data
    }

    static func jpegEncoding(from bitmap: NSBitmapImageRep, maximumBytes: Int) -> JPEGEncoding? {

        func encoded(_ quality: Double) -> Data? {
            bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }

        if let maximumQuality = encoded(1.0), maximumQuality.count <= maximumBytes {
            return JPEGEncoding(data: maximumQuality, quality: 1.0)
        }

        guard let minimum = encoded(0.08), minimum.count <= maximumBytes else {
            return nil
        }

        var best = minimum
        var bestQuality = 0.08
        var low = 0.08
        var high = 1.0
        for _ in 0..<14 {
            let quality = (low + high) / 2
            guard let candidate = encoded(quality) else { break }
            if candidate.count <= maximumBytes {
                best = candidate
                bestQuality = quality
                low = quality
            } else {
                high = quality
            }
        }
        return JPEGEncoding(data: best, quality: bestQuality)
    }

    static func pngData(from bitmap: NSBitmapImageRep) -> Data? {
        bitmap.representation(using: .png, properties: [:])
    }

    static func psdData(from bitmap: NSBitmapImageRep) -> Data? {
        imageData(from: bitmap, typeIdentifier: "com.adobe.photoshop-image")
    }

    private static func imageData(from bitmap: NSBitmapImageRep, typeIdentifier: String) -> Data? {
        guard let image = bitmap.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            typeIdentifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func render(
        _ item: PreparedImage,
        width: Int,
        height: Int,
        doNotEnlarge: Bool,
        clarityLevel: ClarityLevel = .clear
    ) -> NSBitmapImageRep? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(cgContext: cgContext, flipped: false)
        NSGraphicsContext.current = context
        context.imageInterpolation = NSImageInterpolation.high
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let sourceWidth = max(item.pixelSize.width, 1)
        let sourceHeight = max(item.pixelSize.height, 1)
        var fitScale = min(CGFloat(width) / sourceWidth, CGFloat(height) / sourceHeight)
        if doNotEnlarge {
            fitScale = min(fitScale, 1)
        }

        let actualScale = fitScale * CGFloat(item.zoom)
        let drawWidth = sourceWidth * actualScale
        let drawHeight = sourceHeight * actualScale
        let centerX = CGFloat(width) / 2 + CGFloat(item.offsetX) * CGFloat(width)
        let centerY = CGFloat(height) / 2 - CGFloat(item.offsetY) * CGFloat(height)
        let destination = NSRect(
            x: centerX - drawWidth / 2,
            y: centerY - drawHeight / 2,
            width: drawWidth,
            height: drawHeight
        )
        item.image.draw(
            in: destination,
            from: NSRect(origin: .zero, size: item.image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        cgContext.flush()
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = cgContext.makeImage() else { return nil }
        let finalImage = sharpen(cgImage, level: clarityLevel) ?? cgImage
        return NSBitmapImageRep(cgImage: finalImage)
    }

    private static func sharpen(_ image: CGImage, level: ClarityLevel) -> CGImage? {
        guard level.sharpness > 0 else { return image }
        let input = CIImage(cgImage: image)
        let filtered = input.applyingFilter(
            "CISharpenLuminance",
            parameters: [kCIInputSharpnessKey: level.sharpness]
        )
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(filtered, from: input.extent)
    }

    private static func filename(
        for item: PreparedImage,
        index: Int,
        format: OutputFormat,
        configuration: ExportConfiguration
    ) -> String {
        let jpegStyleName: String
        switch configuration.namingStrategy {
        case .original:
            let base = (item.originalFilename as NSString).deletingPathExtension
            jpegStyleName = CSVParser.cleanOutputName(base) ?? "image-\(index + 1).jpg"
        case .csv:
            if let name = item.csvFilename {
                jpegStyleName = name
            } else {
                let base = (item.originalFilename as NSString).deletingPathExtension
                jpegStyleName = CSVParser.cleanOutputName(base) ?? "image-\(index + 1).jpg"
            }
        case .sequential:
            let cleanedPrefix = CSVParser.cleanOutputName(configuration.sequentialPrefix)?
                .replacingOccurrences(of: ".jpg", with: "") ?? "image"
            jpegStyleName = String(format: "%@-%03d.jpg", cleanedPrefix, index + 1)
        }
        let stem = (jpegStyleName as NSString).deletingPathExtension
        return "\(stem).\(format.fileExtension)"
    }

    private static func uniqueFilename(_ requested: String, in folder: URL, usedNames: inout Set<String>) -> String {
        let lowercased = requested.lowercased()
        if !usedNames.contains(lowercased),
           !FileManager.default.fileExists(atPath: folder.appendingPathComponent(requested).path) {
            usedNames.insert(lowercased)
            return requested
        }

        let base = (requested as NSString).deletingPathExtension
        var number = 2
        while true {
            let candidate = "\(base)-\(number).jpg"
            if !usedNames.contains(candidate.lowercased()),
               !FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
                usedNames.insert(candidate.lowercased())
                return candidate
            }
            number += 1
        }
    }
}
