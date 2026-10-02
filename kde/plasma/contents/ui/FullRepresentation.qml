import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

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

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "AndroLaunch"
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
                    text: "adb not found. Install it with: sudo dnf install android-tools scrcpy"
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
                          : "The androlaunch helper was not found. Run: curl -fsSL https://raw.githubusercontent.com/aman-senpai/AndroLaunch/master/install.sh | bash"
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents3.AbstractButton.IconOnly
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
                    onClicked: full.backend.dismissMessage()
                }
            }
        }

        // ---- tabs ----------------------------------------------------------
        PlasmaComponents3.TabBar {
            id: tabBar

            Layout.fillWidth: true

            Repeater {
                model: ["Quick", "Apps", "Pair", "Files", "Shell", "AVDs"]

                PlasmaComponents3.TabButton {
                    text: modelData
                }
            }

            onCurrentIndexChanged: full.visitedTab = Math.max(full.visitedTab, currentIndex)
        }

        StackLayout {
            id: stack

            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

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
