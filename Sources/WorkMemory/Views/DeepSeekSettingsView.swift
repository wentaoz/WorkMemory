import SwiftUI

struct DeepSeekSettingsView: View {
    @EnvironmentObject private var settings: DeepSeekSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("模型 API", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Toggle(isOn: $settings.autoSummaryEnabled) {
                    Label("18:00 自动总结", systemImage: "clock")
                }
                .toggleStyle(.switch)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("服务商")
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .trailing)

                    Picker("服务商", selection: providerBinding) {
                        ForEach(ModelProviderPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }

                GridRow {
                    Text("API Key")
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .trailing)

                    SecureField(settings.providerPreset.apiKeyPlaceholder, text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("模型")
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .trailing)

                    TextField("模型", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Base URL")
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .trailing)

                    TextField("Base URL", text: $settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .font(.callout)

            Text("阿里云百炼预设会自动填入 Base URL 和模型 ID：qwen3.6-plus。API Key 保存在本机偏好设置里，不写入钥匙串。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var providerBinding: Binding<ModelProviderPreset> {
        Binding(
            get: { settings.providerPreset },
            set: { settings.applyProviderPreset($0) }
        )
    }
}
