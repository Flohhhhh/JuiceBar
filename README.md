# Juice Bar

<img width="708" height="534" alt="image" src="https://github.com/user-attachments/assets/942686ef-ab1b-46a5-b24b-0e7b9ffebf96" />

Juice Bar is a minimal macOS menu bar utility that shows your Mac’s battery time remaining directly in the menu bar.

Examples:

- `3h 42m`
- `1h 08m`

It is intentionally small:

- no windowed UI
- no onboarding
- no analytics
- no custom UI framework

## What users see

Juice Bar lives in the macOS menu bar.

Juice Bar keeps your menu bar clean by hiding itself when there is no meaningful battery timing information to display.

Clicking it opens a small native menu with:

- current time remaining
- battery percentage
- charging status
- Refresh
- Launch at Login, when supported by the current build/runtime
- Quit

The menu bar item is intentionally hidden when Juice Bar does not yet have meaningful timing information to show, such as AC/not-charging states, brief transition periods after wake/plug/unplug, or when an estimate is rejected by safety checks as implausible.

## For Users

### Download and run Juice Bar

1. Open the project’s GitHub Releases page.
2. Download `JuiceBar.zip`.
3. Unzip it.
4. Drag `JuiceBar.app` to `Applications` if you want to keep it there.
5. Open `JuiceBar.app`.

### Important note about the current build

Current GitHub releases are unsigned test builds.

That means macOS may block the app the first time you open it. If that happens:

<img width="966" height="212" alt="image" src="https://github.com/user-attachments/assets/f9ded96c-3b86-476f-864f-86f6eb0263bd" />

1. Try opening the app once.
2. Open `System Settings > Privacy & Security`.
3. Scroll to the security section near the bottom.
4. Click `Open Anyway`.
5. Confirm the prompt.

After that first approval, you should be able to open Juice Bar normally.

### What to expect

- Juice Bar does not open a normal app window.
- It appears in the menu bar when there is useful charging or discharging time information to show.
- If you do not immediately see it, the app may be in an AC or transition state where the menu bar item is intentionally hidden until a fresh plausible estimate is available.
- Discharge fallback baselines are persisted in `UserDefaults`, so valid learned discharge behavior can still be reused after app relaunch or machine restart on the same macOS account.
- Implausible estimates are hidden instead of clamped. Juice Bar currently rejects discharge estimates above 24 hours and charging estimates above 12 hours.

## For Contributors

### Requirements

- macOS
- Xcode
- Swift 6 toolchain from current Xcode

### Project layout

- `JuiceBar.xcodeproj`: real macOS app project
- `JuiceBar/`: app source files, plist, and assets
- `Package.swift`: Swift package entry for quick local testing
- `Tests/`: formatter tests
- `scripts/release.sh`: release helper script
- `docs/`: release and distribution docs

### Run locally in Xcode

1. Open `JuiceBar.xcodeproj`.
2. Select the `JuiceBar` scheme.
3. Press Run.
4. Look for the menu bar item.

### Run locally from the command line

```bash
swift test
env CLANG_MODULE_CACHE_PATH=.build/ModuleCache swift run JuiceBar
```

For runtime behavior testing, prefer the real `.app` bundle:

```bash
cd /Users/camerongustavson/CodeProjects/juice-bar
pkill JuiceBar
xcodebuild -project JuiceBar.xcodeproj -scheme JuiceBar -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/JuiceBar-*/Build/Products/Debug/JuiceBar.app
```

### Build an unsigned local release zip

```bash
./scripts/release.sh unsigned
```

That produces:

- `dist/export/JuiceBar.app`
- `dist/JuiceBar.zip`

### Release behavior

This repo does not create a release for every merge to `main`.

A GitHub release is created only when the root `VERSION` file changes in a merge to `main`.

Typical flow:

1. Make your code changes.
2. Bump `VERSION` only if that PR should ship.
3. Merge to `main`.
4. GitHub Actions creates release `v<version>` and uploads `JuiceBar.zip`.

More detail:

- `docs/versioning-and-releases.md`
- `docs/release-workflow.md`
- `docs/direct-distribution.md`
- `docs/launch-at-login.md`
- `docs/battery-behavior.md`
- `docs/ui-setup.md`

## Current distribution status

Juice Bar is currently set up for unsigned GitHub releases for early users and testers.

That means:

- releases can be built automatically
- users can download and run the app
- users must bypass Gatekeeper once on first launch

The project is also structured so signed and notarized releases can be added later without changing the basic versioning model.
