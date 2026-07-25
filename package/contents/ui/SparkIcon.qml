import QtQuick

// The Claude spark glyph, drawn from the 16x16 path used by the ClaudeUsageBar
// menu bar app so the two read as the same mark:
//   M8 1L9 6L13 3L10 7L15 8L10 9L13 13L9 10L8 15L7 10L3 13L6 9L1 8L6 7L3 3L7 6Z
// The shape is symmetric under a 180-degree rotation, so the y-axis flip between
// AppKit and Canvas coordinates makes no visual difference.
Canvas {
    id: spark

    property color color: "white"

    // Path vertices in the original 16x16 design grid.
    readonly property var points: [
        [8, 1], [9, 6], [13, 3], [10, 7], [15, 8], [10, 9], [13, 13], [9, 10],
        [8, 15], [7, 10], [3, 13], [6, 9], [1, 8], [6, 7], [3, 3], [7, 6]
    ]

    implicitWidth: 16
    implicitHeight: 16

    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (width <= 0 || height <= 0) return;

        // Uniform scale, centred, so the glyph never distorts in a panel.
        var scale = Math.min(width, height) / 16;
        var offsetX = (width - 16 * scale) / 2;
        var offsetY = (height - 16 * scale) / 2;

        ctx.fillStyle = spark.color;
        ctx.beginPath();
        for (var i = 0; i < points.length; i++) {
            var x = offsetX + points[i][0] * scale;
            var y = offsetY + points[i][1] * scale;
            if (i === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        }
        ctx.closePath();
        ctx.fill();
    }
}
