import QtQuick
import "../../code/qrcode.js" as QR

/*
 * Dependency-free QR code renderer (no QtSvg required).
 * `text` holds the payload, e.g. the Android wireless-debugging QR string.
 */
Canvas {
    id: canvas

    property string text: ""
    property color darkColor: "#000000"
    property color lightColor: "#ffffff"
    property int quietZone: 2

    implicitWidth: 180
    implicitHeight: 180

    onTextChanged: requestPaint()
    onDarkColorChanged: requestPaint()
    onLightColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = canvas.lightColor;
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        if (!canvas.text || canvas.text.length === 0)
            return;

        let qr;
        try {
            qr = QR.generate(canvas.text);
        } catch (e) {
            console.warn("AndroLaunch: QR generation failed:", e);
            return;
        }

        const total = qr.size + canvas.quietZone * 2;
        const cell = Math.min(canvas.width / total, canvas.height / total);
        const offsetX = (canvas.width - cell * total) / 2;
        const offsetY = (canvas.height - cell * total) / 2;

        ctx.fillStyle = canvas.darkColor;
        for (let r = 0; r < qr.size; r++) {
            for (let c = 0; c < qr.size; c++) {
                if (qr.matrix[r][c] !== 1)
                    continue;
                ctx.fillRect(
                    Math.round(offsetX + (c + canvas.quietZone) * cell),
                    Math.round(offsetY + (r + canvas.quietZone) * cell),
                    Math.ceil(cell),
                    Math.ceil(cell)
                );
            }
        }
    }
}
