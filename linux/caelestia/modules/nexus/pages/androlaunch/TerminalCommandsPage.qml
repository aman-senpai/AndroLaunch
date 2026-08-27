pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    isSubPage: true
    title: qsTr("ADB Shell & Commands")

    property string lastOutput: ""
    property bool runningCmd: false

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        RowButton {
            first: true
            last: true
            icon: "terminal"
            text: qsTr("Open Interactive Shell in Terminal")
            subtext: qsTr("Spawns full PTY ADB session in your default terminal")
            disabled: !AndroLaunch.hasConnectedDevice
            onClicked: AndroLaunch.openTerminal()
        }

        SectionHeader {
            text: qsTr("Quick Execute Command")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledTextField {
                id: customInput
                Layout.fillWidth: true
                placeholderText: qsTr("Enter shell command (e.g. getprop ro.build.version.release)...")
                onAccepted: runBtn.clicked()
            }

            IconTextButton {
                id: runBtn
                text: qsTr("Run")
                icon: "play_arrow"
                disabled: !AndroLaunch.hasConnectedDevice || customInput.text.trim().length === 0 || root.runningCmd
                onClicked: {
                    root.runningCmd = true;
                    AndroLaunch.executeShell(customInput.text.trim(), (success, out, err) => {
                        root.runningCmd = false;
                        root.lastOutput = out || err || (success ? qsTr("[Success, no output]") : qsTr("[Command failed]"));
                    });
                }
            }
        }

        // Output Display Box
        StyledRect {
            Layout.fillWidth: true
            visible: root.lastOutput.length > 0
            implicitHeight: Math.min(200, outputText.implicitHeight + Tokens.padding.medium * 2)
            color: Colours.palette.m3surfaceContainerLowest
            radius: Tokens.rounding.medium

            StyledFlickable {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                contentHeight: outputText.implicitHeight
                clip: true

                StyledText {
                    id: outputText
                    width: parent.width
                    text: root.lastOutput
                    font: Tokens.font.mono.small
                    color: Colours.palette.m3onSurface
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        SectionHeader {
            text: qsTr("Saved Custom Commands (%1)").arg(AndroLaunch.customCommands.length)
        }

        ItemList {
            id: cmdList

            showList: AndroLaunch.customCommands.length > 0
            placeholderIcon: "terminal"
            placeholderText: qsTr("No custom commands saved")

            model: AndroLaunch.customCommands

            delegate: StyledRect {
                id: cmdDelegate

                required property var modelData
                required property int index

                anchors.left: cmdList.list.contentItem.left
                anchors.right: cmdList.list.contentItem.right
                implicitHeight: cmdRowLayout.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.extraSmall
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    id: cmdRowLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "code"
                        color: Colours.palette.m3secondary
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: cmdDelegate.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: cmdDelegate.modelData.command
                            color: Colours.palette.m3outline
                            font: Tokens.font.mono.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        icon: "play_arrow"
                        type: IconButton.Filled
                        disabled: !AndroLaunch.hasConnectedDevice
                        onClicked: {
                            root.runningCmd = true;
                            AndroLaunch.executeShell(cmdDelegate.modelData.command, (success, out, err) => {
                                root.runningCmd = false;
                                root.lastOutput = out || err || (success ? qsTr("[Success, no output]") : qsTr("[Command failed]"));
                            });
                        }
                    }

                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        padding: Tokens.padding.extraSmall
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: AndroLaunch.removeCustomCommand(cmdDelegate.modelData.id)
                    }
                }
            }
        }
    }
}
