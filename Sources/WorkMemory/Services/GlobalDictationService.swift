import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import Foundation
import Speech

@MainActor
final class GlobalDictationService: NSObject, ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var statusText = "全局听写未开启"
    @Published private(set) var targetContextText = "尚未选择目标 App"
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()

    @Published var pasteAfterDictation: Bool {
        didSet {
            UserDefaults.standard.set(pasteAfterDictation, forKey: Self.pasteAfterDictationKey)
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }

    private static let pasteAfterDictationKey = "globalDictation.pasteAfterDictation"

    private weak var store: MemoryStore?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private let activeContextReader = ActiveContextReader()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var targetContext: ActiveAppContext?

    override init() {
        pasteAfterDictation = UserDefaults.standard.object(forKey: Self.pasteAfterDictationKey) as? Bool ?? false
        super.init()
    }

    func configure(store: MemoryStore) {
        self.store = store
    }

    func toggleRecording() {
        if isRecording {
            stopRecording(saveTranscript: true)
        } else {
            Task {
                await startRecording()
            }
        }
    }

    func startRecording() async {
        guard !isRecording else { return }

        guard recognizer != nil else {
            statusText = "当前系统不支持语音识别"
            return
        }

        guard await requestPermissions() else { return }

        targetContext = activeContextReader.read()
        targetContextText = makeTargetContextText(targetContext)

        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""
        statusText = "全局听写中..."

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            statusText = "无法启动麦克风：\(error.localizedDescription)"
            cleanupAudio()
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    self.statusText = "语音识别结束：\(error.localizedDescription)"
                    self.stopRecording(saveTranscript: true)
                } else if result?.isFinal == true {
                    self.stopRecording(saveTranscript: true)
                }
            }
        }
    }

    func stopRecording(saveTranscript: Bool) {
        guard isRecording || audioEngine.isRunning else { return }

        recognitionRequest?.endAudio()
        cleanupAudio()
        isRecording = false

        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard saveTranscript, !finalTranscript.isEmpty else {
            statusText = "全局听写已停止"
            return
        }

        let context = makeCapturedContext(targetContext)
        store?.addVoiceMemory(content: finalTranscript, context: context)
        lastSavedAt = Date()
        statusText = "全局听写已保存"

        if pasteAfterDictation {
            pasteIntoTargetApp(finalTranscript)
        }
    }

    func requestSpeechPermissions() {
        Task {
            _ = await requestPermissions()
        }
    }

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityTrusted {
            statusText = "自动粘贴需要辅助功能权限"
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            statusText = "需要开启语音识别权限"
            return false
        }

        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                continuation.resume(returning: allowed)
            }
        }

        guard microphoneAllowed else {
            statusText = "需要开启麦克风权限"
            return false
        }

        return true
    }

    private func cleanupAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func makeCapturedContext(_ context: ActiveAppContext?) -> CapturedContext {
        CapturedContext(
            source: .voice,
            appName: context?.appName,
            bundleIdentifier: context?.bundleIdentifier,
            windowTitle: context?.windowTitle
        )
    }

    private func makeTargetContextText(_ context: ActiveAppContext?) -> String {
        guard let context else { return "未知目标 App" }
        let title = context.windowTitle?.nilIfBlank ?? "无窗口标题"
        return "\(context.appName) · \(title)"
    }

    private func pasteIntoTargetApp(_ text: String) {
        accessibilityTrusted = AXIsProcessTrusted()
        guard accessibilityTrusted else {
            statusText = "已保存；自动粘贴需要辅助功能权限"
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        statusText = "全局听写已保存并粘贴"
    }
}
