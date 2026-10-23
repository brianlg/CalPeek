import CoreGraphics
import Foundation
// Prints any ordinary application window that would be recorded, i.e. anything
// on the desktop that is not CalPeek's own popovers.
//
// The video is a real screen recording with no backdrop covering the desktop,
// so a stray window is not a cosmetic problem: the first cut of this shipped
// the Reminders app across the left half of every frame, real list names and
// all. `intruders` cannot catch it -- that detects windows *above* the
// backdrop's level, and an ordinary window sits at level 0 like the desktop
// itself.
//
// Exits 0 and prints nothing when the desktop is clear.
let minSide = 100.0
let ignored: Set<String> = [
    "CalPeek",            // the subject
    "Window Server",      // the desktop picture and the menu bar itself
    "Dock",               // includes the desktop icon layer
    "Finder",             // desktop only, once CreateDesktop is off
    "Control Center", "SystemUIServer", "Spotlight", "Ice",
]
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var found = false
for w in l {
    guard let owner = w[kCGWindowOwnerName as String] as? String, !ignored.contains(owner) else { continue }
    guard (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let width = b["Width"] as! Double, height = b["Height"] as! Double
    guard width >= minSide, height >= minSide else { continue }
    print("\(owner) \(Int(b["X"] as! Double)),\(Int(b["Y"] as! Double)) \(Int(width))x\(Int(height))")
    found = true
}
exit(found ? 1 : 0)
