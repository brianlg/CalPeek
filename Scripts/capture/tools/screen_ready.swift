import CoreGraphics
import Foundation

// Exits 0 if a capture can actually see the screen, 1 with a reason if not.
//
// A locked screen or a sleeping display does not make screencapture fail
// loudly: `-R` and `-l` report "could not create image", and a full-screen
// grab silently returns a solid black frame. Half a run can complete against
// black before anyone notices. This turns that into one clear preflight
// message instead.
guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else {
    print("NOT READY: no window-server session (headless?)"); exit(1)
}
if (d["CGSSessionScreenIsLocked"] as? Bool) == true || (d["CGSSessionScreenIsLocked"] as? Int) == 1 {
    print("NOT READY: the screen is locked -- unlock it, and consider a longer auto-lock delay for the shoot"); exit(1)
}
if (d["kCGSSessionOnConsoleKey"] as? Bool) == false || (d["kCGSSessionOnConsoleKey"] as? Int) == 0 {
    print("NOT READY: this session is not on the console (fast user switching?)"); exit(1)
}
// Display asleep: CGDisplayIsAsleep is still public.
if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
    print("NOT READY: the display is asleep -- caffeinate -u -t 5 wakes it"); exit(1)
}
print("screen ready")
