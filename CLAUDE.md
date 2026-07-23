# Peek

A minimal, native macOS **menu-bar-only** calendar app (SwiftUI + AppKit). No main window — everything lives in the menu bar status item and an `NSPopover`. `LSUIElement` is set.

## The one rule that matters most: Apple-first, established-solutions-first

Before writing any non-trivial code — especially anything touching UI, layout, colors, system integration, or behavior:

1. **Check Apple's documentation and Human Interface Guidelines first.** If Apple defines a standard control, API, pattern, or design guidance for this, use it. Don't hand-roll what a first-party framework already provides.
2. **If Apple has no established best-practice**, look at how state-of-the-art Mac apps solve the same problem and match that.
3. **Only stray from the established pattern when you are genuinely confident you have a better solution** — and when you do, say so explicitly and explain why in your message to the user.

Do not invent bespoke solutions out of convenience. "It works" is not the bar; "it's how a well-built native Mac app would do it" is.

## Working principles

1. **Surface assumptions before building.** State what you're assuming (behavior, scope, environment) up front so it can be corrected — wrong assumptions held silently are the most common failure mode.
2. **Ask before assuming on functional questions.** How a feature should behave, UX semantics, what's in scope — ask the user. Implementation details are yours to decide; product behavior is theirs.
3. **Stop and ask when requirements conflict.** If two instructions or constraints can't both hold, don't pick one silently — surface the conflict and let the user resolve it.
4. **Push back when warranted.** If a request looks wrong, harmful to the codebase, or there's a clearly better way, say so and make the case. Don't be a yes-machine; disagree, then defer if overruled.
5. **Prefer the boring, obvious solution.** Cleverness is expensive to maintain. Reach for the standard pattern first (see the Apple-first rule above); novelty needs justification.
6. **Touch only what you're asked to touch.** No drive-by refactors, renames, or style fixes outside the task's scope. If you spot something worth fixing nearby, mention it — don't fold it in.

## Design bar: ship-quality, native feel

Treat every UI change as production Mac software. It should be HIG-compliant, pixel-tuned, and indistinguishable from a first-party menu-bar app. Respect light/dark mode, wallpaper-tinted menu bars, Dynamic Type where relevant, and the app's existing minimal aesthetic. Polish is part of "done," not a follow-up.

## Definition of done

For every code change:

1. **Build must pass.** Compile before reporting done.
   ```sh
   xcodebuild -scheme Peek -configuration Debug build
   ```
2. **For any UI change, visually verify at runtime.** Use the `verify` skill — build, launch, and drive the app, then screenshot to confirm it actually looks and behaves right. Don't claim a UI change works without seeing it.
3. **Auto-commit the completed task** with a descriptive message. **Never push** unless explicitly asked.

## Branching

- **Features and multi-commit work start on a new branch** (`feature/...` or `fix/...`) cut from `main`. Commit there as tasks complete.
- **Small single-commit fixes** may land directly on the current branch — no branch ceremony for one-liners.
- **Never merge into `main` yourself.** When a branch is done and verified, stop and tell the user it's ready for review; they merge.

## Build & project generation

This project uses **XcodeGen** — the Xcode project is generated from `project.yml`, not edited by hand.

- **After adding, renaming, or deleting any file**, run `xcodegen generate` before building. This is the #1 recurring mistake — a stale project means your new file isn't in the build. Editing existing files does not require regeneration.
- Never edit `Peek.xcodeproj` directly; change `project.yml` and regenerate.
- Build/verify commands live in the `verify` skill (`.claude/skills/verify/SKILL.md`) — read it before driving the UI. It documents the non-obvious mechanics (CGEvent clicking, region screenshots, the fact that System Events can't see the popover, and how to type into a non-frontmost app).

## Code style & conventions

- **Swift 6**, strict concurrency. UI/AppKit-touching types are `@MainActor`.
- Match the existing house style: `final class`, `///` doc comments explaining *why* (not what), `// MARK:` section dividers, small focused files (one view/model per file).
- Keep it minimal. Don't add abstractions, layers, or files beyond what the change needs.
- Source layout: `PeekApp.swift` (entry, `LSUIElement`), `AppDelegate.swift` (status item, popover, menu, glyph rendering), `MenuBarIconView.swift` (glyph), `CalendarPopoverView.swift` (month view), `SettingsView.swift`, plus models (`*Model.swift`), `WeekdayColor.swift`, `MeetingLinkParser.swift`, `RemindersSupport.swift`, `Preferences.swift`, `GlobalHotKey.swift`.
- User-facing strings go through `Localizable.xcstrings`.

## Dependencies

Prefer Apple frameworks (SwiftUI, AppKit, EventKit, etc.). A third-party SwiftPM package is OK **only when it clearly beats a hand-rolled solution** — flag it and explain the tradeoff before adding it.

## Testing

Add lightweight unit tests for **pure/parseable logic** going forward — date math, `MeetingLinkParser`, and similar. Skip UI tests (verify those visually via the `verify` skill). There is no test target yet; when the first testable logic change lands, set one up via `project.yml`.

## Don't regress these

Peek's core behaviors that changes must not break:

- The menu bar glyph updates live (weekday + day number) and re-renders on date change, light/dark mode, and wallpaper-tinted menu bar changes.
- The popover month view: arrow-key month/year navigation, "Today", event dots (including multi-day spans), day-click event list.
- Right-click context menu, color preset persistence, Launch at Login.
- Creating events/reminders during verification writes to the **real** Calendar/Reminders — clean up test data afterward (see the `verify` skill).
