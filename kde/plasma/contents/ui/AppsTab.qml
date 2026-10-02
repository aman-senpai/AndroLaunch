/*
 * AndroLaunch — installed-apps manager tab.
 *
 * Lists the user apps of the active device, with search, APK install,
 * launch, data-clear, app-mirror and uninstall (guarded by an inline
 * confirmation step) actions.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "components"

ColumnLayout {
    id: appsTab

    required property var backend

    // Search string bound to the header text field.
    property string filter: ""
    // Index of the app whose uninstall confirmation row is open (-1 = none).
    property int confirmIndex: -1

    readonly property var appModel: backend.apps.filter(a => filter.length === 0
        || String(a.name || "").toLowerCase().includes(filter.toLowerCase())
        || String(a.package || "").toLowerCase().includes(filter.toLowerCase()))

    spacing: Kirigami.Units.smallSpacing

    Component.onCompleted: {
        if (backend.hasDevice)
            backend.fetchApps(false)
    }

    Connections {
        target: backend
        function onActiveIdChanged() {
            appsTab.confirmIndex = -1
            backend.fetchApps(true)
        }
    }

    // ---- header ------------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.TextField {
            Layout.fillWidth: true
            placeholderText: "Search apps…"
            enabled: backend.hasDevice
            onTextChanged: {
                appsTab.filter = text
                appsTab.confirmIndex = -1
            }
        }

        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            enabled: backend.hasDevice && !backend.appsLoading
            onClicked: backend.fetchApps(true)

            PlasmaComponents3.ToolTip {
                text: "Refresh app list"
            }
        }

        PlasmaComponents3.ToolButton {
            icon.name: "document-open"
            enabled: backend.hasDevice && !backend.appsLoading
            onClicked: {
                backend.holdPopup()
                apkDialog.open()
            }

            PlasmaComponents3.ToolTip {
                text: "Install an APK"
            }
        }
    }

    // ---- busy --------------------------------------------------------------
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: backend.appsLoading && backend.hasDevice

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            running: backend.appsLoading
        }
    }

    // ---- no device ---------------------------------------------------------
    EmptyState {
        visible: !backend.hasDevice
        iconName: "smartphone"
        message: "Connect a device to manage apps"
    }

    // ---- no results --------------------------------------------------------
    EmptyState {
        visible: backend.hasDevice && !backend.appsLoading && appsTab.appModel.length === 0
        iconName: "application-x-executable"
        message: "No apps found"
    }

    // ---- app list ----------------------------------------------------------
    PlasmaComponents3.ScrollView {
        id: appScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: backend.hasDevice && !backend.appsLoading && appsTab.appModel.length > 0

        // A ListView delegate does not paint text in this applet context (icons and buttons
        // do), so the list is a Repeater inside the scroll area — the same pattern the other
        // tabs use, and the only one verified to render labels here.
        ColumnLayout {
            width: appScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing / 2

            Repeater {
                model: appsTab.appModel

                delegate: RowLayout {
                    id: appRow

                    required property var modelData
                    required property int index

                        Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    readonly property bool confirming: appsTab.confirmIndex === appRow.index

                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignVCenter
                        source: "application-x-executable"
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                        opacity: 0.8
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        // Plain Text on purpose: inside a ListView delegate the qtquickcontrols
                        // shape of a Label inherits a font/colour context that is not initialised
                        // in a plasmoid, and the text then never paints. Text with an explicit
                        // font and colour is self-contained.
                        Text {
                            Layout.fillWidth: true
                            color: palette.windowText
                            font: {
                                const appFont = Qt.application.font;
                                appFont.bold = true;
                                return appFont;
                            }
                            elide: Text.ElideRight
                            text: {
                                const app = appRow.modelData;
                                const name = (app.name || "").trim();
                                if (name.length > 0 && name !== app.package)
                                    return name;
                                const parts = String(app.package || "").split(".").filter(p => p.length > 1);
                                return parts.length > 0 ? parts[parts.length - 1] : (name || app.package);
                            }

                            MouseArea {
                                id: nameHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            // The package id lives here and in search, never in the row.
                            PlasmaComponents3.ToolTip {
                                text: appRow.modelData.package
                                      + (appRow.modelData.system === true ? " — system app" : "")
                                visible: nameHover.containsMouse
                            }
                        }

                    }

                    // Opens the app in its own window (scrcpy virtual display), so several
                    // apps can run side by side — only meaningful with scrcpy installed.
                    PlasmaComponents3.ToolButton {
                        Layout.alignment: Qt.AlignVCenter
                        visible: appsTab.backend.scrcpyPath.length > 0
                        icon.name: "window-new"
                        onClicked: appsTab.backend.appMirror(appRow.modelData.package, appRow.modelData.name)

                        PlasmaComponents3.ToolTip {
                            text: "Open in a new window"
                        }
                    }

                    // Mirrors the phone screen with the app in the foreground.
                    PlasmaComponents3.ToolButton {
                        Layout.alignment: Qt.AlignVCenter
                        visible: appsTab.backend.scrcpyPath.length > 0
                        icon.name: "video-display"
                        onClicked: appsTab.backend.appScreen(appRow.modelData.package, appRow.modelData.name)

                        PlasmaComponents3.ToolTip {
                            text: "Mirror the phone screen with this app open"
                        }
                    }

                    PlasmaComponents3.ToolButton {
                        Layout.alignment: Qt.AlignVCenter
                        icon.name: "media-playback-start"
                        onClicked: appsTab.backend.launchApp(appRow.modelData.package)

                        PlasmaComponents3.ToolTip {
                            text: "Launch on the device only"
                        }
                    }

                    PlasmaComponents3.ToolButton {
                        Layout.alignment: Qt.AlignVCenter
                        icon.name: "edit-clear"
                        onClicked: appsTab.backend.clearAppData(appRow.modelData.package)

                        PlasmaComponents3.ToolTip {
                            text: "Clear app data"
                        }
                    }

                    // Uninstall (initial button).
                    PlasmaComponents3.ToolButton {
                        Layout.alignment: Qt.AlignVCenter
                        visible: !appRow.confirming
                        icon.name: "edit-delete"
                        icon.color: Kirigami.Theme.negativeTextColor
                        onClicked: appsTab.confirmIndex = appRow.index

                        PlasmaComponents3.ToolTip {
                            text: "Uninstall app"
                        }
                    }

                    // Inline uninstall confirmation.
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        visible: appRow.confirming
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            text: "Uninstall?"
                            color: Kirigami.Theme.negativeTextColor
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }

                        PlasmaComponents3.ToolButton {
                            icon.name: "edit-delete"
                            icon.color: Kirigami.Theme.negativeTextColor
                            onClicked: {
                                appsTab.confirmIndex = -1
                                appsTab.backend.uninstallApp(appRow.modelData.package)
                            }
                        }

                        PlasmaComponents3.ToolButton {
                            text: "Cancel"
                            onClicked: appsTab.confirmIndex = -1
                        }
                    }
                }
            
            }
        }

    }

    // ---- footer ------------------------------------------------------------
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: backend.hasDevice
        opacity: 0.6
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        elide: Text.ElideRight
        text: {
            let label = backend.apps.length + " apps · " + appsTab.appModel.length + " shown";
            if (backend.appsSource === "scrcpy")
                label += " · names from scrcpy";
            else if (backend.appsSource === "cache")
                label += " · cached names (scrcpy unavailable)";
            else if (backend.appsSource === "pm")
                label += " · package names: scrcpy could not list apps";
            return label;
        }
    }

    // ---- APK installer picker ---------------------------------------------
    FileDialog {
        id: apkDialog

        title: "Select an APK to install"
        nameFilters: ["Android packages (*.apk)"]

        onAccepted: {
            backend.releasePopup()
            backend.installApk(String(selectedFile).replace("file://", ""))
        }

        onRejected: {
            backend.releasePopup()
        }
    }
}
