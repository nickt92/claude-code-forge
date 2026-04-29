import MarkdownUI
import SwiftUI

/// Thin wrapper around MarkdownUI for consistent rendered markdown across the app.
/// Used in: OnboardingView (live preview + review), DiffPreviewView (rendered tab),
/// ClaudeMdContentView (rendered toggle).
struct RenderedMarkdownView: View {
    let content: String
    var fontSize: CGFloat = 12

    var body: some View {
        Markdown(content)
            .markdownTextStyle {
                FontSize(fontSize)
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                configuration.label
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .markdownTextStyle {
                        FontSize(fontSize - 1)
                        FontFamilyVariant(.monospaced)
                    }
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
    }
}
