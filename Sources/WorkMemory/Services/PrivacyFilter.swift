import Foundation

struct PrivacyFilter {
    private let blockedBundleIdentifiers: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.1password.1password",
        "com.agilebits.onepassword7",
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
        "2fa"
    ]

    private let blockedURLPatterns = [
        "password",
        "login",
        "signin",
        "auth",
        "checkout",
        "payment",
        "bank",
        "paypal",
        "stripe",
        "private"
    ]

    func allows(context: ActiveAppContext) -> Bool {
        if let bundleIdentifier = context.bundleIdentifier?.lowercased(),
           blockedBundleIdentifiers.contains(bundleIdentifier) {
            return false
        }

        let title = context.windowTitle?.lowercased() ?? ""
        return !blockedTextPatterns.contains { title.contains($0.lowercased()) }
    }

    func allows(page: BrowserPageContext) -> Bool {
        let combined = "\(page.title) \(page.url)".lowercased()
        return !blockedURLPatterns.contains { combined.contains($0.lowercased()) }
    }

    func allows(text: String) -> Bool {
        let lowered = text.lowercased()
        return !blockedTextPatterns.contains { lowered.contains($0.lowercased()) }
    }
}
