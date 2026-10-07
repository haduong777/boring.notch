# Codex usage tab

The Codex tab uses the normal 120-point body inside the existing 190-point open
notch. It does not enlarge the window or borrow the expanded calendar layout.

- The tab shows the Codex icon and the remaining percentage. When the selected
  allowance is exhausted, it shows a reset countdown such as `2d 20h` or `2h 20m`.
- The panel places the account tier at the top right, the remaining allowance and
  progress track in the middle, and available limit resets, credits
  and reset countdown underneath.
- When both five-hour and weekly windows are present, five-hour usage is the
  primary display and weekly usage appears in the footer. A depleted window
  takes priority; if both are depleted, the later reset gates the display.
- Refreshing is automatic. The panel omits manual refresh and routine
  update/preview labels; the footer appears only for another quota window or
  a stale-data warning.
- Window names come from reported durations. Missing fields remain unavailable;
  they are not converted into zero. A known zero credit balance is displayed as
  zero, and unlimited credits remain explicitly unlimited.
- Token totals are omitted. Codex's available account token summary contains
  daily buckets rather than an exact quota-window total, and this integration
  does not scan local conversation logs to approximate one.

## Reader and refresh

The embedded XPC helper discovers the installed Codex CLI and launches a short,
read-only `codex app-server --listen stdio://` session. After initialization it
calls only `account/read` and `account/rateLimits/read`. Codex handles its saved
login and any normal token renewal. The main app receives an encoded snapshot
containing display fields; email addresses, account credentials and raw responses
are not exposed through the XPC method.

One shared manager serves all notch windows. It refreshes every two minutes, on
wake, and on opening an old panel. Failed reads back off to five
minutes. Each RPC session has a 15-second deadline, bounded output buffering and
child cleanup. Loading, missing CLI, signed-out, unsupported API-key/Bedrock
accounts and fetch failures have explicit states. Previous readings are marked
as stale after a failure or five minutes without a successful update; stale
percentages are removed from the tab label. An elapsed reset time triggers a new
read rather than an invented full allowance.

The main app retains its sandbox. The helper already runs outside it, so the
Codex child can use its existing sign-in without broadening the main app's file
permissions. Monitoring sends no model prompt, switches no account, purchases no
credits and consumes no banked reset.

References: [official app-server protocol](https://learn.chatgpt.com/docs/app-server)
and [Codex setup](https://learn.chatgpt.com/docs/quickstart).
The Swift implementation is original; no third-party tracker package was added.
`CodexIcon.imageset/codex.svg` uses the official Codex vector glyph from the
installed ChatGPT desktop app (`webview/assets/codex_new-f14177b03534.svg`). Its
outer contour and terminal shapes form a monochrome silhouette, rendered as a
template image to match the selected and unselected tab colors.

## Preview

Quit the previous Calendar Preview before rebuilding, then run from the repo:

```sh
bash scripts/preview-calendar.sh
```

The script builds an ad-hoc signed app with the separate identity
`dev.hadg.boringnotch.calendar-preview`, preserves the main sandbox and helper
entitlements, and disables automatic update checks for that preview. Hover over
the notch and click the Codex icon. Usage comes from the current Codex login.
Production signing/notarization is a separate distribution check.

For account-independent UI checks, Debug supports fixtures:

```sh
BORING_NOTCH_CODEX_PREVIEW=exhausted-weekly bash scripts/preview-calendar.sh
```

Available fixtures: `weekly`, `five-hour`, `exhausted-weekly`, `exhausted-five-hour`,
`unknown-credits`, `stale`, `signed-out`, and `missing-cli`. Fixtures make no usage
requests and are excluded from Release builds. The preview script also accepts
`BORING_NOTCH_DERIVED_DATA` to reuse an existing Xcode build cache.

## Verification

Run the offline decoder and subprocess tests with:

```sh
bash scripts/test-codex-usage.sh
```

The tests cover window selection, multi-bucket precedence, percentage bounds,
countdown formatting, nullable credits/reset inventory, account setup states,
plan fallback, tiny credit balances, fragmented JSONL replies, notifications and
bounded timeout cleanup. They do not access a live account or start a model task.
All 30 checks passed. Debug and Release builds succeeded; the Release binary was
also checked to confirm that the fixture launch argument is absent.

The native preview has been inspected in weekly, exhausted-weekly and live
five-hour states, including manual refresh and switching between Home, expanded
calendar and Shelf. The revised spacing and standard height were inspected after
refinement. A live read through the sandboxed app and unsandboxed helper succeeded.
Remaining runtime checks include a full VoiceOver/keyboard pass, Reduce Motion,
and additional displays. Missing-data/setup fixture checks were interrupted when
the Mac locked.

The shared body frame now survives tab changes, so replacing an expanded Home
view with Shelf or Codex retains an animatable height. The month-expansion reset
runs in a 0.35-second animation and respects Reduce Motion. The native panel stays
fixed and top-aligned.
