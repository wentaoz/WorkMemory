import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var monitor: PassiveCaptureMonitor
    @EnvironmentObject private var settings: DeepSeekSettings
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("设置 WorkMemory")
                    .font(.largeTitle.weight(.semibold))
                Text("先选择需要记录的来源。所有原始活动保存在本机，并会合并成工作会话。")
                    .foregroundStyle(.secondary)
            }

            GroupBox("采集来源") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用无感采集", isOn: $monitor.isEnabled)
                    Toggle("窗口活动", isOn: $monitor.capturesWindows)
                    Toggle("浏览网页", isOn: $monitor.capturesBrowser)
                    Toggle("输入片段", isOn: $monitor.capturesTyping)
                    Toggle("本地 OCR", isOn: $monitor.isOCREnabled)
                }
                .toggleStyle(.switch)
                .padding(.vertical, 6)
            }

            GroupBox("AI 总结") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("自动生成每日总结", isOn: $settings.autoSummaryEnabled)
                    Text("模型和 API Key 可稍后在设置中配置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            HStack {
                Spacer()
                Button("开始使用") {
                    if !monitor.capturesWindows && !monitor.capturesBrowser && !monitor.capturesTyping && !monitor.isOCREnabled {
                        monitor.isEnabled = false
                    }
                    onComplete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 600)
    }
}
