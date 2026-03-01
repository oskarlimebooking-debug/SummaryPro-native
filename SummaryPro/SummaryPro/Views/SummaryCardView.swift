import SwiftUI

struct SummaryCardView: View {
    let summary: Summary
    let index: Int

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(summary.title)
                    .font(.headline)

                Spacer()

                Button(action: copyContent) {
                    Text(copied ? "Kopirano!" : "Kopiraj")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            markdownContent
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    private var markdownContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(parseMarkdownLines(summary.content), id: \.self) { line in
                markdownLine(line)
            }
        }
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("## ") {
            Text(renderInline(String(trimmed.dropFirst(3))))
                .font(.subheadline)
                .fontWeight(.bold)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("# ") {
            Text(renderInline(String(trimmed.dropFirst(2))))
                .font(.headline)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(renderInline(String(trimmed.dropFirst(2))))
                    .font(.subheadline)
            }
        } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            let content = String(trimmed[match.upperBound...])
            let number = String(trimmed[..<match.upperBound]).trimmingCharacters(in: .whitespaces)
            HStack(alignment: .top, spacing: 6) {
                Text(number)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(renderInline(content))
                    .font(.subheadline)
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 4)
        } else {
            Text(renderInline(trimmed))
                .font(.subheadline)
        }
    }

    private func renderInline(_ text: String) -> AttributedString {
        // Try using iOS markdown rendering
        if let attributed = try? AttributedString(markdown: text) {
            return attributed
        }
        return AttributedString(text)
    }

    private func parseMarkdownLines(_ content: String) -> [String] {
        content.components(separatedBy: "\n")
    }

    private func copyContent() {
        let text = summary.title + "\n\n" + stripMarkdown(summary.content)
        UIPasteboard.general.string = text
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func stripMarkdown(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "### ", with: "", options: [], range: nil)
        result = result.replacingOccurrences(of: "## ", with: "", options: [], range: nil)
        result = result.replacingOccurrences(of: "# ", with: "", options: [], range: nil)

        // Remove bold markers
        while let range = result.range(of: #"\*\*(.+?)\*\*"#, options: .regularExpression) {
            let match = result[range]
            let inner = match.dropFirst(2).dropLast(2)
            result.replaceSubrange(range, with: inner)
        }

        // Remove italic markers
        while let range = result.range(of: #"\*(.+?)\*"#, options: .regularExpression) {
            let match = result[range]
            let inner = match.dropFirst(1).dropLast(1)
            result.replaceSubrange(range, with: inner)
        }

        return result
    }
}
