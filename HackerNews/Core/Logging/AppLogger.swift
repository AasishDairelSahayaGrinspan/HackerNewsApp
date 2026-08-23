import Foundation
import os

enum AppLogger {
    static let networking = Logger(subsystem: "com.hacknews.app", category: "networking")
    static let persistence = Logger(subsystem: "com.hacknews.app", category: "persistence")
    static let cache = Logger(subsystem: "com.hacknews.app", category: "cache")
    static let ui = Logger(subsystem: "com.hacknews.app", category: "ui")
    static let general = Logger(subsystem: "com.hacknews.app", category: "general")

    static func logNetwork(_ message: String) {
        #if DEBUG
        networking.debug("\(message, privacy: .public)")
        #endif
    }
}
