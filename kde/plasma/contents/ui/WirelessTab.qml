/*
 * AndroLaunch — Wireless tab.
 *
 * QR pairing, manual pairing, direct Wi-Fi connect, USB → TCP/IP switchover and
 * the list of currently connected devices. All work is delegated to the frozen
 * `backend` API; nothing here talks to adb directly.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "components"
import "../code/util.js" as Util

ColumnLayout {
    id: root

    required property var backend

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.smallSpacing

    readonly property bool controlsEnabled: backend.helperReady && !backend.adbMissing
    property string pairStatus: ""

    function handleScanToggle(on) {
        if (on) {
            if (!backend.qr || !backend.qr.payload)
                backend.startQrPairing();
            pollTimer.start();
            pollWindow.restart();
        } else {
            pollTimer.stop();
            pollWindow.stop();
        }
    }

    // Whenever a QR payload exists and no device is connected yet, keep polling
    // for 120 s so that a scan is picked up without touching the switch.
    function syncAutoPoll() {
        if (!backend.qr || !backend.qr.payload || backend.hasDevice)
            return;
        if (!scanSwitch.checked)
            scanSwitch.checked = true;
        pollTimer.start();
        pollWindow.restart();
    }

    Component.onCompleted: syncAutoPoll()

    Timer {
        id: pollTimer
        interval: 3000
        repeat: true
        onTriggered: root.backend.pollPairing()
    }

    Timer {
        id: pollWindow
        interval: 120000
        repeat: false
        onTriggered: {
            pollTimer.stop();
            scanSwitch.checked = false;
        }
    }

    Connections {
        target: root.backend

        function onQrChanged() {
            root.syncAutoPoll();
        }

        function onHasDeviceChanged() {
            if (root.backend.hasDevice) {
                pollTimer.stop();
                pollWindow.stop();
                scanSwitch.checked = false;
            } else {
                root.syncAutoPoll();
            }
        }

        function onPairingFound(ip, port) {
            root.pairStatus = "Found " + ip + ":" + port;
        }
    }

    // ---- adb warning -------------------------------------------------------
    PlasmaComponents3.Frame {
        Layout.fillWidth: true
        visible: root.backend.adbMissing

        RowLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "dialog-warning"
                color: Kirigami.Theme.negativeTextColor
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.negativeTextColor
                text: "adb not found — sudo dnf install android-tools scrcpy"
            }
        }
    }

    PlasmaComponents3.ScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
            id: content
            width: scroll.availableWidth
            height: Math.max(implicitHeight, scroll.availableHeight)
            spacing: Kirigami.Units.smallSpacing

            // ---- QR pairing ------------------------------------------------
            SectionLabel {
                text: "Pair with QR code"
            }

            PlasmaComponents3.Frame {
                Layout.fillWidth: true
                opacity: root.controlsEnabled ? 1 : 0.5

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    QrCode {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.backend.qr.payload ?? ""
                        implicitWidth: Math.min(220, parent.width)
                        implicitHeight: implicitWidth
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.bold: true
                        color: Kirigami.Theme.highlightColor
                        text: "Code: " + (root.backend.qr.password ?? "—")
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: "On the phone: Developer options → Wireless debugging → Pair device with QR code"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.ToolButton {
                            icon.name: "view-refresh"
                            text: "New code"
                            enabled: root.controlsEnabled
                            onClicked: root.backend.startQrPairing()
                        }

                        PlasmaComponents3.Switch {
                            id: scanSwitch
                            text: "Scan for device"
                            enabled: root.controlsEnabled
                            Layout.fillWidth: true
                            onCheckedChanged: root.handleScanToggle(checked)
                        }
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.backend.hasDevice
                              ? "Paired"
                              : (root.pairStatus.length > 0
                                 ? root.pairStatus
                                 : (pollTimer.running ? "Waiting for the phone to scan…" : "Pairing is idle"))
                    }
                }
            }

            // ---- manual pairing --------------------------------------------
            SectionLabel {
                text: "Manual pairing"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextField {
                    id: manualEndpoint
                    Layout.fillWidth: true
                    enabled: root.controlsEnabled
                    placeholderText: "192.168.1.x:37123"
                }

                PlasmaComponents3.TextField {
                    id: manualCode
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                    enabled: root.controlsEnabled
                    placeholderText: "6-digit code"
                }

                ActionButton {
                    iconName: "network-connect"
                    text: "Pair"
                    enabled: root.controlsEnabled
                             && manualEndpoint.text.trim().length > 0
                             && manualCode.text.trim().length > 0
                    onClicked: {
                        const parts = manualEndpoint.text.trim().split(":");
                        const ip = parts[0];
                        const port = parts.length > 1 ? parts[1] : "";
                        root.backend.wirelessPair(ip, port, manualCode.text.trim(), ok => {});
                    }
                }
            }

            // ---- direct connect --------------------------------------------
            SectionLabel {
                text: "Direct connect"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextField {
                    id: connectEndpoint
                    Layout.fillWidth: true
                    enabled: root.controlsEnabled
                    placeholderText: "192.168.1.x:5555"
                }

                ActionButton {
                    iconName: "network-connect"
                    text: "Connect"
                    enabled: root.controlsEnabled && connectEndpoint.text.trim().length > 0
                    onClicked: {
                        const parts = connectEndpoint.text.trim().split(":");
                        const ip = parts[0];
                        const port = parts.length > 1 && parts[1].length > 0 ? parts[1] : "5555";
                        root.backend.wirelessConnect(ip, port);
                    }
                }
            }

            // ---- USB → Wi-Fi -----------------------------------------------
            SectionLabel {
                text: "USB → Wi-Fi"
            }

            ActionButton {
                iconName: "network-wireless"
                text: "Switch USB device to TCP/IP"
                enabled: root.controlsEnabled
                         && root.backend.hasDevice
                         && !(root.backend.activeDevice && root.backend.activeDevice.wireless)
                onClicked: root.backend.enableTcpip("5555")
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
                text: "The phone keeps its current IP address. After switching, unplug USB and connect with the address above."
            }

            // ---- connected devices -----------------------------------------
            SectionLabel {
                text: "Connected"
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.backend.devices.length === 0
                opacity: 0.6
                text: "No devices connected."
            }

            Repeater {
                model: root.backend.devices

                delegate: RowLayout {
                    id: deviceRow

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: Util.deviceIcon(deviceRow.modelData)
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                        opacity: deviceRow.modelData.connected ? 1 : 0.5
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: deviceRow.modelData.name || deviceRow.modelData.model || deviceRow.modelData.id
                        opacity: deviceRow.modelData.connected ? 1 : 0.6
                    }

                    PlasmaComponents3.Label {
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: Util.statusLabel(deviceRow.modelData)
                    }

                    PlasmaComponents3.Label {
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.5
                        text: deviceRow.modelData.id
                    }

                    PlasmaComponents3.ToolButton {
                        icon.name: "network-disconnect"
                        visible: deviceRow.modelData.wireless
                        enabled: root.controlsEnabled
                        onClicked: root.backend.disconnectDevice(deviceRow.modelData.id)
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
