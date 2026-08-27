pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

StyledRect {
    id: root

    readonly property bool available: AndroLaunch.available
    readonly property var dev: AndroLaunch.activeDevice
    readonly property bool hasDev: !!dev && dev.isConnected
    readonly property var qa: dev?.quickActions

    Layout.fillWidth: true
    implicitHeight: mainLayout.implicitHeight + Tokens.padding.medium * 2
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    ColumnLayout {
        id: mainLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        // Header Row: Device icon, Name, Battery & Telemetry
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: 40
                radius: Tokens.rounding.full
                color: root.hasDev ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.hasDev ? (root.dev.isWireless ? "wifi" : "smartphone") : "smartphone"
                    color: root.hasDev ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.small
                    fill: root.hasDev ? 1 : 0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.hasDev ? (root.dev.name || root.dev.model) : qsTr("Android Device")
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                    color: root.hasDev ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (!root.available)
                            return qsTr("ADB not installed");
                        if (!root.hasDev)
                            return qsTr("No device connected");
                        let details = root.dev.serialNumber;
                        if (root.dev.androidVersion)
                            details += ` • Android ${root.dev.androidVersion}`;
                        return details;
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            // Battery Badge
            StyledRect {
                visible: root.hasDev && root.dev.batteryLevel >= 0
                implicitWidth: battLayout.implicitWidth + Tokens.padding.small * 2
                implicitHeight: battLayout.implicitHeight + Tokens.padding.extraSmall * 2
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainerHigh

                RowLayout {
                    id: battLayout
                    anchors.centerIn: parent
                    spacing: 2

                    MaterialIcon {
                        text: Icons.getBatteryIcon((root.dev?.batteryLevel ?? 0) / 100, root.dev?.isCharging ?? false)
                        color: (root.dev?.batteryLevel ?? 0) <= 20 ? Colours.palette.m3error : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        text: `${root.dev?.batteryLevel ?? 0}%${root.dev?.isCharging ? " ⚡" : ""}`
                        font: Tokens.font.label.small
                    }
                }
            }

            IconButton {
                icon: "refresh"
                type: IconButton.Text
                padding: Tokens.padding.extraSmall
                onClicked: AndroLaunch.scanDevices()
            }
        }

        // Action Buttons Row: Mirror, Camera, Shell, Disconnect
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasDev
            spacing: Tokens.spacing.extraSmall

            IconTextButton {
                Layout.fillWidth: true
                text: qsTr("Mirror")
                icon: "screen_share"
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                onClicked: AndroLaunch.startMirroring()
            }

            IconButton {
                icon: "videocam"
                type: IconButton.Tonal
                isRound: true
                onClicked: AndroLaunch.startCameraMirroring()
            }

            IconButton {
                icon: "terminal"
                type: IconButton.Tonal
                isRound: true
                onClicked: AndroLaunch.openTerminal()
            }

            IconButton {
                visible: root.dev?.isWireless ?? false
                icon: "link_off"
                type: IconButton.Tonal
                isRound: true
                onClicked: AndroLaunch.disconnect(root.dev?.id ?? "")
            }
        }

        // Quick Toggles Row
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasDev
            spacing: Tokens.spacing.extraSmall

            IconButton {
                Layout.fillWidth: true
                icon: "wifi"
                isToggle: true
                isRound: true
                shapeMorph: true
                checked: root.qa?.wifi ?? false
                onClicked: AndroLaunch.toggleWifi(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "bluetooth"
                isToggle: true
                isRound: true
                shapeMorph: true
                checked: root.qa?.bluetooth ?? false
                onClicked: AndroLaunch.toggleBluetooth(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "signal_cellular_alt"
                isToggle: true
                isRound: true
                shapeMorph: true
                checked: root.qa?.mobileData ?? false
                onClicked: AndroLaunch.toggleMobileData(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "dark_mode"
                isToggle: true
                isRound: true
                shapeMorph: true
                checked: root.qa?.darkMode ?? false
                onClicked: AndroLaunch.toggleDarkMode(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "do_not_disturb_on"
                isToggle: true
                isRound: true
                shapeMorph: true
                checked: root.qa?.dnd ?? false
                onClicked: AndroLaunch.toggleDnd(!checked)
            }
            IconButton {
                Layout.fillWidth: true
                icon: "screen_rotation"
                isToggle: true
                isRound: true
                shapeMorph: true
                checked: root.qa?.autoRotate ?? false
                onClicked: AndroLaunch.toggleAutoRotate(!checked)
            }
        }

        // Brightness & Volume Sliders
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.hasDev
            spacing: 2

            // Brightness Slider
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "brightness_medium"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledSlider {
                    Layout.fillWidth: true
                    value: (root.qa?.brightness ?? 128) / 255
                    onInteraction: val => AndroLaunch.setBrightness(Math.round(val * 255))
                }
            }

            // Volume Slider
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "volume_up"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledSlider {
                    Layout.fillWidth: true
                    value: (root.qa?.volume ?? 50) / 100
                    onInteraction: val => AndroLaunch.setVolume(Math.round(val * 100))
                }
            }
        }
    }
}
