# Security Policy

CalPeek is a free, open source macOS menu bar calendar. It runs sandboxed on
your Mac, has no backend, no accounts, and no telemetry. Your calendar and
reminder data is read through EventKit and never leaves the device.

## Supported Versions

Only the most recent release receives security fixes. CalPeek ships through
two channels from one codebase, and they patch at different speeds:

| Channel | Source | Fix delivery |
| --- | --- | --- |
| Mac App Store | App Store | Gated on App Review, typically a few days |
| Direct | [GitHub Releases](https://github.com/brianlg/CalPeek/releases) | Ships as soon as it is notarized, delivered by Sparkle |

## Reporting a Vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub:

**[Report a vulnerability](https://github.com/brianlg/CalPeek/security/advisories/new)**

That form is private between you and the maintainer, and it lets us discuss and
prepare a fix before anything becomes public.

If you cannot use GitHub, email **support@briangibson.dev** instead. Please do
not include exploit details in the subject line.

### What to include

The more of this you can provide, the faster it gets triaged:

- CalPeek version and build number (right-click the menu bar icon, then About)
- **Which channel you installed from**, App Store or direct download. The two
  builds differ, so this matters.
- Your macOS version and whether you are on Apple silicon or Intel
- Steps to reproduce, what you observed, and what you expected
- What an attacker could actually do with it
- Any proof of concept, crash log, or screenshot

### What to expect

- **Acknowledgement within 3 business days.**
- **An initial assessment within 10 business days**, telling you whether it is
  confirmed, and if so a rough fix timeline.
- **A status update at least every 2 weeks** until it is resolved.

If you have not heard back within those windows, feel free to nudge the same
advisory thread.

### Disclosure

We use coordinated disclosure. Please give us up to 90 days, or until a fix
ships if that comes sooner, before discussing the issue publicly. Once the fix
is out we will publish a security advisory, and you will be credited in it and
in the release notes unless you would rather stay anonymous.

CalPeek is free software with no revenue, so there is no bug bounty. Credit and
genuine thanks are what we can offer.

## Scope

### In scope

- Sandbox escape, privilege escalation, or anything that gets code running
  outside CalPeek's own entitlements
- Unsafe handling of calendar or reminder content, for example a crafted event
  causing the meeting link parser to open a hostile URL
- Anything that causes calendar, reminder, or event data to leave the device
- Direct builds only: the Sparkle update path, including appcast fetching,
  EdDSA signature verification, and downgrade or rollback attacks

### Out of scope

- Vulnerabilities in macOS, EventKit, or other Apple frameworks. Report those
  to [Apple](https://security.apple.com/).
- Issues requiring physical access to an unlocked, logged-in Mac
- Issues requiring the user to first install other malicious software
- Social engineering, phishing, or attacks on the maintainer's accounts
- Automated scanner output with no demonstrated impact on CalPeek
- Missing hardening flags or best practices with no exploitable consequence

Non-security bugs belong in the
[issue tracker](https://github.com/brianlg/CalPeek/issues/new/choose).
