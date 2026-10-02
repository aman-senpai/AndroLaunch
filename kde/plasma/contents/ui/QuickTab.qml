pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "components"
import "../code/util.js" as Util

PlasmaComponents3.ScrollView {
    id: root

    required property var backend

    anchors.fill: parent

    ColumnLayout {
        id: content

        width: root.availableWidth
        height: Math.max(implicitHeight, root.availableHeight)
        spacing: Kirigami.Units.smallSpacing

        // ---- 1. empty state -------------------------------------------------
        EmptyState {
            visible: root.backend.uiDevices.length === 0
            iconName: "smartphone"
            message: "No Android device connected"
            hint: "Connect over USB or pair over Wi-Fi. Enable USB debugging on the device."
        }

        ColumnLayout {
            visible: root.backend.uiDevices.length === 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                ActionButton {
                    iconName: "video-display"
                    text: "Mirror Screen"
                    enabled: false
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "camera-web"
                    enabled: false

                    PlasmaComponents3.ToolTip {
                        text: "Open camera"
                    }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "utilities-terminal"
                    enabled: false

                    PlasmaComponents3.ToolTip {
                        text: "Open terminal"
                    }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-list-details"
                    enabled: false

                    PlasmaComponents3.ToolTip {
                        text: "Open logcat"
                    }
                }
            }

            ActionButton {
                iconName: "view-refresh"
                text: "Rescan"
                onClicked: root.backend.refresh()
            }
        }

        // ---- 2. device card -------------------------------------------------
        PlasmaComponents3.Frame {
            Layout.fillWidth: true
            visible: root.backend.activeDevice !== null

            ColumnLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: Util.deviceIcon(root.backend.activeDevice)
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: implicitWidth
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: root.backend.activeDevice ? (root.backend.activeDevice.name || root.backend.activeDevice.id) : ""
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: {
                                const device = root.backend.activeDevice;
                                if (!device)
                                    return "";
                                const name = (device.name || "").trim();
                                const model = (device.model || "").trim();
                                const parts = [Util.statusLabel(device)];
                                if (model && model !== name)
                                    parts.push(model);
                                if (device.address)
                                    parts.push(device.address);
                                if (device.android)
                                    parts.push("Android " + device.android + (device.api ? " (API " + device.api + ")" : ""));
                                if (parts.length === 0)
                                    parts.push(Util.statusLabel(device));
                                return parts.join(" • ");
                            }
                            elide: Text.ElideRight
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing / 2
                        visible: root.backend.activeBattery >= 0

                        Kirigami.Icon {
                            source: Util.batteryIcon(root.backend.activeBattery, root.backend.activeCharging)
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: implicitWidth
                        }

                        PlasmaComponents3.Label {
                            text: root.backend.activeBattery + "%"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.8
                        }
                    }

                    PlasmaComponents3.ToolButton {
                        icon.name: "view-refresh"
                        onClicked: root.backend.refresh()

                        PlasmaComponents3.ToolTip {
                            text: "Refresh device state"
                        }
                    }
                }

                PlasmaComponents3.ComboBox {
                    Layout.fillWidth: true
                    visible: root.backend.connectedCount > 1
                    model: root.backend.uiDevices.map(d => d.name || d.id)
                    currentIndex: {
                        for (let i = 0; i < root.backend.uiDevices.length; ++i) {
                            if (root.backend.uiDevices[i].id === root.backend.activeId)
                                return i;
                        }
                        return -1;
                    }
                    onActivated: index => root.backend.selectDevice(root.backend.uiDevices[index].id)
                }
            }
        }

        // ---- 3. action row --------------------------------------------------
        RowLayout {
            visible: root.backend.hasDevice
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            ActionButton {
                iconName: "video-display"
                text: "Mirror Screen"
                fillWidth: false
                enabled: root.backend.hasDevice
                onClicked: root.backend.mirror()
            }

            PlasmaComponents3.ToolButton {
                icon.name: "camera-web"
                enabled: root.backend.hasDevice
                onClicked: root.backend.camera()

                PlasmaComponents3.ToolTip {
                    text: "Open camera"
                }
            }

            PlasmaComponents3.ToolButton {
                icon.name: "utilities-terminal"
                enabled: root.backend.hasDevice
                onClicked: root.backend.openTerminal()

                PlasmaComponents3.ToolTip {
                    text: "Open terminal"
                }
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-list-details"
                enabled: root.backend.hasDevice
                onClicked: root.backend.openLogcat()

                PlasmaComponents3.ToolTip {
                    text: "Open logcat"
                }
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents3.ToolButton {
                icon.name: "network-disconnect"
                visible: root.backend.activeDevice !== null && root.backend.activeDevice.wireless === true
                onClicked: root.backend.disconnectDevice(root.backend.activeId)

                PlasmaComponents3.ToolTip {
                    text: "Disconnect " + (root.backend.activeDevice ? root.backend.activeDevice.name : "")
                }
            }

            PlasmaComponents3.ToolButton {
                icon.name: "window-close"
                visible: root.backend.mirrors.length > 0
                onClicked: root.backend.stopMirrors()

                PlasmaComponents3.ToolTip {
                    text: "Stop mirroring"
                }
            }
        }

        // ---- 4. quick controls ---------------------------------------------
        SectionLabel {
            text: "Quick controls"
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            ToggleChip {
                iconName: "network-wireless"
                label: "Wi-Fi"
                enabled: root.backend.hasDevice
                active: root.backend.quick.wifi === true
                onToggled: requested => root.backend.toggle("wifi", requested)
            }

            ToggleChip {
                iconName: "network-bluetooth"
                label: "Bluetooth"
                enabled: root.backend.hasDevice
                active: root.backend.quick.bluetooth === true
                onToggled: requested => root.backend.toggle("bluetooth", requested)
            }

            ToggleChip {
                iconName: "network-mobile-0-5g"
                label: "Data"
                enabled: root.backend.hasDevice
                active: root.backend.quick.mobileData === true
                onToggled: requested => root.backend.toggle("data", requested)
            }

            ToggleChip {
                iconName: "preferences-system"
                label: "Dark"
                enabled: root.backend.hasDevice
                active: root.backend.quick.darkMode === true
                onToggled: requested => root.backend.toggle("darkmode", requested)
            }

            ToggleChip {
                iconName: "network-flightmode-on"
                label: "Airplane"
                enabled: root.backend.hasDevice
                active: root.backend.quick.airplaneMode === true
                onToggled: requested => root.backend.toggle("airplane", requested)
            }

            ToggleChip {
                iconName: "mark-location"
                label: "Location"
                enabled: root.backend.hasDevice
                active: root.backend.quick.location === true
                onToggled: requested => root.backend.toggle("location", requested)
            }

            ToggleChip {
                iconName: "notifications-disabled"
                label: "DND"
                enabled: root.backend.hasDevice
                active: root.backend.quick.dnd === true
                onToggled: requested => root.backend.toggle("dnd", requested)
            }

            ToggleChip {
                iconName: "object-rotate-right"
                label: "Rotate"
                enabled: root.backend.hasDevice
                active: root.backend.quick.autoRotate === true
                onToggled: requested => root.backend.toggle("rotate", requested)
            }
        }

        // ---- 5. display & sound --------------------------------------------
        SectionLabel {
            text: "Display & sound"
        }

        ValueSlider {
            iconName: "brightness-high"
            enabled: root.backend.hasDevice
            value: (root.backend.effectiveQuick.brightness ?? 128) / (root.backend.effectiveQuick.brightnessMax ?? 255)
            valueText: Math.round((root.backend.effectiveQuick.brightness ?? 128) / (root.backend.effectiveQuick.brightnessMax ?? 255) * 100) + "%"
            onMoved: v => root.backend.setBrightness(Math.round(v * 100))
        }

        ValueSlider {
            iconName: "audio-volume-high"
            enabled: root.backend.hasDevice
            value: (root.backend.effectiveQuick.volume ?? 50) / 100
            valueText: (root.backend.effectiveQuick.volume ?? 50) + "%"
            onMoved: v => root.backend.setVolume(Math.round(v * 100))
        }

        // ---- 6. power -------------------------------------------------------
        SectionLabel {
            text: "Power"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                Layout.fillWidth: true
                text: "Normal"
                display: PlasmaComponents3.ToolButton.TextOnly
                enabled: root.backend.hasDevice
                onClicked: root.backend.reboot("normal")
            }

            PlasmaComponents3.ToolButton {
                Layout.fillWidth: true
                text: "Bootloader"
                display: PlasmaComponents3.ToolButton.TextOnly
                enabled: root.backend.hasDevice
                onClicked: root.backend.reboot("bootloader")
            }

            PlasmaComponents3.ToolButton {
                Layout.fillWidth: true
                text: "Recovery"
                display: PlasmaComponents3.ToolButton.TextOnly
                enabled: root.backend.hasDevice
                onClicked: root.backend.reboot("recovery")
            }
        }

        // ---- 7. open windows ------------------------------------------------
        SectionLabel {
            visible: root.backend.mirrors.length > 0
            text: "Open windows"
        }

        Repeater {
            model: root.backend.mirrors

            delegate: RowLayout {
                id: windowRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: windowRow.modelData.kind === "camera" ? "camera-web"
                            : (windowRow.modelData.kind === "mirror" ? "video-display" : "window-new")
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                    opacity: 0.8
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: {
                        const mirror = windowRow.modelData;
                        if (mirror.kind === "mirror")
                            return "Device screen";
                        if (mirror.kind === "camera")
                            return "Camera";
                        if (mirror.kind === "screen-app")
                            return (mirror.label || mirror.app) + " (device screen)";
                        return mirror.label || mirror.app || "App window";
                    }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "window-close"
                    onClicked: root.backend.stopMirror(windowRow.modelData.pid)

                    PlasmaComponents3.ToolTip {
                        text: "Close this window"
                    }
                }
            }
        }

        // ---- 8. previous devices -------------------------------------------
        SectionLabel {
            visible: root.backend.previous.length > 0
            text: "Previous devices"
        }

        Repeater {
            model: root.backend.previous

            delegate: RowLayout {
                id: previousRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: previousRow.modelData.wireless ? "network-wireless" : "smartphone"
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                    opacity: 0.8
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: previousRow.modelData.name || previousRow.modelData.id
                        elide: Text.ElideRight
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: previousRow.modelData.id
                        elide: Text.ElideRight
                        opacity: 0.6
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "network-connect"
                    onClicked: root.backend.connectPrevious(previousRow.modelData.id)

                    PlasmaComponents3.ToolTip {
                        text: "Reconnect"
                    }
                }
            }
        }
    }
}
