import Foundation
import PDFKit

struct ExtractedDocumentSection: Hashable {
    var locator: String
    var text: String
}

struct ExtractedDocumentText {
    var sections: [ExtractedDocumentSection]
    var format: String

    var text: String {
        sections.map { "[\($0.locator)]\n\($0.text)" }.joined(separator: "\n\n")
    }
}

struct DocumentTextExtractor {
    enum ExtractionError: LocalizedError {
        case unsupportedFormat
        case emptyText
        case zipExtractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "暂不支持该文件类型"
            case .emptyText: return "未提取到可总结文本"
            case .zipExtractionFailed(let path): return "无法从压缩文档中读取 \(path)"
            }
        }
    }

    let supportedExtensions: Set<String> = ["txt", "md", "pdf", "docx", "csv", "xlsx", "pptx"]

    func extract(from url: URL) throws -> ExtractedDocumentText {
        let ext = url.pathExtension.lowercased()
        let sections: [ExtractedDocumentSection]
        switch ext {
        case "txt", "md", "csv":
            sections = [.init(locator: "全文", text: try String(contentsOf: url, encoding: .utf8))]
        case "pdf":
            sections = try extractPDF(url)
        case "docx":
            sections = [.init(locator: "文档正文", text: XMLPlainTextExtractor.extract(from: try unzipEntry("word/document.xml", from: url)))]
        case "xlsx":
            sections = try extractXLSX(url)
        case "pptx":
            sections = try extractPPTX(url)
        default:
            throw ExtractionError.unsupportedFormat
        }
        return try result(sections: sections, format: ext)
    }

    private func result(sections: [ExtractedDocumentSection], format: String) throws -> ExtractedDocumentText {
        var remaining = 200_000
        let cleaned = sections.compactMap { section -> ExtractedDocumentSection? in
            guard remaining > 0 else { return nil }
            let normalized = normalize(section.text)
            guard !normalized.isEmpty else { return nil }
            let text = normalized.clipped(to: remaining)
            remaining -= text.count
            return .init(locator: section.locator, text: text)
        }
        guard cleaned.reduce(0, { $0 + $1.text.count }) >= 20 else { throw ExtractionError.emptyText }
        return ExtractedDocumentText(sections: cleaned, format: format)
    }

    private func extractPDF(_ url: URL) throws -> [ExtractedDocumentSection] {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.emptyText }
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index)?.string.map { .init(locator: "第 \(index + 1) 页", text: $0) }
        }
    }

    private func extractXLSX(_ url: URL) throws -> [ExtractedDocumentSection] {
        let sharedStrings: [String]
        if let xml = try? unzipEntry("xl/sharedStrings.xml", from: url) {
            sharedStrings = XLSXSharedStringsExtractor.extract(from: xml)
        } else {
            sharedStrings = []
        }
        let entries = try zipEntries(from: url)
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
            .sorted()
        return entries.enumerated().compactMap { index, entry in
            guard let xml = try? unzipEntry(entry, from: url) else { return nil }
            return .init(
                locator: "Sheet \(index + 1)",
                text: XLSXWorksheetTextExtractor.extract(from: xml, sharedStrings: sharedStrings)
            )
        }
    }

    private func extractPPTX(_ url: URL) throws -> [ExtractedDocumentSection] {
        try zipEntries(from: url)
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted()
            .enumerated()
            .compactMap { index, entry in
                guard let xml = try? unzipEntry(entry, from: url) else { return nil }
                return .init(locator: "Slide \(index + 1)", text: XMLPlainTextExtractor.extract(from: xml))
            }
    }

    private func zipEntries(from url: URL) throws -> [String] {
        try runUnzip(arguments: ["-Z1", url.path], fallbackPath: "")
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
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExtractionError.zipExtractionFailed(fallbackPath) }
        return String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func normalize(_ text: String) -> String {
        text.components(separatedBy: .newlines)
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
        if !cleaned.isEmpty { parts.append(cleaned) }
    }
}

private final class XLSXSharedStringsExtractor: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentParts: [String] = []
    private var isInsideString = false
    private var isCapturingText = false

    static func extract(from xml: String) -> [String] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let extractor = XLSXSharedStringsExtractor()
        let parser = XMLParser(data: data)
        parser.delegate = extractor
        parser.parse()
        return extractor.strings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "si" {
            isInsideString = true
            currentParts = []
        } else if elementName == "t", isInsideString {
            isCapturingText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCapturingText { currentParts.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "t" {
            isCapturingText = false
        } else if elementName == "si" {
            strings.append(currentParts.joined())
            currentParts = []
            isInsideString = false
        }
    }
}

private final class XLSXWorksheetTextExtractor: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [String] = []
    private var currentRow: [String] = []
    private var currentCellType = ""
    private var currentValue = ""
    private var isCapturingValue = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func extract(from xml: String, sharedStrings: [String]) -> String {
        guard let data = xml.data(using: .utf8) else { return "" }
        let extractor = XLSXWorksheetTextExtractor(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = extractor
        parser.parse()
        return extractor.rows.joined(separator: "\n")
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "row" {
            currentRow = []
        } else if elementName == "c" {
            currentCellType = attributeDict["t"] ?? ""
            currentValue = ""
        } else if elementName == "v" || (elementName == "t" && currentCellType == "inlineStr") {
            isCapturingValue = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCapturingValue { currentValue += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "v" || elementName == "t" {
            isCapturingValue = false
        } else if elementName == "c" {
            let value: String
            if currentCellType == "s",
               let index = Int(currentValue),
               sharedStrings.indices.contains(index) {
                value = sharedStrings[index]
            } else {
                value = currentValue
            }
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentRow.append(value)
            }
        } else if elementName == "row", !currentRow.isEmpty {
            rows.append(currentRow.joined(separator: "\t"))
        }
    }
}
