import Foundation

extension String {
    /// Safely converts HN HTML to AttributedString. Falls back to plain text on failure.
    var hnAttributedString: AttributedString {
        // HN uses <p>, <i>, <pre><code>, <a href>
        // We do lightweight cleaning then use AttributedString with HTML
        let wrapped = "<div style=\"font-family:-apple-system; font-size:15px;\">\(self)</div>"
        guard let data = wrapped.data(using: .utf8) else {
            return AttributedString(self)
        }
        do {
            // Use NSAttributedString HTML init on main thread via helper
            let ns = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
            )
            return AttributedString(ns)
        } catch {
            // Fallback: strip tags crudely
            let stripped = self.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            return AttributedString(stripped)
        }
    }

    var strippedHTML: String {
        // C++ fast path (HNCppEngine::stripHTML) handles 100+ comments efficiently
        let cppStripped = CppEngine.stripHTML(self)
        // Fallback to Swift if C++ returns empty but input not empty (should not happen)
        if cppStripped.isEmpty && !self.isEmpty {
            return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cppStripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
