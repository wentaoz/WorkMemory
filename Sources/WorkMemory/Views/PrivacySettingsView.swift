import SwiftUI

struct PrivacySettingsView: View {
    @AppStorage(PrivacyRules.bundleKey) private var extraBundles = ""
    @AppStorage(PrivacyRules.keywordKey) private var extraKeywords = ""
    @AppStorage(PrivacyRules.domainKey) private var extraDomains = ""
    @AppStorage(PrivacyRules.pathKey) private var extraPaths = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("隐私过滤", systemImage: "eye.slash")
                .font(.headline)

            Text("默认会跳过密码管理器、系统设置、登录/支付页，以及标题里的密码、验证码等。短英文词按词边界匹配，避免把 author、privacy 误杀。下面可以追加自己的规则，每行一条。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                ruleRow("应用 Bundle ID", text: $extraBundles, placeholder: "com.example.wallet")
                ruleRow("关键词", text: $extraKeywords, placeholder: "工资单\n社保号")
                ruleRow("域名", text: $extraDomains, placeholder: "bank.example.com")
                ruleRow("URL 路径段", text: $extraPaths, placeholder: "billing")
            }
            .font(.callout)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func ruleRow(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            TextEditor(text: text)
                .font(.callout)
                .frame(minHeight: 54, maxHeight: 80)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 6)
                            .padding(.leading, 6)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}
