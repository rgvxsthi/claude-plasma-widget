import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

Item {
    id: compact

    // Icon choices, matching the Enum order declared in config/main.xml.
    readonly property int iconNone: 0
    readonly property int iconClaudeCode: 1
    readonly property int iconSpark: 2

    readonly property int panelIcon: Plasmoid.configuration.panelIcon
    readonly property bool showIcon: panelIcon !== iconNone
    readonly property bool showPercentage: Plasmoid.configuration.showPanelPercentage
    readonly property bool showResetTime: Plasmoid.configuration.showPanelResetTime
    readonly property bool showLabel: Plasmoid.configuration.showPanelLabel
    readonly property bool showBars: Plasmoid.configuration.showPanelBars
    readonly property bool colorIcon: Plasmoid.configuration.colorIconByUsage

    // The readout block is anything that is not the bars.
    readonly property bool showReadout: showIcon || showPercentage || showResetTime || showLabel

    readonly property var bucket: root.panelBucket
    readonly property real fiveHourUsage: root.fiveHourUsage
    readonly property real sevenDayUsage: root.sevenDayUsage
    readonly property bool showWeekly: Plasmoid.configuration.showWeeklyUsage
    readonly property bool showBarPercent: Plasmoid.configuration.showPercentageText
    readonly property bool hasError: root.errorMessage !== ""
    readonly property bool isLoading: !root.hasData && !hasError
    readonly property bool dimmed: hasError || isLoading
    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Same steps the ClaudeUsageBar menu bar app uses: green until 70%, amber to
    // 90%, red beyond.
    readonly property color usageColor: {
        if (dimmed) return Kirigami.Theme.disabledTextColor;
        if (bucket.usage >= 0.90) return Kirigami.Theme.negativeTextColor;
        if (bucket.usage >= 0.70) return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.positiveTextColor;
    }

    // A vertical panel constrains width, a horizontal one constrains height, so the
    // preferred size has to be expressed along the free axis only.
    Layout.preferredWidth: isVertical ? -1 : mainLayout.implicitWidth
    Layout.minimumWidth: isVertical ? -1 : Kirigami.Units.gridUnit * 2
    Layout.preferredHeight: isVertical
        ? Kirigami.Units.gridUnit * (showBars && showWeekly ? 2.6 : 1.4)
        : -1
    Layout.minimumHeight: isVertical ? Kirigami.Units.gridUnit : -1

    // Text sizing is derived from the panel height, which is zero on the first
    // layout pass; clamping keeps Text items from warning and vanishing.
    readonly property int readoutFontSize: Math.max(1, Math.round(height * 0.55))
    readonly property int iconSize: Math.max(8, Math.round(height * 0.75))

    RowLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: Math.round(Kirigami.Units.smallSpacing / 2)
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            id: readout
            visible: compact.showReadout
            spacing: Math.round(Kirigami.Units.smallSpacing / 2)
            Layout.alignment: Qt.AlignVCenter

            // The Claude Code mark. It is a single-path monochrome glyph, so it
            // recolours cleanly as a mask when tinting by usage is enabled.
            Kirigami.Icon {
                visible: compact.panelIcon === compact.iconClaudeCode
                source: Qt.resolvedUrl("../images/claude-code-icon.svg")
                isMask: compact.colorIcon
                color: compact.usageColor
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: compact.iconSize
                Layout.preferredWidth: compact.iconSize
            }

            SparkIcon {
                visible: compact.panelIcon === compact.iconSpark
                color: compact.colorIcon ? compact.usageColor : Kirigami.Theme.textColor
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: compact.iconSize
                Layout.preferredWidth: compact.iconSize
            }

            // Which limit is being shown — useful once the panel tracks something
            // other than "highest", e.g. "Fable".
            Text {
                visible: compact.showLabel
                text: compact.dimmed ? "" : compact.bucket.shortLabel
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: compact.readoutFontSize
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: compact.showPercentage
                text: compact.dimmed ? "—" : Math.round(compact.bucket.usage * 100) + "%"
                color: Kirigami.Theme.textColor
                font.pixelSize: compact.readoutFontSize
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }

            // Separates the percentage from the countdown, so the two numbers do not
            // read as one value: "15% • 4h 2m".
            Text {
                visible: compact.showPercentage && resetTimeLabel.visible
                text: "•"
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: compact.readoutFontSize
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Math.round(Kirigami.Units.smallSpacing / 2)
                Layout.rightMargin: Math.round(Kirigami.Units.smallSpacing / 2)
            }

            Text {
                id: resetTimeLabel
                visible: compact.showResetTime && text !== ""
                text: {
                    root.nowTick; // dependency: keep the countdown fresh
                    if (compact.dimmed || !compact.bucket.resetsAt) return "";
                    return root.formatShortRemaining(compact.bucket.resetsAt);
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: compact.readoutFontSize
                Layout.alignment: Qt.AlignVCenter
            }
        }

        ColumnLayout {
            id: barLayout
            visible: compact.showBars
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            spacing: Math.round(Kirigami.Units.smallSpacing / 2)

            UsageBar {
                Layout.fillWidth: true
                Layout.fillHeight: true
                value: compact.hasError ? 0 : compact.fiveHourUsage
                label: "5h"
                showPercentage: compact.showBarPercent
                dimmed: compact.dimmed
            }

            UsageBar {
                Layout.fillWidth: true
                Layout.fillHeight: true
                value: compact.hasError ? 0 : compact.sevenDayUsage
                label: "7d"
                showPercentage: compact.showBarPercent
                dimmed: compact.dimmed
                visible: compact.showWeekly
            }
        }
    }

    // Error indicator, shown only when nothing else in the panel would reveal the
    // failure (the icon and percentage already grey out on their own).
    Kirigami.Icon {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        source: "dialog-warning"
        visible: compact.hasError && !compact.showReadout
    }

    // Sibling of the layout rather than its parent, so the bars are not children
    // of a MouseArea and hit-testing stays predictable.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh();
            } else {
                root.expanded = !root.expanded;
            }
        }
    }
}
