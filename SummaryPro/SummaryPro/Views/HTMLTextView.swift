import SwiftUI
import UIKit

struct HTMLTextView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let styledHTML = """
        <html>
        <head>
        <style>
        body {
            font-family: -apple-system, sans-serif;
            font-size: 15px;
            color: \(UIColor.label.cssColor);
            line-height: 1.4;
        }
        a { color: #1A73E8; }
        hr { border: none; border-top: 1px solid \(UIColor.separator.cssColor); margin: 12px 0; }
        p { margin: 0 0 8px 0; }
        ul, ol { padding-left: 20px; margin: 4px 0 8px 0; }
        li { margin-bottom: 4px; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """

        guard let data = styledHTML.data(using: .utf8) else { return }

        DispatchQueue.main.async {
            if let attrStr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            ) {
                textView.attributedText = attrStr
            }
        }
    }
}

private extension UIColor {
    var cssColor: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let resolved = resolvedColor(with: UITraitCollection.current)
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)), \(a))"
    }
}
