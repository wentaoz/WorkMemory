import SwiftUI

@main
struct WorkMemoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MemoryStore()
    @StateObject private var actionStore = ActionItemStore()
    @StateObject private var documentIndexStore = DocumentImportIndexStore()
    @StateObject private var hotKeyService = HotKeyService()
    @StateObject private var passiveCaptureMonitor = PassiveCaptureMonitor()
    @StateObject private var globalDictationService = GlobalDictationService()
    @StateObject private var deepSeekSettings = DeepSeekSettings()
    @StateObject private var dailySummaryService = DailySummaryService()
    @StateObject private var webSummaryService = WebSummaryService()
    @StateObject private var askMemoryService = AskMemoryService()
    @StateObject private var actionItemExtractionService = ActionItemExtractionService()
    @StateObject private var documentImportService = DocumentImportService()
    @StateObject private var appLogStore = AppLogStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("WorkMemory", id: "main") {
            ContentView()
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
                .environmentObject(appLogStore)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
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
                    appDelegate.configure(
                        store: store,
                        hotKeyService: hotKeyService,
                        passiveCaptureMonitor: passiveCaptureMonitor,
                        globalDictationService: globalDictationService,
                        openMainWindow: openMainWindow
                    )
                }
        }
        .commands {
            CommandMenu("Memory") {
                Button("Quick Capture") {
                    openMainWindow()
                    store.requestComposerFocus()
                }
                .keyboardShortcut(" ", modifiers: [.option])

                Button(globalDictationService.isRecording ? "Stop Global Dictation" : "Start Global Dictation") {
                    globalDictationService.toggleRecording()
                }
                .keyboardShortcut(" ", modifiers: [.option, .shift])

                Toggle("Paste After Dictation", isOn: $globalDictationService.pasteAfterDictation)
                Toggle("Passive Capture", isOn: $passiveCaptureMonitor.isEnabled)
                Toggle("Local OCR", isOn: $passiveCaptureMonitor.isOCREnabled)
                Toggle("Auto Summary at 18:00", isOn: $deepSeekSettings.autoSummaryEnabled)

                Button("Summarize Today") {
                    dailySummaryService.summarizeTodayManually()
                }
                .disabled(dailySummaryService.isSummarizing)

                Button("Summarize Selected") {
                    dailySummaryService.summarizeSelectedManually()
                }
                .disabled(dailySummaryService.isSummarizing || store.selectedForSummaryCount == 0)

                Button("Summarize Web Pages") {
                    webSummaryService.summarize()
                }
                .disabled(webSummaryService.isSummarizing || store.webPageItems(for: webSummaryService.range).isEmpty)

                Button("Extract Today Actions") {
                    actionItemExtractionService.extractToday()
                }
                .disabled(actionItemExtractionService.isExtracting)

                Button("Scan Documents") {
                    documentImportService.scanNow()
                }
                .disabled(documentImportService.isScanning || documentImportService.folderPath.isEmpty)

                Button("Capture OCR Now") {
                    passiveCaptureMonitor.captureCurrentWindowOCRNow()
                }
                .keyboardShortcut("o", modifiers: [.option, .command])
            }
        }

        MenuBarExtra("WorkMemory", systemImage: "brain.head.profile") {
            Button(globalDictationService.isRecording ? "Stop Global Dictation" : "Start Global Dictation") {
                globalDictationService.toggleRecording()
            }

            Toggle("Paste After Dictation", isOn: $globalDictationService.pasteAfterDictation)

            Text(globalDictationService.statusText)

            Divider()

            Button("Extract Today Actions") {
                actionItemExtractionService.extractToday()
            }
            .disabled(actionItemExtractionService.isExtracting)

            Text("\(actionStore.openItems.count) open actions")

            Divider()

            Button("Scan Documents") {
                documentImportService.scanNow()
            }
            .disabled(documentImportService.isScanning || documentImportService.folderPath.isEmpty)

            Toggle("Auto Document Scan", isOn: $documentImportService.autoImportEnabled)

            Text(documentImportService.statusText)

            Divider()

            Button(dailySummaryService.isSummarizing ? "Summarizing Today..." : "Summarize Today") {
                dailySummaryService.summarizeTodayManually()
            }
            .disabled(dailySummaryService.isSummarizing)

            Button("Summarize Selected (\(store.selectedForSummaryCount))") {
                dailySummaryService.summarizeSelectedManually()
            }
            .disabled(dailySummaryService.isSummarizing || store.selectedForSummaryCount == 0)

            Toggle("Auto Summary 18:00", isOn: $deepSeekSettings.autoSummaryEnabled)

            Text(dailySummaryService.statusText)

            Divider()

            Button(webSummaryService.isSummarizing ? "Summarizing Web..." : "Summarize Web Pages") {
                webSummaryService.summarize()
            }
            .disabled(webSummaryService.isSummarizing || store.webPageItems(for: webSummaryService.range).isEmpty)

            Text(webSummaryService.statusText)

            Divider()

            Toggle("Passive Capture", isOn: $passiveCaptureMonitor.isEnabled)
            Toggle("Local OCR", isOn: $passiveCaptureMonitor.isOCREnabled)
                .disabled(!passiveCaptureMonitor.isEnabled)

            Button("Capture OCR Now") {
                passiveCaptureMonitor.captureCurrentWindowOCRNow()
            }

            if !passiveCaptureMonitor.accessibilityTrusted {
                Button("Grant Accessibility") {
                    passiveCaptureMonitor.requestAccessibilityPermission()
                }
            }

            if passiveCaptureMonitor.isOCREnabled && !passiveCaptureMonitor.screenCaptureTrusted {
                Button("Grant Screen Recording") {
                    passiveCaptureMonitor.requestScreenCapturePermission()
                }
            }

            if !passiveCaptureMonitor.accessibilityTrusted ||
                (passiveCaptureMonitor.isOCREnabled && !passiveCaptureMonitor.screenCaptureTrusted) {
                Button("Refresh Permissions") {
                    passiveCaptureMonitor.refreshPermissionStatus()
                }
            }

            Divider()

            Button("Quick Capture") {
                openMainWindow()
                store.requestComposerFocus()
            }

            Button("Today Summary") {
                openMainWindow()
                store.requestTodayView()
            }

            Divider()

            Text(passiveCaptureMonitor.statusText)

            if store.recentItems.isEmpty {
                Text("No memories yet")
            } else {
                ForEach(store.recentItems.prefix(5)) { item in
                    Button(item.menuTitle) {
                        openMainWindow()
                        store.select(item: item)
                    }
                }
            }

            Divider()

            Button("Quit WorkMemory") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
