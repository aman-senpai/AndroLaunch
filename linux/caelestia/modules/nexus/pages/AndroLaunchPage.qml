pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool available: AndroLaunch.available
    readonly property var dev: AndroLaunch.activeDevice
    readonly property bool hasDev: !!dev && dev.isConnected
    readonly property var qa: dev?.quickActions

    title: qsTr("Android Devices (AndroLaunch)")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ADB Status Warning (if missing)
        StyledRect {
            Layout.fillWidth: true
            visible: !root.available
            implicitHeight: noAdbLayout.implicitHeight + Tokens.padding.medium * 2
            color: Colours.palette.m3errorContainer
            radius: Tokens.rounding.medium

            RowLayout {
                id: noAdbLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "warning"
                    color: Colours.palette.m3onErrorContainer
                    fontStyle: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: qsTr("Android Platform Tools Not Found")
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onErrorContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Please install `android-tools` (or Android SDK) and `scrcpy` on your system.")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onErrorContainer
                        wrapMode: Text.WordWrap
                    }
                }

                IconTextButton {
                    text: qsTr("Re-scan")
                    icon: "refresh"
                    onClicked: AndroLaunch.checkPaths()
                }
            }
        }

        // Active Device Hero Card
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: heroLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            ColumnLayout {
                id: heroLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: 52
                        radius: Tokens.rounding.full
                        color: root.hasDev ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: root.hasDev ? (root.dev.isWireless ? "wifi" : "smartphone") : "smartphone"
                            color: root.hasDev ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.large
                            fill: root.hasDev ? 1 : 0
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.hasDev ? (root.dev.name || root.dev.model) : qsTr("No Android Device Connected")
                            font: Tokens.font.title.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (!root.hasDev)
                                    return qsTr("Plug in a device via USB or connect over Wi-Fi");
                                let details = root.dev.serialNumber;
                                if (root.dev.androidVersion)
                                    details += ` • Android ${root.dev.androidVersion} (SDK ${root.dev.apiLevel})`;
                                return details;
                            }
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }

                    // Battery & Status Badge
                    StyledRect {
                        visible: root.hasDev && root.dev.batteryLevel >= 0
                        implicitWidth: battLayout.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: battLayout.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: Colours.tPalette.m3surfaceContainerHigh

                        RowLayout {
                            id: battLayout
                            anchors.centerIn: parent
                            spacing: Tokens.spacing.extraSmall

                            MaterialIcon {
                                text: Icons.getBatteryIcon((root.dev?.batteryLevel ?? 0) / 100, root.dev?.isCharging ?? false)
                                color: (root.dev?.batteryLevel ?? 0) <= 20 ? Colours.palette.m3error : Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                text: `${root.dev?.batteryLevel ?? 0}%${root.dev?.isCharging ? " ⚡" : ""}`
                                font: Tokens.font.label.medium
                            }
                        }
                    }

                    IconButton {
                        icon: "refresh"
                        type: IconButton.Tonal
                        onClicked: AndroLaunch.scanDevices()
                    }
                }

                // Action Bar on Device Card
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.hasDev
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        Layout.fillWidth: true
                        text: qsTr("Mirror Screen")
                        icon: "screen_share"
                        inactiveColour: Colours.palette.m3primary
                        inactiveOnColour: Colours.palette.m3onPrimary
                        onClicked: AndroLaunch.startMirroring()
                    }

                    IconTextButton {
                        text: qsTr("Camera")
                        icon: "videocam"
                        type: IconButton.Tonal
                        onClicked: AndroLaunch.startCameraMirroring()
                    }

                    IconTextButton {
                        text: qsTr("Terminal")
                        icon: "terminal"
                        type: IconButton.Tonal
                        onClicked: AndroLaunch.openTerminal()
                    }

                    IconTextButton {
                        visible: root.dev?.isWireless ?? false
                        text: qsTr("Disconnect")
                        icon: "link_off"
                        type: IconButton.Tonal
                        onClicked: AndroLaunch.disconnect(root.dev?.id ?? "")
                    }
                }
            }
        }

        // Multiple Connected Devices Switcher (if > 1)
        SectionHeader {
            visible: AndroLaunch.devices.length > 1
            text: qsTr("All Connected Devices (%1)").arg(AndroLaunch.devices.length)
        }

        Repeater {
            model: AndroLaunch.devices.length > 1 ? AndroLaunch.devices : []

            RowButton {
                id: devRowBtn
                required property var modelData
                required property int index

                icon: modelData.isWireless ? "wifi" : "usb"
                text: modelData.name || modelData.model || modelData.id
                subtext: `${modelData.status} • ${modelData.id}`
                onClicked: AndroLaunch.selectDevice(devRowBtn.modelData.id)
            }
        }

        // Quick Controls
        SectionHeader {
            text: qsTr("Device Quick Controls")
        }

        ToggleRow {
            first: true
            text: qsTr("Wi-Fi")
            subtext: qsTr("Toggle Android Wi-Fi adapter")
            disabled: !root.hasDev
            checked: root.qa?.wifi ?? false
            onToggled: AndroLaunch.toggleWifi(!checked)
        }

        ToggleRow {
            text: qsTr("Bluetooth")
            subtext: qsTr("Toggle Android Bluetooth adapter")
            disabled: !root.hasDev
            checked: root.qa?.bluetooth ?? false
            onToggled: AndroLaunch.toggleBluetooth(!checked)
        }

        ToggleRow {
            text: qsTr("Mobile Data")
            subtext: qsTr("Toggle cellular data connection")
            disabled: !root.hasDev
            checked: root.qa?.mobileData ?? false
            onToggled: AndroLaunch.toggleMobileData(!checked)
        }

        ToggleRow {
            text: qsTr("Dark Mode")
            subtext: qsTr("Toggle Android night theme")
            disabled: !root.hasDev
            checked: root.qa?.darkMode ?? false
            onToggled: AndroLaunch.toggleDarkMode(!checked)
        }

        ToggleRow {
            text: qsTr("Airplane Mode")
            subtext: qsTr("Disable all wireless radios")
            disabled: !root.hasDev
            checked: root.qa?.airplaneMode ?? false
            onToggled: AndroLaunch.toggleAirplaneMode(!checked)
        }

        ToggleRow {
            text: qsTr("Location")
            subtext: qsTr("Toggle GPS / high accuracy location")
            disabled: !root.hasDev
            checked: root.qa?.location ?? false
            onToggled: AndroLaunch.toggleLocation(!checked)
        }

        ToggleRow {
            text: qsTr("Do Not Disturb")
            subtext: qsTr("Mute alerts and notifications")
            disabled: !root.hasDev
            checked: root.qa?.dnd ?? false
            onToggled: AndroLaunch.toggleDnd(!checked)
        }

        ToggleRow {
            last: true
            text: qsTr("Auto Rotate")
            subtext: qsTr("Toggle accelerometer rotation")
            disabled: !root.hasDev
            checked: root.qa?.autoRotate ?? false
            onToggled: AndroLaunch.toggleAutoRotate(!checked)
        }

        // Sliders
        SectionHeader {
            text: qsTr("Brightness & Volume")
        }

        SliderRow {
            first: true
            icon: "brightness_medium"
            label: qsTr("Screen Brightness")
            valueLabel: `${Math.round(((root.qa?.brightness ?? 128) / 255) * 100)}%`
            value: (root.qa?.brightness ?? 128) / 255
            onMoved: val => AndroLaunch.setBrightness(Math.round(val * 255))
        }

        SliderRow {
            last: true
            icon: "volume_up"
            label: qsTr("Media Volume")
            valueLabel: `${root.qa?.volume ?? 50}%`
            value: (root.qa?.volume ?? 50) / 100
            onMoved: val => AndroLaunch.setVolume(Math.round(val * 15), 3)
        }

        // Bi-directional Clipboard Sync
        SectionHeader {
            text: qsTr("Productivity & Clipboard")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconTextButton {
                Layout.fillWidth: true
                icon: "content_paste"
                text: qsTr("Send PC Clipboard to Phone")
                disabled: !root.hasDev
                onClicked: {
                    // Get host clipboard via wl-paste / xclip
                    const clipProc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["wl-paste"]; stdout: StdioCollector {} }', root);
                    clipProc.onExited.connect(() => {
                        const txt = clipProc.stdout.text.trim();
                        if (txt) AndroLaunch.syncHostToDevice(txt);
                        clipProc.destroy();
                    });
                    clipProc.running = true;
                }
            }

            IconTextButton {
                Layout.fillWidth: true
                icon: "content_copy"
                text: qsTr("Fetch Phone Clipboard")
                disabled: !root.hasDev
                onClicked: AndroLaunch.syncDeviceToHost()
            }
        }

        // Subpage Navigation Section
        SectionHeader {
            text: qsTr("Management Hub")
        }

        NavRow {
            first: true
            icon: "screen_share"
            text: qsTr("Screen & Camera Mirroring Settings")
            subtext: qsTr("Configure Scrcpy display, bitrate, fps, and camera parameters")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            icon: "apps"
            text: qsTr("Applications")
            subtext: qsTr("Browse, launch, install APK, clear data, and uninstall apps")
            onClicked: {
                if (AndroLaunch.apps.length === 0)
                    AndroLaunch.fetchApps();
                root.nState.openSubPage(2);
            }
        }

        NavRow {
            icon: "folder"
            text: qsTr("File Explorer")
            subtext: qsTr("Browse remote storage, upload/download files, delete items")
            onClicked: {
                if (AndroLaunch.files.length === 0)
                    AndroLaunch.browsePath("/sdcard");
                root.nState.openSubPage(3);
            }
        }

        NavRow {
            icon: "terminal"
            text: qsTr("ADB Shell & Commands")
            subtext: qsTr("Run interactive terminal shell and manage custom commands")
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            icon: "wifi"
            text: qsTr("Wireless Pairing & Connect")
            subtext: qsTr("Pair Android 11+ devices with Wi-Fi code or connect via IP")
            onClicked: root.nState.openSubPage(5)
        }

        NavRow {
            last: true
            icon: "phone_android"
            text: qsTr("Android Virtual Devices (AVD)")
            subtext: qsTr("Manage and launch Android emulators")
            onClicked: root.nState.openSubPage(6)
        }

        // Reboot Controls
        SectionHeader {
            text: qsTr("Power & Reboot")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconTextButton {
                Layout.fillWidth: true
                text: qsTr("System Reboot")
                icon: "restart_alt"
                disabled: !root.hasDev
                onClicked: AndroLaunch.reboot("normal")
            }

            IconTextButton {
                Layout.fillWidth: true
                text: qsTr("Bootloader")
                icon: "memory"
                disabled: !root.hasDev
                onClicked: AndroLaunch.reboot("bootloader")
            }

            IconTextButton {
                Layout.fillWidth: true
                text: qsTr("Recovery")
                icon: "build"
                disabled: !root.hasDev
                onClicked: AndroLaunch.reboot("recovery")
            }
        }
    }
}
