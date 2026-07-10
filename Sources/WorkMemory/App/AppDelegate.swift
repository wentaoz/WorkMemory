import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didConfigure = false
    #if DEBUG
    private var guiRegressionHarness: GUIRegressionHarness?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        #if DEBUG
        if ProcessInfo.processInfo.environment["WORKMEMORY_TEST_MODE"] == "1" {
            guiRegressionHarness = GUIRegressionHarness()
            guiRegressionHarness?.show()
        }
        #endif
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
