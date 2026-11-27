import QtQuick
import "../.."

Item {
    id: root

    property var points: []
    property color lineColor: Theme.ok
    property var secondaryPoints: []
    property color secondaryLineColor: Theme.info
    property real drawProgress: 1.0

    implicitHeight: 44

    onPointsChanged: canvas.requestPaint()
    onSecondaryPointsChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onSecondaryLineColorChanged: canvas.requestPaint()
    onDrawProgressChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    function animateDraw() {
        if (Theme.reduceMotion) {
            drawAnim.stop();
            drawProgress = 1.0;
            canvas.requestPaint();
            return;
        }
        drawProgress = 0.0;
        drawAnim.restart();
    }

    NumberAnimation {
        id: drawAnim
        target: root
        property: "drawProgress"
        from: 0.0
        to: 1.0
        duration: 650
        easing.type: Easing.OutCubic
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (width <= 0 || height <= 0) return;

            function drawSeries(pts, col, fillAlpha) {
                if (!pts || pts.length < 2) return;
                const maxCount = Math.max(2, Math.round(pts.length * root.drawProgress));
                const stepX = width / Math.max(1, pts.length - 1);

                ctx.beginPath();
                for (let i = 0; i < maxCount; ++i) {
                    const x = i * stepX;
                    const val = Math.max(0, Math.min(100, Number(pts[i]) || 0));
                    const y = height - 4 - (val / 100.0) * (height - 8);
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }

                const lastX = (maxCount - 1) * stepX;
                const grad = ctx.createLinearGradient(0, 0, 0, height);
                grad.addColorStop(0, Qt.rgba(col.r, col.g, col.b, fillAlpha));
                grad.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0.0));

                ctx.strokeStyle = col;
                ctx.lineWidth = 2;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.stroke();

                ctx.lineTo(lastX, height);
                ctx.lineTo(0, height);
                ctx.closePath();
                ctx.fillStyle = grad;
                ctx.fill();
            }

            if (root.secondaryPoints && root.secondaryPoints.length >= 2) {
                drawSeries(root.secondaryPoints, root.secondaryLineColor, 0.22);
            }
            drawSeries(root.points, root.lineColor, 0.36);
        }
    }
}
