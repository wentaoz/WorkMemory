import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechTranscriber: NSObject, ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published var statusMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var canRecord: Bool {
        recognizer != nil
    }

    func resetTranscript() {
        transcript = ""
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording()
            }
        }
    }

    func startRecording() async {
        guard let recognizer else {
            statusMessage = "当前系统不支持语音识别。"
            return
        }

        guard await requestPermissions() else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""
        statusMessage = "正在听写..."

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
            statusMessage = "无法启动麦克风：\(error.localizedDescription)"
            cleanupAudio()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    self.statusMessage = "语音识别结束：\(error.localizedDescription)"
                    self.stopRecording()
                } else if result?.isFinal == true {
                    self.statusMessage = "语音识别完成。"
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording || audioEngine.isRunning else { return }
        recognitionRequest?.endAudio()
        cleanupAudio()
        isRecording = false
        if transcript.isEmpty {
            statusMessage = "已停止录音。"
        }
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            statusMessage = "需要开启语音识别权限。"
            return false
        }

        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                continuation.resume(returning: allowed)
            }
        }

        guard microphoneAllowed else {
            statusMessage = "需要开启麦克风权限。"
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
}
