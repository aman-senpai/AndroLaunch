pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> cameraFacingItems: [
        MenuItem {
            text: qsTr("Back Camera")
        },
        MenuItem {
            text: qsTr("Front Camera")
        }
    ]

    isSubPage: true
    title: qsTr("Screen & Camera Mirroring")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Screen Mirroring (Scrcpy)")
        }

        ToggleRow {
            first: true
            text: qsTr("Flex Display")
            subtext: qsTr("Resize virtual display dynamically with the window")
            checked: AndroLaunch.scrcpyConfig.flexDisplay
            onToggled: {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { flexDisplay: checked });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        ToggleRow {
            text: qsTr("Audio Forwarding")
            subtext: qsTr("Forward Android audio to Linux PipeWire")
            checked: AndroLaunch.scrcpyConfig.audioEnabled
            onToggled: {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { audioEnabled: checked });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        ToggleRow {
            text: qsTr("Keep Active / Stay Awake")
            subtext: qsTr("Prevent device from sleeping during mirroring session")
            checked: AndroLaunch.scrcpyConfig.keepActive
            onToggled: {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { keepActive: checked });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        ToggleRow {
            text: qsTr("Aspect Ratio Lock")
            subtext: qsTr("Maintain device aspect ratio when resizing window")
            checked: AndroLaunch.scrcpyConfig.lockAspectRatio
            onToggled: {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { lockAspectRatio: checked });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Borderless Window")
            subtext: qsTr("Open mirroring window without system titlebars/borders")
            checked: AndroLaunch.scrcpyConfig.borderless
            onToggled: {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { borderless: checked });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        SectionHeader {
            text: qsTr("Performance & Video")
        }

        SliderRow {
            first: true
            icon: "speed"
            label: qsTr("Max Frame Rate")
            valueLabel: `${AndroLaunch.scrcpyConfig.maxFps} FPS`
            value: AndroLaunch.scrcpyConfig.maxFps / 120
            onMoved: val => {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { maxFps: Math.max(15, Math.round(val * 120)) });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        SliderRow {
            last: true
            icon: "high_quality"
            label: qsTr("Video Bitrate")
            valueLabel: `${AndroLaunch.scrcpyConfig.bitRate} Mbps`
            value: AndroLaunch.scrcpyConfig.bitRate / 32
            onMoved: val => {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { bitRate: Math.max(2, Math.round(val * 32)) });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        SectionHeader {
            text: qsTr("Camera Mirroring")
        }
        SelectRow {
            first: true
            label: qsTr("Camera Facing")
            subtext: qsTr("Select front or rear camera")
            menuItems: root.cameraFacingItems
            active: root.cameraFacingItems[AndroLaunch.scrcpyConfig.cameraFacing === "front" ? 1 : 0]
            onSelected: item => {
                const isFront = root.cameraFacingItems.indexOf(item) === 1;
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { cameraFacing: isFront ? "front" : "back" });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        ToggleRow {
            text: qsTr("Camera Flashlight / Torch")
            subtext: qsTr("Enable device flash during camera mirror")
            checked: AndroLaunch.scrcpyConfig.cameraTorch
            onToggled: {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { cameraTorch: checked });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        SliderRow {
            last: true
            icon: "zoom_in"
            label: qsTr("Camera Zoom")
            valueLabel: `${AndroLaunch.scrcpyConfig.cameraZoom.toFixed(1)}x`
            value: (AndroLaunch.scrcpyConfig.cameraZoom - 1.0) / 4.0
            onMoved: val => {
                const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { cameraZoom: 1.0 + val * 4.0 });
                AndroLaunch.scrcpyConfig = conf;
            }
        }

        RowButton {
            Layout.topMargin: Tokens.spacing.large
            first: true
            last: true
            icon: "screen_share"
            text: qsTr("Launch Screen Mirroring Now")
            disabled: !AndroLaunch.hasConnectedDevice
            onClicked: AndroLaunch.startMirroring()
        }
    }
}
