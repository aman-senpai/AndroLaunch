pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    isSubPage: true
    title: qsTr("Applications")

    property string searchFilter: ""

    readonly property FileDialog fileDialog: FileDialog {
        id: fileDialog
        title: qsTr("Select APK to Install")
        filterLabel: qsTr("Android Packages (*.apk)")
        filters: ["apk"]
        onAccepted: path => AndroLaunch.installApk(path)
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Top Action Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledTextField {
                Layout.fillWidth: true
                placeholderText: qsTr("Search installed applications...")
                onTextChanged: root.searchFilter = text.toLowerCase()
            }

            IconTextButton {
                text: qsTr("Install APK")
                icon: "download"
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                disabled: !AndroLaunch.hasConnectedDevice
                onClicked: fileDialog.open()
            }

            IconButton {
                icon: "refresh"
                type: IconButton.Tonal
                disabled: !AndroLaunch.hasConnectedDevice
                onClicked: AndroLaunch.fetchApps("", true)
            }
        }

        SectionHeader {
            first: true
            text: qsTr("Installed Applications (%1)").arg(AndroLaunch.apps.length)
        }

        ItemList {
            id: appList

            showList: AndroLaunch.hasConnectedDevice && AndroLaunch.apps.length > 0
            placeholderIcon: "apps"
            placeholderText: AndroLaunch.loadingApps ? qsTr("Loading applications...") : (AndroLaunch.hasConnectedDevice ? qsTr("No applications found") : qsTr("No device connected"))

            model: ScriptModel {
                values: AndroLaunch.apps.filter(a => root.searchFilter.length === 0 || a.name.toLowerCase().includes(root.searchFilter) || a.packageName.toLowerCase().includes(root.searchFilter))
            }

            delegate: StyledRect {
                id: appDelegate

                required property var modelData
                required property int index

                anchors.left: appList.list.contentItem.left
                anchors.right: appList.list.contentItem.right
                implicitHeight: appRowLayout.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.extraSmall
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    id: appRowLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: 36
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3secondaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "android"
                            color: Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.small
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: appDelegate.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: appDelegate.modelData.packageName
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    // Action buttons
                    IconButton {
                        icon: "launch"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        onClicked: AndroLaunch.launchApp(appDelegate.modelData.packageName)
                    }

                    IconButton {
                        icon: "screen_share"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        onClicked: AndroLaunch.startAppMirroring(appDelegate.modelData.packageName)
                    }

                    IconButton {
                        icon: "cleaning_services"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        onClicked: AndroLaunch.clearAppData(appDelegate.modelData.packageName)
                    }

                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: AndroLaunch.uninstallApp(appDelegate.modelData.packageName)
                    }
                }
            }
        }
    }
}
