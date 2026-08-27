pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

StyledRect {
    id: root

    readonly property bool hasDev: AndroLaunch.hasConnectedDevice
    readonly property var dev: AndroLaunch.activeDevice
    readonly property var qa: dev?.quickActions

    readonly property real nonAnimHeight: layout.implicitHeight + Tokens.padding.large * 2

    implicitHeight: nonAnimHeight
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    ColumnLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Header Row
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: devIcon.implicitHeight + Tokens.padding.medium

                radius: Tokens.rounding.full
                color: root.hasDev ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: devIcon
                    anchors.centerIn: parent
                    text: root.hasDev ? (root.dev.isWireless ? "wifi" : "smartphone") : "smartphone"
                    color: root.hasDev ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.medium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.hasDev ? (root.dev.name || root.dev.model) : qsTr("Android Device")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (!AndroLaunch.available)
                            return qsTr("ADB not installed");
                        if (!root.hasDev)
                            return qsTr("No device connected");
                        let info = root.dev.status;
                        if (root.dev.batteryLevel >= 0)
                            info += ` • ${root.dev.batteryLevel}%${root.dev.isCharging ? " ⚡" : ""}`;
                        return info;
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            IconButton {
                icon: "screen_share"
                type: IconButton.Filled
                disabled: !root.hasDev
                onClicked: AndroLaunch.startMirroring()
            }
        }

        // Quick Controls Row
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasDev
            spacing: Tokens.spacing.extraSmall

            IconButton {
                Layout.fillWidth: true
                icon: "wifi"
                isToggle: true
                checked: root.qa?.wifi ?? false
                onClicked: AndroLaunch.toggleWifi(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "bluetooth"
                isToggle: true
                checked: root.qa?.bluetooth ?? false
                onClicked: AndroLaunch.toggleBluetooth(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "dark_mode"
                isToggle: true
                checked: root.qa?.darkMode ?? false
                onClicked: AndroLaunch.toggleDarkMode(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "do_not_disturb_on"
                isToggle: true
                checked: root.qa?.dnd ?? false
                onClicked: AndroLaunch.toggleDnd(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "videocam"
                type: IconButton.Tonal
                onClicked: AndroLaunch.startCameraMirroring()
            }
            IconButton {
                Layout.fillWidth: true
                icon: "terminal"
                type: IconButton.Tonal
                onClicked: AndroLaunch.openTerminal()
            }
        }
    }
}
