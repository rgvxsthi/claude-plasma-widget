# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

KDE Plasma 6 panel widget that displays Claude Code token usage (5-hour session and 7-day weekly) as color-coded progress bars. Reads OAuth credentials from `~/.claude/.credentials.json` and polls the Anthropic usage API.

**Plugin ID:** `com.github.claude-code-usage`

## Install / Update / Uninstall

```bash
# Install or update, then clear the QML cache and restart plasmashell:
bash install.sh --restart

# Install/update only (no restart — changes will NOT be visible yet):
bash install.sh

# Uninstall:
kpackagetool6 -t Plasma/Applet -r com.github.claude-code-usage
```

Installed location: `~/.local/share/plasma/plasmoids/com.github.claude-code-usage/`

There are no build steps or tests. QML is interpreted at runtime by plasmashell.
Restarting plasmashell is mandatory after any QML change — it caches compiled QML.

## Validation

Static-check QML before installing (needs `qt6-qtdeclarative-devel`):

```bash
cd package/contents/ui
for f in *.qml; do qmllint-qt6 -I /usr/lib64/qt6/qml --unqualified disable "$f"; done
```

`--unqualified disable` is required: `root`, `Plasmoid`, and `i18n` are injected by
plasmashell at runtime, so qmllint reports them as unqualified access false positives.

## Architecture

**main.qml** is the root `PlasmoidItem`. It owns all state (usage values, error message, access token) and handles the data pipeline:
- Timer fires → `fetchCredentials()` reads the JSON file via `Plasma5Support.DataSource` (executable engine running `cat`) → parses out the first `accessToken` → `fetchUsage()` does an `XMLHttpRequest` GET to `https://api.anthropic.com/api/oauth/usage` → updates properties → QML bindings propagate to both representations.
- If the token is expired (or the API returns 401), `triggerTokenRefresh()` runs `claude -p ''` to make the CLI renew it, then re-reads the credentials file.

**State invariants to preserve:**
- `errorMessage` is for genuine failures only. Transient progress goes in `statusMessage`, otherwise the popup renders a warning icon for something merely in flight.
- Every terminal path must clear `fetching`, or the concurrency guard in `fetchCredentials()` blocks all future polls. Use `finishWithError()` rather than setting `errorMessage` by hand. `watchdogTimer` is the backstop.
- `refreshCooldownMs` prevents a persistently expired token from spawning a `claude` process on every poll. `refresh()` (manual) deliberately bypasses it.
- Relative-time bindings reference `root.nowTick` to declare a dependency on the 30 s tick timer; function calls alone are not reactive in QML.

**PATH caveat:** plasmashell is started by the session with a minimal `PATH`
(typically `/usr/local/bin:/usr/bin:/bin`), which excludes `~/.local/bin` where
Claude Code installs. `triggerTokenRefresh()` therefore prepends the usual install
locations, and the `claudePath` setting is the manual override. Exit code 127 from
the refresh data source is surfaced as "Claude CLI not found".

**CompactRepresentation.qml** (panel inline) and **FullRepresentation.qml** (click popup) both read state from `root.*` properties defined in main.qml. They don't fetch data themselves.

**UsageBar.qml** is the thin usage rail used by both representations. It takes a 0.0–1.0 `value` and tints with `Kirigami.Theme.highlightColor` normally, stepping to `neutralTextColor` at 75% and `negativeTextColor` at 90%.

**SparkIcon.qml** draws the Claude spark glyph on a `Canvas` from the 16x16 path used by ClaudeUsageBar. **images/claude-code-icon.svg** is the Claude Code mark, a single-path monochrome SVG rendered through `Kirigami.Icon` with `isMask` so it can be tinted by usage level.

**One colour scale:** `warnThreshold` (70%) and `criticalThreshold` (90%) live in main.qml, and everything colour-coded goes through `usageLevelColor(usage, normalColor)`. Don't reintroduce inline thresholds — the icon, percentage text, bars and popup rows previously drifted apart at 70 vs 75.

## Extra usage / spend

The payload describes pay-as-you-go credits **twice**, and both are null/disabled unless the account enabled it:

- `extra_usage` — `used_credits` / `monthly_limit` as minor units, with `decimal_places` and `currency` alongside, plus `is_enabled`.
- `spend` — `used` and `limit` as nested money objects `{amount_minor, currency, exponent}`, plus `percent` and `enabled`.

`buildCreditInfo()` prefers whichever actually carries figures and otherwise reports nothing. Amounts are rendered as `12.34 USD` rather than with a symbol, because the currency is whatever the account is billed in. Gated behind `showCreditUsage`, off by default — it is billing information.

## QML gotchas hit here

- **`contentHeight` is FINAL on `PlasmaExtras.Representation`.** Declaring a property with that name fails the whole component with "Cannot override FINAL property", which surfaces as "Type FullRepresentation unavailable". `qmllint` does *not* catch it; the journal does. The popup's own is `popupContentHeight`.
- **Plasma persists popup height and never grows it.** Once shown, `popupHeight` is stored in `plasma-org.kde.plasma.desktop-appletsrc`; adding a row later clips the bottom. `Layout.minimumHeight` is held at the content height to force Plasma to clamp the stored value back up.
- **`console.log()` is filtered** in plasmashell; `console.warn()` reaches the journal. Useful for probing the API payload shape.

## Usage buckets

`buildUsageBuckets()` normalises the API payload into `usageBuckets`, a flat ordered list of `{key, label, usage, resetsAt, modelScoped}`. The payload reports limits in two shapes:

- Top-level objects with `utilization` (0–100): `five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_opus`.
- A `limits` array whose entries carry `percent` and a `scope`. Entries with `scope: null` are the account-wide 5-hour/weekly limits already covered above; entries with `scope.model.display_name` are per-model weekly caps. **Fable arrives only this way** — there is no `seven_day_fable` key.

`limits[]` wins for per-model caps; the top-level `seven_day_sonnet`/`seven_day_opus` keys are a fallback used only when `limits[]` did not already name that model *and* the cap is non-zero, so plans don't grow permanently empty rows.

The payload also contains internal codename keys for unreleased features (`tangelo`, `nimbus_quill`, `cinder_cove`, ...). These are deliberately **not** surfaced — only documented buckets and `limits[]` entries become rows.

The popup is data-driven off `visibleBuckets()`, so a newly introduced limit gets a row with no code change.

**Config hand-off:** the settings dialog runs in its own scope and cannot read applet state, so `publishKnownLimits()` writes the discovered `{key,label}` list into the `knownLimits` config entry, and `configGeneral.qml` parses it to populate the "Track limit" picker. It only writes when the set changes, to avoid rewriting the config file on every poll.

**Config system:** `config/main.xml` defines the schema (KConfigXT), `config/config.qml` registers the settings tab, `ui/configGeneral.qml` is the settings page UI. Settings use `cfg_` property aliases for automatic Plasma config binding.

## API Details

- **Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
- **Auth:** `Authorization: Bearer {token}` + `anthropic-beta: oauth-2025-04-20`
- **Response fields:** `five_hour.utilization` and `seven_day.utilization` are percentages (0–100), divided by 100 in main.qml for the 0.0–1.0 bars. Reset times are in `*.resets_at` as ISO datetimes.

## Credentials File Format

`~/.claude/.credentials.json` has structure: `{ "claudeAiOauth": { "accessToken": "...", "refreshToken": "...", ... } }`. The code iterates top-level keys and picks the first object with an `accessToken` field.
