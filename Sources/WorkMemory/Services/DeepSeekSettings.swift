import Foundation

@MainActor
final class DeepSeekSettings: ObservableObject {
    @Published private(set) var providerPreset: ModelProviderPreset {
        didSet {
            UserDefaults.standard.set(providerPreset.rawValue, forKey: Self.providerPresetKey)
        }
    }

    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: Self.apiKeyKey)
        }
    }

    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey)
        }
    }

    @Published var model: String {
        didSet {
            UserDefaults.standard.set(model, forKey: Self.modelKey)
        }
    }

    @Published var autoSummaryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSummaryEnabled, forKey: Self.autoSummaryEnabledKey)
        }
    }

    private static let providerPresetKey = "modelAPI.providerPreset"
    private static let apiKeyKey = "deepseek.apiKey"
    private static let baseURLKey = "deepseek.baseURL"
    private static let modelKey = "deepseek.model"
    private static let autoSummaryEnabledKey = "deepseek.autoSummaryEnabled"

    init() {
        let storedProvider = UserDefaults.standard.string(forKey: Self.providerPresetKey)
        let initialProvider = storedProvider.flatMap(ModelProviderPreset.init(rawValue:)) ?? .deepSeek
        providerPreset = initialProvider
        apiKey = UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? ""
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLKey)
            ?? initialProvider.defaultBaseURL
            ?? "https://api.deepseek.com"
        model = UserDefaults.standard.string(forKey: Self.modelKey)
            ?? initialProvider.defaultModel
            ?? "deepseek-v4-pro"
        autoSummaryEnabled = UserDefaults.standard.object(forKey: Self.autoSummaryEnabledKey) as? Bool ?? false
    }

    func applyProviderPreset(_ preset: ModelProviderPreset) {
        providerPreset = preset

        if let defaultBaseURL = preset.defaultBaseURL {
            baseURL = defaultBaseURL
        }

        if let defaultModel = preset.defaultModel {
            model = defaultModel
        }
    }
}
