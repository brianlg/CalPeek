import AppKit
import Foundation

// Region screenshot without `screencapture -R`, which on this machine starts
// failing with "could not create image from rect" for *every* rect after the
// display has slept, while full-screen capture keeps working. The direct
// CoreGraphics region APIs are gone from this SDK (ScreenCaptureKit only), so
// this takes the full screen with screencapture and crops. The temp frame is
// TIFF, not PNG: encoding and then decoding a 3600x2338 PNG cost ~0.9s, which
// is longer than the text caret stays solid after a keystroke; TIFF is ~0.3s.
//
//   ./grab <x> <y> <w> <h> <out.png>     (points, top-left origin, 2x output)
let a = CommandLine.arguments
guard a.count == 6, let x = Double(a[1]), let y = Double(a[2]),
      let w = Double(a[3]), let h = Double(a[4]) else {
    FileHandle.standardError.write("usage: grab x y w h out.png\n".data(using: .utf8)!); exit(2)
}
let tmp = NSTemporaryDirectory() + "grab-\(getpid()).tiff"
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-t", "tiff", tmp]
try! p.run(); p.waitUntilExit()
defer { try? FileManager.default.removeItem(atPath: tmp) }
guard p.terminationStatus == 0,
      let full = NSImage(contentsOfFile: tmp)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("grab: full-screen capture failed\n".data(using: .utf8)!); exit(1)
}
let scale = Double(full.width) / (NSScreen.main?.frame.width ?? 1800)
let px = CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale).integral
guard let crop = full.cropping(to: px) else {
    FileHandle.standardError.write("grab: rect \(px) outside \(full.width)x\(full.height)\n".data(using: .utf8)!); exit(1)
}
try! NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[5]))
