import Foundation

@MainActor
final class DeepSeekSettings: ObservableObject {
    @Published private(set) var providerPreset: ModelProviderPreset {
        didSet {
            defaults.set(providerPreset.rawValue, forKey: Self.providerPresetKey)
        }
    }

    @Published var apiKey: String {
        didSet {
            persistAPIKey(apiKey)
        }
    }

    @Published var baseURL: String {
        didSet {
            defaults.set(baseURL, forKey: Self.baseURLKey)
        }
    }

    @Published var model: String {
        didSet {
            defaults.set(model, forKey: Self.modelKey)
        }
    }

    @Published var autoSummaryEnabled: Bool {
        didSet {
            defaults.set(autoSummaryEnabled, forKey: Self.autoSummaryEnabledKey)
        }
    }

    @Published var autoSummaryHour: Int {
        didSet {
            autoSummaryHour = min(23, max(0, autoSummaryHour))
            defaults.set(autoSummaryHour, forKey: Self.autoSummaryHourKey)
        }
    }

    private static let providerPresetKey = "modelAPI.providerPreset"
    nonisolated static let apiKeyKey = "deepseek.apiKey"
    private static let baseURLKey = "deepseek.baseURL"
    private static let modelKey = "deepseek.model"
    private static let autoSummaryEnabledKey = "deepseek.autoSummaryEnabled"
    private static let autoSummaryHourKey = "deepseek.autoSummaryHour"

    private let defaults: UserDefaults
    private let keychainAccount: String
    private var isRestoringPersistedValues = true

    init(
        userDefaults: UserDefaults = .standard,
        keychainAccount: String = DeepSeekSettings.apiKeyKey
    ) {
        self.defaults = userDefaults
        self.keychainAccount = keychainAccount

        let storedProvider = userDefaults.string(forKey: Self.providerPresetKey)
        let initialProvider = storedProvider.flatMap(ModelProviderPreset.init(rawValue:)) ?? .deepSeek
        providerPreset = initialProvider
        apiKey = Self.loadAPIKey(userDefaults: userDefaults, keychainAccount: keychainAccount)
        baseURL = userDefaults.string(forKey: Self.baseURLKey)
            ?? initialProvider.defaultBaseURL
            ?? "https://api.deepseek.com"
        model = userDefaults.string(forKey: Self.modelKey)
            ?? initialProvider.defaultModel
            ?? "deepseek-v4-pro"
        autoSummaryEnabled = userDefaults.object(forKey: Self.autoSummaryEnabledKey) as? Bool ?? false
        autoSummaryHour = userDefaults.object(forKey: Self.autoSummaryHourKey) as? Int ?? 18
        if ProcessInfo.processInfo.environment["WORKMEMORY_TEST_MODE"] == "1" {
            autoSummaryEnabled = false
        }
        isRestoringPersistedValues = false
        persistAPIKey(apiKey)
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

    private static func loadAPIKey(userDefaults: UserDefaults, keychainAccount: String) -> String {
        if let keychain = KeychainStore.password(account: keychainAccount)?.nilIfBlank {
            userDefaults.removeObject(forKey: apiKeyKey)
            return keychain
        }
        if let legacy = userDefaults.string(forKey: apiKeyKey)?.nilIfBlank {
            KeychainStore.setPassword(legacy, account: keychainAccount)
            userDefaults.removeObject(forKey: apiKeyKey)
            return legacy
        }
        return ""
    }

    private func persistAPIKey(_ value: String) {
        guard !isRestoringPersistedValues else { return }
        KeychainStore.setPassword(value, account: keychainAccount)
        defaults.removeObject(forKey: Self.apiKeyKey)
    }
}
