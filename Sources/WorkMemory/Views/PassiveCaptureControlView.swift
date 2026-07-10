import SwiftUI

struct PassiveCaptureControlView: View {
    @EnvironmentObject private var monitor: PassiveCaptureMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlRows

            if monitor.isEnabled {
                sourceToggles
            }

            permissionRows

            statusRows
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var sourceToggles: some View {
        HStack(spacing: 18) {
            Toggle("窗口", isOn: $monitor.capturesWindows)
            Toggle("网页", isOn: $monitor.capturesBrowser)
            Toggle("输入", isOn: $monitor.capturesTyping)
        }
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    private var controlRows: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                captureToggles
                ocrButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                captureToggles
                ocrButtons
            }
        }
    }

    private var captureToggles: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $monitor.isEnabled) {
                Label("无感记录", systemImage: monitor.isEnabled ? "record.circle.fill" : "record.circle")
                    .font(.headline)
            }
            .toggleStyle(.switch)

            Toggle(isOn: $monitor.isOCREnabled) {
                Label("本地 OCR", systemImage: "viewfinder")
            }
            .toggleStyle(.switch)
            .disabled(!monitor.isEnabled)
        }
    }

    private var ocrButtons: some View {
        HStack(spacing: 8) {
            Button {
                monitor.captureCurrentWindowOCRNow()
            } label: {
                Label("立即 OCR", systemImage: "camera.viewfinder")
            }
            .keyboardShortcut("o", modifiers: [.option, .command])
            .help("立即截取当前前台窗口并保存 OCR 结果，快捷键 Option + Command + O")

            Button {
                monitor.refreshPermissionStatus()
            } label: {
                Label("刷新权限", systemImage: "arrow.clockwise")
            }
            .help("重新读取辅助功能和屏幕录制权限状态")
        }
    }

    @ViewBuilder
    private var permissionRows: some View {
        if !monitor.accessibilityTrusted {
            permissionRow(
                title: "辅助功能未授权",
                systemImage: "lock.open",
                requestTitle: "请求授权",
                requestAction: monitor.requestAccessibilityPermission,
                settingsAction: monitor.openAccessibilitySettings
            )
        }

        if monitor.isOCREnabled && !monitor.screenCaptureTrusted {
            permissionRow(
                title: "屏幕录制未生效",
                systemImage: "rectangle.dashed",
                requestTitle: "请求授权",
                requestAction: monitor.requestScreenCapturePermission,
                settingsAction: monitor.openScreenRecordingSettings
            )
        }
    }

    private func permissionRow(
        title: String,
        systemImage: String,
        requestTitle: String,
        requestAction: @escaping () -> Void,
        settingsAction: @escaping () -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                Button(requestTitle, action: requestAction)

                Button {
                    settingsAction()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("打开系统权限设置")
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Button(requestTitle, action: requestAction)

                    Button {
                        settingsAction()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("打开系统权限设置")
                }
            }
        }
        .font(.caption)
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLabel(
                monitor.statusText,
                systemImage: statusSystemImage,
                color: statusColor
            )

            statusLabel(
                monitor.currentContextText,
                systemImage: "macwindow",
                color: .secondary
            )

            HStack(spacing: 10) {
                statusLabel(
                    monitor.lastCaptureText,
                    systemImage: "tray.and.arrow.down",
                    color: .secondary
                )

                if let lastCapturedAt = monitor.lastCapturedAt {
                    Text(DateFormatting.time.string(from: lastCapturedAt))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .font(.caption)
    }

    private func statusLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSystemImage: String {
        hasPermissionWarning ? "exclamationmark.shield" : "checkmark.shield"
    }

    private var statusColor: Color {
        hasPermissionWarning ? .orange : .secondary
    }

    private var hasPermissionWarning: Bool {
        !monitor.accessibilityTrusted || (monitor.isOCREnabled && !monitor.screenCaptureTrusted)
    }
}
