import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didConfigure = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func configure(
        store: MemoryStore,
        hotKeyService: HotKeyService,
        passiveCaptureMonitor: PassiveCaptureMonitor,
        globalDictationService: GlobalDictationService,
        openMainWindow: @escaping () -> Void
    ) {
        guard !didConfigure else { return }
        didConfigure = true

        hotKeyService.registerShortcuts(
            quickCapture: {
                openMainWindow()
                store.requestComposerFocus()
            },
            globalDictation: {
                Task { @MainActor in
                    globalDictationService.toggleRecording()
                }
            },
            instantOCR: {
                Task { @MainActor in
                    passiveCaptureMonitor.captureCurrentWindowOCRNow()
                }
            }
        )
    }
}
