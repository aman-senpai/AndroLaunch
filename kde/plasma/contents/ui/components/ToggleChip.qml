import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

/*
 * Chip-style toggle. `active` is the authoritative state coming from the device;
 * clicking emits the REQUESTED state through `toggled(requested)` and does not
 * toggle itself. Implemented as a wrapper (not a Button subclass) because
 * AbstractButton already declares a `toggled()` signal.
 */
Item {
    id: chip

    property string iconName: ""
    property string label: ""
    property bool active: false

    signal toggled(bool requested)

    Layout.fillWidth: true
    Layout.minimumWidth: Kirigami.Units.gridUnit * 4
    Layout.preferredHeight: button.implicitHeight

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    opacity: enabled ? 1 : 0.5

    PlasmaComponents3.Button {
        id: button

        anchors.fill: parent
        icon.name: chip.iconName
        text: chip.label
        highlighted: chip.active
        enabled: chip.enabled
        onClicked: chip.toggled(!chip.active)
    }
}
