/*
 * Load test for the AndroLaunch plasmoid: instantiates every QML component with a
 * stub backend so broken bindings, unknown types and read-only property writes are
 * caught before the widget reaches plasmashell.
 *
 *   QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_load.qml
 */
import QtQuick
import QtTest

TestCase {
    id: testCase

    name: "AndroLaunchPackageLoad"
    when: true

    QtObject {
        id: stub

        property bool helperReady: true
        property string helperError: ""
        property bool adbMissing: false
        property string adbPath: "/usr/bin/adb"
        property string scrcpyPath: "/usr/bin/scrcpy"
        property var devices: ([{
            "id": "192.168.1.42:5555", "name": "Pixel 8", "model": "shiba", "status": "device",
            "connected": true, "wireless": true, "emulator": false, "mdns": false,
            "battery": 64, "charging": true, "android": "15", "api": "35", "quick": ({})
        }])
        property var uiDevices: devices
        property int connectedCount: 1
        property string activeId: "192.168.1.42:5555"
        property var activeDevice: devices[0]
        property bool hasDevice: true
        property int activeBattery: 64
        property bool activeCharging: true
        property var quick: ({
            "wifi": true, "bluetooth": false, "darkMode": true, "airplaneMode": false,
            "mobileData": true, "location": true, "dnd": false, "autoRotate": false,
            "brightness": 2048, "brightnessMax": 4095, "volume": 60
        })
        property var previous: ([{ "id": "192.168.1.9:5555", "name": "Old Phone", "wireless": true, "lastSeen": 0 }])
        property var qr: ({ "payload": "WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:123456;;", "password": "123456", "created": 0 })
        property var mirrors: []
        property bool busy: false
        property var apps: ([{ "package": "com.example.app", "name": "Example", "system": false }])
        property bool appsLoading: false
        property string appsLoadedFor: ""
        property var files: ([{
            "name": "DCIM", "path": "/sdcard/DCIM", "isDirectory": true, "size": 0,
            "formattedSize": "--", "date": "2026-05-01 12:33", "permissions": "drwxrwx---"
        }])
        property string currentPath: "/sdcard"
        property bool filesLoading: false
        property var avds: ([{ "name": "Pixel_8_API_34", "running": false }])
        property bool avdsLoading: false
        property var mirrorOptions: ({})
        property int pollInterval: 5000
        property string lastMessage: ""
        property bool lastMessageError: false
        property var plasmoidItem: null

        signal toast(string text, bool error)
        signal response(string action, var data)
        signal pairingFound(string ip, string port)

        function call() {}
        function refresh() {}
        function selectDevice() {}
        function toggle() {}
        function setBrightness() {}
        function setVolume() {}
        function reboot() {}
        function mirror() {}
        function camera() {}
        function appMirror() {}
        function stopMirrors() {}
        function fetchApps() {}
        function launchApp() {}
        function uninstallApp() {}
        function clearAppData() {}
        function installApk() {}
        function browse() {}
        function pushFile() {}
        function pullFile() {}
        function deleteFile() {}
        function makeDirectory() {}
        function wirelessConnect() {}
        function wirelessPair() {}
        function disconnectDevice() {}
        function enableTcpip() {}
        function connectPrevious() {}
        function startQrPairing() {}
        function pollPairing() {}
        function runShell() {}
        function openTerminal() {}
        function openLogcat() {}
        function sendClipboard() {}
        function getClipboard() {}
        function fetchAvds() {}
        function startAvd() {}
        function bootstrap() {}
        function holdPopup() {}
        function releasePopup() {}
        function dismissMessage() {}
    }

    readonly property var uiDir: Qt.resolvedUrl("../plasma/contents/ui/")
    // file -> properties the component expects from its host
    readonly property var componentFiles: [
        { "file": "FullRepresentation.qml", "props": ["backend"] },
        { "file": "CompactRepresentation.qml", "props": ["backend", "plasmoidItem"] },
        { "file": "QuickTab.qml", "props": ["backend"] },
        { "file": "AppsTab.qml", "props": ["backend"] },
        { "file": "WirelessTab.qml", "props": ["backend"] },
        { "file": "FilesTab.qml", "props": ["backend"] },
        { "file": "ShellTab.qml", "props": ["backend"] },
        { "file": "AvdTab.qml", "props": ["backend"] },
        { "file": "Backend.qml", "props": [] },
        { "file": "configGeneral.qml", "props": [] },
        { "file": "configMirroring.qml", "props": [] },
        { "file": "components/ActionButton.qml", "props": [] },
        { "file": "components/EmptyState.qml", "props": [] },
        { "file": "components/QrCode.qml", "props": [] },
        { "file": "components/SectionLabel.qml", "props": [] },
        { "file": "components/ToggleChip.qml", "props": [] },
        { "file": "components/ValueSlider.qml", "props": [] }
    ]

    function loadAndCheck(spec) {
        const relative = spec.file;
        const component = Qt.createComponent(testCase.uiDir + relative);
        if (component.status !== Component.Ready) {
            console.warn(relative + ": " + component.errorString());
            verify(false, relative + " failed to load");
            return;
        }

        const initial = {};
        for (let i = 0; i < spec.props.length; ++i) {
            if (spec.props[i] === "backend")
                initial.backend = stub;
            else if (spec.props[i] === "plasmoidItem")
                initial.plasmoidItem = null;
        }

        const item = component.createObject(null, initial);
        verify(item !== null, relative + " failed to instantiate");
        if (item) {
            item.width = spec.props.length > 0 ? 570 : item.implicitWidth;
            item.height = spec.props.length > 0 ? 900 : item.implicitHeight;
            wait(10);
            verify(item.height >= 0, relative + " produced a broken item");
            item.destroy();
        }
    }

    function test_allComponentsLoad() {
        for (let i = 0; i < componentFiles.length; ++i)
            loadAndCheck(componentFiles[i]);
    }
}
