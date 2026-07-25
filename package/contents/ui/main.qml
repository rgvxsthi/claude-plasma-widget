import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // Every limit the API reported, in display order. Each entry is
    // { key, label, usage (0..1), resetsAt (ISO string), modelScoped (bool) }.
    property var usageBuckets: []

    // Kept as first-class properties because the panel view and the tooltip
    // always show these two specifically, regardless of what else exists.
    property real fiveHourUsage: 0.0
    property real sevenDayUsage: 0.0
    property string fiveHourResetsAt: ""
    property string sevenDayResetsAt: ""

    // The limit the panel is tracking, resolved from the panelSource setting.
    // Always an object: { key, label, shortLabel, usage, resetsAt }.
    readonly property var panelBucket: {
        usageBuckets; // dependency
        Plasmoid.configuration.panelSource; // dependency
        return resolvePanelBucket();
    }

    readonly property real peakUsage: panelBucket.usage

    // Presentation state. errorMessage is for genuine failures only; statusMessage
    // carries transient progress ("Loading...", "Refreshing token...") so the popup
    // does not show a warning icon for something that is merely in flight.
    property string errorMessage: ""
    property string statusMessage: ""
    property bool hasData: false
    property double lastUpdated: 0

    // Ticks every 30s purely so relative-time bindings ("resets in 4 hr 20 min")
    // re-evaluate. Bindings reference root.nowTick to declare the dependency.
    property int nowTick: 0

    // Internal state
    property string accessToken: ""
    property bool fetching: false
    property double tokenExpiresAt: 0
    property bool refreshingToken: false
    property double lastRefreshAttempt: 0

    // Minimum gap between `claude` invocations, so a persistently expired token
    // cannot spawn a CLI process on every poll.
    readonly property int refreshCooldownMs: 120000

    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 10

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    toolTipMainText: i18n("Claude Code Usage")
    toolTipSubText: {
        root.nowTick; // dependency: keep relative times fresh
        if (errorMessage !== "") return errorMessage;
        if (!hasData) return statusMessage !== "" ? statusMessage : i18n("Loading usage data...");

        var lines = [];
        for (var i = 0; i < usageBuckets.length; i++) {
            var bucket = usageBuckets[i];
            var line = i18n("%1: %2%", bucket.label, Math.round(bucket.usage * 100));
            if (bucket.resetsAt) {
                line += " — " + formatResetSummary(bucket.resetsAt);
            }
            lines.push(line);
        }
        if (statusMessage !== "") {
            lines.push(statusMessage);
        }
        return lines.join("\n");
    }

    // ---------------------------------------------------------------- formatting

    // Matches the phrasing used by the Claude desktop app: a countdown while the
    // reset is within a day, an absolute weekday and time beyond that.
    function formatResetSummary(isoString) {
        if (!isoString) return "";
        var d = new Date(isoString);
        if (isNaN(d.getTime())) return "";

        var deltaMinutes = Math.round((d.getTime() - Date.now()) / 60000);
        if (deltaMinutes <= 0) return i18n("Resets now");
        if (deltaMinutes < 60) return i18n("Resets in %1 min", deltaMinutes);
        if (deltaMinutes < 1440) {
            var hours = Math.floor(deltaMinutes / 60);
            var minutes = deltaMinutes % 60;
            return minutes > 0 ? i18n("Resets in %1 hr %2 min", hours, minutes)
                               : i18n("Resets in %1 hr", hours);
        }
        return i18n("Resets %1", Qt.formatDateTime(d, "ddd h:mm AP"));
    }

    // Compact countdown for the panel, where horizontal space is scarce: "4h 9m".
    function formatShortRemaining(isoString) {
        if (!isoString) return "";
        var d = new Date(isoString);
        if (isNaN(d.getTime())) return "";

        var deltaMinutes = Math.round((d.getTime() - Date.now()) / 60000);
        if (deltaMinutes <= 0) return i18nc("time remaining until a usage limit resets", "now");
        if (deltaMinutes < 60) return i18nc("minutes remaining", "%1m", deltaMinutes);

        var hours = Math.floor(deltaMinutes / 60);
        var minutes = deltaMinutes % 60;
        if (hours < 24) {
            return minutes > 0 ? i18nc("hours and minutes remaining", "%1h %2m", hours, minutes)
                               : i18nc("hours remaining", "%1h", hours);
        }
        var days = Math.floor(hours / 24);
        var remainingHours = hours % 24;
        return remainingHours > 0 ? i18nc("days and hours remaining", "%1d %2h", days, remainingHours)
                                  : i18nc("days remaining", "%1d", days);
    }

    function formatLastUpdated() {
        root.nowTick; // dependency: keep this label fresh
        if (root.lastUpdated <= 0) return i18n("never");
        var deltaSeconds = Math.round((Date.now() - root.lastUpdated) / 1000);
        if (deltaSeconds < 60) return i18n("just now");
        var minutes = Math.round(deltaSeconds / 60);
        if (minutes < 60) return i18nc("how long ago the data was fetched", "%1 min ago", minutes);
        return Qt.formatDateTime(new Date(root.lastUpdated), "hh:mm AP");
    }

    // ------------------------------------------------------------------- parsing

    // Normalises the usage payload into a flat, ordered list. Buckets arrive in two
    // shapes: named top-level objects carrying `utilization`, and model-scoped
    // entries inside a `limits` array carrying `percent` — Fable is reported the
    // latter way, as a limits[] entry whose scope.model.display_name is "Fable".
    //
    // The payload also contains internal codename keys (unreleased features). Those
    // are deliberately not surfaced: only the documented buckets and the plan-aware
    // limits[] entries are turned into rows.
    function buildUsageBuckets(resp) {
        var buckets = [];
        var seen = {};

        function push(key, label, obj, modelScoped) {
            if (!obj || seen[key]) return false;
            var raw = obj.utilization != null ? obj.utilization
                    : (obj.percent != null ? obj.percent : null);
            if (raw == null || isNaN(raw)) return false;
            seen[key] = true;
            buckets.push({
                key: key,
                label: label,
                usage: Math.max(0, Math.min(1, raw / 100.0)),
                resetsAt: obj.resets_at || "",
                modelScoped: !!modelScoped
            });
            return true;
        }

        push("five_hour", i18n("5-hour limit"), resp.five_hour, false);
        push("seven_day", i18n("Weekly · all models"), resp.seven_day, false);

        // limits[] is the plan-aware source of truth for per-model caps, so it wins.
        // Entries with a null scope are the account-wide 5-hour and weekly limits
        // already added above.
        var namedModels = {};
        if (resp.limits && resp.limits.length !== undefined) {
            for (var i = 0; i < resp.limits.length; i++) {
                var entry = resp.limits[i];
                var model = entry && entry.scope ? entry.scope.model : null;
                var displayName = model ? model.display_name : null;
                if (!displayName) continue;
                namedModels[displayName.toLowerCase()] = true;
                push("model_" + displayName, i18n("Weekly · %1", displayName), entry, true);
            }
        }

        // Fallback for plans that report a per-model cap as a top-level key instead.
        // Only added when limits[] did not already cover that model and the cap has
        // actually been used, otherwise every plan grows permanently empty rows.
        function pushTopLevelModel(key, name, obj) {
            if (namedModels[name.toLowerCase()]) return;
            if (!obj || !(obj.utilization > 0)) return;
            push(key, i18n("Weekly · %1", name), obj, true);
        }

        pushTopLevelModel("seven_day_sonnet", i18n("Sonnet"), resp.seven_day_sonnet);
        pushTopLevelModel("seven_day_opus", i18n("Opus"), resp.seven_day_opus);

        return buckets;
    }

    function bucketUsage(key) {
        for (var i = 0; i < usageBuckets.length; i++) {
            if (usageBuckets[i].key === key) return usageBuckets[i].usage;
        }
        return 0;
    }

    function bucketResetsAt(key) {
        for (var i = 0; i < usageBuckets.length; i++) {
            if (usageBuckets[i].key === key) return usageBuckets[i].resetsAt;
        }
        return "";
    }

    // Short tag for the panel: "5h", "7d", or the bare model name for per-model caps.
    function shortLabelFor(key, label) {
        if (key === "five_hour") return i18nc("short label for the 5-hour limit", "5h");
        if (key === "seven_day") return i18nc("short label for the weekly limit", "7d");
        if (key.indexOf("model_") === 0) return key.substring("model_".length);
        return label;
    }

    // Resolves the panel's tracked limit. An empty panelSource — the default —
    // means "whichever limit is highest right now", which is the number that
    // actually tells you how close you are to being cut off.
    function resolvePanelBucket() {
        var fallback = {
            key: "", label: i18n("Usage"),
            shortLabel: i18nc("short label when no limit is known", "—"),
            usage: 0, resetsAt: ""
        };
        if (!usageBuckets || usageBuckets.length === 0) return fallback;

        var wanted = Plasmoid.configuration.panelSource || "";
        var chosen = null;

        if (wanted !== "") {
            for (var i = 0; i < usageBuckets.length; i++) {
                if (usageBuckets[i].key === wanted) {
                    chosen = usageBuckets[i];
                    break;
                }
            }
            // Fall through to "highest" if the configured limit is no longer reported,
            // rather than showing a permanently blank panel.
        }

        if (!chosen) {
            for (var j = 0; j < usageBuckets.length; j++) {
                if (!chosen || usageBuckets[j].usage > chosen.usage) {
                    chosen = usageBuckets[j];
                }
            }
        }

        if (!chosen) return fallback;
        return {
            key: chosen.key,
            label: chosen.label,
            shortLabel: shortLabelFor(chosen.key, chosen.label),
            usage: chosen.usage,
            resetsAt: chosen.resetsAt
        };
    }

    // Publishes the discovered limits so the config page can offer them in its
    // picker. The config dialog runs in its own scope and cannot read applet state,
    // so this is the hand-off. Only written when the set actually changes, to keep
    // it from rewriting the config file on every poll.
    function publishKnownLimits() {
        var entries = [];
        for (var i = 0; i < usageBuckets.length; i++) {
            entries.push({ key: usageBuckets[i].key, label: usageBuckets[i].label });
        }
        var encoded = JSON.stringify(entries);
        if (encoded !== Plasmoid.configuration.knownLimits) {
            Plasmoid.configuration.knownLimits = encoded;
        }
    }

    // Model-scoped limits sitting at zero are noise, so they stay hidden until used.
    function visibleBuckets() {
        var result = [];
        for (var i = 0; i < usageBuckets.length; i++) {
            var bucket = usageBuckets[i];
            if (bucket.modelScoped && Plasmoid.configuration.hideUnusedModelLimits
                    && bucket.usage < 0.01) {
                continue;
            }
            result.push(bucket);
        }
        return result;
    }

    // --------------------------------------------------------------------- timers

    Timer {
        id: pollTimer
        interval: Math.max(15, Plasmoid.configuration.refreshInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchCredentials()
    }

    // Keeps relative timestamps ("in 4 hr 20 min", "3 min ago") current between polls.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowTick++
    }

    // Safety net: if a data source or XHR never calls back, `fetching` would stay
    // true forever and block every subsequent poll. Clear it after a hard timeout.
    Timer {
        id: watchdogTimer
        interval: 30000
        repeat: false
        onTriggered: {
            if (root.fetching) {
                root.fetching = false;
                root.refreshingToken = false;
                root.statusMessage = "";
                if (!root.hasData && root.errorMessage === "") {
                    root.errorMessage = i18n("Timed out while fetching usage data");
                }
            }
        }
    }

    // --------------------------------------------------------------- data sources

    Plasma5Support.DataSource {
        id: credentialsSource
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            credentialsSource.disconnectSource(source);

            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            var exitCode = data["exit code"] || 0;

            if (exitCode !== 0 || stdout.trim() === "") {
                root.finishWithError(i18n("Cannot read credentials file: %1",
                    stderr.trim() || i18n("file not found or empty")));
                return;
            }

            try {
                var creds = JSON.parse(stdout);
                // Find the first account with an accessToken
                var token = "";
                var expiresAt = 0;
                for (var key in creds) {
                    if (creds[key] && creds[key].accessToken) {
                        token = creds[key].accessToken;
                        expiresAt = creds[key].expiresAt || 0;
                        break;
                    }
                }

                if (!token) {
                    root.finishWithError(i18n("No access token found in credentials file"));
                    return;
                }

                root.accessToken = token;
                root.tokenExpiresAt = expiresAt;
                root.errorMessage = "";

                if (root.tokenExpiresAt > 0 && Date.now() > root.tokenExpiresAt) {
                    if (!root.refreshingToken && root.canAttemptRefresh()) {
                        root.triggerTokenRefresh();
                    } else {
                        root.finishWithError(i18n("Token expired — run `claude` in a terminal to sign in again"));
                        root.refreshingToken = false;
                    }
                    return;
                }

                root.refreshingToken = false;
                root.fetchUsage();
            } catch (e) {
                root.finishWithError(i18n("Invalid JSON in credentials file: %1", e.message));
            }
        }
    }

    Plasma5Support.DataSource {
        id: refreshSource
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            refreshSource.disconnectSource(source);

            var exitCode = data["exit code"] || 0;
            var stderr = (data["stderr"] || "").trim();

            // 127 from the shell means the binary was not found. plasmashell is
            // started by the session with a minimal PATH that usually excludes
            // ~/.local/bin, which is where Claude Code installs by default.
            if (exitCode === 127 || stderr.indexOf("command not found") !== -1) {
                root.refreshingToken = false;
                root.finishWithError(i18n("Claude CLI not found. Set its full path in the widget settings."));
                return;
            }
            if (exitCode === 124) {
                root.refreshingToken = false;
                root.finishWithError(i18n("Timed out refreshing the token via the Claude CLI"));
                return;
            }

            // Any other non-zero exit is not necessarily fatal: `claude -p ""` can
            // exit non-zero while still having written a fresh token. Re-read and see.
            root.fetching = false;
            root.fetchCredentials();
        }
    }

    // ---------------------------------------------------------------------- logic

    // Centralised failure path so `fetching` and the status line can never be left stale.
    function finishWithError(message) {
        root.errorMessage = message;
        root.statusMessage = "";
        root.fetching = false;
        watchdogTimer.stop();
    }

    function canAttemptRefresh() {
        if (!Plasmoid.configuration.autoRefreshToken) return false;
        return (Date.now() - root.lastRefreshAttempt) > root.refreshCooldownMs;
    }

    // Quote a path for POSIX sh, expanding a leading ~ to "$HOME" so the shell
    // resolves it. Everything after that is single-quoted to prevent injection.
    function shellQuotePath(path) {
        if (path === "~") {
            return "\"$HOME\"";
        }
        if (path.indexOf("~/") === 0) {
            return "\"$HOME\"'" + path.substring(1).replace(/'/g, "'\\''") + "'";
        }
        return "'" + path.replace(/'/g, "'\\''") + "'";
    }

    function fetchCredentials() {
        if (fetching) return;
        fetching = true;
        watchdogTimer.restart();

        if (!hasData && errorMessage === "") {
            statusMessage = i18n("Loading usage data...");
        }

        var path = Plasmoid.configuration.credentialsPath || "~/.claude/.credentials.json";
        credentialsSource.connectSource("timeout 5 cat " + shellQuotePath(path));
    }

    function triggerTokenRefresh() {
        root.refreshingToken = true;
        root.lastRefreshAttempt = Date.now();
        root.statusMessage = i18n("Refreshing token...");
        watchdogTimer.restart();

        // `claude -p ""` triggers the CLI's OAuth refresh during startup (which uses DPoP
        // internally) and writes the new token to the credentials file. An empty prompt
        // exits without making a model API call. timeout guards against hangs.
        var configuredPath = (Plasmoid.configuration.claudePath || "").trim();
        var binary = configuredPath !== "" ? shellQuotePath(configuredPath) : "claude";

        // plasmashell inherits a minimal session PATH (often just /usr/local/bin:/usr/bin:/bin),
        // so prepend the locations Claude Code actually installs into before falling back to it.
        var pathPrefix = 'PATH="$HOME/.local/bin:$HOME/bin:$HOME/.npm-global/bin:/usr/local/bin:$PATH" ';
        refreshSource.connectSource(pathPrefix + "timeout 12 " + binary + " -p '' </dev/null");
    }

    function fetchUsage() {
        if (!root.accessToken) {
            root.fetching = false;
            watchdogTimer.stop();
            return;
        }

        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + root.accessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.timeout = 10000;

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText);
                    root.usageBuckets = root.buildUsageBuckets(resp);
                    root.publishKnownLimits();
                    root.fiveHourUsage = root.bucketUsage("five_hour");
                    root.sevenDayUsage = root.bucketUsage("seven_day");
                    root.fiveHourResetsAt = root.bucketResetsAt("five_hour");
                    root.sevenDayResetsAt = root.bucketResetsAt("seven_day");
                    root.errorMessage = "";
                    root.statusMessage = "";
                    root.hasData = true;
                    root.lastUpdated = Date.now();
                    root.fetching = false;
                    watchdogTimer.stop();
                } catch (e) {
                    root.finishWithError(i18n("Failed to parse usage response: %1", e.message));
                }
            } else if (xhr.status === 401) {
                // Token rejected by API — try refreshing via claude CLI
                root.accessToken = "";
                if (!root.refreshingToken && root.canAttemptRefresh()) {
                    root.triggerTokenRefresh();
                } else {
                    root.refreshingToken = false;
                    root.finishWithError(i18n("Token rejected — run `claude` in a terminal to sign in again"));
                }
            } else if (xhr.status === 0) {
                root.finishWithError(i18n("Network error: cannot reach the Anthropic API"));
            } else if (xhr.status === 429) {
                root.finishWithError(i18n("Rate limited by the API — try a longer refresh interval"));
            } else {
                root.finishWithError(i18n("API error: HTTP %1", xhr.status));
            }
        };

        xhr.send();
    }

    // Manual refresh: clear the guards so the user always gets a real attempt.
    function refresh() {
        root.refreshingToken = false;
        root.lastRefreshAttempt = 0;
        root.fetching = false;
        root.errorMessage = "";
        root.statusMessage = i18n("Refreshing...");
        root.fetchCredentials();
    }
}
