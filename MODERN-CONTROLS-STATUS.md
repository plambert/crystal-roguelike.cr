# Modern controls implementation status

Worktree: `.agents/worktrees/modern-controls/` in the original checkout.
Branch: `feature/modern-controls`.

## Current state

The complete interface is implemented in this worktree. The feature and its supporting
branches are committed locally. No changes have been merged into main or pushed.

The Planned TODO item "A modern control configuration" is implemented. `TODO.md` remains
unchanged for its keeper to move the item to Completed.

## Integrated

* Shared keyboard and mouse staircase previews, including repeat-to-follow, expiry,
  cancellation, and floor invalidation. Arriving at stairs does not change floors.
* Traditional and Modern scheme preferences, migration, a compact side-by-side chooser,
  and safe choice persistence with a current-session fallback after a write failure.
* Injected reusable menu navigation, letterless selection, typed menu values, named safe
  confirmations, live navigation rebinding, and arbitrary-length target lists.
* A typed command catalog with stable categories, complete and available projections,
  semantic targets, and read-only viewer restrictions.
* A regression preventing the key that opens a child menu from activating that child.
* Compact comparison and named confirmation layouts that keep instructions and safe
  choices visible at 40x16, including confirmation selection after resizing.
* Modern movement and walking, catalogs, inventory, item actions, targeting, confirmations,
  panel navigation, forms, help, history, startup, and read-only replay controls.
* First-launch prompting, saved preference migration, comparison from Options, and live
  scheme switching that replaces owned keybindings without dropping caller bindings.
* Grouped quantities and item details, coordinate-specific spike targets, nested utility
  return paths, and readable compact end-screen outcomes.
* Independent keypress acceptance tests and reviewed workflow regressions.

## Try it

Run from this worktree:

```sh
bin/crystal-roguelike --no-autosubmit --no-update-check
```

If no scheme has been chosen, the side-by-side comparison appears first. Select a card
with arrows or `a/d`, then confirm with `f` or Enter. The default highlight is Modern.
The choice is saved to `options.json` without changing other preferences.

For an existing Traditional configuration, `O` opens Options. Change Control scheme in the
Input section or choose Compare. In Modern, open Options from the `r` or `f` catalog.
Traditional also has `F2` for the shared catalog.

To try a run without game saves, add `--no-save`. UI preferences still follow the existing
Options persistence policy. To isolate all testing state, set `XDG_STATE_HOME` to a fresh
temporary directory before launching.

## Controls

The agreed controls are spatial movement, Shift+direction walking, Ctrl+X explore, `r` for
all commands, `f` for available commands, `i` for inventory, and Tab/Shift+Tab for panels.
`.` waits in both schemes, plain Space pages messages, and Shift+Space waits only with
kitty keyboard support. Both schemes keep `<` and `>` for shared staircase navigation.

In lists, use `w/s` to select, `a/d` for tabs, `f` or Enter to activate, and Escape to go
back. Text fields retain normal typing. Traditional dedicated keys and item letters remain
available under the Traditional scheme.

## Compatibility notes

* Inventory letters remain internal model identifiers. Modern does not bind item-selection
  keys to them or show their gutters. Existing narrative history may still mention legacy
  item-letter annotations as text; those are not active modern shortcuts.
* The color picker retains its existing arrow and Tab controls inside the editing popup;
  the surrounding modern theme form supports the selectable navigation keys.
* The terminal smoke checks use forced 256-color, non-kitty input. Modifier-aware Wait is
  covered by capability and synthetic-event tests, not a physical kitty keyboard session.
* Platform execution checks were performed on macOS; no Windows or Linux CI was run here.

## Latest validation

This integration worktree passes formatting, ameba, all 4,176 specs, `shards build`, and
Markdown checks. Both golden replay fixtures verify with the built executable. A real
pseudo-terminal smoke run of this executable passes at 80x24 and 40x16, covering first-launch
choice, saved preference, inventory, both catalogs, confirmation, and exit.

There are no blocking questions requiring a user decision.
