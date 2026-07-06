import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct ActiveAppContext: Equatable {
    var appName: String
    var bundleIdentifier: String?
    var processIdentifier: pid_t
    var windowTitle: String?
    var windowID: CGWindowID?

    var contextKey: String {
        [
            bundleIdentifier ?? appName,
            windowTitle ?? ""
        ]
        .joined(separator: "|")
    }
}

struct ActiveContextReader {
    func read() -> ActiveAppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let processIdentifier = app.processIdentifier
        let windowInfo = frontmostWindowInfo(for: processIdentifier)

        return ActiveAppContext(
            appName: app.localizedName ?? "Unknown App",
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: processIdentifier,
            windowTitle: windowTitle(for: processIdentifier) ?? windowInfo?.title,
            windowID: windowInfo?.windowID
        )
    }

    private func windowTitle(for processIdentifier: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(processIdentifier)

        guard let focusedWindow: AXUIElement = copyAttribute(
            from: appElement,
            attribute: kAXFocusedWindowAttribute
        ) else {
            return nil
        }

        let title: String? = copyAttribute(
            from: focusedWindow,
            attribute: kAXTitleAttribute
        )

        return title?.nilIfBlank
    }

    private func frontmostWindowInfo(for processIdentifier: pid_t) -> (windowID: CGWindowID, title: String?)? {
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let ownerPID = intValue(window[kCGWindowOwnerPID as String]),
                  ownerPID == Int(processIdentifier),
                  let layer = intValue(window[kCGWindowLayer as String]),
                  layer == 0,
                  let windowIDValue = intValue(window[kCGWindowNumber as String]) else {
                continue
            }

            let title = (window[kCGWindowName as String] as? String)?.nilIfBlank
            return (CGWindowID(windowIDValue), title)
        }

        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? UInt32 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
