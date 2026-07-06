import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class PassiveCaptureMonitor: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            isEnabled ? startTimer() : stopTimer()
        }
    }

    @Published var isOCREnabled: Bool {
        didSet {
            UserDefaults.standard.set(isOCREnabled, forKey: Self.ocrEnabledDefaultsKey)
            refreshPermissionStatus()
            if isOCREnabled {
                if !screenCaptureTrusted {
                    statusText = Self.screenCapturePendingText
                }
            }
        }
    }

    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var screenCaptureTrusted = CGPreflightScreenCaptureAccess()
    @Published private(set) var statusText = "无感记录未开启"
    @Published private(set) var currentContextText = "尚未读取当前上下文"
    @Published private(set) var lastCaptureText = "尚未自动保存"
    @Published private(set) var lastCapturedAt: Date?

    private static let enabledDefaultsKey = "passiveCapture.isEnabled"
    private static let ocrEnabledDefaultsKey = "passiveCapture.ocrEnabled"
    private static let screenCapturePendingText = "等待屏幕录制授权；授权后请重启或刷新"
    private let activeContextReader = ActiveContextReader()
    private let textReader = AccessibilityTextReader()
    private let browserReader = BrowserContextReader()
    private let ocrService = WindowOCRService()
    private let privacyFilter = PrivacyFilter()
    private let minimumTextDeltaLength = 18
    private let timerInterval: TimeInterval = 4
    private let ocrInterval: TimeInterval = 20

    private weak var store: MemoryStore?
    private var timer: Timer?
    private var lastWindowKey: String?
    private var lastBrowserKey: String?
    private var lastReadableContext: ActiveAppContext?
    private var lastOCRRunAt: Date?
    private var ocrInFlight = false
    private var ocrDigests: [String: String] = [:]
    private var textBaselines: [String: String] = [:]
    private var lastFocusedTextKey: String?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? false
        isOCREnabled = UserDefaults.standard.object(forKey: Self.ocrEnabledDefaultsKey) as? Bool ?? false
    }

    func configure(store: MemoryStore) {
        self.store = store
        refreshPermissionStatus()
        if isEnabled {
            startTimer()
        }
    }

    func refreshPermissionStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
        screenCaptureTrusted = CGPreflightScreenCaptureAccess()

        if !accessibilityTrusted {
            statusText = "等待辅助功能授权"
        } else if isOCREnabled && !screenCaptureTrusted {
            statusText = Self.screenCapturePendingText
        } else if isEnabled {
            statusText = "无感记录运行中"
        } else {
            statusText = "无感记录未开启"
        }
    }

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)

        if accessibilityTrusted, isEnabled {
            startTimer()
        } else {
            statusText = "需要在系统设置中允许辅助功能权限"
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func requestScreenCapturePermission() {
        let requested = CGRequestScreenCaptureAccess()
        screenCaptureTrusted = requested || CGPreflightScreenCaptureAccess()

        if screenCaptureTrusted {
            statusText = "屏幕录制权限已允许"
        } else {
            statusText = Self.screenCapturePendingText
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func captureCurrentWindowOCRNow() {
        refreshPermissionStatus()
        guard screenCaptureTrusted else {
            statusText = Self.screenCapturePendingText
            return
        }

        let activeContext = activeContextReader.read()
        let context: ActiveAppContext?

        if let activeContext,
           !isOwnApp(activeContext),
           privacyFilter.allows(context: activeContext) {
            context = activeContext
        } else {
            context = lastReadableContext
        }

        guard let context else {
            statusText = "请先切到目标窗口后按 ⌥⌘O"
            return
        }

        guard privacyFilter.allows(context: context) else {
            statusText = "当前窗口已被隐私规则跳过"
            return
        }

        currentContextText = makeContextText(context)
        captureWindowOCR(context, force: true)
    }

    private func startTimer() {
        guard timer == nil else { return }
        statusText = "无感记录运行中"
        poll()

        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        statusText = "无感记录已暂停"
    }

    private func poll() {
        guard isEnabled else { return }

        refreshPermissionStatus()
        guard accessibilityTrusted else {
            statusText = "等待辅助功能授权"
            return
        }

        guard let context = activeContextReader.read() else {
            statusText = "无法读取当前前台 App"
            return
        }

        currentContextText = makeContextText(context)

        guard !isOwnApp(context), privacyFilter.allows(context: context) else {
            statusText = "当前窗口已跳过"
            return
        }

        lastReadableContext = context

        if let page = browserReader.readPage(for: context), privacyFilter.allows(page: page) {
            captureBrowserPage(page, context: context)
        } else {
            captureActiveWindow(context)
        }

        captureFocusedText(context)
        captureWindowOCR(context, force: false)
        statusText = "无感记录运行中"
    }

    private func captureBrowserPage(_ page: BrowserPageContext, context: ActiveAppContext) {
        guard lastBrowserKey != page.key else { return }
        lastBrowserKey = page.key

        let pageText = browserReader.readPageText(for: context).flatMap(normalizedPageText)
        let content: String

        if let pageText {
            content = """
            页面：\(page.title)
            URL：\(page.url)

            网页正文摘录：
            \(pageText.clipped(to: 8_000))
            """
        } else {
            content = """
            页面：\(page.title)
            URL：\(page.url)

            网页正文摘录：未读取到正文，仅保存标题和 URL
            """
        }

        emit(
            PassiveCaptureSnapshot(
                source: .browser,
                content: content,
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                windowTitle: context.windowTitle,
                pageTitle: page.title,
                url: page.url
            )
        )
    }

    private func normalizedPageText(_ rawText: String) -> String? {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let text = lines.joined(separator: "\n")
        guard text.count >= 40 else { return nil }
        return text
    }

    private func captureActiveWindow(_ context: ActiveAppContext) {
        guard lastWindowKey != context.contextKey else { return }
        lastWindowKey = context.contextKey

        let title = context.windowTitle ?? context.appName
        let content = """
        App：\(context.appName)
        窗口：\(title)
        """

        emit(
            PassiveCaptureSnapshot(
                source: .activeWindow,
                content: content,
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                windowTitle: context.windowTitle
            )
        )
    }

    private func captureFocusedText(_ context: ActiveAppContext) {
        guard let focusedText = textReader.readFocusedText(in: context) else { return }
        guard privacyFilter.allows(text: focusedText.text) else { return }

        let key = focusedText.contextKey
        let currentText = focusedText.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentText.isEmpty else {
            textBaselines[key] = ""
            lastFocusedTextKey = key
            return
        }

        if lastFocusedTextKey != key, textBaselines[key] == nil {
            textBaselines[key] = currentText
            lastFocusedTextKey = key
            return
        }

        let baseline = textBaselines[key] ?? ""
        guard currentText.hasPrefix(baseline) else {
            textBaselines[key] = currentText
            lastFocusedTextKey = key
            return
        }

        let delta = String(currentText.dropFirst(baseline.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard delta.count >= minimumTextDeltaLength else { return }

        textBaselines[key] = currentText
        lastFocusedTextKey = key

        emit(
            PassiveCaptureSnapshot(
                source: .typing,
                content: delta.clipped(to: 1_200),
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                windowTitle: context.windowTitle
            )
        )
    }

    private func captureWindowOCR(_ context: ActiveAppContext, force: Bool) {
        guard force || isOCREnabled else { return }
        guard context.windowID != nil else {
            statusText = force ? "当前窗口无法截图 OCR" : statusText
            return
        }

        screenCaptureTrusted = CGPreflightScreenCaptureAccess()
        guard screenCaptureTrusted else {
            statusText = Self.screenCapturePendingText
            return
        }

        guard !ocrInFlight else {
            if force {
                statusText = "OCR 正在运行"
            }
            return
        }

        let now = Date()
        if !force, let lastOCRRunAt, now.timeIntervalSince(lastOCRRunAt) < ocrInterval {
            return
        }

        lastOCRRunAt = now
        ocrInFlight = true
        if force {
            statusText = "正在执行立即 OCR..."
        }

        let ocrService = self.ocrService
        Task {
            let result = await Task.detached(priority: .utility) {
                ocrService.recognizeText(in: context)
            }.value

            await MainActor.run {
                self.handleOCRResult(result, context: context, isManual: force)
            }
        }
    }

    private func handleOCRResult(_ result: OCRResult?, context: ActiveAppContext, isManual: Bool) {
        ocrInFlight = false
        guard let result else {
            if isManual {
                statusText = "OCR 未识别到足够文字"
            }
            return
        }

        guard privacyFilter.allows(text: result.text) else {
            if isManual {
                statusText = "OCR 结果已被隐私规则跳过"
            }
            return
        }

        let digest = ocrDigest(for: result.text)
        guard digest.count >= 60 else {
            if isManual {
                statusText = "OCR 文本太少，未保存"
            }
            return
        }

        let key = context.contextKey
        guard ocrDigests[key] != digest else {
            if isManual {
                statusText = "OCR 内容与上次相同，未重复保存"
            }
            return
        }
        ocrDigests[key] = digest

        let content = """
        OCR 识别文本（\(result.lineCount) 行）

        \(result.text.clipped(to: 3_000))
        """

        emit(
            PassiveCaptureSnapshot(
                source: .ocr,
                content: content,
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                windowTitle: context.windowTitle
            )
        )

        if isManual {
            statusText = "立即 OCR 已保存"
        }
    }

    private func ocrDigest(for text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .clipped(to: 4_000)
    }

    private func emit(_ snapshot: PassiveCaptureSnapshot) {
        store?.addCapturedMemory(snapshot)
        lastCapturedAt = snapshot.createdAt
        lastCaptureText = "\(snapshot.source.label) · \(snapshot.content.replacingOccurrences(of: "\n", with: " ").clipped(to: 80))"
    }

    private func isOwnApp(_ context: ActiveAppContext) -> Bool {
        if let bundleIdentifier = context.bundleIdentifier,
           bundleIdentifier == Bundle.main.bundleIdentifier {
            return true
        }

        return context.appName == "WorkMemory"
    }

    private func makeContextText(_ context: ActiveAppContext) -> String {
        let title = context.windowTitle?.nilIfBlank ?? "无窗口标题"
        return "\(context.appName) · \(title)"
    }
}
