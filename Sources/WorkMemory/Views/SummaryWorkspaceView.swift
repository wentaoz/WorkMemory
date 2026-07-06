import SwiftUI

struct SummaryWorkspaceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AISummaryControlView()

            WebSummaryControlView()
        }
    }
}
