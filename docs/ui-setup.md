# UI Setup Notes

This document covers the basics of Juice Bar's current UI approach and where the main pieces live.

## Summary

Juice Bar uses native macOS UI primitives:

- `NSStatusItem` for the menu bar item
- `NSMenu` for the menu
- native `NSMenuItem` rows for actions like `Refresh` and `Quit`
- a custom `NSView` embedded in the first menu item for the informational battery block

The app does not use a custom window or web-style UI. The only SwiftUI scene left is an empty `Settings` scene required by the `App` entry point.

## Why this setup exists

We originally used `MenuBarExtra`, but plain informational `Text` rows inside the menu were rendered like disabled menu items and looked darker than the native Apple battery panels we were trying to match.

The current setup keeps the bottom action rows fully native while letting the top informational block use AppKit label colors and layout.

## Main files

- `JuiceBar/JuiceBarApp.swift`
  - Minimal SwiftUI app entry.
  - Declares the app and installs `AppDelegate`.
- `JuiceBar/AppDelegate.swift`
  - Sets the app activation policy to `.accessory`.
  - Creates the `StatusItemController`.
- `JuiceBar/StatusItemController.swift`
  - Owns the `NSStatusItem`, `NSMenu`, and menu update flow.
  - Builds the native action items.
  - Hosts the custom top info view.
- `JuiceBar/BatteryMenuViewModel.swift`
  - Supplies all UI strings and actions.
  - Handles refresh timing, battery polling, and quit behavior.

## Runtime flow

1. `JuiceBarApp` starts.
2. `AppDelegate` creates `StatusItemController(viewModel: BatteryMenuViewModel())`.
3. `StatusItemController` creates:
   - the menu bar button
   - the menu
   - the custom info block
   - native `Refresh` and `Quit` menu items
4. The controller subscribes to `viewModel.objectWillChange`.
5. Whenever the view model changes, the controller updates:
   - menu bar title and charging bolt
   - visibility of the status item
   - text inside the info block

## Current menu structure

The menu is intentionally small:

- top custom info block
  - battery headline, for example `5h 17m remaining`
  - battery percentage line, for example `76% battery`
  - divider
  - `Info` heading
  - `Status: ...`
  - `Data Source: ...`
- separator
- native `Refresh`
- native `Quit`

## Native styling rules

- The menu bar item text uses `NSFont.monospacedDigitSystemFont`.
- The charging indicator uses the native SF Symbol `bolt.fill`.
- The top summary line uses `labelColor`.
- Secondary informational lines use `secondaryLabelColor`.
- The actions at the bottom must stay real `NSMenuItem`s so they inherit standard hover, highlight, and keyboard behavior.

## Important implementation details

### Custom menu view sizing

The top informational block is an `NSView` placed into `infoItem.view`.

That view must always have an explicit frame size before the menu opens. `StatusItemController.sizeInfoView()` handles this by copying the view's `intrinsicContentSize` into its frame and forcing layout.

If the top block ever appears blank again, check:

- `BatteryMenuInfoView.intrinsicContentSize`
- `StatusItemController.sizeInfoView()`
- any changes to manual layout math in `layout()`

### Action rows

`Refresh` and `Quit` are standard `NSMenuItem`s. Avoid replacing them with custom views unless there is a strong reason, because that would lose native interaction behavior.

### Visibility

The status item is hidden when `viewModel.showsMenuBarItem` is `false`. That logic comes from `BatteryMenuBarVisibilityPolicy` through the view model.

## Making UI changes safely

For text and layout changes:

- prefer updating string composition in `BatteryMenuViewModel`
- keep AppKit layout changes inside `StatusItemController.swift`
- preserve native menu items for actions

For structural changes:

- if the top informational block needs more custom styling, extend `BatteryMenuInfoView`
- if a row needs native hover/highlight behavior, make it an `NSMenuItem`, not part of the custom view

## Verification

Use both checks when changing the UI:

```bash
swift test
xcodebuild -project JuiceBar.xcodeproj -scheme JuiceBar -configuration Debug build
```

Then relaunch the built app and inspect the menu visually.
