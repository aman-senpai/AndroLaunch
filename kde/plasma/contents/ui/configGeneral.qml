import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    property alias cfg_helperPath: helperField.text
    property alias cfg_pollInterval: pollSpin.value

    spacing: Kirigami.Units.largeSpacing

    Kirigami.FormLayout {
        Layout.fillWidth: true

        PlasmaComponents3.TextField {
            id: helperField

            Kirigami.FormData.label: "Backend executable:"
            placeholderText: "androlaunch"
        }

        PlasmaComponents3.SpinBox {
            id: pollSpin

            Kirigami.FormData.label: "Refresh interval (seconds):"
            from: 2
            to: 120
            stepSize: 1
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Kirigami.FormData.isSection: false
            wrapMode: Text.WordWrap
            opacity: 0.7
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Absolute path or command name of the AndroLaunch helper. "
                + "Installed by default to ~/.local/bin/androlaunch. "
                + "adb comes from the android-tools package, mirroring needs scrcpy."
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
