import Foundation

struct PrivacyRules: Equatable {
    var extraBundleIdentifiers: [String]
    var extraKeywords: [String]
    var extraDomains: [String]
    var extraPathSegments: [String]

    static let bundleKey = "privacyFilter.extraBundleIDs"
    static let keywordKey = "privacyFilter.extraKeywords"
    static let domainKey = "privacyFilter.extraDomains"
    static let pathKey = "privacyFilter.extraPathSegments"

    static func load(defaults: UserDefaults = .standard) -> PrivacyRules {
        PrivacyRules(
            extraBundleIdentifiers: stringList(defaults.string(forKey: bundleKey)),
            extraKeywords: stringList(defaults.string(forKey: keywordKey)),
            extraDomains: stringList(defaults.string(forKey: domainKey)),
            extraPathSegments: stringList(defaults.string(forKey: pathKey))
        )
    }

    static func stringList(_ rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        return rawValue
            .replacingOccurrences(of: ",", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

struct PrivacyFilter {
    var rulesOverride: PrivacyRules?
    var defaults: UserDefaults

    init(rules: PrivacyRules? = nil, userDefaults: UserDefaults = .standard) {
        self.rulesOverride = rules
        self.defaults = userDefaults
    }

    private let blockedBundleIdentifiers: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.Passwords",
        "com.apple.passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.1password.safari",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "com.dashlane.dashlane",
        "org.keepassx.keepassxc",
        "com.keepassx.keepassxc",
        "com.apple.ScreenSaver.Engine"
    ]

    private let blockedTextPatterns = [
        "password",
        "passcode",
        "验证码",
        "密码",
        "信用卡",
        "银行卡",
        "credit card",
        "one-time code",
        "2fa",
        "otp",
        "cvv",
        "安全码"
    ]

    private let blockedHosts = [
        "paypal.com",
        "stripe.com",
        "checkout.stripe.com",
        "alipay.com",
        "pay.google.com"
    ]

    private let blockedPathSegments: Set<String> = [
        "login",
        "signin",
        "signup",
        "checkout",
        "payment",
        "password",
        "passwd",
        "2fa",
        "verify",
        "wallet",
        "private",
        "auth"
    ]

    func allows(context: ActiveAppContext) -> Bool {
        let rules = currentRules
        if let bundleIdentifier = context.bundleIdentifier?.lowercased() {
            if blockedBundleIdentifiers.contains(bundleIdentifier)
                || rules.extraBundleIdentifiers.contains(bundleIdentifier) {
                return false
            }
        }

        let title = context.windowTitle ?? ""
        return !containsSensitiveText(title, extraKeywords: rules.extraKeywords)
    }

    func allows(page: BrowserPageContext) -> Bool {
        let rules = currentRules
        if let url = URL(string: page.url), let host = url.host?.lowercased() {
            if isBlockedHost(host, extraDomains: rules.extraDomains) {
                return false
            }
            let segments = url.path
                .lowercased()
                .split(separator: "/")
                .map(String.init)
            let extraSegments = Set(rules.extraPathSegments)
            if segments.contains(where: { blockedPathSegments.contains($0) || extraSegments.contains($0) }) {
                return false
            }
        }

        return !containsSensitiveText(page.title, extraKeywords: rules.extraKeywords)
    }

    func allows(text: String) -> Bool {
        !containsSensitiveText(text, extraKeywords: currentRules.extraKeywords)
    }

    private var currentRules: PrivacyRules {
        rulesOverride ?? PrivacyRules.load(defaults: defaults)
    }

    private func isBlockedHost(_ host: String, extraDomains: [String]) -> Bool {
        if extraDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }
        if blockedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }
        let labels = host.split(separator: ".").map(String.init)
        return labels.contains { label in
            label == "paypal" || label == "stripe" || label == "alipay"
                || label.contains("bank") || label.contains("banco")
        }
    }

    private func containsSensitiveText(_ text: String, extraKeywords: [String]) -> Bool {
        let keywords = blockedTextPatterns + extraKeywords
        return keywords.contains { matchesKeyword(text, keyword: $0) }
    }

    func matchesKeyword(_ text: String, keyword: String) -> Bool {
        let haystack = text.lowercased()
        let needle = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }

        let isCJK = needle.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
        if isCJK || needle.contains(where: \.isWhitespace) || needle.count >= 6 {
            return haystack.contains(needle)
        }

        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let beforeIsLetter = range.lowerBound > haystack.startIndex
                && haystack[haystack.index(before: range.lowerBound)].isLetter
            let afterIsLetter = range.upperBound < haystack.endIndex
                && haystack[range.upperBound].isLetter
            if !beforeIsLetter && !afterIsLetter {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }
}
