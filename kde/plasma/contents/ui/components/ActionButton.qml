import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmaComponents3.Button {
    id: component

    property string iconName: ""
    property bool danger: false
    property bool fillWidth: true

    Layout.fillWidth: component.fillWidth
    icon.name: component.iconName
    icon.color: component.danger ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    text: ""
}
