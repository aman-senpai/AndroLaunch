import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "components"
import "../code/util.js" as Util

ColumnLayout {
    id: root

    required property var backend
    property string confirmPath: ""
    property bool newFolderVisible: false

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.smallSpacing

    Component.onCompleted: if (root.backend.hasDevice)
        root.backend.browse(root.backend.currentPath || "/sdcard", true)

    Connections {
        target: root.backend

        function onActiveIdChanged() {
            root.confirmPath = ""
            root.backend.browse("/sdcard", true)
        }

        function onCurrentPathChanged() {
            root.confirmPath = ""
            pathField.text = root.backend.currentPath
        }
    }

    function openUploadDialog() {
        root.backend.holdPopup()
        uploadDialog.open()
    }

    // ---- path bar ----------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.ToolButton {
            icon.name: "go-up"
            enabled: root.backend.hasDevice
            PlasmaComponents3.ToolTip.text: "Go up"
            onClicked: root.backend.browse(Util.parentPath(root.backend.currentPath), false)
        }

        PlasmaComponents3.TextField {
            id: pathField
            Layout.fillWidth: true
            enabled: root.backend.hasDevice
            text: root.backend.currentPath
            placeholderText: "/sdcard"
            onAccepted: root.backend.browse(text, false)
        }

        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            enabled: root.backend.hasDevice
            PlasmaComponents3.ToolTip.text: "Refresh"
            onClicked: root.backend.browse(root.backend.currentPath, false)
        }

        PlasmaComponents3.ToolButton {
            icon.name: "folder-new"
            enabled: root.backend.hasDevice
            PlasmaComponents3.ToolTip.text: "New folder"
            onClicked: root.newFolderVisible = !root.newFolderVisible
        }

        PlasmaComponents3.ToolButton {
            icon.name: "document-open"
            enabled: root.backend.hasDevice
            PlasmaComponents3.ToolTip.text: "Upload file"
            onClicked: root.openUploadDialog()
        }
    }

    // ---- new folder inline form -------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: root.newFolderVisible

        PlasmaComponents3.TextField {
            id: newFolderField
            Layout.fillWidth: true
            placeholderText: "Folder name"
            onAccepted: createButton.clicked()
        }

        PlasmaComponents3.Button {
            id: createButton
            text: "Create"
            enabled: newFolderField.text.length > 0
            onClicked: {
                if (newFolderField.text.length === 0)
                    return;
                var name = newFolderField.text;
                newFolderField.text = "";
                root.newFolderVisible = false;
                root.backend.makeDirectory(root.backend.currentPath + "/" + name);
            }
        }

        PlasmaComponents3.Button {
            text: "Cancel"
            onClicked: {
                newFolderField.text = "";
                root.newFolderVisible = false;
            }
        }
    }

    // ---- content -----------------------------------------------------------
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        PlasmaComponents3.ScrollView {
            id: fileScroll
            anchors.fill: parent
            visible: root.backend.hasDevice && !root.backend.filesLoading && root.backend.files.length > 0

            // Repeater instead of a ListView: a ListView delegate does not paint text in this
            // applet context (icons do), while this pattern renders correctly everywhere else.
            ColumnLayout {
                width: fileScroll.availableWidth
                spacing: 0

                Repeater {
                    model: root.backend.files

                    delegate: Item {
                            id: fileRow

                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: rowContent.implicitHeight + Kirigami.Units.smallSpacing * 2

                        Rectangle {
                            anchors.fill: parent
                            color: rowMouse.containsMouse && fileRow.modelData.isDirectory
                                ? Kirigami.Theme.hoverColor
                                : "transparent"
                            radius: Kirigami.Units.smallSpacing
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: fileRow.modelData.isDirectory
                            onClicked: root.backend.browse(fileRow.modelData.path, false)
                        }

                        RowLayout {
                            id: rowContent
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.smallSpacing
                            anchors.rightMargin: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: fileRow.modelData.isDirectory ? "folder" : "application-x-executable"
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: implicitWidth
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    font: {
                                        const appFont = Qt.application.font;
                                        appFont.bold = true;
                                        return appFont;
                                    }
                                    color: palette.windowText
                                    Layout.fillWidth: true
                                    text: fileRow.modelData.name
                                    elide: Text.ElideRight
                                }

                                Text {
                                    font: Qt.application.font
                                    color: palette.windowText
                                    Layout.fillWidth: true
                                    text: fileRow.modelData.formattedSize + " • " + fileRow.modelData.date
                                    opacity: 0.6
                                    elide: Text.ElideRight
                                }
                            }

                            PlasmaComponents3.Label {
                                visible: root.confirmPath === fileRow.modelData.path
                                text: "Delete?"
                                color: Kirigami.Theme.negativeTextColor
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }

                            PlasmaComponents3.ItemDelegate {
                                visible: fileRow.modelData.isDirectory
                                Layout.preferredWidth: implicitWidth
                                icon.name: "go-next"
                                onClicked: root.backend.browse(fileRow.modelData.path, false)
                            }

                            PlasmaComponents3.ToolButton {
                                visible: !fileRow.modelData.isDirectory
                                icon.name: "download"
                                PlasmaComponents3.ToolTip.text: "Download"
                                onClicked: root.backend.pullFile(fileRow.modelData.path, "~/Downloads")
                            }

                            PlasmaComponents3.ToolButton {
                                icon.name: "edit-delete"
                                icon.color: root.confirmPath === fileRow.modelData.path
                                    ? Kirigami.Theme.negativeTextColor
                                    : Kirigami.Theme.textColor
                                PlasmaComponents3.ToolTip.text: "Delete"
                                onClicked: {
                                    if (root.confirmPath === fileRow.modelData.path) {
                                        root.confirmPath = "";
                                        root.backend.deleteFile(fileRow.modelData.path);
                                    } else {
                                        root.confirmPath = fileRow.modelData.path;
                                    }
                                }
                            }
                        }
                    }
                
                }
            }

        }

        EmptyState {
            anchors.fill: parent
            visible: !root.backend.hasDevice
            iconName: "smartphone"
            message: "Connect a device to browse its storage"
        }

        EmptyState {
            anchors.fill: parent
            visible: root.backend.hasDevice && !root.backend.filesLoading && root.backend.files.length === 0
            iconName: "folder"
            message: "This folder is empty"
        }

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            visible: root.backend.hasDevice && root.backend.filesLoading
            running: visible
        }
    }

    // ---- footer ------------------------------------------------------------
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: root.backend.files.length === 1 ? "1 item" : root.backend.files.length + " items"
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.6
    }

    SectionLabel {
        text: "Tip"
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: "Long-press style delete confirmation: click the trash icon twice"
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.55
        wrapMode: Text.WordWrap
    }

    // ---- upload dialog -----------------------------------------------------
    FileDialog {
        id: uploadDialog
        title: "Upload file"
        fileMode: FileDialog.OpenFile
        onAccepted: {
            root.backend.releasePopup()
            root.backend.pushFile(String(selectedFile).replace("file://", ""), root.backend.currentPath)
        }
        onRejected: root.backend.releasePopup()
    }
}
