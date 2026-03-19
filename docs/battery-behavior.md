# Battery Behavior Notes

This document summarizes the current battery estimation and menu bar behavior in Juice Bar.

## Summary

Juice Bar prefers macOS system battery estimates, but it now has fallback behavior for the periods where Apple telemetry lags or returns no estimate.

The app also hides the menu bar item when there is nothing useful to display, rather than showing stale or misleading text.

## Estimate Priority

When Juice Bar is discharging, it resolves time remaining in this order:

1. `IOPSGetTimeRemainingEstimate()`
2. trusted power-source description values
3. battery registry values such as `TimeRemaining` and `AvgTimeToEmpty`
4. a derived estimate from observed discharge rate
5. a provisional estimate from cached discharge-rate baselines

When Juice Bar is charging, it only shows Apple-provided time-to-full values.

If macOS does not provide a charging estimate yet, Juice Bar does not invent one.

## Transition Handling

Recent work tightened state handling around plug and unplug transitions:

- stale charge estimates are not reused after unplug
- stale discharge estimates are not reused after plug-in
- unplug transitions can use fallback discharge estimates before Activity Monitor catches up
- plug-in transitions prefer AC state over a transient negative amperage sample if the app was just on battery

This is meant to reduce the common transition bugs where the app briefly showed the wrong icon, reused the wrong estimate, or stayed in the wrong mode.

## Persistent Fallback Baselines

Juice Bar stores two smoothed discharge-rate baselines in `UserDefaults`:

- short-term baseline
- long-term baseline

These are used only for provisional discharge fallback.

Important constraint:

- long-lived baselines are updated only from observed discharge samples
- Apple/system estimates may seed the in-memory session fallback, but they do not persist into the long-term averages

This keeps startup fallback available without letting optimistic system estimates permanently skew the stored baseline.

## Menu Bar Visibility

Juice Bar now hides the menu bar item unless there is meaningful timing information to show.

Current visibility policy:

- hide on AC power with no charging estimate
- hide while charging if time to full is still unavailable
- hide while discharging if time remaining is still unavailable
- show once a real charging or discharging estimate is available

This is a product choice to avoid showing a misleading placeholder in the menu bar during transition states.

## Debug Logging

Battery debug logging is opt-in.

Use it when investigating state transitions or estimate selection:

```bash
cd /Users/camerongustavson/CodeProjects/juice-bar
pkill JuiceBar
xcodebuild -project JuiceBar.xcodeproj -scheme JuiceBar -configuration Debug build
log stream --style compact --level debug --process JuiceBar --predicate 'category == "Battery"'
```

In a second terminal:

```bash
JUICEBAR_BATTERY_DEBUG=1 ~/Library/Developer/Xcode/DerivedData/JuiceBar-*/Build/Products/Debug/JuiceBar.app/Contents/MacOS/JuiceBar
```

The logs include:

- power-source and charging transitions
- resolved estimate source and minutes
- raw registry/system input used for that refresh
- UI state after stabilization

## Local Testing

For runtime behavior, test the real app bundle, not `swift run`.

Use:

```bash
cd /Users/camerongustavson/CodeProjects/juice-bar
pkill JuiceBar
xcodebuild -project JuiceBar.xcodeproj -scheme JuiceBar -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/JuiceBar-*/Build/Products/Debug/JuiceBar.app
```

`swift run JuiceBar` is still useful for package-level development, but app-bundle-specific behavior such as launch at login and menu bar runtime behavior should be tested from the built `.app`.
