# Modern controls implementation status

Worktree: `.agents/worktrees/modern-controls/` in the original checkout.
Branch: `feature/modern-controls`.

## Current state

The reusable foundations are integrated and validated. Complete gameplay input wiring is
still in progress on `feature/modern-controls-ui`; the Modern option is not ready to use
as a complete control scheme in this checkout yet. No changes have been merged into main.

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

## Remaining integration and validation

* Profile-aware gameplay, menu, form, help, history, and replay input bindings.
* Command dispatch through the existing shared action flows, with parent menu restoration.
* First-launch startup and live scheme switching from Options.
* Letterless modern item presentation and final end-to-end acceptance coverage.
* Keyboard-only and mixed mouse/keyboard smoke testing of the completed feature.

The agreed controls are spatial movement, Shift+direction walking, Ctrl+X explore, `r` for
all commands, `f` for available commands, `i` for inventory, and Tab/Shift+Tab for panels.
`.` waits in both schemes, plain Space pages messages, and Shift+Space waits only with
kitty keyboard support. Both schemes keep `<` and `>` for shared staircase navigation.

## Latest validation

The integrated foundations pass formatting, ameba, all 4,130 specs, `shards build`, and
the explicit changelog Markdown check. The completed interface will be validated again
after integration. There are no questions requiring a user decision at this stage.
