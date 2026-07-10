#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class GUIRegressionHarness {
    private let store = MemoryStore()
    private let actionStore = ActionItemStore()
    private let documentIndexStore = DocumentImportIndexStore()
    private let passiveCaptureMonitor = PassiveCaptureMonitor()
    private let globalDictationService = GlobalDictationService()
    private let deepSeekSettings = DeepSeekSettings()
    private let dailySummaryService = DailySummaryService()
    private let webSummaryService = WebSummaryService()
    private let askMemoryService = AskMemoryService()
    private let actionItemExtractionService = ActionItemExtractionService()
    private let documentImportService = DocumentImportService()
    private let reminderExportService = ReminderExportService()
    private let appLogStore = AppLogStore.shared
    private let window: NSWindow

    init() {
        let root = ContentView()
            .environmentObject(store)
            .environmentObject(actionStore)
            .environmentObject(documentIndexStore)
            .environmentObject(passiveCaptureMonitor)
            .environmentObject(globalDictationService)
            .environmentObject(deepSeekSettings)
            .environmentObject(dailySummaryService)
            .environmentObject(webSummaryService)
            .environmentObject(askMemoryService)
            .environmentObject(actionItemExtractionService)
            .environmentObject(documentImportService)
            .environmentObject(reminderExportService)
            .environmentObject(appLogStore)
            .frame(minWidth: 920, minHeight: 620)

        window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "WorkMemory GUI Regression"
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()

        passiveCaptureMonitor.configure(store: store)
        globalDictationService.configure(store: store)
        dailySummaryService.configure(store: store, settings: deepSeekSettings)
        webSummaryService.configure(store: store, settings: deepSeekSettings)
        askMemoryService.configure(memoryStore: store, settings: deepSeekSettings)
        actionItemExtractionService.configure(
            memoryStore: store,
            actionStore: actionStore,
            settings: deepSeekSettings
        )
        documentImportService.configure(
            memoryStore: store,
            indexStore: documentIndexStore,
            settings: deepSeekSettings
        )
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
#endif
