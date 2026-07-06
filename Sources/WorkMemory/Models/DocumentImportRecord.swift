import Foundation

enum DocumentImportStatus: String, Codable {
    case pending
    case imported
    case failed

    var label: String {
        switch self {
        case .pending:
            return "待处理"
        case .imported:
            return "已导入"
        case .failed:
            return "失败"
        }
    }
}

struct DocumentImportRecord: Identifiable, Codable, Hashable {
    var id: String { path }
    var path: String
    var fileName: String
    var fileExtension: String
    var modifiedAt: Date
    var size: UInt64
    var lastProcessedAt: Date?
    var status: DocumentImportStatus
    var message: String

    var fingerprint: String {
        "\(path)|\(Int(modifiedAt.timeIntervalSince1970))|\(size)"
    }
}
