import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

/*
 * Flat, full-width button whose icon + label pair is centred.
 *
 * Plasma's own content item switches the label to Text.AlignLeft as soon as an
 * icon is shown (Private/ButtonContent.qml), so a row of wide buttons reads as
 * ragged: every label hugs the left edge of its own third. The pair is anchored
 * to the centre of the content area here instead.
 */
PlasmaComponents3.ToolButton {
    id: component

    readonly property color tint: icon.color.a > 0 ? icon.color : Kirigami.Theme.textColor

    Layout.fillWidth: true
    // A common preferred width makes the row's members equal thirds instead of
    // each one growing by its own label length, so the labels line up.
    Layout.preferredWidth: 1
    display: PlasmaComponents3.AbstractButton.TextBesideIcon

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        RowLayout {
            id: row

            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
                source: component.icon.name
                color: component.tint
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignVCenter
                text: component.text
                color: component.tint
            }
        }
    }
}
