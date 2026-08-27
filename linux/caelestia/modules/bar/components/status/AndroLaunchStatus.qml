pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property color colour

    readonly property bool hasDevice: AndroLaunch.hasConnectedDevice
    readonly property var dev: AndroLaunch.activeDevice
    readonly property int batt: dev?.batteryLevel ?? -1
    readonly property bool isCharging: dev?.isCharging ?? false

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    Behavior on implicitHeight {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    ColumnLayout {
        id: layout

        spacing: Tokens.spacing.medium / 2

        MaterialIcon {
            id: icon

            animate: true
            text: {
                if (!AndroLaunch.available)
                    return "adb";
                if (!root.hasDevice)
                    return "smartphone";
                if (root.batt >= 0)
                    return Icons.getBatteryIcon(root.batt / 100, root.isCharging);
                return "smartphone";
            }
            color: {
                if (root.batt >= 0 && root.batt <= 20 && !root.isCharging)
                    return Colours.palette.m3error;
                return root.colour;
            }
            fontStyle: Tokens.font.icon.medium
            fill: root.hasDevice ? 1 : 0

            Behavior on fill {
                Anim {}
            }

            SequentialAnimation on opacity {
                running: AndroLaunch.scanning
                loops: Animation.Infinite

                Anim {
                    from: 1
                    to: 0.4
                    duration: Tokens.anim.durations.normal
                }
                Anim {
                    from: 0.4
                    to: 1
                    duration: Tokens.anim.durations.normal
                }
            }
        }
    }
}
