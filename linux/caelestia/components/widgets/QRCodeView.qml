pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import "../../utils/QRCode.js" as QR

Item {
    id: root

    property string text: ""
    property color darkColor: "#000000"
    property color lightColor: "#ffffff"
    property int quietZone: 4

    implicitWidth: 200
    implicitHeight: 200

    Image {
        id: qrImage
        anchors.fill: parent
        anchors.margins: 4
        fillMode: Image.PreserveAspectFit
        source: root.text.length > 0 ? QR.toSVG(root.text, root.quietZone, root.darkColor.toString(), root.lightColor.toString()) : ""
        smooth: false
        asynchronous: false
    }
}
