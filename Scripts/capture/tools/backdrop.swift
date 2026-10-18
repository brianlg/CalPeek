import AppKit

// Full-screen gradient shown behind CalPeek's popovers so their vibrancy
// resolves against a known colour and no other window bleeds through.
extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt32(s, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF)/255, green: CGFloat((v >> 8) & 0xFF)/255,
                  blue: CGFloat(v & 0xFF)/255, alpha: 1)
    }
}
let stops = CommandLine.arguments.dropFirst().map(NSColor.init(hex:))
let colors = stops.count >= 2 ? Array(stops) : [NSColor(hex: "#FFF9F0"), NSColor(hex: "#D5E3F8")]

// A single argument that names an existing file is an image ground: the App
// Store frames and the video now share one supplied desktop image, and a
// gradient approximating it would leave the popover's vibrancy resolving
// against a tone the wallpaper never actually shows.
let groundImage: NSImage? = {
    guard let first = CommandLine.arguments.dropFirst().first,
          FileManager.default.fileExists(atPath: first) else { return nil }
    return NSImage(contentsOfFile: first)
}()

final class GradientView: NSView {
    override func draw(_ r: NSRect) {
        if let img = groundImage {
            // Scale to fill, matching how macOS lays the same file out as the
            // wallpaper, so the band compose_scene rebuilds lines up with the
            // body of the frame.
            let s = max(bounds.width / img.size.width, bounds.height / img.size.height)
            let w = img.size.width * s, h = img.size.height * s
            img.draw(in: NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h))
        } else {
            NSGradient(colors: colors)?.draw(in: bounds, angle: -60)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!
let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
win.contentView = GradientView()
// Above ordinary app windows, below the menu bar (24) and popover layer (25).
win.level = NSWindow.Level(rawValue: 20)
win.isOpaque = true
win.ignoresMouseEvents = true
win.collectionBehavior = [.canJoinAllSpaces, .stationary]
win.setFrame(screen.frame, display: true)
win.orderFrontRegardless()

// SELF-DESTRUCT. This window covers the whole screen above every app, so it
// must never outlive an interrupted run. Hard ceiling, independent of whatever
// the driving script does or fails to do.
let ttl = ProcessInfo.processInfo.environment["BACKDROP_TTL"].flatMap(Double.init) ?? 150
DispatchQueue.main.asyncAfter(deadline: .now() + ttl) { exit(0) }
app.run()
