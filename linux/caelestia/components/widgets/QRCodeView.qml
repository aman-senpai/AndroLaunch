pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import "../../utils/QRCode.js" as QR

Item {
    id: root

    property string text: ""
    property color darkColor: "#000000"
    property color lightColor: "#ffffff"
    property int quietZone: 2

    implicitWidth: 200
    implicitHeight: 200

    onTextChanged: canvas.requestPaint()
    onDarkColorChanged: canvas.requestPaint()
    onLightColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            if (!root.text || root.text.length === 0)
                return;

            let qr;
            try {
                qr = QR.generate(root.text);
            } catch (e) {
                console.warn("QRCode generation error:", e);
                return;
            }

            const matrix = qr.matrix;
            const matrixSize = qr.size;
            const totalModules = matrixSize + root.quietZone * 2;
            const moduleSize = Math.floor(Math.min(width, height) / totalModules);
            const offsetX = Math.floor((width - moduleSize * totalModules) / 2) + root.quietZone * moduleSize;
            const offsetY = Math.floor((height - moduleSize * totalModules) / 2) + root.quietZone * moduleSize;

            // Draw Background
            ctx.fillStyle = root.lightColor;
            ctx.fillRect(0, 0, width, height);

            // Draw Dark Modules
            ctx.fillStyle = root.darkColor;
            for (let r = 0; r < matrixSize; r++) {
                for (let c = 0; c < matrixSize; c++) {
                    if (matrix[r][c] === 1) {
                        ctx.fillRect(offsetX + c * moduleSize, offsetY + r * moduleSize, moduleSize, moduleSize);
                    }
                }
            }
        }
    }
}
