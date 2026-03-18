# Launch At Login Notes

This document explains the current `Launch at Login` behavior in Juice Bar.

## Summary

Juice Bar uses `SMAppService.mainApp` for launch-at-login on macOS.

That support is environment-dependent.

Observed behavior today:

- `swift run JuiceBar`: launch at login is not available because the app is not running from a real `.app` bundle
- Xcode app runs from `JuiceBar.xcodeproj`: launch at login may be available because Xcode launches a real app bundle
- current packaged unsigned builds: the launch-at-login feature is hidden entirely

Because of that, the menu should only show the `Launch at Login` toggle when the current app instance can actually control that setting.

## What The App Does

The menu now follows this policy:

- if launch at login is supported for the current app instance, show the status and toggle
- if the app is running from an unsigned bundled build, hide the entire launch-at-login section
- if launch at login is unavailable for other reasons, hide the toggle and show only the explanatory note

That avoids presenting a control that cannot work.

## Current States

Juice Bar treats launch at login as one of these states:

- `On`
- `Off`
- `Pending Approval`
- `Unavailable`
- `Unknown`

`Pending Approval` means macOS accepted the request but still requires user approval in `System Settings > General > Login Items`.

`Unavailable` currently covers two different cases:

- Juice Bar is not running from a real app bundle
- Juice Bar is running from a signed bundle, but macOS still reports that this build does not support launch at login

Unsigned bundled builds are treated differently:

- the feature is hidden entirely
- no explanatory note is shown in the menu

## Why Local CLI Runs Fail

When running from `swift run`, Juice Bar is not launched as a normal bundled macOS app.

In that environment, launch-at-login support is expected to be unavailable, and the app shows a note instead of a toggle.

## Why Unsigned GitHub Builds Hide The Feature

The current GitHub tester build path is intentionally unsigned.

In `scripts/release.sh`, the `unsigned` build disables code signing during the app build.

Because of that, Juice Bar now treats the downloaded unsigned app as ineligible for launch at login and removes the feature from the menu entirely.

This is a product decision to avoid shipping a control that appears broken in tester builds.

## Current Product Decision

For now, the correct product behavior is:

- do not show a broken `Launch at Login` toggle
- hide the feature entirely in unsigned distributed builds
- do show a short explanation when the feature is unavailable for other reasons
- keep the feature available in builds where macOS reports it as controllable

## If We Revisit This Later

To make launch at login reliable in distributed builds, test it against the actual shipped artifact, not only local development runs.

Suggested verification:

1. Build the exact release artifact.
2. Launch the exported `JuiceBar.app`.
3. Check whether the menu shows the toggle.
4. Toggle it on.
5. Verify the app appears in `System Settings > General > Login Items`.
6. Sign out and sign back in to confirm real behavior.

If a signed exported build still reports `unavailable for this build`, the release packaging path needs further investigation.
