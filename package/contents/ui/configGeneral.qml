import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configPage

    property alias cfg_panelIcon: panelIconCombo.currentIndex
    property alias cfg_colorIconByUsage: colorIconCheck.checked
    property alias cfg_showPanelPercentage: showPercentageCheck.checked
    property alias cfg_showPanelResetTime: showResetTimeCheck.checked
    property alias cfg_showPanelLabel: showLabelCheck.checked
    property alias cfg_showPanelBars: showBarsCheck.checked
    property alias cfg_showWeeklyUsage: showWeeklyCheck.checked
    property alias cfg_showPercentageText: barPercentageCheck.checked
    property alias cfg_hideUnusedModelLimits: hideUnusedCheck.checked
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_credentialsPath: credentialsField.text
    property alias cfg_autoRefreshToken: autoRefreshCheck.checked
    property alias cfg_claudePath: claudePathField.text

    // Not aliases: these are driven by hand because a ComboBox stores a string key
    // rather than an index, and knownLimits is written by the applet, never here.
    property string cfg_panelSource: ""
    property string cfg_knownLimits: ""

    // "Highest" plus whatever limits the applet last saw. Falls back to the two
    // limits that always exist, so the picker is usable before the first fetch.
    readonly property var limitOptions: {
        var options = [{ key: "", label: i18n("Highest limit (automatic)") }];
        var discovered = [];
        try {
            if (cfg_knownLimits !== "") {
                discovered = JSON.parse(cfg_knownLimits);
            }
        } catch (e) {
            discovered = [];
        }
        if (!discovered || discovered.length === 0) {
            discovered = [
                { key: "five_hour", label: i18n("5-hour limit") },
                { key: "seven_day", label: i18n("Weekly · all models") }
            ];
        }
        return options.concat(discovered);
    }

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Panel")
        }

        QQC2.ComboBox {
            id: limitCombo
            Kirigami.FormData.label: i18n("Track limit:")
            textRole: "label"
            valueRole: "key"
            model: configPage.limitOptions
            onActivated: configPage.cfg_panelSource = currentValue

            // The model is rebuilt whenever the applet discovers new limits, so the
            // selection has to be re-resolved rather than set once at startup.
            function syncSelection() {
                var index = indexOfValue(configPage.cfg_panelSource);
                currentIndex = index >= 0 ? index : 0;
            }
            Component.onCompleted: syncSelection()
            onModelChanged: syncSelection()
        }

        QQC2.ComboBox {
            id: panelIconCombo
            Kirigami.FormData.label: i18n("Icon:")
            // Index order must match the Enum choices in config/main.xml.
            model: [
                i18n("None"),
                i18n("Claude Code mark"),
                i18n("Spark")
            ]
        }

        QQC2.CheckBox {
            id: colorIconCheck
            text: i18n("Tint the icon by usage level")
            enabled: panelIconCombo.currentIndex !== 0
        }

        QQC2.CheckBox {
            id: showPercentageCheck
            Kirigami.FormData.label: i18n("Show in panel:")
            text: i18n("Percentage used")
        }

        QQC2.CheckBox {
            id: showResetTimeCheck
            text: i18n("Time until reset")
        }

        QQC2.CheckBox {
            id: showLabelCheck
            text: i18n("Which limit is shown")
        }

        QQC2.CheckBox {
            id: showBarsCheck
            text: i18n("Usage bars")
        }

        QQC2.CheckBox {
            id: showWeeklyCheck
            Kirigami.FormData.label: i18n("Bars:")
            text: i18n("Include the weekly bar")
            enabled: showBarsCheck.checked
        }

        QQC2.CheckBox {
            id: barPercentageCheck
            text: i18n("Label each bar with its percentage")
            enabled: showBarsCheck.checked
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Popup")
        }

        QQC2.CheckBox {
            id: hideUnusedCheck
            Kirigami.FormData.label: i18n("Model limits:")
            text: i18n("Hide per-model weekly limits until they are used")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Updates")
        }

        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh interval:")
            from: 15
            to: 3600
            stepSize: 30
            editable: true

            textFromValue: function(value) {
                if (value < 60) return i18n("%1 seconds", value);
                if (value % 60 === 0) return i18np("%1 minute", "%1 minutes", value / 60);
                return i18n("%1 min %2 s", Math.floor(value / 60), value % 60);
            }

            valueFromText: function(text) {
                var digits = text.replace(/[^0-9]/g, "");
                return digits === "" ? refreshSpin.value : parseInt(digits, 10);
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Authentication")
        }

        QQC2.TextField {
            id: credentialsField
            Kirigami.FormData.label: i18n("Credentials file:")
            Layout.fillWidth: true
            placeholderText: "~/.claude/.credentials.json"
        }

        QQC2.CheckBox {
            id: autoRefreshCheck
            Kirigami.FormData.label: i18n("Expired token:")
            text: i18n("Refresh automatically using the Claude CLI")
        }

        QQC2.TextField {
            id: claudePathField
            Kirigami.FormData.label: i18n("Claude CLI path:")
            Layout.fillWidth: true
            enabled: autoRefreshCheck.checked
            placeholderText: i18n("Leave empty to search PATH")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            visible: autoRefreshCheck.checked
            text: i18n("Plasma runs with a minimal PATH that often excludes ~/.local/bin. If token refresh reports that the CLI was not found, enter its full path here — run `which claude` in a terminal to find it.")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }
    }
}
