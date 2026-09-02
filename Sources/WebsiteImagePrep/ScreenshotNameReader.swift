import CoreGraphics
import Foundation
import Vision

enum ScreenshotNameReader {
    enum RecognitionError: LocalizedError {
        case invalidImage
        case noText

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "The screenshot could not be read."
            case .noText:
                return "No readable names were found in the screenshot. Try a clearer or larger screenshot."
            }
        }
    }

    static func recognizeRows(in cgImage: CGImage) throws -> [[String]] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let items: [RecognizedItem] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return RecognizedItem(text: cleanOCRLine(text), box: observation.boundingBox)
        }
        guard !items.isEmpty else { throw RecognitionError.noText }
        return groupedRows(items)
    }

    private struct RecognizedItem {
        let text: String
        let box: CGRect
        var centerY: CGFloat { box.midY }
    }

    private static func groupedRows(_ items: [RecognizedItem]) -> [[String]] {
        let sorted = items.sorted {
            if abs($0.centerY - $1.centerY) > 0.012 { return $0.centerY > $1.centerY }
            return $0.box.minX < $1.box.minX
        }
        var groups: [[RecognizedItem]] = []

        for item in sorted {
            if let last = groups.indices.last {
                let averageY = groups[last].map(\.centerY).reduce(0, +) / CGFloat(groups[last].count)
                let averageHeight = groups[last].map { $0.box.height }.reduce(0, +) / CGFloat(groups[last].count)
                let tolerance = max(max(averageHeight * 0.55, item.box.height * 0.55), 0.012)
                if abs(averageY - item.centerY) <= tolerance {
                    groups[last].append(item)
                    continue
                }
            }
            groups.append([item])
        }

        return groups.map { group in
            group.sorted { $0.box.minX < $1.box.minX }.map(\.text)
        }
    }

    private static func cleanOCRLine(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"^\s*[•●▪︎\-]?\s*\d+[\.)\-:]\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
