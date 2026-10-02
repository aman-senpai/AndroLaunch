import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: empty

    property string iconName: "smartphone"
    property string message: ""
    property string hint: ""

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.smallSpacing

    Item {
        Layout.fillHeight: true
    }

    Kirigami.Icon {
        Layout.alignment: Qt.AlignHCenter
        source: empty.iconName
        implicitWidth: Kirigami.Units.iconSizes.huge
        implicitHeight: implicitWidth
        opacity: 0.35
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: empty.message
        opacity: 0.8
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: empty.hint.length > 0
        text: empty.hint
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.55
    }

    Item {
        Layout.fillHeight: true
    }
}
