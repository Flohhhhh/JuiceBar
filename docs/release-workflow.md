# Release Workflow

This is the basic direct-download release path for Juice Bar.

## Recommended versioning model

Use a simple `VERSION` file at the repo root.

- Bump `VERSION` in the pull request that should produce a release.
- Merge that pull request into `main`.
- GitHub Actions creates the release only when `VERSION` changed in that merge.

This avoids publishing a new app for every single merge to `main`.

For the repo-level behavior and merge rules, see `docs/versioning-and-releases.md`.

## Prerequisites

You need:

1. An Apple Developer account enrolled in the paid Developer Program
2. Xcode signed into that account
3. A `Developer ID Application` certificate available to Xcode
4. A final bundle identifier set in the `JuiceBar` target

## One-time notarization setup

Create a keychain profile for `notarytool`:

```bash
xcrun notarytool store-credentials "juicebar-notary"
```

That command will prompt for:

- Apple ID
- app-specific password
- Team ID

After that, you can notarize with:

```bash
NOTARY_PROFILE=juicebar-notary ./scripts/release.sh notarize
```

## Release commands

Unsigned tester build:

```bash
./scripts/release.sh unsigned
```

That builds a release `.app` without Apple signing and zips it for GitHub uploads. Users will need to use `Open Anyway` the first time they launch it.

Archive the app:

```bash
DEVELOPMENT_TEAM=YOURTEAMID ./scripts/release.sh archive
```

Export a signed Developer ID app from the archive:

```bash
DEVELOPMENT_TEAM=YOURTEAMID ./scripts/release.sh export
```

Archive, export, zip, notarize, and restaple in one pass:

```bash
DEVELOPMENT_TEAM=YOURTEAMID NOTARY_PROFILE=juicebar-notary ./scripts/release.sh all
```

## Output

The script writes release artifacts to `./dist/`:

- `JuiceBar.xcarchive`
- `export/JuiceBar.app`
- `JuiceBar.zip`
- `ExportOptions.plist`

Upload the final `JuiceBar.zip` to GitHub Releases.

## GitHub automation

The repository includes a workflow at `.github/workflows/release.yml`.

Behavior:

1. It runs on pushes to `main` and on manual dispatch.
2. On `main`, it only releases if the `VERSION` file changed in that push.
3. It builds an unsigned macOS release zip.
4. It creates a GitHub Release tagged as `v<version>`.

Example:

- `VERSION` changes from `0.1.0` to `0.2.0`
- merge to `main`
- workflow creates release `v0.2.0`
- release asset is `JuiceBar.zip`

## Sanity checks

After notarization, you can verify locally:

```bash
spctl -a -vvv dist/export/JuiceBar.app
codesign --verify --deep --strict dist/export/JuiceBar.app
```

## Notes

- The script uses the shared `JuiceBar` scheme in `JuiceBar.xcodeproj`.
- It uses the `developer-id` export method, which is the normal path for GitHub downloads.
- If you prefer Xcode’s UI, `Product > Archive` still works and maps to the same release model.
