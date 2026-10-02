import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

/*
 * Chip-style toggle. `active` is the authoritative state coming from the device;
 * clicking emits the REQUESTED state through `toggled(requested)` and does not
 * toggle itself. Implemented as a wrapper (not a Button subclass) because
 * AbstractButton already declares a `toggled()` signal.
 *
 * Two things make the tile read as a toggle rather than a button:
 *
 *  1. a blue switch next to the label — the tile itself stays neutral, since a
 *     filled tile read as a highlighted button rather than as a state, and
 *  2. an optimistic state: `adb shell svc ...` takes a moment to run, so the
 *     tile shows the requested state immediately and falls back to the device
 *     state once the poll echoes it — or after `pendingTimeout` if it never
 *     does, rather than lying about a failed toggle.
 */
Item {
    id: chip

    property string iconName: ""
    property string label: ""
    property bool active: false

    // How long the optimistic state may stand in for the device's answer.
    property int pendingTimeout: 4000

    signal toggled(bool requested)

    property bool pendingValue: false

    readonly property bool pending: pendingTimer.running
    readonly property bool shownState: pending ? pendingValue : active

    onActiveChanged: {
        if (pending && active === pendingValue)
            pendingTimer.stop();
    }

    Layout.fillWidth: true
    Layout.minimumWidth: Kirigami.Units.gridUnit * 7
    Layout.preferredHeight: implicitHeight

    implicitWidth: button.implicitWidth
    implicitHeight: Kirigami.Units.gridUnit * 2
    opacity: enabled ? 1 : 0.5

    Accessible.name: label
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: shownState

    Timer {
        id: pendingTimer
        interval: chip.pendingTimeout
    }

    PlasmaComponents3.Button {
        id: button

        anchors.fill: parent
        enabled: chip.enabled
        flat: true
        // The background below is a plain Rectangle, so the button no longer
        // inherits the theme's frame margins as padding: without these the icon
        // and the switch sat flush against the tile edge.
        leftPadding: Kirigami.Units.smallSpacing
        rightPadding: Kirigami.Units.smallSpacing
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing
        onClicked: {
            const requested = !chip.shownState;
            chip.pendingValue = requested;
            pendingTimer.restart();
            chip.toggled(requested);
        }

        background: Rectangle {
            radius: Kirigami.Units.smallSpacing * 1.5
            // The tile surface stays neutral in both states: the switch below is
            // the only thing that turns accent-coloured, so the row reads as a
            // list of switches rather than a light show of blue buttons.
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
            opacity: button.pressed ? 0.75 : (button.hovered ? 0.9 : 1)

            Behavior on opacity {
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                }
            }
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: implicitWidth
                source: chip.iconName
                color: Kirigami.Theme.textColor
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: chip.label
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.textColor
            }

            // Compact switch: knob position and track colour give the state away
            // at a glance, which is what makes a toggle read as a toggle.
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.75)
                implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.9)

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: chip.shownState ? Kirigami.Theme.highlightColor : "transparent"
                    border.width: chip.shownState ? 0 : 1
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)

                    Behavior on color {
                        ColorAnimation {
                            duration: Kirigami.Units.shortDuration
                        }
                    }
                }

                Rectangle {
                    width: parent.height
                    height: parent.height
                    radius: height / 2
                    x: chip.shownState ? parent.width - width : 0
                    color: chip.shownState
                        ? Kirigami.Theme.highlightedTextColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.55)

                    Behavior on x {
                        NumberAnimation {
                            duration: Kirigami.Units.shortDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }

        PlasmaComponents3.ToolTip.text: chip.label + (chip.shownState ? ": on" : ": off")
    }
}
