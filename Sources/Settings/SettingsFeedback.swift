import AppKit
import SwiftUI
import Carbon

/// One semantic presentation for transient progress, actionable failures and
/// ordinary feedback. Empty feedback occupies no space; real text wraps fully.
enum SettingsFeedbackKind {
    case information, progress, warning, success
    var color: NSColor {
        switch self {
        case .information, .progress: .secondaryLabelColor
        case .warning: StatusColors.warning
        case .success: StatusColors.success
        }
    }
}

struct SettingsFeedback: View {
    let text: String?
    var kind: SettingsFeedbackKind = .warning
    var body: some View {
        if let text, !text.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                if kind == .progress { ProgressView().controlSize(.small).accessibilityLabel("Checking") }
                else if kind == .warning { Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true) }
                Text(text).fixedSize(horizontal: false, vertical: true)
            }.font(.callout).foregroundStyle(Color(nsColor: kind.color))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

