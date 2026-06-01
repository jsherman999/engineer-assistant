# Engineer Assistant

A native macOS app that teaches a high-school STEM student about MacOS and Linux. Two modes:

- **Ask Mode** — open-ended Q&A with Claude about sysadmin, coding, MacOS, or Linux.
- **Course Mode** — name a subject, get a short interactive course with hands-on exercises in a real sandboxed shell.

Every chat and shell session is recorded for a parent or instructor to review.

## Status

Pre-alpha. See [PLAN.md](./PLAN.md) for the full design and phased build plan.

## Requirements

- M1 (or newer Apple Silicon) Mac running macOS 14+
- Xcode 15+
- An Anthropic API key (stored in macOS Keychain)
- For Linux courses: `brew install podman` (Docker also supported as fallback)

## Building

```sh
swift build
swift run EngineerAssistant
```

Or open `Package.swift` in Xcode and run the `EngineerAssistant` scheme.

## Project layout

```
PLAN.md               -- full design document
Sources/
  EngineerAssistant/  -- SwiftUI app + core logic
Tests/                -- unit tests
```

## License

TBD.
