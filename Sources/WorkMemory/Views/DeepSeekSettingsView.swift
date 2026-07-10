import SwiftUI

struct DeepSeekSettingsView: View {
    @EnvironmentObject private var settings: DeepSeekSettings
    @State private var isTesting = false
    @State private var connectionStatus = "尚未测试"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("模型 API", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                HStack(spacing: 10) {
                    Toggle("自动总结", isOn: $settings.autoSummaryEnabled)
                        .toggleStyle(.switch)

                    Picker("时间", selection: $settings.autoSummaryHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .disabled(!settings.autoSummaryEnabled)
                }
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

            HStack(spacing: 10) {
                Button {
                    testConnection()
                } label: {
                    Label(isTesting ? "测试中" : "测试连接", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(isTesting)

                Label(connectionStatus, systemImage: connectionStatus == "连接成功" ? "checkmark.circle" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(connectionStatus == "连接成功" ? Color.green : Color.secondary)
            }
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

    private func testConnection() {
        isTesting = true
        connectionStatus = "正在连接 \(settings.model)..."
        let configuration = DeepSeekClient.Configuration(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            model: settings.model
        )
        Task {
            do {
                _ = try await DeepSeekClient().testConnection(configuration: configuration)
                connectionStatus = "连接成功"
            } catch {
                connectionStatus = error.localizedDescription
            }
            isTesting = false
        }
    }
}
