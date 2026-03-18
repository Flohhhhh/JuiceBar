# Versioning And Releases

This repo does **not** create a GitHub release for every merge to `main`.

Instead, releases are intentional and version-driven.

## Core rule

A merge to `main` creates a GitHub release only when the root `VERSION` file changed in that merge.

Examples:

- Merge a bug fix PR without changing `VERSION`: no release
- Merge a feature PR without changing `VERSION`: no release
- Merge a PR that changes `VERSION` from `0.1.0` to `0.2.0`: release `v0.2.0` is created

## Why this setup exists

This keeps normal development separate from publishing.

Benefits:

- no noisy release spam on every merge
- explicit control over when a build is considered shippable
- a simple semantic versioning flow
- predictable tags and GitHub Releases

## Release trigger behavior

The workflow at `.github/workflows/release.yml` runs on:

- pushes to `main`
- manual `workflow_dispatch`

On pushes to `main`, it checks whether `VERSION` changed between the previous commit and the new commit.

- If `VERSION` changed: build release artifacts and create a GitHub release
- If `VERSION` did not change: do nothing beyond the workflow check

On manual dispatch:

- the workflow is allowed to release even without a `VERSION` diff

## Version format

The `VERSION` file should contain a plain semantic version string:

```text
0.1.0
```

The workflow converts that into a GitHub tag:

```text
v0.1.0
```

## Recommended team workflow

1. Keep feature and fix PRs separate from release intent unless you actually want to ship that merge.
2. When a set of changes is ready to release, update `VERSION` in that PR.
3. Merge that PR into `main`.
4. Let GitHub Actions create the release automatically.

## What the workflow publishes

Right now the release workflow builds an **unsigned** macOS app zip:

- `JuiceBar.zip`

That matches the current distribution strategy for early users and testers.

## Important limitation

Because the app is currently released unsigned:

- users can download it from GitHub
- users will need to bypass Gatekeeper once with `Open Anyway`

If you later move to Developer ID signing and notarization, this same version-driven workflow can be extended to publish signed releases instead.
