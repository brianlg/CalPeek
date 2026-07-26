import os

extension Logger {
    /// Shared unified-logging handle (Apple's replacement for `NSLog`).
    /// Filter in Console.app by the bundle-id subsystem.
    static let calPeek = Logger(subsystem: "com.calpeek.CalPeek", category: "CalPeek")
}
