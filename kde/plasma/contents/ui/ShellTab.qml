pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "components"

ColumnLayout {
    id: root

    required property var backend

    // ---- local state -------------------------------------------------------
    property bool running: false
    property string output: ""
    property bool ranOk: true
    property string clipText: ""

    readonly property var presets: [
        {
            label: "Screenshot",
            icon: "camera-photo",
            command: "screencap -p /sdcard/screenshot.png && echo \"Saved to /sdcard/screenshot.png\""
        },
        {
            label: "IP address",
            icon: "network-wireless",
            command: "ip addr show wlan0 | grep 'inet '"
        },
        {
            label: "Battery info",
            icon: "battery-080",
            command: "dumpsys battery"
        },
        {
            label: "Memory info",
            icon: "applications-system",
            command: "dumpsys meminfo"
        },
        {
            label: "Top processes",
            icon: "view-list-details",
            command: "top -n 1 -b -m 10"
        },
        {
            label: "Storage",
            icon: "drive-removable-media-usb",
            command: "df -h /data /sdcard"
        }
    ]

    spacing: Kirigami.Units.smallSpacing

    // ---- helpers -----------------------------------------------------------
    function formatOutput(envelope) {
        if (!envelope)
            return "Error: No response from the androlaunch helper";
        const data = envelope.data || ({});
        const stdout = (data.stdout || "").trim();
        const stderr = (data.stderr || "").trim();
        const message = (envelope.message || envelope.error || "").trim();
        if (envelope.ok === false)
            return "Error: " + (stderr || stdout || message || "Command failed");
        if (stdout.length > 0)
            return stdout;
        if (stderr.length > 0)
            return stderr;
        return message;
    }

    function runCmd(command) {
        if (running || !root.backend.hasDevice)
            return;
        if (!command || command.trim().length === 0)
            return;
        running = true;
        root.backend.runShell(command, envelope => {
            root.ranOk = !!(envelope && envelope.ok !== false);
            root.output = root.formatOutput(envelope);
            root.running = false;
        });
    }

    // ---- no device ---------------------------------------------------------
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? Kirigami.Units.gridUnit * 7 : 0
        visible: !root.backend.hasDevice

        EmptyState {
            anchors.fill: parent
            iconName: "smartphone"
            message: "Connect a device to run commands"
            hint: "ADB shell commands, presets, terminals and clipboard tools need an active device."
        }
    }

    // ---- content -----------------------------------------------------------
    PlasmaComponents3.ScrollView {
        id: scroller

        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
            width: scroller.availableWidth
            spacing: Kirigami.Units.smallSpacing

            SectionLabel {
                text: "Run a command"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextField {
                    id: cmdField

                    Layout.fillWidth: true
                    placeholderText: "e.g. getprop ro.product.model"
                    enabled: root.backend.hasDevice && !root.running
                    onAccepted: root.runCmd(text)
                }

                PlasmaComponents3.BusyIndicator {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    running: root.running
                    visible: root.running
                }

                ActionButton {
                    Layout.fillWidth: false
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                    iconName: "system-run"
                    text: "Run"
                    enabled: root.backend.hasDevice && !root.running && cmdField.text.trim().length > 0
                    onClicked: root.runCmd(cmdField.text)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                SectionLabel {
                    text: "Output"
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "edit-copy"
                    enabled: root.output.length > 0
                    onClicked: root.backend.sendClipboard(root.output)
                    PlasmaComponents3.ToolTip.text: "Copy output to clipboard"
                }
            }

            PlasmaComponents3.TextArea {
                id: outputArea

                Layout.fillWidth: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 6
                readOnly: true
                wrapMode: TextEdit.NoWrap
                selectByMouse: true
                font.family: "monospace"
                color: root.ranOk ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                text: root.output

                PlasmaComponents3.Label {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: Kirigami.Units.smallSpacing
                    text: "Output appears here"
                    visible: root.output.length === 0
                    opacity: 0.45
                }
            }

            SectionLabel {
                text: "Preset commands"
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.presets

                    ActionButton {
                        required property var modelData

                        iconName: modelData.icon
                        text: modelData.label
                        enabled: root.backend.hasDevice && !root.running
                        onClicked: root.runCmd(modelData.command)
                    }
                }
            }

            SectionLabel {
                text: "Terminals"
            }

            ActionButton {
                iconName: "utilities-terminal"
                text: "Open interactive ADB shell"
                enabled: root.backend.hasDevice
                onClicked: root.backend.openTerminal()
            }

            ActionButton {
                iconName: "view-list-details"
                text: "Open logcat in terminal"
                enabled: root.backend.hasDevice
                onClicked: root.backend.openLogcat()
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Interactive sessions open in Konsole; this panel shows one-shot command output."
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.55
            }

            SectionLabel {
                text: "Clipboard"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextField {
                    Layout.fillWidth: true
                    placeholderText: "Text to copy to the device"
                    text: root.clipText
                    enabled: root.backend.hasDevice
                    onTextEdited: root.clipText = text
                }

                ActionButton {
                    Layout.fillWidth: false
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                    iconName: "edit-copy"
                    text: "Send to device"
                    enabled: root.backend.hasDevice && root.clipText.length > 0
                    onClicked: root.backend.sendClipboard(root.clipText)
                }
            }

            ActionButton {
                iconName: "edit-download"
                text: "Get from device"
                enabled: root.backend.hasDevice
                onClicked: root.backend.getClipboard(text => {
                    root.clipText = text;
                })
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Reading the device clipboard requires the ADBClipboard companion app installed on Android."
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.55
            }
        }
    }
}
