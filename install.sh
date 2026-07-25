#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR/package"
PLUGIN_ID="com.github.claude-code-usage"

RESTART=0
for arg in "$@"; do
    case "$arg" in
        --restart) RESTART=1 ;;
        -h|--help)
            echo "Usage: bash install.sh [--restart]"
            echo "  --restart  Clear the QML cache and restart plasmashell afterwards."
            exit 0
            ;;
        *)
            echo "Error: unknown option '$arg' (try --help)"
            exit 1
            ;;
    esac
done

if [ ! -d "$PACKAGE_DIR" ]; then
    echo "Error: package/ directory not found at $PACKAGE_DIR"
    exit 1
fi

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "Error: kpackagetool6 not found. This widget requires KDE Plasma 6."
    exit 1
fi

# Try to update first; if that fails (not installed yet), do a fresh install.
# Both streams are suppressed because kpackagetool6 prints "Plugin ... is not
# installed" on stdout, which is expected noise on a first install.
if kpackagetool6 -t Plasma/Applet -u "$PACKAGE_DIR" >/dev/null 2>&1; then
    echo "Widget updated successfully."
else
    kpackagetool6 -t Plasma/Applet -i "$PACKAGE_DIR"
    echo "Widget installed successfully."
fi

if [ "$RESTART" -eq 1 ]; then
    echo "Clearing QML cache and restarting plasmashell..."
    rm -rf ~/.cache/plasmashell/qmlcache
    # plasmashell --replace detaches; the old instance exits on its own.
    (plasmashell --replace >/dev/null 2>&1 &)
    echo "plasmashell restarted."
else
    echo ""
    echo "plasmashell caches QML, so run this to pick up the changes:"
    echo "  rm -rf ~/.cache/plasmashell/qmlcache && plasmashell --replace &>/dev/null & disown"
    echo "(or re-run this script with --restart)"
fi

echo ""
echo "To use: Right-click your panel → 'Add Widgets' → search 'Claude Code Usage'"
echo "To uninstall: kpackagetool6 -t Plasma/Applet -r $PLUGIN_ID"
