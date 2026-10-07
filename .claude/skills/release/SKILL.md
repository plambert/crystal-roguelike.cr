---
name: release
description: Cut a release of crystal-roguelike. Writes the NEWS.md entry, closes the changelog section, bumps the version, tags, pushes, and watches the release workflow through to the Discord post. Use when asked to release, deploy or tag a version.
argument-hint: <version, such as 0.3.1>
context: fork
---

# Cutting a release

The version is `$ARGUMENTS`, written as `X.Y.Z` with no `v`. Stop and ask when it is missing or
does not read that way.

Work in the main checkout on `main`. Follow `AGENTS.md` for the news voice and the commit style.

## 1. Check the ground

* `git fetch`, then confirm the tree is clean and `main` is level with `origin/main`. Stop if
  either is false.
* Confirm `git tag --list v$VERSION` is empty.
* Confirm `## [Unreleased]` in `CHANGELOG.md` has at least one bullet. A release with an empty
  section is not cut.
* Run `crystal tool format --check`, `ameba`, `crystal spec` and `shards build`. Stop on any
  failure and report it.

## 2. Write the news

Read the Unreleased section of `CHANGELOG.md`. Add a section to `NEWS.md` directly under the intro
paragraph, before the previous version:

```markdown
## [X.Y.Z] - YYYY-MM-DD
```

The heading must match the changelog heading exactly, because the release workflow finds the entry
by it. Write the entry in the voice `AGENTS.md` describes under "Keeping the news".

## 3. Close the changelog

* Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and open an empty `## [Unreleased]` above
  it.
* Under the new version heading, before the first subheading, write one sentence that sums the
  release up, in the same style as the earlier sections.
* At the foot of the file, point the `[Unreleased]` link at `compare/vX.Y.Z...HEAD` and add
  `[X.Y.Z]: .../compare/vPREVIOUS...vX.Y.Z` under it.

## 4. Bump the version

* `version:` in `shard.yml`.
* Every mention of the previous version in `README.md` (`grep -n PREVIOUS README.md`).
* `shards build`, then `./bin/crystal-roguelike --version` must print the new version.

## 5. Check and commit

* `rumdl check --no-exclude CHANGELOG.md`, `rumdl check NEWS.md`, `rumdl check README.md`.
* Commit `CHANGELOG.md NEWS.md README.md shard.yml` by path, with the message `Release X.Y.Z` and
  bullets saying what was done.
* `git tag vX.Y.Z`, then `git push origin main` and `git push origin vX.Y.Z`.

## 6. Watch the release

Find the run with `gh run list --limit 5` and poll `gh run view <id> --json status` every 15
seconds for the first five minutes, then every minute, until it is `completed`. Do not use
`pgrep`. Then confirm:

* every job concluded `success`;
* `gh release view vX.Y.Z --json assets` lists two archives per platform plus `SHA256SUMS`;
* the release body starts with the NEWS.md entry and ends with the changelog links;
* the "Announce the release on Discord" step logged `Discord answered HTTP 204`.

## 7. Report

Say the version, the commit and tag, the job results, the asset count, and whether the Discord
post went out. If anything failed, say what and stop; do not retry a tag push.
