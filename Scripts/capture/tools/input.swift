import CoreGraphics
import Foundation
// click <x> <y> | move <x> <y> | glide <x> <y> <ms> | hold <x> <y> <ms> | esc
// key <vk> | keyto <pid> <vk> | type <pid> <text> | typeslow <pid> <text>
let a = CommandLine.arguments
func post(_ t: CGEventType, _ x: Double, _ y: Double) {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
        .post(tap: .cghidEventTap)
}
switch a[1] {
case "click":
    let x = Double(a[2])!, y = Double(a[3])!
    post(.mouseMoved, x, y); usleep(200_000)
    post(.leftMouseDown, x, y); usleep(120_000)
    post(.leftMouseUp, x, y)
case "move":
    // Park the cursor without clicking. Leaving it over the status item or a
    // day cell lets a help tag or hover state appear in the shot, and an
    // outside *click* to move it away would dismiss the popover.
    post(.mouseMoved, Double(a[2])!, Double(a[3])!)
case "hold":
    let x = Double(a[2])!, y = Double(a[3])!, ms = UInt32(a[4])!
    post(.mouseMoved, x, y); usleep(200_000)
    post(.leftMouseDown, x, y); usleep(ms * 1000)
    post(.leftMouseUp, x, y)
case "rightclick":
    let x = Double(a[2])!, y = Double(a[3])!
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(200_000)
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .right)!.post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .right)!.post(tap: .cghidEventTap)
case "key":
    // Arbitrary virtual key, posted globally (menus take key focus).
    let vk = CGKeyCode(UInt16(a[2])!)
    CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: true)!.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: false)!.post(tap: .cghidEventTap)
case "keyto":
    // A real virtual key delivered to CalPeek's pid. `key` posts globally and
    // lands in whatever is frontmost (Xcode, usually); `type` sends unicode
    // with virtualKey 0, which a text field takes as characters -- so Return
    // via `type` inserts a newline instead of firing the default button.
    let pid = pid_t(a[2])!, vk = CGKeyCode(UInt16(a[3])!)
    CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: true)!.postToPid(pid)
    usleep(60_000)
    CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: false)!.postToPid(pid)
case "glide":
    // Move the cursor along an eased path at 120Hz instead of teleporting.
    // A recorded video shows the cursor, and a jump cut from one side of the
    // screen to the other is the single clearest tell that a "screen
    // recording" was actually assembled from stills.
    let gx = Double(a[2])!, gy = Double(a[3])!, ms = Double(a[4])!
    var start = CGPoint(x: gx, y: gy)
    if let e = CGEvent(source: nil) { start = e.location }
    let steps = max(2, Int(ms / 1000 * 120))
    for i in 1...steps {
        let p = Double(i) / Double(steps)
        // easeInOutCubic: accelerate off the mark, settle onto the target.
        let e = p < 0.5 ? 4*p*p*p : 1 - pow(-2*p + 2, 3)/2
        post(.mouseMoved, start.x + (gx - start.x) * e, start.y + (gy - start.y) * e)
        usleep(useconds_t(ms * 1000 / Double(steps)))
    }
case "typeslow":
    // Same delivery as `type`, but on a human rhythm: 75-145ms per character,
    // longer across a word boundary. Seeded, so a re-record of the same take
    // types at the same pace.
    let pid = pid_t(a[2])!
    var seed: UInt64 = 0x5EED_CA1E
    func rnd() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1000) / 1000
    }
    var prev: Character? = nil
    for ch in a[3] {
        var u = UniChar(String(ch).unicodeScalars.first!.value)
        let d = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        d.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u); d.postToPid(pid)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u); up.postToPid(pid)
        var dt = 0.075 + rnd() * 0.07
        if ch == " " { dt += 0.11 }
        if prev == " " { dt += 0.05 }
        prev = ch
        usleep(useconds_t(dt * 1_000_000))
    }
case "esc":
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)!.post(tap: .cghidEventTap)
case "type":
    // CalPeek is never frontmost, so keystrokes must be posted to its pid.
    let pid = pid_t(a[2])!
    for ch in a[3].unicodeScalars {
        var u = UniChar(ch.value)
        let d = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        d.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u); d.postToPid(pid)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u); up.postToPid(pid)
        usleep(30_000)
    }
default: print("unknown verb")
}
