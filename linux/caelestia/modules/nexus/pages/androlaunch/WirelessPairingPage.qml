pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.widgets
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    isSubPage: true
    title: qsTr("Wireless Pairing & Connect")

    Component.onCompleted: AndroLaunch.startQRPairing()
    Component.onDestruction: AndroLaunch.stopQRPairing()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Pair with QR Code (Recommended)")
        }

        // QR Code Container Card
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: qrCardLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            ColumnLayout {
                id: qrCardLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Scan this QR code with your Android device")
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Settings → Developer Options → Wireless Debugging → Pair device with QR code")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                }

                // QR Image Frame
                StyledRect {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 200
                    implicitHeight: 200
                    radius: Tokens.rounding.medium
                    color: "#ffffff"

                    QRCodeView {
                        anchors.centerIn: parent
                        width: 180
                        height: 180
                        text: AndroLaunch.qrString
                        darkColor: "#000000"
                        lightColor: "#ffffff"
                        quietZone: 1
                    }
                }

                // Pairing Code & Status Row
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.small

                    StyledRect {
                        implicitWidth: codeText.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: codeText.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: Colours.tPalette.m3surfaceContainerHigh

                        StyledText {
                            id: codeText
                            anchors.centerIn: parent
                            text: qsTr("Pairing Code: %1").arg(AndroLaunch.pairingPassword)
                            font: Tokens.font.title.small
                            color: Colours.palette.m3primary
                        }
                    }

                    IconTextButton {
                        text: qsTr("Regenerate")
                        icon: "refresh"
                        type: IconButton.Tonal
                        onClicked: AndroLaunch.startQRPairing()
                    }
                }

                // Live status text
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "sync"
                        color: Colours.palette.m3secondary
                        fontStyle: Tokens.font.icon.small

                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 2000
                            loops: Animation.Infinite
                            running: AndroLaunch.isQRPairingActive
                        }
                    }

                    StyledText {
                        text: AndroLaunch.qrPairingStatus || qsTr("Waiting for device to scan...")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3secondary
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Direct Wi-Fi Connect")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledTextField {
                id: connectIpField
                Layout.fillWidth: true
                placeholderText: "192.168.1.xxx:5555"
            }

            IconTextButton {
                text: qsTr("Connect")
                icon: "wifi"
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                onClicked: {
                    const parts = connectIpField.text.trim().split(":");
                    AndroLaunch.connectWireless(parts[0], parts[1] || "5555");
                }
            }
        }

        SectionHeader {
            text: qsTr("Manual 6-digit Code Pairing")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledTextField {
                id: pairIpField
                Layout.fillWidth: true
                placeholderText: "IP:Port (e.g. 192.168.1.50:37123)"
            }

            StyledTextField {
                id: pairCodeField
                implicitWidth: 120
                placeholderText: qsTr("6-digit Code")
            }

            IconTextButton {
                text: qsTr("Pair")
                icon: "sync"
                onClicked: {
                    const parts = pairIpField.text.trim().split(":");
                    if (parts.length >= 2)
                        AndroLaunch.pairWireless(parts[0], parts[1], pairCodeField.text.trim());
                }
            }
        }

        SectionHeader {
            text: qsTr("USB to Wireless Switch")
        }

        RowButton {
            first: true
            last: true
            icon: "cable"
            text: qsTr("Enable TCP/IP Mode on Connected USB Device")
            subtext: qsTr("Restarts ADB daemon on port 5555 so you can disconnect USB cable")
            disabled: !AndroLaunch.hasConnectedDevice || AndroLaunch.activeDevice.isWireless
            onClicked: AndroLaunch.enableTcpip("5555")
        }
    }
}
