import Foundation

enum WordDocumentExportError: LocalizedError {
    case zipFailed

    var errorDescription: String? {
        switch self {
        case .zipFailed:
            return "生成 Word 文档失败"
        }
    }
}

struct WordDocumentExportService {
    static func export(item: MemoryItem, to outputURL: URL) throws {
        let fileManager = FileManager.default
        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("WorkMemoryDocx-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        try createPackage(for: item, at: workspaceURL)

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workspaceURL
        process.arguments = [
            "-qr",
            outputURL.path,
            "[Content_Types].xml",
            "_rels",
            "docProps",
            "word"
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WordDocumentExportError.zipFailed
        }
    }

    static func defaultFileName(for item: MemoryItem) -> String {
        let cleaned = item.title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let title = cleaned.isEmpty ? "WorkMemory AI 总结" : cleaned.clipped(to: 48)
        return "\(title).docx"
    }

    private static func createPackage(for item: MemoryItem, at rootURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("_rels", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("docProps", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("word/_rels", isDirectory: true), withIntermediateDirectories: true)

        try write(contentTypesXML, to: rootURL.appendingPathComponent("[Content_Types].xml"))
        try write(rootRelationshipsXML, to: rootURL.appendingPathComponent("_rels/.rels"))
        try write(corePropertiesXML(for: item), to: rootURL.appendingPathComponent("docProps/core.xml"))
        try write(appPropertiesXML, to: rootURL.appendingPathComponent("docProps/app.xml"))
        try write(documentRelationshipsXML, to: rootURL.appendingPathComponent("word/_rels/document.xml.rels"))
        try write(stylesXML, to: rootURL.appendingPathComponent("word/styles.xml"))
        try write(numberingXML, to: rootURL.appendingPathComponent("word/numbering.xml"))
        try write(documentXML(for: item), to: rootURL.appendingPathComponent("word/document.xml"))
    }

    private static func documentXML(for item: MemoryItem) -> String {
        let paragraphs = documentParagraphs(for: item).joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraphs)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func documentParagraphs(for item: MemoryItem) -> [String] {
        var paragraphs: [String] = [
            paragraph(item.title, style: "Title"),
            paragraph("导出时间：\(DateFormatting.dateTime.string(from: Date()))", style: "Subtitle"),
            paragraph("记录时间：\(DateFormatting.dateTime.string(from: item.createdAt))", style: "Meta")
        ]

        if let summary = item.context?.summary, !summary.isEmpty {
            paragraphs.append(paragraph("来源：\(summary)", style: "Meta"))
        }

        paragraphs.append(emptyParagraph)

        let lines = item.content.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                paragraphs.append(emptyParagraph)
                index += 1
            } else if isMarkdownTableStart(lines: lines, index: index) {
                let parsedTable = parseMarkdownTable(lines: lines, startIndex: index)
                paragraphs.append(tableXML(rows: parsedTable.rows))
                index = parsedTable.nextIndex
            } else if line.hasPrefix("### ") {
                paragraphs.append(paragraph(String(line.dropFirst(4)), style: "Heading3"))
                index += 1
            } else if line.hasPrefix("## ") {
                paragraphs.append(paragraph(String(line.dropFirst(3)), style: "Heading2"))
                index += 1
            } else if line.hasPrefix("# ") {
                paragraphs.append(paragraph(String(line.dropFirst(2)), style: "Heading1"))
                index += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                paragraphs.append(listParagraph(String(line.dropFirst(2)), numID: 1))
                index += 1
            } else if let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression),
                      range.lowerBound == line.startIndex {
                paragraphs.append(listParagraph(String(line[range.upperBound...]), numID: 2))
                index += 1
            } else {
                paragraphs.append(paragraph(cleanMarkdown(line), style: "Normal"))
                index += 1
            }
        }

