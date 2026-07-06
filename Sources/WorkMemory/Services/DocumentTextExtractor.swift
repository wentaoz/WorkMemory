import Foundation
import PDFKit

struct ExtractedDocumentText {
    var text: String
    var format: String
}

struct DocumentTextExtractor {
    enum ExtractionError: LocalizedError {
        case unsupportedFormat
        case emptyText
        case zipExtractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "暂不支持该文件类型"
            case .emptyText:
                return "未提取到可总结文本"
            case .zipExtractionFailed(let path):
                return "无法从压缩文档中读取 \(path)"
            }
        }
    }

    let supportedExtensions: Set<String> = ["txt", "md", "pdf", "docx", "csv", "xlsx", "pptx"]

    func extract(from url: URL) throws -> ExtractedDocumentText {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "txt", "md", "csv":
            let text = try String(contentsOf: url, encoding: .utf8)
            return try result(text: text, format: ext)
        case "pdf":
            return try result(text: extractPDF(url), format: ext)
        case "docx":
            return try result(text: extractDOCX(url), format: ext)
        case "xlsx":
            return try result(text: extractXLSX(url), format: ext)
        case "pptx":
            return try result(text: extractPPTX(url), format: ext)
        default:
            throw ExtractionError.unsupportedFormat
        }
    }

    private func result(text: String, format: String) throws -> ExtractedDocumentText {
        let cleaned = normalize(text)
        guard cleaned.count >= 20 else { throw ExtractionError.emptyText }
        return ExtractedDocumentText(text: cleaned.clipped(to: 40_000), format: format)
    }

    private func extractPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.emptyText
        }

        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
    }

    private func extractDOCX(_ url: URL) throws -> String {
        let xml = try unzipEntry("word/document.xml", from: url)
        return XMLPlainTextExtractor.extract(from: xml)
    }

    private func extractXLSX(_ url: URL) throws -> String {
        if let sharedStrings = try? unzipEntry("xl/sharedStrings.xml", from: url) {
            return XMLPlainTextExtractor.extract(from: sharedStrings)
        }

        let worksheetEntries = try zipEntries(from: url)
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
            .sorted()

        let sheetTexts = worksheetEntries.compactMap { entry -> String? in
            guard let xml = try? unzipEntry(entry, from: url) else { return nil }
            return XMLPlainTextExtractor.extract(from: xml)
        }

        return sheetTexts.joined(separator: "\n\n")
    }

    private func extractPPTX(_ url: URL) throws -> String {
        let slideEntries = try zipEntries(from: url)
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted()

        let slideTexts = slideEntries.enumerated().compactMap { index, entry -> String? in
            guard let xml = try? unzipEntry(entry, from: url) else { return nil }
            let text = XMLPlainTextExtractor.extract(from: xml)
            guard !text.isEmpty else { return nil }
            return "Slide \(index + 1)\n\(text)"
        }

        return slideTexts.joined(separator: "\n\n")
    }

    private func zipEntries(from url: URL) throws -> [String] {
        let output = try runUnzip(arguments: ["-Z1", url.path], fallbackPath: "")
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func unzipEntry(_ entry: String, from url: URL) throws -> String {
        try runUnzip(arguments: ["-p", url.path, entry], fallbackPath: entry)
    }

    private func runUnzip(arguments: [String], fallbackPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExtractionError.zipExtractionFailed(fallbackPath)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func normalize(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private final class XMLPlainTextExtractor: NSObject, XMLParserDelegate {
    private var parts: [String] = []

    static func extract(from xml: String) -> String {
        guard let data = xml.data(using: .utf8) else { return "" }
        let extractor = XMLPlainTextExtractor()
        let parser = XMLParser(data: data)
        parser.delegate = extractor
        parser.parse()
        return extractor.parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        parts.append(cleaned)
    }
}
