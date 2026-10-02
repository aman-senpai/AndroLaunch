import QtQuick
import org.kde.kirigami as Kirigami

/*
 * Panel (menubar) representation: the AndroLaunch mark from the macOS app
 * (MenuIcons.imageset, the tile with the Android head cut out). The icon is the only
 * thing drawn here — device, connection type and battery level are in the tooltip and
 * in the popup. Clicking it expands the popup.
 *
 * The glyph is a bitmap with a hairline dark edge so it stays legible on light and
 * dark panels — panel applets cannot rely on Kirigami.Theme.textColor, which follows
 * the window colour scheme while the panel may use the opposite one.
 */
Item {
    id: compact

    required property var backend
    required property var plasmoidItem

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    readonly property bool active: backend.hasDevice

    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    Image {
        id: icon

        anchors.fill: parent
        source: Qt.resolvedUrl("../icons/androlaunch-menubar.png")
        sourceSize.width: Kirigami.Units.iconSizes.smallMedium
        sourceSize.height: Kirigami.Units.iconSizes.smallMedium
        smooth: true
        opacity: compact.active ? 1 : 0.6
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: compact.plasmoidItem.expanded = !compact.plasmoidItem.expanded
    }
}