        return paragraphs
    }

    private static func isMarkdownTableStart(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }

        let headerCells = markdownTableCells(from: lines[index])
        let separatorCells = markdownTableCells(from: lines[index + 1])

        guard headerCells.count >= 2, separatorCells.count == headerCells.count else {
            return false
        }

        return separatorCells.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func parseMarkdownTable(lines: [String], startIndex: Int) -> (rows: [[String]], nextIndex: Int) {
        var rows: [[String]] = [markdownTableCells(from: lines[startIndex])]
        var index = startIndex + 2

        while index < lines.count {
            let cells = markdownTableCells(from: lines[index])
            guard cells.count >= 2 else { break }
            rows.append(cells)
            index += 1
        }

        let columnCount = rows.map(\.count).max() ?? 0
        let normalizedRows = rows.map { row in
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }

        return (normalizedRows, index)
    }

    private static func markdownTableCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else { return [] }

        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }

        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func tableXML(rows: [[String]]) -> String {
        guard let columnCount = rows.first?.count, columnCount > 0 else {
            return emptyParagraph
        }

        let tableWidth = 9_360
        let columnWidth = tableWidth / columnCount
        let grid = Array(repeating: "<w:gridCol w:w=\"\(columnWidth)\"/>", count: columnCount).joined()
        let tableRows = rows.enumerated().map { rowIndex, row in
            tableRowXML(cells: row, width: columnWidth, isHeader: rowIndex == 0)
        }.joined(separator: "\n")

        return """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="\(tableWidth)" w:type="dxa"/>
            <w:tblLayout w:type="fixed"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="6" w:space="0" w:color="D0D5DD"/>
              <w:left w:val="single" w:sz="6" w:space="0" w:color="D0D5DD"/>
              <w:bottom w:val="single" w:sz="6" w:space="0" w:color="D0D5DD"/>
              <w:right w:val="single" w:sz="6" w:space="0" w:color="D0D5DD"/>
              <w:insideH w:val="single" w:sz="6" w:space="0" w:color="EAECF0"/>
              <w:insideV w:val="single" w:sz="6" w:space="0" w:color="EAECF0"/>
            </w:tblBorders>
            <w:tblCellMar>
              <w:top w:w="120" w:type="dxa"/>
              <w:left w:w="140" w:type="dxa"/>
              <w:bottom w:w="120" w:type="dxa"/>
              <w:right w:w="140" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid>\(grid)</w:tblGrid>
          \(tableRows)
        </w:tbl>
        <w:p/>
        """
    }

    private static func tableRowXML(cells: [String], width: Int, isHeader: Bool) -> String {
        let cellXML = cells.map { tableCellXML(text: $0, width: width, isHeader: isHeader) }.joined(separator: "\n")

        return """
        <w:tr>
          \(cellXML)
        </w:tr>
        """
    }

    private static func tableCellXML(text: String, width: Int, isHeader: Bool) -> String {
        let shading = isHeader ? #"<w:shd w:val="clear" w:color="auto" w:fill="EEF4FF"/>"# : ""
        let bold = isHeader ? "<w:b/>" : ""
        let color = isHeader ? "1D4ED8" : "101828"

        return """
        <w:tc>
          <w:tcPr>
            <w:tcW w:w="\(width)" w:type="dxa"/>
            <w:vAlign w:val="center"/>
            \(shading)
          </w:tcPr>
          <w:p>
            <w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>
            <w:r>
              <w:rPr>\(bold)<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="PingFang SC"/><w:sz w:val="20"/><w:color w:val="\(color)"/></w:rPr>
              <w:t xml:space="preserve">\(escapeXML(cleanMarkdown(text)))</w:t>
            </w:r>
          </w:p>
        </w:tc>
        """
    }

    private static func paragraph(_ text: String, style: String) -> String {
        """
        <w:p>
          <w:pPr><w:pStyle w:val="\(style)"/></w:pPr>
          <w:r><w:t xml:space="preserve">\(escapeXML(cleanMarkdown(text)))</w:t></w:r>
        </w:p>
        """
    }

    private static func listParagraph(_ text: String, numID: Int) -> String {
        """
        <w:p>
          <w:pPr>
            <w:pStyle w:val="ListParagraph"/>
            <w:numPr><w:ilvl w:val="0"/><w:numId w:val="\(numID)"/></w:numPr>
          </w:pPr>
          <w:r><w:t xml:space="preserve">\(escapeXML(cleanMarkdown(text)))</w:t></w:r>
        </w:p>
        """
    }

    private static var emptyParagraph: String {
        "<w:p/>"
    }

    private static func cleanMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func corePropertiesXML(for item: MemoryItem) -> String {
        let isoFormatter = ISO8601DateFormatter()
        let now = isoFormatter.string(from: Date())

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escapeXML(item.title))</dc:title>
          <dc:creator>WorkMemory</dc:creator>
          <cp:lastModifiedBy>WorkMemory</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private static func write(_ content: String, to url: URL) throws {
        try content.data(using: .utf8)?.write(to: url)
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
      <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let documentRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
    </Relationships>
    """

    private static let appPropertiesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
      <Application>WorkMemory</Application>
    </Properties>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
        <w:name w:val="Normal"/>
        <w:qFormat/>
        <w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>
        <w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="PingFang SC"/><w:sz w:val="22"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Title">
        <w:name w:val="Title"/>
        <w:basedOn w:val="Normal"/>
        <w:next w:val="Subtitle"/>
        <w:qFormat/>
        <w:pPr><w:spacing w:after="220"/></w:pPr>
        <w:rPr><w:b/><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="PingFang SC"/><w:sz w:val="34"/><w:color w:val="1F4FD8"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Subtitle">
        <w:name w:val="Subtitle"/>
        <w:basedOn w:val="Normal"/>
        <w:qFormat/>
        <w:rPr><w:color w:val="667085"/><w:sz w:val="20"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Meta">
        <w:name w:val="Meta"/>
        <w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:after="80"/></w:pPr>
        <w:rPr><w:color w:val="667085"/><w:sz w:val="18"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading1">
        <w:name w:val="heading 1"/>
        <w:basedOn w:val="Normal"/>
        <w:next w:val="Normal"/>
        <w:qFormat/>
        <w:pPr><w:spacing w:before="280" w:after="120"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="101828"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading2">
        <w:name w:val="heading 2"/>
        <w:basedOn w:val="Normal"/>
        <w:next w:val="Normal"/>
        <w:qFormat/>
        <w:pPr><w:spacing w:before="220" w:after="100"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="24"/><w:color w:val="1F2937"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading3">
        <w:name w:val="heading 3"/>
        <w:basedOn w:val="Normal"/>
        <w:next w:val="Normal"/>
        <w:qFormat/>
        <w:pPr><w:spacing w:before="160" w:after="80"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="22"/><w:color w:val="344054"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="ListParagraph">
        <w:name w:val="List Paragraph"/>
        <w:basedOn w:val="Normal"/>
        <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
      </w:style>
    </w:styles>
    """

    private static let numberingXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:abstractNum w:abstractNumId="0">
        <w:lvl w:ilvl="0">
          <w:start w:val="1"/>
          <w:numFmt w:val="bullet"/>
          <w:lvlText w:val="•"/>
          <w:lvlJc w:val="left"/>
          <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
        </w:lvl>
      </w:abstractNum>
      <w:abstractNum w:abstractNumId="1">
        <w:lvl w:ilvl="0">
          <w:start w:val="1"/>
          <w:numFmt w:val="decimal"/>
          <w:lvlText w:val="%1."/>
          <w:lvlJc w:val="left"/>
          <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
        </w:lvl>
      </w:abstractNum>
      <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
      <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
    </w:numbering>
    """
}
