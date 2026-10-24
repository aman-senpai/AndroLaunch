import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "components"
import "../code/util.js" as Util

/*
 * Expanded (popup) representation: device header, tab bar, lazily loaded tabs
 * and a footer with the most common actions.
 */
Item {
    id: full

    required property var backend

    // Kirigami.Theme carries no colour set inside a plasmoid (Plasma's own Label uses
    // Kirigami.Theme.textColor, which resolves to black there), so declare it explicitly:
    // every text/icon colour below then follows the popup's window colours.
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window

    implicitWidth: Kirigami.Units.gridUnit * 31
    implicitHeight: Kirigami.Units.gridUnit * 35

    property int visitedTab: 0
    readonly property int tabCount: 6
    property int selectedTab: 0
    property bool developerToolsVisible: false

    function selectTab(index) {
        selectedTab = index;
        visitedTab = Math.max(visitedTab, index);
        tabBar.currentIndex = index < 4 ? index : -1;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // ---- header --------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Image {
                source: Qt.resolvedUrl("../icons/androlaunch.png")
                sourceSize.width: Kirigami.Units.iconSizes.medium
                sourceSize.height: Kirigami.Units.iconSizes.medium
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                smooth: true
            }

            // The popup header is a single identity line: transport, battery and
            // the Android version all live on the device card below, so repeating
            // them here was noise.
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
                objectName: "deviceTitle"
                text: full.backend.activeDevice ? Util.deviceIdentity(full.backend.activeDevice) : "AndroLaunch"
                font.bold: true
            }

            PlasmaComponents3.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Layout.preferredWidth
                running: full.backend.busy
                visible: running
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                display: PlasmaComponents3.AbstractButton.IconOnly
                Accessible.name: "Refresh device state"
                onClicked: full.backend.refresh()
                PlasmaComponents3.ToolTip {
                    text: "Refresh device state"
                }
            }
        }

        // ---- dependency warning --------------------------------------------
        PlasmaComponents3.Frame {
            Layout.fillWidth: true
            visible: full.backend.adbMissing
            padding: Kirigami.Units.smallSpacing

            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "dialog-warning"
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: full.backend.adbRepair
                }
            }
        }

        // ---- backend missing -----------------------------------------------
        PlasmaComponents3.Frame {
            Layout.fillWidth: true
            visible: !full.backend.helperReady
            padding: Kirigami.Units.smallSpacing

            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "dialog-error"
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: full.backend.helperError.length > 0
                          ? full.backend.helperError
                          : "The androlaunch helper was not found. Re-run the AndroLaunch installer or set its executable path in Configure AndroLaunch, then Retry."
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    Accessible.name: "Retry backend connection"
                    onClicked: full.backend.bootstrap()
                    PlasmaComponents3.ToolTip {
                        text: "Retry"
                    }
                }
            }
        }

        // ---- transient message ---------------------------------------------
        PlasmaComponents3.Frame {
            Layout.fillWidth: true
            visible: full.backend.lastMessage.length > 0
            padding: Kirigami.Units.smallSpacing

            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: full.backend.lastMessageError ? "dialog-error" : "dialog-information"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: full.backend.lastMessage
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "window-close"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    Accessible.name: "Dismiss message"
                    onClicked: full.backend.dismissMessage()
                }
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: full.backend.helperReady && !full.backend.adbMissing && !full.backend.scrcpyCompatible
            wrapMode: Text.Wrap
            text: full.backend.scrcpySummary + " Apps, files and device controls remain available with an authorized device."
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }

        PlasmaComponents3.Button {
            visible: full.backend.helperReady && (full.backend.adbMissing || !full.backend.scrcpyCompatible)
            text: "Retry dependencies"
            icon.name: "view-refresh"
            onClicked: full.backend.bootstrap()
        }

        // ---- tabs ----------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents3.TabBar {
                id: tabBar
                Layout.fillWidth: true

                Repeater {
                    model: ["Device", "Apps", "Wireless", "Files"]
                    PlasmaComponents3.TabButton {
                        required property string modelData
                        text: modelData
                    }
                }
                onCurrentIndexChanged: {
                    if (currentIndex >= 0)
                        full.selectTab(currentIndex);
                }
            }

            PlasmaComponents3.ToolButton {
                icon.name: "applications-development"
                checkable: true
                checked: full.developerToolsVisible
                Accessible.name: "Show developer tools"
                PlasmaComponents3.ToolTip.text: "Developer tools: Console and Emulators"
                onClicked: full.developerToolsVisible = !full.developerToolsVisible
            }
        }

        RowLayout {
            visible: full.developerToolsVisible
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                text: "Developer tools"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.fillWidth: true
            }
            PlasmaComponents3.Button {
                text: "Console"
                checked: full.selectedTab === 4
                onClicked: full.selectTab(4)
            }
            PlasmaComponents3.Button {
                text: "Emulators"
                checked: full.selectedTab === 5
                onClicked: full.selectTab(5)
            }
        }

        StackLayout {
            id: stack

            Layout.fillWidth: true
            Layout.fillHeight: true
            // The tab content used to sit flush against the popup frame, which
            // made the toggle tiles and the action rows look crammed.
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            currentIndex: full.selectedTab

            Loader {
                active: full.visitedTab >= 0
                asynchronous: false
                sourceComponent: QuickTab {
                    backend: full.backend
                }
            }

            Loader {
                active: full.visitedTab >= 1
                asynchronous: false
                sourceComponent: AppsTab {
                    backend: full.backend
                }
            }

            Loader {
                active: full.visitedTab >= 2
                asynchronous: false
                sourceComponent: WirelessTab {
                    backend: full.backend
                }
            }

            Loader {
                active: full.visitedTab >= 3
                asynchronous: false
                sourceComponent: FilesTab {
                    backend: full.backend
                }
            }

            Loader {
                active: full.visitedTab >= 4
                asynchronous: false
                sourceComponent: ShellTab {
                    backend: full.backend
                }
            }

            Loader {
                active: full.visitedTab >= 5
                asynchronous: false
                sourceComponent: AvdTab {
                    backend: full.backend
                }
            }
        }
    }
}
