import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    id: row

    property string iconName: ""
    property real value: 0
    property string valueText: ""

    signal moved(real value)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        source: row.iconName
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: implicitWidth
        opacity: 0.8
    }

    PlasmaComponents3.Slider {
        id: slider

        Layout.fillWidth: true
        enabled: row.enabled
        from: 0
        to: 1
        stepSize: 0.01
        onMoved: row.moved(value)
    }

    Binding {
        target: slider
        property: "value"
        value: row.value
        when: !slider.pressed
        restoreMode: Binding.RestoreNone
    }

    PlasmaComponents3.Label {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
        horizontalAlignment: Text.AlignRight
        // while dragging show the position under the finger, not the device's old value
        text: slider.pressed ? Math.round(slider.value * 100) + "%" : row.valueText
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.8
    }
}
