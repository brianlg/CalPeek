import os

extension Logger {
    /// Shared unified-logging handle (Apple's replacement for `NSLog`).
    /// Filter in Console.app by the bundle-id subsystem.
    static let peek = Logger(subsystem: "com.peek.Peek", category: "Peek")
}
