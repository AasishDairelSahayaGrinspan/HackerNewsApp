import Foundation

extension String {
    /// Converts HN HTML into an AttributedString for rich presentation.
    /// The engine supplies a plain-text projection for list rows; this rich
    /// conversion is presentation-only and stays in Swift.
    var hnAttributedString: AttributedString {
        let wrapped = "<div style=\"font-family:-apple-system; font-size:15px;\">\(self)</div>"
        guard let data = wrapped.data(using: .utf8) else {
            return AttributedString(self)
        }
        do {
            let attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
            )
            return AttributedString(attributed)
        } catch {
            return AttributedString(strippedHTML)
        }
    }

    /// Lightweight fallback used only if HTML rendering fails. The C++ engine
    /// owns the primary HTML-to-text conversion.
    var strippedHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
