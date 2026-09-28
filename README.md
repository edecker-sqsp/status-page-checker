# What's Down, Doc?

A tiny native macOS menu bar app that watches status pages for the services you depend on and tells you, at a glance, whether anything's on fire.

No Dock icon, no windows — just a colored dot in the menu bar.

## What it does

WDD polls a configurable list of status pages on an interval and rolls their health up into a single indicator:

- 🟢 **all clear** — everything operational (or under scheduled maintenance)
- 🟡 **degraded** — something's reporting a partial outage, or a check failed and its status is genuinely unknown
- 🔴 **outage** — a real, confirmed outage somewhere

Click the menu bar icon to open a two-tab panel:

- **Status** — every monitored service, worst first, with its current health, a description of what's happening (e.g. an open incident's title), the specific affected components, and a link to the real status page. A "last checked" timestamp sits at the bottom.
- **Settings** — the poll interval, per-service **On**/**Notify** toggles (drag a row by its grip handle to reorder the list; the order also breaks ties in the Status tab when healths are equal), a form to add your own status page, and a **Launch at login** toggle.

Ships pre-configured with four services, each individually toggleable:

| Service | Status page |
|---|---|
| Squarespace | https://status.squarespace.com/ |
| GitHub | https://www.githubstatus.com/ |
| Claude | https://status.claude.com/ |
| Slack | https://slack-status.com/ |

### Adding your own services

Most public status pages run [Atlassian Statuspage](https://www.atlassian.com/software/statuspage), which exposes a predictable `/api/v2/summary.json` endpoint. In Settings, paste any status page URL into "Add a service" and click **Verify & Add** — WDD probes that endpoint and, if it's a recognized Statuspage instance, adds it (prefilling the name from the page itself). Slack's own status page (`slack-status.com` / `status.slack.com`) is also supported via its own API. Anything else is rejected with a reason rather than silently failing.

### Why the health verdict isn't just the page's own "indicator"

Statuspage's top-level `status.indicator` can lag reality — a page can say "All Systems Operational" while an incident affecting a real component is still open. WDD cross-checks the indicator against per-component states and open incidents and takes the worse of the two, so a page can't quietly under-report a problem.

### Notifications

Toggling **Notify** on for a service posts a native notification when its health changes (down → notified, and back up → notified). Notifications are suppressed for the very first check after launch (so you don't get a burst for things that were already broken) and for transitions into/out of "unknown" (a flaky network check shouldn't page you).

## How to use it

1. Build it (see below), then move `What's Down, Doc?.app` to `/Applications` — this matters for **Launch at login** and notifications to behave reliably.
2. Open it. A green dot appears in the menu bar; no Dock icon, no window.
3. Click the dot to see current status or change settings.
4. In Settings, set your preferred check interval (minimum 10 seconds — polling someone else's status API faster than that risks getting rate-limited), toggle services on/off, and add any custom Statuspage-backed service you care about.
5. Quit either from the button at the bottom of the Settings tab, or by right-clicking the menu bar icon and choosing **Quit**.

## Tech

- **Swift 6** / **SwiftUI** for the settings/status panel, **AppKit** (`NSStatusItem` + `NSPopover`) for the menu bar item and popover host — SwiftUI alone can't create a menu bar extra with this level of control, so the two are combined via `NSHostingController`.
- **Swift Concurrency** (`async`/`await`, `withTaskGroup`) — all enabled services are checked concurrently, so total latency is the slowest single page, not the sum of all of them.
- **`@Observable`** (the Observation framework) for the settings/monitor state driving the UI.
- **URLSession** for polling, **UserNotifications** for local notifications, **ServiceManagement** (`SMAppService`) for the login-item toggle.
- No third-party dependencies — pure Swift Package Manager, Apple frameworks only.
- `LSUIElement` in `Info.plist` is what makes it a background-only, windowless, Dock-icon-free app.

## How to build it

This project was built and is intended to work with **just Xcode's Command Line Tools** — no full Xcode installation required.

```sh
git clone <this repo>   # or just cd into it if you already have it
cd status-checker
./build.sh
open "What's Down, Doc?.app"
```

`build.sh` runs `swift build -c release`, assembles `What's Down, Doc?.app` (copying in `Resources/Info.plist` and `Resources/AppIcon.icns`), and ad-hoc code-signs it. That's the whole toolchain — no project file, no full asset catalog (the menu bar icon itself is just an emoji string; the app-icon `.icns` is generated once via `sips`/`iconutil`, not rebuilt by `build.sh`).

Builds natively on both Apple Silicon and Intel — the binary is whatever architecture the machine you build on is.

**One Command-Line-Tools quirk to know about:** the macOS 26+ SDK redeclares SwiftUI's `@State` as a compiler macro whose plugin ships only with full Xcode, so `@State` won't compile with just the CLT. `Sources/StatusChecker/UI/SwiftUIShims.swift` aliases the still-present property-wrapper struct as `@UIState`, and the views use that instead. If you add new view-local state, use `@UIState`, not `@State`. (`@Bindable`, `@FocusState`, etc. are unaffected.)

### Development

- `swift build` / `swift run` — build/run the debug binary directly (it'll pick up a Dock icon in this mode since it's not running from a proper signed bundle, but the logic and UI all work).
- `swift test` — runs the `swift-testing` suite in `Tests/`. On a Command-Line-Tools-only machine this needs CLT 26 / Swift 6.4 or newer (older CLT could build the suite but not execute it, for lack of Xcode's `xctest` hosting); `Package.swift` carries the extra framework/plugin search paths that make it work without Xcode.
- `swift run StatusChecker -- --self-check` — runs a built-in, dependency-free set of logic checks (mapping rules, health aggregation, URL detection) against real, recorded API responses. Predates `swift test` working on CLT-only machines, and still handy as a zero-dependency sanity check of the same logic.
