pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "components"

ColumnLayout {
    id: root

    required property var backend

    // Set when the helper reports that the emulator tooling is unavailable.
    property bool emulatorMissing: false

    spacing: Kirigami.Units.smallSpacing

    Component.onCompleted: root.backend.fetchAvds()

    Connections {
        target: root.backend
        function onResponse(action, data) {
            if (action !== "avds" || !data)
                return
            if (data.ok === false)
                root.emulatorMissing = true
            else if (data.ok === true)
                root.emulatorMissing = false
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        SectionLabel {
            Layout.fillWidth: true
            text: "Android Virtual Devices"
        }

        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            text: "Refresh"
            enabled: !root.backend.avdsLoading
            onClicked: root.backend.fetchAvds()

            PlasmaComponents3.ToolTip {
                text: "Refresh AVD list"
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            running: root.backend.avdsLoading
            visible: root.backend.avdsLoading
        }

        EmptyState {
            anchors.fill: parent
            visible: !root.backend.avdsLoading && root.emulatorMissing
            iconName: "computer"
            message: "Android emulator not installed"
            hint: "Install it with: sudo dnf install android-tools  (the `emulator` binary is currently not available from Fedora packages — install the Android SDK emulator to use AVDs)"
        }

        EmptyState {
            anchors.fill: parent
            visible: !root.backend.avdsLoading && !root.emulatorMissing
                     && root.backend.avds.length === 0
            iconName: "computer"
            message: "No virtual devices found"
            hint: "Create one with avdmanager / Android Studio"
        }

        PlasmaComponents3.ScrollView {
            id: scroll
            anchors.fill: parent
            visible: !root.backend.avdsLoading && !root.emulatorMissing
                     && root.backend.avds.length > 0

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.backend.avds

                    delegate: RowLayout {
                        id: avdRow
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Kirigami.Units.mediumSpacing

                        Kirigami.Icon {
                            source: "computer"
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: implicitWidth
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: avdRow.modelData.name
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: avdRow.modelData.running ? "Running" : "Stopped"
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                opacity: 0.6
                            }
                        }

                        PlasmaComponents3.ToolButton {
                            icon.name: "media-playback-start"
                            text: "Start"
                            enabled: !avdRow.modelData.running
                            onClicked: root.backend.startAvd(avdRow.modelData.name)

                            PlasmaComponents3.ToolTip {
                                text: avdRow.modelData.running
                                      ? "This virtual device is already running"
                                      : "Start " + avdRow.modelData.name
                            }
                        }
                    }
                }
            }
        }
    }

    ActionButton {
        iconName: "view-refresh"
        text: "Refresh emulators"
        enabled: !root.backend.avdsLoading
        onClicked: root.backend.fetchAvds()
    }
}
