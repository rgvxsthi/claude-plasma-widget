import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A thin, flat usage rail styled after the Claude Desktop plan-usage panel:
// a low-contrast track with an accent-coloured fill, rather than a bordered box.
Item {
    id: usageBar

    property real value: 0.0        // 0.0 to 1.0
    property string label: ""       // e.g. "5h", "7d"
    property bool showPercentage: false
    property bool dimmed: false     // no data yet, or an error is showing

    // Rail thickness. Deliberately thin — the bar reads as a line, not a container.
    property int barThickness: Math.max(2, Math.round(Kirigami.Units.gridUnit * 0.22))

    implicitHeight: Math.max(barThickness, Math.round(Kirigami.Units.gridUnit * 0.7))
    implicitWidth: Kirigami.Units.gridUnit * 6

    readonly property real clampedValue: Math.min(1.0, Math.max(0.0, value))

    // Accent blue at normal levels, matching Claude Desktop. The amber/red steps
    // are kept because a panel widget exists to warn you before you hit the cap.
    // Thresholds come from main.qml so the bars, the icon and the percentage text
    // all step at the same points.
    readonly property color barColor: dimmed
        ? Kirigami.Theme.disabledTextColor
        : root.usageLevelColor(clampedValue, Kirigami.Theme.highlightColor)

    readonly property color trackColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                                Kirigami.Theme.textColor.g,
                                                Kirigami.Theme.textColor.b, 0.15)

    // Font sizes derive from the row height, which is zero during the first layout
    // pass. Clamping avoids "font.pixelSize must be greater than 0" warnings and
    // text that never becomes visible.
    function scaledFontSize(basis, factor) {
        return Math.max(1, Math.round(basis * factor));
    }

    RowLayout {
        id: barRow
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // Label. Hidden on narrow panels where it would crowd out the rail itself.
        Text {
            text: usageBar.label
            color: Kirigami.Theme.textColor
            font.pixelSize: usageBar.scaledFontSize(barRow.height, 0.7)
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
            visible: usageBar.label !== "" && usageBar.width > Kirigami.Units.gridUnit * 3
        }

        Rectangle {
            id: track
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: usageBar.barThickness
            radius: height / 2
            color: usageBar.trackColor

            Rectangle {
                id: fill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                // Never render a sliver narrower than the rail is tall, otherwise a
                // small non-zero percentage rounds away to an invisible dot.
                width: usageBar.clampedValue <= 0
                    ? 0
                    : Math.max(parent.width * usageBar.clampedValue, parent.height)
                radius: parent.radius
                color: usageBar.barColor
                opacity: usageBar.dimmed ? 0.4 : 1.0

                Behavior on width {
                    NumberAnimation {
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.InOutQuad
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Kirigami.Units.longDuration
                    }
                }
            }
        }

        // Sits beside the rail rather than on top of it — a thin bar has no room
        // for an overlay.
        Text {
            text: Math.round(usageBar.clampedValue * 100) + "%"
            color: Kirigami.Theme.textColor
            font.pixelSize: usageBar.scaledFontSize(barRow.height, 0.62)
            Layout.alignment: Qt.AlignVCenter
            visible: usageBar.showPercentage && !usageBar.dimmed
        }
    }
}
