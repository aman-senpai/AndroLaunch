/*
 * Guards the device labels in the popup:
 *   - the header is a single identity line (the transport, battery and Android
 *     version belong to the device card below it),
 *   - a device that reports neither name nor model still gets an identity instead
 *     of an empty bold line.
 *
 *   QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_device_labels.qml
 */
import QtQuick
import QtQuick.Window
import QtTest
import org.kde.kirigami as Kirigami

TestCase {
    id: testCase

    name: "AndroLaunchDeviceLabels"
    when: true

    Window {
        id: win
        visible: true
        width: Kirigami.Units.gridUnit * 30 + 40
        height: 700
        color: Kirigami.Theme.backgroundColor
    }

    property var popup: null
    property var backend: null

    readonly property var recorder: QtObject {
        property var calls: []
    }

    function createBackend(device) {
        return Qt.createQmlObject('
            import QtQuick;
            QtObject {
                property bool hasDevice: true
                property string activeId: "dev"
                property var uiDevices: []
                property var activeDevice: null
                property var quick: ({})
                property var effectiveQuick: ({})
                property var mirrors: []
                property int activeBattery: 20
                property bool activeCharging: false
                property int connectedCount: 1
                property bool busy: false
                property bool adbMissing: false
                property bool helperReady: true
                property string helperError: ""
                property var previous: []
                property string lastMessage: ""
                property bool lastMessageError: false
                signal toast(string text, bool error)
                signal response(string action, var data)
                function refresh() {}
                function selectDevice() {}
                function toggle() {}
                function setBrightness() {}
                function setVolume() {}
                function reboot() {}
                function mirror() {}
                function camera() {}
                function stopMirrors() {}
                function stopMirror() {}
                function openTerminal() {}
                function openLogcat() {}
                function disconnectDevice() {}
                function connectPrevious() {}
                function dismissMessage() {}
                function bootstrap() {}
            }', testCase, "stubBackend");
    }

    function findByName(item, name) {
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; ++i) {
            const nested = findByName(item.children[i], name);
            if (nested)
                return nested;
        }
        return null;
    }

    function label(name) {
        const item = findByName(popup, name);
        verify(item !== null, "found label: " + name);
        return item.text;
    }

    function hasLabel(name) {
        return findByName(popup, name) !== null;
    }

    function start(device) {
        backend = createBackend(device);
        backend.uiDevices = device ? [device] : [];
        backend.activeDevice = device;
        backend.activeId = device ? device.id : "";

        const component = Qt.createComponent(Qt.resolvedUrl("../plasma/contents/ui/FullRepresentation.qml"));
        verify(component.status === Component.Ready, "popup loads: " + component.errorString());
        popup = component.createObject(win.contentItem, {
            "x": 0,
            "y": 0,
            "width": Kirigami.Units.gridUnit * 30,
            "height": 620,
            "backend": backend
        });
        verify(popup !== null, "popup created");
        wait(400);
    }

    function cleanup() {
        if (popup) {
            popup.destroy();
            popup = null;
        }
        backend = null;
    }

    function test_header_is_the_identity_line_only() {
        start({ "id": "adb-1", "name": "M2007J17I", "model": "M2007J17I", "address": "192.168.1.37:41105", "android": "12", "api": 31, "connected": true, "wireless": true });

        compare(label("deviceTitle"), "M2007J17I", "header names the device");
        verify(!hasLabel("deviceSubtitle"), "header has no second line");

        compare(label("cardTitle"), "M2007J17I", "card uses the same identity");
        verify(label("cardSubtitle").indexOf("Wi-Fi") === 0, "card carries the transport");
        verify(label("cardSubtitle").indexOf("Android 12 (API 31)") !== -1, "card carries the Android version");
    }

    function test_nameless_device_still_gets_an_identity() {
        start({ "id": "192.168.1.37:41105", "name": "", "model": "", "address": "192.168.1.37:41105", "android": "12", "api": 31, "connected": true, "wireless": true });

        compare(label("deviceTitle"), "192.168.1.37:41105", "falls back to the address");
        compare(label("cardTitle"), "192.168.1.37:41105", "card matches the header");
    }

    function test_whitespace_name_does_not_blank_the_title() {
        start({ "id": "adb-1", "name": "   ", "model": "", "address": "192.168.1.37:41105", "connected": true, "wireless": true });

        verify(label("deviceTitle").trim().length > 0, "title is never blank: " + JSON.stringify(label("deviceTitle")));
    }

    function test_app_name_is_the_fallback_without_a_device() {
        start(null);

        compare(label("deviceTitle"), "AndroLaunch", "header falls back to the app name");
        verify(!hasLabel("deviceSubtitle"), "no device status line");
    }
}
