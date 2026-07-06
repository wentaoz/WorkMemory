import Foundation

struct BrowserPageContext: Equatable {
    var title: String
    var url: String

    var key: String {
        "\(title)|\(url)"
    }
}

struct BrowserContextReader {
    func readPage(for context: ActiveAppContext) -> BrowserPageContext? {
        guard let bundleIdentifier = context.bundleIdentifier else { return nil }

        if bundleIdentifier == "com.apple.Safari" {
            return runSafariScript()
        }

        if let applicationName = chromiumApplicationName(for: bundleIdentifier) {
            return runChromiumScript(applicationName: applicationName)
        }

        return nil
    }

    func readPageText(for context: ActiveAppContext) -> String? {
        guard let bundleIdentifier = context.bundleIdentifier else { return nil }

        if bundleIdentifier == "com.apple.Safari" {
            return runSafariPageTextScript()
        }

        if let applicationName = chromiumApplicationName(for: bundleIdentifier) {
            return runChromiumPageTextScript(applicationName: applicationName)
        }

        return nil
    }

    private func chromiumApplicationName(for bundleIdentifier: String) -> String? {
        switch bundleIdentifier {
        case "com.google.Chrome":
            return "Google Chrome"
        case "com.microsoft.edgemac":
            return "Microsoft Edge"
        case "com.brave.Browser":
            return "Brave Browser"
        case "company.thebrowser.Browser":
            return "Arc"
        default:
            return nil
        }
    }

    private func runSafariScript() -> BrowserPageContext? {
        let script = """
        tell application "Safari"
          if not (exists front window) then return ""
          set currentTab to current tab of front window
          return (name of currentTab) & linefeed & (URL of currentTab)
        end tell
        """

        return run(script: script)
    }

    private func runSafariPageTextScript() -> String? {
        let script = """
        tell application "Safari"
          if not (exists front window) then return ""
          set currentTab to current tab of front window
          return do JavaScript "\(pageTextJavaScript)" in currentTab
        end tell
        """

        return runText(script: script)
    }

    private func runChromiumScript(applicationName: String) -> BrowserPageContext? {
        let script = """
        tell application "\(applicationName)"
          if not (exists front window) then return ""
          set currentTab to active tab of front window
          return (title of currentTab) & linefeed & (URL of currentTab)
        end tell
        """

        return run(script: script)
    }

    private func runChromiumPageTextScript(applicationName: String) -> String? {
        let script = """
        tell application "\(applicationName)"
          if not (exists front window) then return ""
          set currentTab to active tab of front window
          return execute currentTab javascript "\(pageTextJavaScript)"
        end tell
        """

        if let text = runText(script: script) {
            return text
        }

        let fallbackScript = """
        tell application "\(applicationName)"
          if not (exists front window) then return ""
          tell active tab of front window
            return execute javascript "\(pageTextJavaScript)"
          end tell
        end tell
        """

        return runText(script: fallbackScript)
    }

    private func run(script: String) -> BrowserPageContext? {
        var error: NSDictionary?
        guard let output = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else {
            return nil
        }

        let parts = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard parts.count >= 2 else { return nil }

        return BrowserPageContext(
            title: parts[0],
            url: parts[1]
        )
    }

    private func runText(script: String) -> String? {
        var error: NSDictionary?
        guard let output = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else {
            return nil
        }

        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var pageTextJavaScript: String {
        """
        (() => {
          const text = document.body ? document.body.innerText : '';
          return text.replace(/[ \\t]+/g, ' ').slice(0, 12000);
        })();
        """
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: " ")
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
