import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.components as PlasmaComponents3

PlasmaExtras.Representation {
    id: full

    readonly property string errorMsg: root.errorMessage
    readonly property string statusMsg: root.statusMessage
    readonly property bool hasData: root.hasData

    implicitWidth: Kirigami.Units.gridUnit * 21
    implicitHeight: contentLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    // Kept low so the popup sizes to its rows rather than reserving empty space
    // when only a couple of limits are reported.
    Layout.minimumHeight: Kirigami.Units.gridUnit * 6
    Layout.maximumWidth: Kirigami.Units.gridUnit * 32
    Layout.maximumHeight: Kirigami.Units.gridUnit * 32

    // One limit row, laid out the way the Claude desktop app presents them:
    // name on the left, reset summary and percentage right-aligned, thin rail below.
    component LimitRow: ColumnLayout {
        id: limitRow

        property string title: ""
        property real usage: 0.0
        property string resetsAt: ""

        Layout.fillWidth: true
        spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: limitRow.title
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            QQC2.Label {
                text: {
                    root.nowTick; // dependency: keep the countdown fresh
                    return limitRow.resetsAt ? root.formatResetSummary(limitRow.resetsAt) : "";
                }
                visible: text !== ""
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }

            QQC2.Label {
                text: Math.round(limitRow.usage * 100) + "%"
                color: {
                    if (limitRow.usage >= 0.90) return Kirigami.Theme.negativeTextColor;
                    if (limitRow.usage >= 0.75) return Kirigami.Theme.neutralTextColor;
                    return Kirigami.Theme.disabledTextColor;
                }
                horizontalAlignment: Text.AlignRight
                // Reserve the width of "100%" so the rails below stay aligned
                // across rows regardless of each row's current value.
                Layout.minimumWidth: percentMetrics.width
            }
        }

        UsageBar {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.4
            value: limitRow.usage
        }
    }

    TextMetrics {
        id: percentMetrics
        font: Kirigami.Theme.defaultFont
        text: "100%"
    }

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent

            Kirigami.Heading {
                text: i18n("Plan usage limits")
                level: 4
                Layout.fillWidth: true
            }

            PlasmaComponents3.BusyIndicator {
                running: root.fetching
                visible: running
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: !root.fetching
                onClicked: root.refresh()
                PlasmaComponents3.ToolTip {
                    text: i18n("Refresh now")
                }
            }
        }
    }

    // Error state — with a retry action, so the user is not forced to hunt for
    // the refresh button in the header.
    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: full.errorMsg !== ""
        iconName: "dialog-warning"
        text: i18n("Cannot load usage")
        explanation: full.errorMsg

        helpfulAction: Kirigami.Action {
            icon.name: "view-refresh"
            text: i18n("Retry")
            onTriggered: root.refresh()
        }
    }

    // First-load state — previously the popup showed a misleading 0% here.
    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: full.errorMsg === "" && !full.hasData
        iconName: "view-refresh"
        text: full.statusMsg !== "" ? full.statusMsg : i18n("Loading usage data...")
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing
        visible: full.errorMsg === "" && full.hasData

        // Rows are data-driven: whatever limits the API reports get a row, so a
        // newly introduced model-scoped limit appears without a code change.
        Repeater {
            model: {
                root.usageBuckets; // dependency: rebuild when the payload changes
                return root.visibleBuckets();
            }

            delegate: ColumnLayout {
                required property int index
                required property var modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: index > 0
                }

                LimitRow {
                    title: modelData.label
                    usage: modelData.usage
                    resetsAt: modelData.resetsAt
                }
            }
        }

        Item { Layout.fillHeight: true }

        QQC2.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: full.statusMsg !== ""
                ? full.statusMsg
                : i18n("Updated %1", root.formatLastUpdated())
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
        }
    }
}
