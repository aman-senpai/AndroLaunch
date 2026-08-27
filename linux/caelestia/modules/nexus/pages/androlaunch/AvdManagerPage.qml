pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    isSubPage: true
    title: qsTr("Android Virtual Devices (AVD)")

    Component.onCompleted: AndroLaunch.fetchAvds()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Installed Emulators (%1)").arg(AndroLaunch.avds.length)
                font: Tokens.font.body.medium
            }

            IconButton {
                icon: "refresh"
                type: IconButton.Tonal
                onClicked: AndroLaunch.fetchAvds()
            }
        }

        ItemList {
            id: avdList

            showList: AndroLaunch.avds.length > 0
            placeholderIcon: "phone_android"
            placeholderText: AndroLaunch.loadingAvds ? qsTr("Detecting virtual devices...") : qsTr("No Android Virtual Devices (AVDs) found")

            model: AndroLaunch.avds

            delegate: StyledRect {
                id: avdDelegate

                required property var modelData
                required property int index

                anchors.left: avdList.list.contentItem.left
                anchors.right: avdList.list.contentItem.right
                implicitHeight: avdRowLayout.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.extraSmall
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    id: avdRowLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "phone_android"
                        color: avdDelegate.modelData.isRunning ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: avdDelegate.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: avdDelegate.modelData.isRunning ? qsTr("Running") : qsTr("Stopped")
                            color: avdDelegate.modelData.isRunning ? Colours.palette.m3primary : Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconTextButton {
                        text: avdDelegate.modelData.isRunning ? qsTr("Running") : qsTr("Launch")
                        icon: avdDelegate.modelData.isRunning ? "check" : "play_arrow"
                        disabled: avdDelegate.modelData.isRunning
                        inactiveColour: Colours.palette.m3primaryContainer
                        inactiveOnColour: Colours.palette.m3onPrimaryContainer
                        onClicked: AndroLaunch.startAvd(avdDelegate.modelData.name)
                    }
                }
            }
        }
    }
}
