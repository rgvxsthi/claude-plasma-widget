# Claude Code Usage — KDE Plasma 6 Widget

A panel widget that shows your Claude Code token usage at a glance. Sits alongside your clock, network widget, etc.

![Compact view shows two progress bars: 5-hour session and 7-day weekly usage]

## Features

- **Claude-style popup** — laid out like the Claude desktop app's plan usage panel:
  one row per limit with a reset summary, percentage, and a thin accent rail
- **Every limit, automatically** — the 5-hour and weekly caps plus any per-model
  weekly limit the API reports (Fable, Sonnet, Opus), with no code change needed
  when a new one appears
- **Spark panel indicator** — the Claude spark glyph tinted by how close you are to
  a cap (green under 70%, amber to 90%, red beyond), next to the headline percentage
- **Middle-click to refresh** — without opening the popup
- **Auto-refreshing** — polls the Anthropic usage API on a configurable interval (default 10 min)
- **Automatic token refresh** — when the OAuth token expires, the widget re-runs the Claude CLI to renew it
- **Horizontal and vertical panels** — sizing adapts to the panel orientation
- **Theme-aware** — uses Kirigami/Plasma theme colors, so it follows your accent color

### Panel display

The panel readout is built from independent parts, so you can compose exactly what
you want — for example `🦀 15% • 4h 1m`:

| Part | Default | Notes |
|------|---------|-------|
| Icon | Claude Code mark | Or the spark glyph, or none |
| Tint icon by usage | On | Green under 70%, amber to 90%, red beyond |
| Percentage used | On | |
| Time until reset | On | Compact form: `4h 1m`, `13m`, `2d 3h` |
| Which limit is shown | Off | Short tag such as `5h`, `7d`, `Fable` |
| Usage bars | On | Thin `5h` / `7d` rails |

**Track limit** picks which limit drives the icon, percentage, and countdown:
the highest one (default), the 5-hour limit, the weekly limit, or any per-model
limit the API reports. The picker is populated from limits actually seen on your
account, so `Weekly · Fable` appears once your plan reports it.

Tracking *the highest* is the useful default — it is the number that tells you how
close you are to being cut off, whichever cap that happens to be.

## Requirements

- KDE Plasma 6
- Claude Code with OAuth login (`~/.claude/.credentials.json` must exist)

## Install

```bash
git clone https://github.com/fluffyspace/claude-plasma-widget.git
cd claude-plasma-widget
bash install.sh --restart
```

Then right-click your panel → **Add Widgets** → search **Claude Code Usage** → drag to panel.

## Update

```bash
bash install.sh --restart
```

`--restart` clears the QML cache and restarts plasmashell, which is required for
plasmashell to pick up changed QML. Omit it to install without restarting.

## Uninstall

```bash
kpackagetool6 -t Plasma/Applet -r com.github.claude-code-usage
```

## Configuration

Right-click the widget → **Configure**:

**Panel** — see the table above, plus **Track limit**.

**Popup**

| Setting | Default | Description |
|---------|---------|-------------|
| Hide per-model weekly limits until used | Off | Collapses rows sitting at 0% |

**Updates**

| Setting | Default | Description |
|---------|---------|-------------|
| Refresh interval | 10 min | Time between API polls (15 s – 60 min) |

**Authentication**

| Setting | Default | Description |
|---------|---------|-------------|
| Credentials file | `~/.claude/.credentials.json` | Path to Claude Code credentials |
| Expired token | On | Auto-renew an expired token via the Claude CLI |
| Claude CLI path | *(empty)* | Full path to `claude`; empty searches `PATH` |

## Troubleshooting

**"Claude CLI not found"** — plasmashell is started by the session manager with a
minimal `PATH` (typically `/usr/local/bin:/usr/bin:/bin`), which excludes
`~/.local/bin` where Claude Code installs by default. The widget prepends the
usual install locations, but if your `claude` lives elsewhere, run `which claude`
in a terminal and paste the full path into **Claude CLI path** in the settings.

**"Token expired — run `claude` in a terminal to sign in again"** — the refresh
attempt did not produce a valid token. Run `claude` yourself to re-authenticate.

**Changes to the widget do not appear** — plasmashell caches compiled QML. Run
`bash install.sh --restart`.

## Credits

- Originally by [sizeak](https://github.com/sizeak/claude-plasma-widget), with the
  auto-refresh work from [fluffyspace](https://github.com/fluffyspace/claude-plasma-widget).
  This repo continues from that branch with a reworked UI and data model.
- Popup layout follows the plan usage panel in the Claude desktop app.
- The spark glyph and its colour thresholds come from
  [ClaudeUsageBar](https://github.com/Artzainnn/ClaudeUsageBar) (MIT), a macOS menu
  bar app for the same job.
- `package/contents/images/claude-code-icon.svg` is the Claude Code mark and belongs
  to Anthropic; it is bundled for identification only.

## License

MIT — see [LICENSE](LICENSE).
