# Contributing to CalPeek

Thanks for your interest in CalPeek. Bug reports, small fixes, and focused
improvements are welcome. For larger changes, please open an issue first so
we can agree on the approach before you invest time in it.

## Building from source

See the [README](README.md#building-from-source) for a quick build, and
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the full picture (XcodeGen,
the two distribution targets, debug builds).

The short version: the Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding, renaming,
or deleting a file, run `xcodegen generate` before building. Never edit
`CalPeek.xcodeproj` directly.

## Commit messages

Follow the standard Git convention (there is a template in `.gitmessage`;
opt in with `git config commit.template .gitmessage`):

- **Subject**: imperative mood, capitalized, no trailing period, 50
  characters or fewer. "Add a Reminders section to the day popover", not
  "added reminders section."
- **Body** (optional): separated from the subject by a blank line, wrapped
  at 72 characters. Explain what changed and why, not how. Obvious
  one-liners need no body.
- Reference issues in the footer: `Fixes #123`.

Pull request titles follow the same subject rules, since a squash merge
uses the PR title as the commit subject.

## Style and scope

- Swift 6 with strict concurrency; UI and AppKit-touching types are
  `@MainActor`.
- Match the existing house style: `final class`, `///` doc comments that
  explain why, `// MARK:` dividers, small focused files.
- Prefer Apple frameworks and HIG-standard patterns over hand-rolled
  solutions or third-party dependencies.
- Keep changes focused. No drive-by refactors or style fixes outside the
  scope of the change.
- User-facing strings go through `Localizable.xcstrings`.
