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
    title: qsTr("File Explorer")

    readonly property FileDialog uploadDialog: FileDialog {
        id: uploadDialog
        title: qsTr("Select File to Upload to Android")
        onAccepted: path => {
            const fileName = path.split("/").pop();
            const remoteDest = `${AndroLaunch.currentPath}/${fileName}`;
            AndroLaunch.pushFile(path, remoteDest);
        }
    }

    Component.onCompleted: {
        if (AndroLaunch.hasConnectedDevice && AndroLaunch.files.length === 0)
            AndroLaunch.browsePath(AndroLaunch.currentPath);
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Path Navigation Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconButton {
                icon: "arrow_upward"
                type: IconButton.Tonal
                disabled: !AndroLaunch.hasConnectedDevice || AndroLaunch.currentPath === "/"
                onClicked: {
                    const parts = AndroLaunch.currentPath.split("/").filter(p => p.length > 0);
                    parts.pop();
                    const newPath = "/" + parts.join("/");
                    AndroLaunch.browsePath(newPath || "/");
                }
            }

            StyledTextField {
                id: pathField
                Layout.fillWidth: true
                text: AndroLaunch.currentPath
                onAccepted: AndroLaunch.browsePath(text)
            }

            IconTextButton {
                text: qsTr("Go")
                icon: "arrow_forward"
                onClicked: AndroLaunch.browsePath(pathField.text)
            }

            IconTextButton {
                text: qsTr("Upload")
                icon: "upload"
                disabled: !AndroLaunch.hasConnectedDevice
                onClicked: uploadDialog.open()
            }

            IconButton {
                icon: "refresh"
                type: IconButton.Tonal
                disabled: !AndroLaunch.hasConnectedDevice
                onClicked: AndroLaunch.browsePath(AndroLaunch.currentPath)
            }
        }

        SectionHeader {
            first: true
            text: qsTr("Files & Folders (%1)").arg(AndroLaunch.files.length)
        }

        ItemList {
            id: fileList

            showList: AndroLaunch.hasConnectedDevice && AndroLaunch.files.length > 0
            placeholderIcon: "folder"
            placeholderText: AndroLaunch.loadingFiles ? qsTr("Loading directory contents...") : (AndroLaunch.hasConnectedDevice ? qsTr("Directory is empty") : qsTr("No device connected"))

            model: AndroLaunch.files

            delegate: StyledRect {
                id: fileDelegate

                required property var modelData
                required property int index

                anchors.left: fileList.list.contentItem.left
                anchors.right: fileList.list.contentItem.right
                implicitHeight: fileRowLayout.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.extraSmall
                color: Colours.tPalette.m3surfaceContainer

                StateLayer {
                    onClicked: {
                        if (fileDelegate.modelData.isDirectory)
                            AndroLaunch.browsePath(fileDelegate.modelData.path);
                    }
                }

                RowLayout {
                    id: fileRowLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: fileDelegate.modelData.isDirectory ? "folder" : "description"
                        color: fileDelegate.modelData.isDirectory ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: fileDelegate.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `${fileDelegate.modelData.formattedSize} • ${fileDelegate.modelData.permissions}`
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        visible: !fileDelegate.modelData.isDirectory
                        icon: "download"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        onClicked: {
                            const dest = `/home/senpai/Downloads/${fileDelegate.modelData.name}`;
                            AndroLaunch.pullFile(fileDelegate.modelData.path, dest);
                        }
                    }

                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: AndroLaunch.deleteFile(fileDelegate.modelData.path)
                    }
                }
            }
        }
    }
}
