import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    property alias cfg_maxFps: fpsSpin.value
    property alias cfg_bitRate: bitrateSpin.value
    property alias cfg_maxSize: sizeSpin.value
    property alias cfg_audio: audioSwitch.checked
    property alias cfg_stayAwake: awakeSwitch.checked
    property alias cfg_aspectRatioLock: aspectSwitch.checked
    property alias cfg_borderless: borderlessSwitch.checked
    property alias cfg_newDisplay: newDisplaySwitch.checked
    property alias cfg_flexDisplay: flexSwitch.checked
    property alias cfg_cameraTorch: torchSwitch.checked
    property alias cfg_cameraZoom: zoomSlider.value
    property string cfg_cameraFacing: "back"

    spacing: Kirigami.Units.largeSpacing

    Kirigami.FormLayout {
        Layout.fillWidth: true

        PlasmaComponents3.SpinBox {
            id: fpsSpin

            Kirigami.FormData.label: "Frame rate limit (fps):"
            from: 0
            to: 240
            stepSize: 10
            textFromValue: value => value === 0 ? "unlimited" : value + " fps"
        }

        PlasmaComponents3.SpinBox {
            id: bitrateSpin

            Kirigami.FormData.label: "Bitrate (Mbps):"
            from: 1
            to: 100
        }

        PlasmaComponents3.SpinBox {
            id: sizeSpin

            Kirigami.FormData.label: "Max resolution (px):"
            from: 0
            to: 4096
            stepSize: 120
            textFromValue: value => value === 0 ? "native" : value + " px"
        }

        PlasmaComponents3.Switch {
            id: audioSwitch

            Kirigami.FormData.label: "Forward audio:"
            text: checked ? "Enabled" : "Disabled"
        }

        PlasmaComponents3.Switch {
            id: awakeSwitch

            Kirigami.FormData.label: "Keep device awake:"
            text: checked ? "Enabled" : "Disabled"
        }

        PlasmaComponents3.Switch {
            id: aspectSwitch

            Kirigami.FormData.label: "Lock window aspect ratio:"
            text: checked ? "Enabled" : "Disabled"
        }

        PlasmaComponents3.Switch {
            id: borderlessSwitch

            Kirigami.FormData.label: "Borderless window:"
            text: checked ? "Enabled" : "Disabled"
        }

        PlasmaComponents3.Switch {
            id: newDisplaySwitch

            Kirigami.FormData.label: "Virtual display:"
            text: checked ? "Enabled" : "Disabled"
        }

        PlasmaComponents3.Switch {
            id: flexSwitch

            Kirigami.FormData.label: "Resize virtual display with window:"
            text: checked ? "Enabled" : "Disabled"
            enabled: newDisplaySwitch.checked
        }
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Camera"
        }

        PlasmaComponents3.ComboBox {
            id: facingBox

            Kirigami.FormData.label: "Camera facing:"
            model: ["back", "front"]
            currentIndex: Math.max(0, model.indexOf(cfg_cameraFacing))
            onActivated: cfg_cameraFacing = model[index]
        }

        PlasmaComponents3.Switch {
            id: torchSwitch

            Kirigami.FormData.label: "Flash torch:"
            text: checked ? "Enabled" : "Disabled"
        }

        RowLayout {
            Kirigami.FormData.label: "Camera zoom:"

            PlasmaComponents3.Slider {
                id: zoomSlider

                Layout.fillWidth: true
                from: 1
                to: 8
                stepSize: 0.1
            }

            PlasmaComponents3.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: zoomSlider.value.toFixed(1) + "x"
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
