import Foundation

enum ModelProviderPreset: String, CaseIterable, Identifiable {
    case deepSeek
    case aliyunBailian
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepSeek:
            return "DeepSeek"
        case .aliyunBailian:
            return "阿里云百炼"
        case .custom:
            return "自定义"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .deepSeek:
            return "https://api.deepseek.com"
        case .aliyunBailian:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .custom:
            return nil
        }
    }

    var defaultModel: String? {
        switch self {
        case .deepSeek:
            return "deepseek-v4-pro"
        case .aliyunBailian:
            return "qwen3.6-plus"
        case .custom:
            return nil
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .deepSeek:
            return "DeepSeek API Key"
        case .aliyunBailian:
            return "阿里云 DashScope API Key"
        case .custom:
            return "API Key"
        }
    }
}
