# Direct Distribution Checklist

This project now has two ways to work:

- `Package.swift` for quick local testing and code-level iteration
- `JuiceBar.xcodeproj` for building a real `.app` bundle you can archive, sign, notarize, and upload to GitHub Releases

## Local app testing in Xcode

1. Open `JuiceBar.xcodeproj` in Xcode.
2. Select the `JuiceBar` scheme.
3. Press Run.
4. Look for the battery time text in the macOS menu bar.

## Scripted release path

For a repeatable GitHub release flow, use `scripts/release.sh`.

Examples:

1. `./scripts/release.sh unsigned`
2. `DEVELOPMENT_TEAM=YOURTEAMID ./scripts/release.sh archive`
3. `DEVELOPMENT_TEAM=YOURTEAMID ./scripts/release.sh export`
4. `DEVELOPMENT_TEAM=YOURTEAMID NOTARY_PROFILE=juicebar-notary ./scripts/release.sh all`

The script writes output into `./dist/`.

## Automatic GitHub releases

This repo also has a GitHub Actions workflow at `.github/workflows/release.yml`.

Recommended usage:

1. Change `VERSION` in the PR that should ship.
2. Merge that PR into `main`.
3. GitHub Actions builds `JuiceBar.zip` and creates a GitHub Release tagged `v<version>`.

If `VERSION` does not change, merges to `main` do not create a release.

For the full versioning behavior, see `docs/versioning-and-releases.md`.

## Before your first release

1. In Xcode, select the project and target, then set:
   - your signing Team
   - a final bundle identifier
   - version and build number
2. Add a real app icon in `JuiceBar/Assets.xcassets/AppIcon.appiconset`.
3. Build and run once as the `.app` target to confirm `Launch at Login` works from the bundle.
4. Follow the one-time notary credential setup in `docs/release-workflow.md`.

## Unsigned GitHub tester build

If you are skipping Apple signing for now, use:

```bash
./scripts/release.sh unsigned
```

That produces:

- `dist/export/JuiceBar.app`
- `dist/JuiceBar.zip`

Testers will need to bypass Gatekeeper once when opening it.

## GitHub release flow

1. In Xcode, choose `Product > Archive`.
2. In Organizer, choose `Distribute App`.
3. Pick `Developer ID`.
4. Let Xcode sign and notarize the app.
5. Export the notarized app as a `.zip`.
6. Upload that `.zip` to GitHub Releases.

## Notes

- `LSUIElement` is already enabled in `JuiceBar/Info.plist`, so the app behaves like a menu bar utility.
- The current bundle identifier is a placeholder starting point. Change it before shipping.
- Launch-at-login behavior depends on how the app is run and packaged. See `docs/launch-at-login.md`.
- You do not need the Mac App Store for this flow, but you do want Developer ID signing and notarization so users can open the app normally.
