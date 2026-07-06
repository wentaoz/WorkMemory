import ApplicationServices
import Foundation

struct FocusedTextSnapshot {
    var text: String
    var role: String?
    var contextKey: String
}

struct AccessibilityTextReader {
    func readFocusedText(in context: ActiveAppContext) -> FocusedTextSnapshot? {
        let systemElement = AXUIElementCreateSystemWide()

        guard let focusedElement: AXUIElement = copyAttribute(
            from: systemElement,
            attribute: kAXFocusedUIElementAttribute
        ) else {
            return nil
        }

        let role: String? = copyAttribute(from: focusedElement, attribute: kAXRoleAttribute)
        let subrole: String? = copyAttribute(from: focusedElement, attribute: kAXSubroleAttribute)

        guard isTextInput(role: role, subrole: subrole) else { return nil }
        guard !isSecureInput(role: role, subrole: subrole) else { return nil }

        let value: String? = copyAttribute(from: focusedElement, attribute: kAXValueAttribute)
        let selectedText: String? = copyAttribute(from: focusedElement, attribute: kAXSelectedTextAttribute)
        let text = value?.nilIfBlank ?? selectedText?.nilIfBlank

        guard let text, text.count <= 20_000 else { return nil }

        return FocusedTextSnapshot(
            text: text,
            role: role,
            contextKey: [
                context.bundleIdentifier ?? context.appName,
                context.windowTitle ?? "",
                role ?? "",
                subrole ?? ""
            ].joined(separator: "|")
        )
    }

    private func isTextInput(role: String?, subrole: String?) -> Bool {
        let roleText = [role, subrole]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return roleText.contains("textfield")
            || roleText.contains("textarea")
            || roleText.contains("text area")
            || roleText.contains("textview")
            || roleText.contains("editable")
    }

    private func isSecureInput(role: String?, subrole: String?) -> Bool {
        let roleText = [role, subrole]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return roleText.contains("secure")
            || roleText.contains("password")
    }
}
