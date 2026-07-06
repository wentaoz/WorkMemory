import CoreGraphics
import Foundation
import Vision

struct OCRResult {
    var text: String
    var lineCount: Int
}

struct WindowOCRService {
    func recognizeText(in context: ActiveAppContext) -> OCRResult? {
        guard let windowID = context.windowID else { return nil }
        guard let image = captureWindowImage(windowID: windowID) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let lines = (request.results ?? [])
            .compactMap { observation in
                observation.topCandidates(1).first?.string.nilIfBlank
            }

        let text = merge(lines: lines)
        guard text.count >= 40 else { return nil }

        return OCRResult(text: text, lineCount: lines.count)
    }

    private func captureWindowImage(windowID: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    private func merge(lines: [String]) -> String {
        var seen = Set<String>()
        var merged: [String] = []

        for line in lines {
            let normalized = line
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()

            guard normalized.count > 1, !seen.contains(normalized) else { continue }

            seen.insert(normalized)
            merged.append(line)
        }

        return merged.joined(separator: "\n")
    }
}
