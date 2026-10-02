import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmaComponents3.Label {
    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.smallSpacing
    Layout.bottomMargin: Kirigami.Units.smallSpacing / 2
    font.bold: true
    font.pointSize: Kirigami.Theme.smallFont.pointSize
    opacity: 0.7
    elide: Text.ElideRight
}
