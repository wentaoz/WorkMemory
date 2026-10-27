import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HealthCenterView()

            DeepSeekSettingsView()

            PassiveCaptureControlView()

            PrivacySettingsView()

            GlobalDictationControlView()

            DocumentImportView()
        }
    }
}
