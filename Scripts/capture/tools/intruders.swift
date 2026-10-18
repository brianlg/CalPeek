import CoreGraphics
import Foundation

// Prints anything on screen that must not end up in a capture, and exits 1 if
// the screen is dirty -- so a capture script can wait until it goes quiet.
//
// Detection is by window *layer*, not by owner name. Matching owners was tried
// and failed: a Time Machine "backup disk is full" alert landed in all five
// App Store frames because whatever owns a notification on this macOS is not
// called "Notification Center". Layer is the reliable signal, since the
// backdrop sits at level 20 and hides every ordinary window beneath it --
// anything still visible above that is either CalPeek or an intruder.
//
// A notification in a marketing asset is not a cosmetic problem: the banners
// carry real content from the machine.

let backdropLevel = 20
let allowedOwners: Set<String> = ["backdrop"]

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var dirty = false

for w in list {
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
    let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let x = b["X"] as! Double, y = b["Y"] as! Double
    let width = b["Width"] as! Double, height = b["Height"] as! Double

    // Below the backdrop: covered, so it cannot appear in the shot.
    guard layer > backdropLevel else { continue }
    guard !allowedOwners.contains(owner) else { continue }

    if owner == "CalPeek" {
        // The popover stack is what we are here to photograph. The help tag is
        // not: it is drawn over the popover's top edge, and mask_region samples
        // the popover's colour from the scene, so a tag still on screen bleeds
        // a ghost of the meeting title into the shot.
        if height < 40, width > 30, y >= 30 {
            print("CalPeek help tag \(x) \(y) \(width)x\(height)")
            dirty = true
        }
        continue
    }

    // Menu bar items live above the backdrop and belong in the frame; the App
    // Store compositor rebuilds that band anyway. Anything confined to it is
    // not an intruder.
    guard y + height > 40 else { continue }

    // Ignore slivers; a real notification or panel is substantial.
    guard width >= 150, height >= 40 else { continue }

    print("\(owner) layer=\(layer) \(x) \(y) \(width)x\(height)")
    dirty = true
}

exit(dirty ? 1 : 0)
