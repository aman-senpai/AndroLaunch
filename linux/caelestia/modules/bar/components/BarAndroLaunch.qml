pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.widgets
import qs.services
import qs.utils

StyledRect {
    id: root

    readonly property bool hasDev: AndroLaunch.hasConnectedDevice
    readonly property var dev: AndroLaunch.activeDevice
    readonly property int batt: dev?.batteryLevel ?? -1
    readonly property bool isCharging: dev?.isCharging ?? false
    readonly property real battProgress: root.batt >= 0 ? root.batt / 100 : 0

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: layout.implicitHeight + Tokens.padding.extraSmall * 2

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full
    clip: true

    StateLayer {
        anchors.fill: parent
        radius: Tokens.rounding.full
        onClicked: {
            if (root.hasDev)
                AndroLaunch.startMirroring();
            else
                AndroLaunch.scanDevices();
        }
    }

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: 2

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 28
            implicitHeight: 28

            CircularProgress {
                anchors.fill: parent
                fgColour: {
                    if (root.batt >= 0 && root.batt <= 20 && !root.isCharging)
                        return Colours.palette.m3error;
                    return Colours.palette.m3primary;
                }
                strokeWidth: 2
                value: root.hasDev && root.batt >= 0 ? root.battProgress : (root.hasDev ? 1 : 0)
                visible: root.hasDev
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: {
                    if (!AndroLaunch.available)
                        return "adb";
                    if (!root.hasDev)
                        return "smartphone";
                    if (root.batt >= 0)
                        return Icons.getBatteryIcon(root.battProgress, root.isCharging);
                    return root.dev?.isWireless ? "wifi" : "smartphone";
                }
                fontStyle: Tokens.font.icon.small
                color: {
                    if (root.batt >= 0 && root.batt <= 20 && !root.isCharging)
                        return Colours.palette.m3error;
                    if (root.hasDev)
                        return Colours.palette.m3primary;
                    return Colours.palette.m3onSurfaceVariant;
                }
                animate: true
            }
        }
    }
}
