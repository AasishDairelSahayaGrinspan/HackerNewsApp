import Foundation

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension Int {
    var abbreviatedScore: String {
        if self >= 1000 {
            return String(format: "%.1fk", Double(self)/1000.0).replacingOccurrences(of: ".0k", with: "k")
        }
        return "\(self)"
    }
}
