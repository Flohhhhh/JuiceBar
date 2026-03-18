# Plan: Battery Time Remaining Menu Bar App

> Source PRD: Battery Time Remaining Menu Bar App PRD from the current thread

## Architectural decisions

Durable decisions that apply across all phases:

- **Application shape**: Native macOS menu bar utility with no windowed UI, no onboarding, and no custom UI layer.
- **UI entry**: SwiftUI `MenuBarExtra` as the primary entry point, with a text-only always-visible label.
- **System integrations**: IOKit Power Sources APIs for battery state and ServiceManagement for launch-at-login.
- **Refresh model**: 30-second timer plus event-driven refresh on power source changes and wake-from-sleep.
- **Key models**: `BatteryState` carries charge percentage, charging/full flags, active power source, and optional remaining minutes.
- **Display rules**: Menu bar label resolves to `xh yym`, `Full`, or `--`; click menu exposes headline, percentage, status, refresh, launch-at-login, and quit.

---

## Phase 1: Menu Bar Skeleton

**User stories**: native-only app entry, always-visible menu bar display, minimal click menu shell

### What to build

Create the macOS menu bar application shell so the app launches as a lightweight accessory app, shows placeholder text in the menu bar, and exposes the minimal native menu structure required by the PRD.

### Acceptance criteria

- [ ] Launching the app creates a menu bar item with text-only output.
- [ ] Clicking the item opens a native menu with headline, battery line, status line, refresh, launch-at-login, and quit.
- [ ] The app does not depend on any custom window, onboarding flow, or non-native UI framework.

---

## Phase 2: Live Battery Read Path

**User stories**: retrieve battery percentage, charging state, power source, and a normalized estimate from IOKit

### What to build

Add a battery service that reads the current internal power source snapshot from IOKit, normalizes it into the app’s battery model, and prefers time-to-empty or time-to-full data appropriate to the current state.

### Acceptance criteria

- [ ] The app can read percentage, charging flag, charged/full flag, and current power source from native APIs.
- [ ] Discharging state resolves a remaining-time estimate using native power APIs.
- [ ] Charging state resolves time-to-full when the system exposes it.

---

## Phase 3: Display State Logic

**User stories**: show `3h 42m`, `1h 08m`, `Full`, or `--` correctly

### What to build

Implement the formatting and state-mapping rules that convert raw battery data into stable menu bar text and a small set of explicit UI states for discharging, charging, full, unknown estimate, and no-battery hardware.

### Acceptance criteria

- [ ] Minute values are formatted without seconds or decimals and always round down.
- [ ] Full batteries render as `Full`.
- [ ] Unknown or unavailable estimates render as `--` in the menu bar.

---

## Phase 4: Refresh And System Events

**User stories**: refresh on timer, power-source changes, and wake-from-sleep with low overhead

### What to build

Wire the app’s state updates to both a low-frequency timer and native power change notifications, then coalesce bursts so the menu bar stays current without wasting work.

### Acceptance criteria

- [ ] The battery state refreshes on a repeating timer within the 30 to 60 second target.
- [ ] Power source changes trigger a near-immediate refresh.
- [ ] Waking from sleep forces a fresh battery snapshot.

---

## Phase 5: App Polish And Delivery

**User stories**: refresh action, launch-at-login toggle, reliable native behavior in edge cases

### What to build

Finish the user-facing controls, connect launch-at-login management, and validate behavior for unknown estimates, AC power, desktops with no internal battery, and other minimal-state edge cases called out in the PRD.

### Acceptance criteria

- [ ] The menu’s Refresh action re-reads battery state immediately.
- [ ] Launch at Login can be toggled through native macOS APIs when the app is running from a proper app bundle.
- [ ] No-battery or unavailable-estimate scenarios remain stable and display `--` or an explanatory menu state instead of crashing.
