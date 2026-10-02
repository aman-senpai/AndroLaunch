/*
 * AndroLaunch — backend bridge between the plasmoid and the `androlaunch` CLI.
 *
 * Every request is a single `androlaunch call <action> <base64-json> --token <n>`
 * invocation. Arguments travel as base64 so no quoting/shell rules apply to
 * paths, package names or user commands.
 */

import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: backend

    // ---- configuration -----------------------------------------------------
    property string helperPath: "androlaunch"
    property int pollInterval: 5000
    property var mirrorOptions: ({
        newDisplay: false,
        flexDisplay: false,
        audio: false,
        stayAwake: true,
        aspectRatioLock: true,
        borderless: false,
        maxFps: 60,
        bitRate: 8,
        maxSize: 0,
        cameraFacing: "back",
        cameraTorch: false,
        cameraZoom: 1.0
    })

    // ---- readiness ---------------------------------------------------------
    // Reference to the PlasmoidItem, set by main.qml. Used to keep the popup
    // open while a native file dialog is up.
    property var plasmoidItem: null

    function holdPopup() {
        if (plasmoidItem)
            plasmoidItem.hideOnWindowDeactivate = false;
    }

    function releasePopup() {
        if (plasmoidItem)
            plasmoidItem.hideOnWindowDeactivate = true;
    }

    property bool helperReady: false
    property string adbPath: ""
    property string scrcpyPath: ""
    property string helperError: ""
    readonly property bool adbMissing: helperReady && adbPath === ""

    // ---- devices -----------------------------------------------------------
    property var devices: []
    property string activeId: ""
    property var previous: []
    property var qr: ({})
    property var mirrors: []
    property bool busy: false

    // Slider writes are coalesced: at most one call per control is in flight and the
    // newest value always wins, so dragging never queues up dozens of adb commands.
    property bool brightnessInFlight: false
    property bool volumeInFlight: false
    property real pendingBrightness: -1
    property real pendingVolume: -1
    property real localBrightness: -1
    property real localVolume: -1
    property double localBrightnessAt: 0
    property double localVolumeAt: 0

    readonly property var activeDevice: {
        if (!activeId)
            return null;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].id === activeId)
                return devices[i];
        }
        return null;
    }
    readonly property bool hasDevice: !!activeDevice && activeDevice.connected
    // The backend collapses the Android 11+ duplicate transports (mDNS alias +
    // host:port) into one entry per phone, so every entry here is addressable.
    readonly property var uiDevices: devices
    readonly property int connectedCount: {
        let count = 0;
        for (let i = 0; i < uiDevices.length; ++i) {
            if (uiDevices[i].connected)
                count += 1;
        }
        return count;
    }
    readonly property int activeBattery: activeDevice ? (activeDevice.battery ?? -1) : -1
    readonly property bool activeCharging: activeDevice ? !!activeDevice.charging : false
    readonly property var quick: activeDevice ? (activeDevice.quick ?? ({})) : ({})

    // What the sliders should show: the device values, with a recent local change taking
    // precedence for a moment so the 5 s poll cannot yank the handle back.
    readonly property var effectiveQuick: {
        const base = quick;
        const out = {};
        for (const key in base)
            out[key] = base[key];
        const now = Date.now();
        if (localBrightness >= 0 && now - localBrightnessAt < 3000) {
            const span = base.brightnessMax || 255;
            out.brightness = Math.round(localBrightness / 100 * span);
            out.brightnessMax = span;
        }
        if (localVolume >= 0 && now - localVolumeAt < 3000)
            out.volume = Math.round(localVolume);
        return out;
    }

    // ---- apps --------------------------------------------------------------
    property var apps: []
    property bool appsLoading: false
    property string appsLoadedFor: ""
    property string appsSource: ""

    // ---- files -------------------------------------------------------------
    property var files: []
    property string currentPath: "/sdcard"
    property bool filesLoading: false

    // ---- emulators ---------------------------------------------------------
    property var avds: []
    property bool avdsLoading: false

    // ---- signals -----------------------------------------------------------
    signal toast(string text, bool error)
    signal response(string action, var data)
    signal pairingFound(string ip, string port)

    // Last user-visible message (shown by the popup's message bar).
    property string lastMessage: ""
    property bool lastMessageError: false

    function dismissMessage() {
        lastMessage = "";
        lastMessageError = false;
    }

    Timer {
        id: messageTimer
        interval: 7000
        onTriggered: backend.dismissMessage()
    }

    // ---- exec bridge -------------------------------------------------------
    P5Support.DataSource {
        id: exec

        engine: "executable"
        connectedSources: []

        property var callbacks: ({})
        property int seq: 0

        onNewData: (sourceName, data) => {
            const token = exec.tokenOf(sourceName);
            const callback = callbacks[token];
            const stdout = (data["stdout"] || "").trim();
            const stderr = (data["stderr"] || "").trim();

            exec.disconnectSource(sourceName);
            if (callback !== undefined)
                delete callbacks[token];

            const envelope = backend.parseEnvelope(stdout);
            if (!envelope) {
                backend.helperReady = false;
                backend.helperError = stderr || stdout || "No response from the androlaunch helper";
            }
            if (callback)
                callback(envelope, stderr);
        }

        onSourceRemoved: sourceName => {
            const token = tokenOf(sourceName);
            if (callbacks[token] !== undefined)
                delete callbacks[token];
        }

        function tokenOf(sourceName) {
            const match = /--token (\S+)/.exec(sourceName || "");
            return match ? match[1] : "";
        }
    }

    function parseEnvelope(text) {
        if (!text)
            return null;
        const start = text.indexOf("{");
        const end = text.lastIndexOf("}");
        if (start === -1 || end <= start)
            return null;
        try {
            return JSON.parse(text.slice(start, end + 1));
        } catch (e) {
            return null;
        }
    }

    // UTF-8 -> base64 for the CLI payload, implemented here on purpose: Qt.btoa() only
    // takes latin1 strings (deprecated) and its Uint8Array overload silently returns an
    // empty string in Qt 6.11, which made every argumented helper call lose its arguments.
    function toBase64(text) {
        const bytes = [];
        for (let i = 0; i < text.length; i++) {
            const code = text.charCodeAt(i);
            if (code < 0x80) {
                bytes.push(code);
            } else if (code < 0x800) {
                bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
            } else if (code < 0xd800 || code >= 0xe000) {
                bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
            } else {
                const next = text.charCodeAt(++i);
                const point = 0x10000 + (((code & 0x3ff) << 10) | (next & 0x3ff));
                bytes.push(0xf0 | (point >> 18), 0x80 | ((point >> 12) & 0x3f),
                           0x80 | ((point >> 6) & 0x3f), 0x80 | (point & 0x3f));
            }
        }

        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let out = "";
        for (let i = 0; i < bytes.length; i += 3) {
            const b0 = bytes[i];
            const b1 = bytes[i + 1];
            const b2 = bytes[i + 2];
            out += alphabet[b0 >> 2];
            out += alphabet[((b0 & 3) << 4) | ((b1 ?? 0) >> 4)];
            out += (b1 === undefined) ? "=" : alphabet[((b1 & 15) << 2) | ((b2 ?? 0) >> 6)];
            out += (b2 === undefined) ? "=" : alphabet[b2 & 63];
        }
        return out;
    }

    function call(action, args, callback) {
        const token = String(++exec.seq);
        const payload = toBase64(JSON.stringify(args || {}));
        exec.callbacks[token] = callback;
        exec.connectSource(helperPath + " call " + action + " " + payload + " --token " + token);
    }

    function notify(envelope, fallbackError) {
        if (!envelope) {
            surface(fallbackError || helperError || "androlaunch helper not available", true);
            return false;
        }
        const ok = envelope.ok === true;
        const text = envelope.message || envelope.error || (ok ? "" : "Operation failed");
        if (text)
            surface(text, !ok);
        if (!ok && envelope.error && envelope.error !== text)
            surface(envelope.error, true);
        return ok;
    }

    function surface(text, error) {
        lastMessage = text;
        lastMessageError = error === true;
        messageTimer.restart();
        toast(text, lastMessageError);
    }

    // ---- bootstrapping -----------------------------------------------------
    function bootstrap() {
        backend.call("version", {}, (envelope, stderr) => {
            if (!envelope) {
                backend.helperReady = false;
                backend.helperError = stderr || "Cannot run " + helperPath + " — run the AndroLaunch installer";
                console.warn("AndroLaunch: backend unavailable:", backend.helperError);
                return;
            }
            backend.helperReady = true;
            backend.helperError = "";
            backend.adbPath = envelope.adb || "";
            backend.scrcpyPath = envelope.scrcpy || "";
            console.info("AndroLaunch: backend ready (adb=" + (backend.adbPath || "missing")
                + ", scrcpy=" + (backend.scrcpyPath || "missing") + ")");
            backend.refresh();
        });
    }

    // ---- device state ------------------------------------------------------
    function refresh() {
        if (!helperReady)
            return;
        busy = true;
        call("state", {}, (envelope, stderr) => {
            busy = false;
            if (!envelope) {
                notify(null, stderr);
                return;
            }
            adbPath = envelope.adb || adbPath;
            scrcpyPath = envelope.scrcpy || scrcpyPath;
            const data = envelope.data || {};
            devices = data.devices || [];
            activeId = data.active || "";
            previous = data.previous || [];
            qr = data.qr || ({});
            mirrors = data.mirrors || [];
            if (appsLoadedFor && appsLoadedFor !== activeId) {
                apps = [];
                appsLoadedFor = "";
            }
        });
    }

    function selectDevice(id) {
        activeId = id;
        call("select", { device: id }, envelope => notify(envelope));
        refresh();
    }

    function toggle(what, on) {
        call("toggle", { what: what, on: on }, envelope => {
            notify(envelope);
            refresh();
        });
    }

    function setBrightness(percent) {
        localBrightness = percent;
        localBrightnessAt = Date.now();
        pendingBrightness = percent;
        pumpBrightness();
    }

    function pumpBrightness() {
        if (brightnessInFlight || pendingBrightness < 0)
            return;
        const value = pendingBrightness;
        pendingBrightness = -1;
        brightnessInFlight = true;
        call("brightness", { percent: value }, envelope => {
            brightnessInFlight = false;
            if (envelope && envelope.ok === false)
                notify(envelope);
            if (pendingBrightness >= 0)
                pumpBrightness();
        });
    }

    function setVolume(value) {
        localVolume = value;
        localVolumeAt = Date.now();
        pendingVolume = value;
        pumpVolume();
    }

    function pumpVolume() {
        if (volumeInFlight || pendingVolume < 0)
            return;
        const value = pendingVolume;
        pendingVolume = -1;
        volumeInFlight = true;
        call("volume", { value: value }, envelope => {
            volumeInFlight = false;
            if (envelope && envelope.ok === false)
                notify(envelope);
            if (pendingVolume >= 0)
                pumpVolume();
        });
    }

    function reboot(mode) {
        call("reboot", { mode: mode }, envelope => notify(envelope));
    }

    // ---- mirroring ---------------------------------------------------------
    function mirror(extraOptions) {
        const options = Object.assign({}, mirrorOptions, extraOptions || {});
        call("mirror", { options: options }, envelope => {
            notify(envelope);
            refreshMirrors();
        });
    }

    function camera(extraOptions) {
        const options = Object.assign({}, mirrorOptions, extraOptions || {});
        call("camera", { options: options }, envelope => {
            notify(envelope);
            refreshMirrors();
        });
    }

    function appMirror(packageName, label) {
        call("app_mirror", {
            package: packageName,
            label: label || packageName,
            options: mirrorOptions
        }, envelope => {
            notify(envelope);
            refreshMirrors();
        });
    }

    function appScreen(packageName, label) {
        call("app_screen", {
            package: packageName,
            label: label || packageName,
            options: mirrorOptions
        }, envelope => {
            notify(envelope);
            refreshMirrors();
        });
    }

    function stopMirror(pid) {
        call("stop_mirror", { pid: pid }, envelope => {
            notify(envelope);
            refreshMirrors();
        });
    }

    function stopMirrors() {
        call("stop_mirrors", {}, envelope => {
            notify(envelope);
            refreshMirrors();
        });
    }

    function refreshMirrors() {
        call("state", {}, envelope => {
            if (envelope && envelope.data)
                mirrors = envelope.data.mirrors || [];
        });
    }

    // ---- apps --------------------------------------------------------------
    function fetchApps(force) {
        if (!hasDevice)
            return;
        if (appsLoading)
            return;
        if (!force && appsLoadedFor === activeId && apps.length > 0)
            return;
        appsLoading = true;
        call("apps", { device: activeId, system: false, refresh: force === true }, envelope => {
            appsLoading = false;
            if (!envelope) {
                notify(null);
                return;
            }
            if (envelope.ok) {
                apps = envelope.data || [];
                appsLoadedFor = activeId;
                appsSource = envelope.source || "";
            } else {
                apps = [];
                notify(envelope);
            }
        });
    }

    function launchApp(packageName) {
        call("app_launch", { package: packageName }, envelope => notify(envelope));
    }

    function uninstallApp(packageName) {
        call("app_uninstall", { package: packageName }, envelope => {
            notify(envelope);
            fetchApps(true);
        });
    }

    function clearAppData(packageName) {
        call("app_clear", { package: packageName }, envelope => notify(envelope));
    }

    function installApk(path) {
        call("apk_install", { path: path }, envelope => {
            notify(envelope);
            fetchApps(true);
        });
    }

    // ---- files -------------------------------------------------------------
    function browse(path, silent) {
        if (!hasDevice)
            return;
        filesLoading = true;
        currentPath = path;
        call("files", { path: path }, envelope => {
            filesLoading = false;
            if (!envelope) {
                notify(null);
                return;
            }
            if (envelope.ok) {
                files = envelope.data || [];
                if (envelope.path)
                    currentPath = envelope.path;
            } else {
                files = [];
                if (!silent)
                    notify(envelope);
            }
        });
    }

    function pushFile(localPath, remotePath) {
        call("file_push", { local: localPath, remote: remotePath }, envelope => {
            notify(envelope);
            browse(currentPath, true);
        });
    }

    function pullFile(remotePath, localPath) {
        call("file_pull", { remote: remotePath, local: localPath }, envelope => notify(envelope));
    }

    function deleteFile(remotePath) {
        call("file_delete", { remote: remotePath }, envelope => {
            notify(envelope);
            browse(currentPath, true);
        });
    }

    function makeDirectory(remotePath) {
        call("file_mkdir", { remote: remotePath }, envelope => {
            notify(envelope);
            browse(currentPath, true);
        });
    }

    // ---- wireless ----------------------------------------------------------
    function wirelessConnect(ip, port) {
        call("wireless_connect", { ip: ip, port: port || "5555" }, envelope => {
            notify(envelope);
            refresh();
        });
    }

    function wirelessPair(ip, port, code, done) {
        call("wireless_pair", { ip: ip, port: port, code: code }, envelope => {
            notify(envelope);
            if (done)
                done(envelope && envelope.ok === true);
        });
    }

    function disconnectDevice(id) {
        call("wireless_disconnect", { target: id || activeId }, envelope => {
            notify(envelope);
            refresh();
        });
    }

    function enableTcpip(port) {
        call("tcpip", { port: port || "5555" }, envelope => notify(envelope));
    }

    function connectPrevious(id) {
        call("connect_previous", { id: id }, envelope => {
            notify(envelope);
            refresh();
        });
    }

    // ---- QR pairing --------------------------------------------------------
    function startQrPairing() {
        call("qr_new", {}, envelope => {
            if (envelope && envelope.data)
                qr = envelope.data;
        });
    }

    function pollPairing() {
        call("discover_pairing", {}, envelope => {
            if (!envelope || !envelope.data || envelope.data.length === 0)
                return;
            const service = envelope.data[0];
            if (!qr.password)
                return;
            call("wireless_pair", { ip: service.ip, port: service.port, code: qr.password }, pairEnvelope => {
                if (!(pairEnvelope && pairEnvelope.ok)) {
                    notify(pairEnvelope);
                    return;
                }
                pairingFound(service.ip, service.port);
                call("discover_connect", {}, connectEnvelope => {
                    let port = "5555";
                    if (connectEnvelope && connectEnvelope.data && connectEnvelope.data.length > 0)
                        port = connectEnvelope.data[0].port;
                    wirelessConnect(service.ip, port);
                });
            });
        });
    }

    // ---- shell / tools -----------------------------------------------------
    function runShell(command, callback) {
        call("shell", { command: command }, envelope => {
            if (callback)
                callback(envelope);
            else
                notify(envelope);
        });
    }

    function openTerminal() {
        call("open_terminal", {}, envelope => notify(envelope));
    }

    function openLogcat() {
        call("open_logcat", {}, envelope => notify(envelope));
    }

    function sendClipboard(text) {
        call("clipboard_send", { text: text }, envelope => notify(envelope));
    }

    function getClipboard(callback) {
        call("clipboard_get", {}, envelope => {
            if (callback)
                callback(envelope && envelope.data ? envelope.data.text : "");
            else
                notify(envelope);
        });
    }

    function fetchAvds() {
        avdsLoading = true;
        call("avds", {}, envelope => {
            avdsLoading = false;
            if (!envelope) {
                notify(null);
                return;
            }
            avds = envelope.data || [];
            if (!envelope.ok)
                notify(envelope);
        });
    }

    function startAvd(name) {
        call("avd_start", { name: name }, envelope => notify(envelope));
    }

    Component.onCompleted: bootstrap()

    Component.onDestruction: {
        const pending = exec.sources || [];
        for (let i = 0; i < pending.length; ++i)
            exec.disconnectSource(pending[i]);
    }

    Timer {
        interval: backend.pollInterval
        running: backend.helperReady
        repeat: true
        onTriggered: backend.refresh()
    }
}
