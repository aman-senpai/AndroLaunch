pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.widgets
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property PopoutState popouts

    width: 420
    spacing: Tokens.spacing.medium

    readonly property bool available: AndroLaunch.available
    readonly property var dev: AndroLaunch.activeDevice
    readonly property bool hasDev: !!dev && dev.isConnected
    readonly property var qa: dev?.quickActions

    property string currentTab: "main" // "main", "apps", "config", "wireless", "commands", "avds"
    property string appFilter: ""
    // Component: Tab Button
    component TabButton: StyledRect {
        id: tabBtn
        property string tabId: ""
        property string iconName: ""
        property string label: ""
        signal clicked

        Layout.fillWidth: true
        implicitHeight: 34
        radius: Tokens.rounding.small
        color: root.currentTab === tabId ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

        StateLayer {
            onClicked: {
                root.currentTab = tabBtn.tabId;
                tabBtn.clicked();
            }
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 4
            MaterialIcon {
                text: tabBtn.iconName
                color: root.currentTab === tabBtn.tabId ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                text: tabBtn.label
                color: root.currentTab === tabBtn.tabId ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }

    // Component: Config Pill
    component ConfigPill: StyledRect {
        id: pill
        property string text: ""
        property bool selected: false
        signal clicked

        Layout.fillWidth: true
        implicitHeight: 28
        radius: Tokens.rounding.full
        color: pill.selected ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

        StateLayer {
            radius: Tokens.rounding.full
            onClicked: pill.clicked()
        }

        StyledText {
            anchors.centerIn: parent
            text: pill.text
            color: pill.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            font: Tokens.font.label.small
        }
    }

    // Component: Quick Toggle Button
    component QuickToggleBtn: StyledRect {
        id: btn
        property string icon: ""
        property string label: ""
        property bool active: false
        signal clicked

        Layout.fillWidth: true
        implicitHeight: 44
        radius: Tokens.rounding.small
        color: btn.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

        StateLayer {
            disabled: !root.hasDev
            onClicked: btn.clicked()
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: btn.icon
                color: btn.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
                fill: btn.active ? 1 : 0
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: btn.label
                color: btn.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }
    // Header Title & Refresh Button
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "smartphone"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.medium
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("AndroLaunch")
            font: Tokens.font.body.builders.medium.weight(Font.Bold).build()
        }

        IconButton {
            icon: "refresh"
            type: IconButton.Text
            padding: Tokens.padding.extraSmall
            onClicked: AndroLaunch.scanDevices()
        }
    }

    // ADB Missing Warning
    Loader {
        Layout.fillWidth: true
        active: !root.available
        visible: active

        sourceComponent: StyledRect {
            implicitHeight: noAdbCol.implicitHeight + Tokens.padding.medium * 2
            color: Colours.palette.m3errorContainer
            radius: Tokens.rounding.medium

            ColumnLayout {
                id: noAdbCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    spacing: Tokens.spacing.small
                    MaterialIcon {
                        text: "warning"
                        color: Colours.palette.m3onErrorContainer
                    }
                    StyledText {
                        text: qsTr("ADB Not Found")
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onErrorContainer
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Please install `android-tools` (or Android SDK) and `scrcpy`.")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onErrorContainer
                    wrapMode: Text.WordWrap
                }

                IconTextButton {
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("Re-check")
                    icon: "refresh"
                    onClicked: AndroLaunch.checkPaths()
                }
            }
        }
    }

    // Active Device Card / Telemetry Header
    StyledRect {
        Layout.fillWidth: true
        visible: root.available
        implicitHeight: devCardLayout.implicitHeight + Tokens.padding.small * 2
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.medium

        ColumnLayout {
            id: devCardLayout
            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: root.hasDev ? (root.dev.isWireless ? "wifi" : "usb") : "smartphone"
                    color: root.hasDev ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.hasDev ? (root.dev.name || root.dev.model) : qsTr("No devices found")
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.hasDev
                        text: {
                            if (!root.hasDev) return "";
                            let info = root.dev.serialNumber;
                            if (root.dev.androidVersion)
                                info += ` • ${root.dev.androidVersion} (API ${root.dev.apiLevel})`;
                            return info;
                        }
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                // Battery Badge
                RowLayout {
                    visible: root.hasDev && root.dev.batteryLevel >= 0
                    spacing: 2

                    MaterialIcon {
                        text: Icons.getBatteryIcon((root.dev?.batteryLevel ?? 0) / 100, root.dev?.isCharging ?? false)
                        color: (root.dev?.batteryLevel ?? 0) <= 20 ? Colours.palette.m3error : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        text: `${root.dev?.batteryLevel ?? 0}%${root.dev?.isCharging ? " ⚡" : ""}`
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }

            // Multiple Devices List (if > 1)
            Repeater {
                model: AndroLaunch.devices.length > 1 ? AndroLaunch.devices : []

                RowLayout {
                    id: devRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: modelData.id !== root.dev?.id

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.name || modelData.id
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                    }

                    IconTextButton {
                        text: qsTr("Select")
                        padding: Tokens.padding.extraSmall
                        onClicked: AndroLaunch.selectDevice(devRow.modelData.id)
                    }
                }
            }
        }
    }

    // Quick Action Bar (Mirror, Camera, Shell, Logcat, Disconnect)
    RowLayout {
        Layout.fillWidth: true
        visible: root.available && root.hasDev
        spacing: Tokens.spacing.extraSmall

        IconTextButton {
            Layout.fillWidth: true
            text: qsTr("Mirror")
            icon: "screen_share"
            inactiveColour: Colours.palette.m3primary
            inactiveOnColour: Colours.palette.m3onPrimary
            onClicked: AndroLaunch.startMirroring()
        }

        IconButton {
            icon: "videocam"
            type: IconButton.Tonal
            onClicked: AndroLaunch.startCameraMirroring()
        }

        IconButton {
            icon: "terminal"
            type: IconButton.Tonal
            onClicked: AndroLaunch.openTerminal()
        }

        IconButton {
            icon: "receipt_long"
            type: IconButton.Tonal
            onClicked: AndroLaunch.openLogcat()
        }

        IconButton {
            visible: root.dev?.isWireless ?? false
            icon: "link_off"
            type: IconButton.Tonal
            onClicked: AndroLaunch.disconnect(root.dev?.id ?? "")
        }
    }

    // Navigation Tabs (Controls, Apps, Config, Pair, Shell, AVDs)
    RowLayout {
        Layout.fillWidth: true
        visible: root.available
        spacing: Tokens.spacing.extraSmall
        TabButton {
            tabId: "main"
            iconName: "tune"
            label: qsTr("Quick")
        }
        TabButton {
            tabId: "apps"
            iconName: "apps"
            label: qsTr("Apps")
            onClicked: {
                root.currentTab = "apps";
                if (AndroLaunch.apps.length === 0)
                    AndroLaunch.fetchApps();
            }
        }
        TabButton {
            tabId: "config"
            iconName: "settings"
            label: qsTr("Config")
        }
        TabButton {
            tabId: "wireless"
            iconName: "wifi"
            label: qsTr("Pair")
            onClicked: {
                root.currentTab = "wireless";
                AndroLaunch.startQRPairing();
            }
        }
        TabButton {
            tabId: "commands"
            iconName: "terminal"
            label: qsTr("Shell")
        }
        TabButton {
            tabId: "avds"
            iconName: "phone_android"
            label: qsTr("AVD")
            onClicked: {
                root.currentTab = "avds";
                if (AndroLaunch.avds.length === 0)
                    AndroLaunch.fetchAvds();
            }
        }
    }

    // TAB 1: QUICK ACTIONS & CONTROLS
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.available && root.currentTab === "main"
        spacing: Tokens.spacing.small

        // Quick Toggles Grid (4x2)
        GridLayout {
            Layout.fillWidth: true
            columns: 4
            rowSpacing: Tokens.spacing.extraSmall
            columnSpacing: Tokens.spacing.extraSmall

            QuickToggleBtn {
                icon: "wifi"
                label: qsTr("Wi-Fi")
                active: root.qa?.wifi ?? false
                onClicked: AndroLaunch.toggleWifi(!active)
            }
            QuickToggleBtn {
                icon: "bluetooth"
                label: qsTr("Bluetooth")
                active: root.qa?.bluetooth ?? false
                onClicked: AndroLaunch.toggleBluetooth(!active)
            }
            QuickToggleBtn {
                icon: "signal_cellular_alt"
                label: qsTr("Data")
                active: root.qa?.mobileData ?? false
                onClicked: AndroLaunch.toggleMobileData(!active)
            }
            QuickToggleBtn {
                icon: "dark_mode"
                label: qsTr("Dark")
                active: root.qa?.darkMode ?? false
                onClicked: AndroLaunch.toggleDarkMode(!active)
            }
            QuickToggleBtn {
                icon: "airplanemode_active"
                label: qsTr("Airplane")
                active: root.qa?.airplaneMode ?? false
                onClicked: AndroLaunch.toggleAirplaneMode(!active)
            }
            QuickToggleBtn {
                icon: "location_on"
                label: qsTr("Location")
                active: root.qa?.location ?? false
                onClicked: AndroLaunch.toggleLocation(!active)
            }
            QuickToggleBtn {
                icon: "do_not_disturb_on"
                label: qsTr("DND")
                active: root.qa?.dnd ?? false
                onClicked: AndroLaunch.toggleDnd(!active)
            }
            QuickToggleBtn {
                icon: "screen_rotation"
                label: qsTr("Rotate")
                active: root.qa?.autoRotate ?? false
                onClicked: AndroLaunch.toggleAutoRotate(!active)
            }
        }

        // Sliders: Brightness & Volume
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.hasDev
            spacing: Tokens.spacing.extraSmall

            // Brightness Slider
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "brightness_medium"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledSlider {
                    Layout.fillWidth: true
                    value: (root.qa?.brightness ?? 128) / 255
                    onInteraction: val => AndroLaunch.setBrightness(Math.round(val * 255))
                }
            }

            // Volume Slider
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "volume_up"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledSlider {
                    Layout.fillWidth: true
                    value: (root.qa?.volume ?? 50) / 100
                    onInteraction: val => AndroLaunch.setVolume(Math.round(val * 100))
                }
        }

        // Power & Reboot Row
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasDev
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Reboot:")
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            IconTextButton {
                text: qsTr("System")
                icon: "restart_alt"
                padding: Tokens.padding.extraSmall
                onClicked: AndroLaunch.reboot("normal")
            }
            IconTextButton {
                text: qsTr("Bootloader")
                icon: "memory"
                padding: Tokens.padding.extraSmall
                onClicked: AndroLaunch.reboot("bootloader")
            }
            IconTextButton {
                text: qsTr("Recovery")
                icon: "build"
                padding: Tokens.padding.extraSmall
                onClicked: AndroLaunch.reboot("recovery")
            }
        }

        // Previous Devices Reconnect List (if any)
        ColumnLayout {
            Layout.fillWidth: true
            visible: AndroLaunch.previousDevices.length > 0
            spacing: 2

            StyledText {
                text: qsTr("Previous Devices")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }

            Repeater {
                model: AndroLaunch.previousDevices

                RowLayout {
                    id: prevDevRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "history"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: prevDevRow.modelData.name || prevDevRow.modelData.serialNumber
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    IconTextButton {
                        text: AndroLaunch.connectingDeviceId === prevDevRow.modelData.serialNumber ? qsTr("Connecting...") : qsTr("Connect")
                        icon: "wifi"
                        padding: Tokens.padding.extraSmall
                        disabled: AndroLaunch.connectingDeviceId.length > 0
                        onClicked: AndroLaunch.connectPrevious(prevDevRow.modelData.serialNumber)
                    }
                }
            }
        }
    }

    // TAB 2: APPS MANAGER
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.available && root.currentTab === "apps"
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            StyledTextField {
                id: appSearch
                Layout.fillWidth: true
                placeholderText: qsTr("Search apps...")
                onTextChanged: root.appFilter = text.toLowerCase()
            }

            IconButton {
                icon: "refresh"
                type: IconButton.Tonal
                padding: Tokens.padding.extraSmall
                onClicked: AndroLaunch.fetchApps("", true)
            }
        }

        // App List
        StyledListView {
            Layout.fillWidth: true
            implicitHeight: Math.min(220, count * 40)
            clip: true
            spacing: 2

            model: ScriptModel {
                values: AndroLaunch.apps.filter(a => root.appFilter.length === 0 || a.name.toLowerCase().includes(root.appFilter) || a.packageName.toLowerCase().includes(root.appFilter)).slice(0, 15)
            }

            delegate: StyledRect {
                id: appItem
                required property var modelData
                width: ListView.view.width
                implicitHeight: 36
                radius: Tokens.rounding.extraSmall
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "android"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: appItem.modelData.name
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    IconButton {
                        icon: "play_arrow"
                        type: IconButton.Text
                        padding: 2
                        onClicked: AndroLaunch.launchApp(appItem.modelData.packageName)
                    }

                    IconButton {
                        icon: "screen_share"
                        type: IconButton.Text
                        padding: 2
                        onClicked: AndroLaunch.startAppMirroring(appItem.modelData.packageName)
                    }

                    IconButton {
                        icon: "cleaning_services"
                        type: IconButton.Text
                        padding: 2
                        onClicked: AndroLaunch.clearAppData(appItem.modelData.packageName)
                    }

                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        padding: 2
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: AndroLaunch.uninstallApp(appItem.modelData.packageName)
                    }
                }
            }
        }
    }

    // TAB 3: CONFIGURATION (macOS Config Submenu Match)
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.available && root.currentTab === "config"
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: qsTr("App Resolution & Display")
            font: Tokens.font.label.small
            color: Colours.palette.m3primary
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            ConfigPill {
                text: "Flex"
                selected: AndroLaunch.scrcpyConfig.flexDisplay
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { flexDisplay: true, maxSize: 0 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "1080p"
                selected: !AndroLaunch.scrcpyConfig.flexDisplay && AndroLaunch.scrcpyConfig.maxSize === 1080
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { flexDisplay: false, maxSize: 1080 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "720p"
                selected: !AndroLaunch.scrcpyConfig.flexDisplay && AndroLaunch.scrcpyConfig.maxSize === 720
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { flexDisplay: false, maxSize: 720 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "4K"
                selected: !AndroLaunch.scrcpyConfig.flexDisplay && AndroLaunch.scrcpyConfig.maxSize === 3840
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { flexDisplay: false, maxSize: 3840 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.extraSmall
            text: qsTr("Frame Rate Limit")
            font: Tokens.font.label.small
            color: Colours.palette.m3primary
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            ConfigPill {
                text: "30 fps"
                selected: AndroLaunch.scrcpyConfig.maxFps === 30
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { maxFps: 30 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "60 fps"
                selected: AndroLaunch.scrcpyConfig.maxFps === 60
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { maxFps: 60 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "90 fps"
                selected: AndroLaunch.scrcpyConfig.maxFps === 90
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { maxFps: 90 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "120 fps"
                selected: AndroLaunch.scrcpyConfig.maxFps === 120
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { maxFps: 120 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.extraSmall
            text: qsTr("Bitrate")
            font: Tokens.font.label.small
            color: Colours.palette.m3primary
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            ConfigPill {
                text: "4 Mbps"
                selected: AndroLaunch.scrcpyConfig.bitRate === 4
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { bitRate: 4 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "8 Mbps"
                selected: AndroLaunch.scrcpyConfig.bitRate === 8
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { bitRate: 8 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "16 Mbps"
                selected: AndroLaunch.scrcpyConfig.bitRate === 16
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { bitRate: 16 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            ConfigPill {
                text: "24 Mbps"
                selected: AndroLaunch.scrcpyConfig.bitRate === 24
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { bitRate: 24 });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
        }

        // Toggles Row: Audio, Aspect Ratio, Stay Awake, Borderless
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            spacing: Tokens.spacing.extraSmall

            IconButton {
                Layout.fillWidth: true
                icon: AndroLaunch.scrcpyConfig.audioEnabled ? "volume_up" : "volume_off"
                isToggle: true
                checked: AndroLaunch.scrcpyConfig.audioEnabled
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { audioEnabled: !checked });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            IconButton {
                Layout.fillWidth: true
                icon: "aspect_ratio"
                isToggle: true
                checked: AndroLaunch.scrcpyConfig.lockAspectRatio
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { lockAspectRatio: !checked });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            IconButton {
                Layout.fillWidth: true
                icon: "visibility"
                isToggle: true
                checked: AndroLaunch.scrcpyConfig.keepActive
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { keepActive: !checked });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
            IconButton {
                Layout.fillWidth: true
                icon: "border_clear"
                isToggle: true
                checked: AndroLaunch.scrcpyConfig.borderless
                onClicked: {
                    const conf = Object.assign({}, AndroLaunch.scrcpyConfig, { borderless: !checked });
                    AndroLaunch.scrcpyConfig = conf;
                }
            }
        }
    }

    // TAB 4: WIRELESS PAIRING
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.available && root.currentTab === "wireless"
        spacing: Tokens.spacing.small
        // QR Code Section
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: qrPopoutLayout.implicitHeight + Tokens.padding.medium * 2
            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.medium

            ColumnLayout {
                id: qrPopoutLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Pair with QR Code")
                    font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Wireless Debugging → Pair device with QR code")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                }

                // QR Frame
                StyledRect {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 180
                    implicitHeight: 180
                    radius: Tokens.rounding.small
                    color: "#ffffff"

                    QRCodeView {
                        anchors.centerIn: parent
                        width: 160
                        height: 160
                        text: AndroLaunch.qrString
                        darkColor: "#000000"
                        lightColor: "#ffffff"
                        quietZone: 4
                    }
                }
                // Code & Regenerate
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: `Code: ${AndroLaunch.pairingPassword}`
                        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                        color: Colours.palette.m3primary
                    }

                    IconButton {
                        icon: "refresh"
                        type: IconButton.Tonal
                        padding: 2
                        onClicked: AndroLaunch.startQRPairing()
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: AndroLaunch.qrPairingStatus || qsTr("Waiting for device scan...")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3secondary
                }
            }
        }

        StyledText {
            text: qsTr("Direct Connect (IP:Port)")
            font: Tokens.font.label.small
            color: Colours.palette.m3primary
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            StyledTextField {
                id: connectIp
                Layout.fillWidth: true
                placeholderText: "192.168.1.xxx:5555"
            }

            IconTextButton {
                text: qsTr("Connect")
                icon: "wifi"
                onClicked: {
                    const parts = connectIp.text.trim().split(":");
                    AndroLaunch.connectWireless(parts[0], parts[1] || "5555");
                }
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.extraSmall
            text: qsTr("Manual 6-digit Code Pairing")
            font: Tokens.font.label.small
            color: Colours.palette.m3primary
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            StyledTextField {
                id: pairTarget
                Layout.fillWidth: true
                placeholderText: "IP:Port (e.g. 192.168.1.50:37123)"
            }

            StyledTextField {
                id: pairCode
                implicitWidth: 80
                placeholderText: "Code"
            }

            IconButton {
                icon: "sync"
                type: IconButton.Filled
                onClicked: {
                    const parts = pairTarget.text.trim().split(":");
                    if (parts.length >= 2)
                        AndroLaunch.pairWireless(parts[0], parts[1], pairCode.text.trim());
                }
            }
        }

        IconTextButton {
            Layout.fillWidth: true
            text: qsTr("Switch USB Device to TCP/IP")
            icon: "cable"
            disabled: !root.hasDev || root.dev.isWireless
            onClicked: AndroLaunch.enableTcpip("5555")
        }
    }
    // TAB 5: SHELL COMMANDS
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.available && root.currentTab === "commands"
        spacing: Tokens.spacing.small

        StyledListView {
            Layout.fillWidth: true
            implicitHeight: Math.min(200, count * 38)
            clip: true
            spacing: 2

            model: AndroLaunch.customCommands

            delegate: StyledRect {
                id: cmdItem
                required property var modelData
                width: ListView.view.width
                implicitHeight: 34
                radius: Tokens.rounding.extraSmall
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "terminal"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3secondary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: cmdItem.modelData.name
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }

                    IconButton {
                        icon: "play_arrow"
                        type: IconButton.Filled
                        padding: 2
                        onClicked: {
                            AndroLaunch.executeShell(cmdItem.modelData.command, (success, out) => {
                                Toaster.toast(cmdItem.modelData.name, out || qsTr("Command finished"), "terminal");
                            });
                        }
                    }
                }
            }
        }

        IconTextButton {
            Layout.fillWidth: true
            text: qsTr("Open Interactive Terminal")
            icon: "terminal"
            disabled: !root.hasDev
            onClicked: AndroLaunch.openTerminal()
        }
    }

    // TAB 6: AVD EMULATORS
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.available && root.currentTab === "avds"
        spacing: Tokens.spacing.small

        StyledListView {
            Layout.fillWidth: true
            implicitHeight: Math.min(200, count * 38)
            clip: true
            spacing: 2

            model: AndroLaunch.avds

            delegate: StyledRect {
                id: avdItem
                required property var modelData
                width: ListView.view.width
                implicitHeight: 34
                radius: Tokens.rounding.extraSmall
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "phone_android"
                        fontStyle: Tokens.font.icon.small
                        color: avdItem.modelData.isRunning ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: avdItem.modelData.name
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }

                    IconTextButton {
                        text: avdItem.modelData.isRunning ? qsTr("Running") : qsTr("Launch")
                        icon: avdItem.modelData.isRunning ? "check" : "play_arrow"
                        disabled: avdItem.modelData.isRunning
                        padding: Tokens.padding.extraSmall
                        onClicked: AndroLaunch.startAvd(avdItem.modelData.name)
                    }
                }
            }
        }

        IconTextButton {
            Layout.fillWidth: true
            text: qsTr("Refresh Emulators")
            icon: "refresh"
            onClicked: AndroLaunch.fetchAvds()
        }
    }

    // Footer: Open Full Nexus Page
    IconTextButton {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        inactiveColour: Colours.palette.m3primaryContainer
        inactiveOnColour: Colours.palette.m3onPrimaryContainer
        verticalPadding: Tokens.padding.extraSmall
        text: qsTr("Open Full Device Manager")
        icon: "settings"

        onClicked: {
            root.popouts.detachRequested("androlaunch");
            Quickshell.execDetached(["caelestia", "shell", "nexus", "open"]);
        }
    }
}
