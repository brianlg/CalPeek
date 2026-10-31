import CoreGraphics
// Prints CalPeek's on-screen windows: id x y w h (frontmost first)
//
// Help tags are skipped. Hovering the status item leaves a ~86x18 tooltip
// window owned by CalPeek, and counting it as a popover breaks every
// "how many windows are open?" assertion a capture script makes -- it reads as
// a popover that Esc will not close. Real popovers are far larger, so a size
// floor separates them cleanly.
let minSide = 100.0
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerName as String] as? String) == "CalPeek" {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let width = b["Width"] as! Double, height = b["Height"] as! Double
    guard width >= minSide, height >= minSide else { continue }
    print("\(w[kCGWindowNumber as String] as! Int) \(b["X"]!) \(b["Y"]!) \(b["Width"]!) \(b["Height"]!)")
}
