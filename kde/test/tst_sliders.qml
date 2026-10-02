/*
 * Guards the widget -> helper call path for the sliders:
 *   - arguments survive encoding (an empty payload silently turns every action into its
 *     default value, which once made the brightness and volume sliders misbehave),
 *   - dragging is coalesced instead of issuing one adb command per pixel,
 *   - the value the user released on is the one that lands.
 *
 *   QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_sliders.qml
 */
import QtQuick
import QtTest

TestCase {
    id: testCase

    name: "AndroLaunchSliders"
    when: true

    property var backend: null
    property string report: ""

    // collects what the sliders ask the backend for
    readonly property var recorder: QtObject {
        property var brightness: []
        property var volume: []
    }

    function initTestCase() {
        const component = Qt.createComponent(Qt.resolvedUrl("../plasma/contents/ui/Backend.qml"));
        verify(component.status === Component.Ready, "Backend.qml loads");
        backend = component.createObject(null, {
            "helperPath": "python3 " + Qt.resolvedUrl("fake_helper.py").toString().replace("file://", ""),
            "pollInterval": 600000
        });
        verify(backend !== null, "backend created");
        tryVerify(function () { return backend.helperReady; }, 5000, "helper ready");
        backend.runShell("reset", function () {});   // truncate the recorded call log
        wait(300);
    }

    function requestReport() {
        report = "";
        backend.runShell("report", function (envelope) {
            report = envelope && envelope.message ? envelope.message : "";
        });
    }

    function value(pattern) {
        const match = pattern.exec(report);
        return match ? Number(match[1]) : NaN;
    }

    function test_drag_is_coalesced() {
        // 20 drag events in one burst, exactly as a slider emits them while moving
        for (let i = 1; i <= 20; ++i)
            backend.setBrightness(i * 5);

        wait(2500);   // let the coalesced writes settle before asking the helper
        requestReport();
        tryVerify(function () { return report.length > 0; }, 8000, "report received");
        verify(/lastBrightness=100/.test(report), "last dragged value reached the helper: " + report);

        const calls = value(/brightness=(\d+)/);
        console.warn("SLIDER REPORT: " + report);
        verify(calls >= 1, "at least one write");
        verify(calls <= 3, "20 rapid updates must not flood the device, got " + calls + " calls");
    }

    function test_volume_uses_same_path() {
        for (let i = 1; i <= 12; ++i)
            backend.setVolume(i * 8);

        wait(1500);
        requestReport();
        tryVerify(function () { return report.length > 0; }, 8000, "report received");
        verify(/lastVolume=96/.test(report), "last volume value reached the helper: " + report);

        const calls = value(/volume=(\d+)/);
        console.warn("VOLUME REPORT: " + report);
        verify(calls <= 2, "12 rapid volume updates must not flood the device, got " + calls + " calls");
    }

    // The Quick tab's sliders must reach the backend with the value under the finger.
    function test_slider_wiring() {
        const calls = [];
        const stub = Qt.createQmlObject('import QtQuick 2.0; QtObject {' +
            'property bool helperReady: true; property string helperError: ""; property bool adbMissing: false;' +
            'property string adbPath: "/usr/bin/adb"; property string scrcpyPath: "/usr/bin/scrcpy";' +
            'property var devices: [{id: "d", name: "Phone", connected: true, wireless: false, emulator: false, battery: 50, charging: false, android: "12", api: "31", address: "", quick: {}}];' +
            'property var uiDevices: devices; property int connectedCount: 1; property string activeId: "d";' +
            'property var activeDevice: devices[0]; property bool hasDevice: true; property int activeBattery: 50;' +
            'property bool activeCharging: false;' +
            'property var quick: ({wifi: true, bluetooth: false, darkMode: false, airplaneMode: false, mobileData: false, location: false, dnd: false, autoRotate: false, brightness: 2048, brightnessMax: 4095, volume: 50});' +
            'property var effectiveQuick: quick; property var previous: []; property var qr: ({}); property var mirrors: [];' +
            'property bool busy: false; property var apps: []; property bool appsLoading: false; property string appsLoadedFor: "";' +
            'property var files: []; property string currentPath: "/sdcard"; property bool filesLoading: false;' +
            'property var avds: []; property bool avdsLoading: false; property var mirrorOptions: ({}); property int pollInterval: 5000;' +
            'property string lastMessage: ""; property bool lastMessageError: false; property var plasmoidItem: null;' +
            'signal toast(string t, bool e); signal response(string a, var d); signal pairingFound(string i, string p);' +
            'function setBrightness(p) { recorder.brightness.push(p); }' +
            'function setVolume(v) { recorder.volume.push(v); }' +
            'function refresh() {} function selectDevice() {} function toggle() {} function reboot() {} function mirror() {}' +
            'function camera() {} function appMirror() {} function appScreen() {} function stopMirror() {} function stopMirrors() {}' +
            'function fetchApps() {} function launchApp() {} function uninstallApp() {} function clearAppData() {} function installApk() {}' +
            'function browse() {} function pushFile() {} function pullFile() {} function deleteFile() {} function makeDirectory() {}' +
            'function wirelessConnect() {} function wirelessPair() {} function disconnectDevice() {} function enableTcpip() {}' +
            'function connectPrevious() {} function startQrPairing() {} function pollPairing() {} function runShell() {}' +
            'function openTerminal() {} function openLogcat() {} function sendClipboard() {} function getClipboard() {}' +
            'function fetchAvds() {} function startAvd() {} function bootstrap() {} function holdPopup() {} function releasePopup() {}' +
            'function dismissMessage() {} function call() {}' +
            '}', testCase);

        const tabComponent = Qt.createComponent(Qt.resolvedUrl("../plasma/contents/ui/QuickTab.qml"));
        verify(tabComponent.status === Component.Ready, "QuickTab loads");
        const tab = tabComponent.createObject(null, { "backend": stub, "width": 570, "height": 1200 });
        verify(tab !== null, "QuickTab created");
        wait(120);

        const sliders = [];
        (function collect(node) {
            if (!node)
                return;
            if (node.toString().indexOf("ValueSlider") !== -1)
                sliders.push(node);
            const kids = node.children;
            for (let i = 0; i < kids.length; ++i)
                collect(kids[i]);
        })(tab);

        verify(sliders.length >= 2, "both sliders exist, found " + sliders.length);
        sliders[0].moved(0.42);   // brightness
        sliders[1].moved(0.66);   // volume
        wait(50);

        console.warn("SLIDER WIRING brightness=" + JSON.stringify(recorder.brightness) + " volume=" + JSON.stringify(recorder.volume));
        verify(recorder.brightness.length > 0, "brightness slider calls the backend");
        verify(recorder.brightness[0] === 42, "42% sent for the brightness slider, got " + recorder.brightness[0]);
        verify(recorder.volume.length > 0, "volume slider calls the backend");
        verify(recorder.volume[0] === 66, "66% sent for the volume slider, got " + recorder.volume[0]);
        tab.destroy();
    }

    function test_payload_is_encoded() {
        const command = "settings put system screen_brightness 12 && echo \"ünïcode ✓\"";
        backend.runShell(command, function () {});

        wait(1500);
        requestReport();
        tryVerify(function () { return report.length > 0; }, 8000, "report received");

        console.warn("PAYLOAD REPORT: " + report);
        verify(report.indexOf("MATCH") !== -1, "payload encoded verbatim: " + report);
    }
}
