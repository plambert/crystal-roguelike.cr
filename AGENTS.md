# A terminal roguelike written in Crystal

The game is built on `github:plambert/termbuf-widgets.cr`. Anything general purpose written for it
lives under `src/roguelike/termbuf_ext/` so that extracting it to that shard is a file move.

`IMPLEMENTATION.md` is the design record: the phases as built, the decisions behind them, and the
list of what has been asked for and not yet built. `TODO.md` is the working list, in four sections:
Planned, Unplanned, Considered and Completed. Read it for what an item means, but do not edit it;
it has its own keeper. When a Planned item is finished, say so in your report and leave the move
to Completed to them.

## Finishing a piece of work

A change is finished when `crystal tool format --check`, `ameba`, `crystal spec` and `shards build`
are all clean, and `rumdl check` passes on any Markdown that changed. The changelog needs
`rumdl check --no-exclude CHANGELOG.md`. Run them; do not reason about whether they would pass.

Commit with explicit paths, never `git add -A`. A new file needs its own `git add` first.

Never add `Co-Authored-By`, `Claude-Session`, or any other mention of an AI assistant to a commit
message, a pull request, a comment, or any file in the repository.

## Commit messages

A plain statement of what the commit does. Imperative, one clause, under about 72 characters. Where
a commit did several things, list them as bullets in the body with a little more detail each.

Simple English. State the facts. No wordplay, no clever constructions, and no sentence whose
subject is the writing itself. Keep measurements and tables in the body: those are data.

## Code comments

Short, present tense, about what the code does now. No history of earlier approaches, no colon
hinged sentences, no "not X but Y". A comment that only restates the line under it is left out.

## Keeping the changelog

Every change a player or a packager would notice goes in `CHANGELOG.md` under `## [Unreleased]`, in
the same commit as the change itself. The headings are the Keep a Changelog set: Added, Changed,
Deprecated, Removed, Fixed, Security. Write what the change does, not how it was built. Internal
refactoring, comment sweeps and spec work are not listed. Lines wrap under 100 characters.

## Keeping the news

`NEWS.md` is what playtesters read. The release page and the Discord announcement show the
version's section from it, so it is written for someone deciding whether to download the release,
not for someone building it.

It is written once, when a release is cut, from the Unreleased section of the changelog. Ordinary
commits do not touch it, and it has no Unreleased section.

The voice is second person and present tense, saying what you will notice when you play. One lead
sentence with the gist, then at most five or six bullets, each one line. Group bullets under
`### New`, `### Changed` and `### Fixed` only when there are enough to need grouping. Leave out
anything a player cannot see: dependency versions, build and packaging mechanics, CI, specs,
refactors. Name a key only when the key is the news. No file names or code identifiers. A release
with nothing visible gets one sentence saying it is a maintenance release.

Good: "Goblin scouts are rarer on the first floor and their stones hurt less, so the first fight
is one you can win."

Bad: "Goblin scout spawn weight on floor 1 is reduced from 30 to 10 via a per-floor spawn weight
in Species, and stone damage is 1d4+1."

## Cutting a release

Releases are cut with the `/release` skill, which carries the whole procedure. The release
workflow refuses a tag whose version has no entry in both `CHANGELOG.md` and `NEWS.md`.
