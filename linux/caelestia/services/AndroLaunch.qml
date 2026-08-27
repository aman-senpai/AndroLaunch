pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services

Singleton {
    id: root

    // Paths and availability
    property string adbPath: ""
    property string scrcpyPath: ""
    readonly property bool available: adbPath.length > 0
    readonly property bool scrcpyAvailable: scrcpyPath.length > 0
    property bool daemonRunning: false
    property bool scanning: false
    property var previousDevices: []
    property string connectingDeviceId: ""

    // QR Code Pairing State (macOS ADBPairingService match)
    property string qrString: ""
    property string pairingPassword: ""
    property bool isQRPairingActive: false
    property string qrPairingStatus: ""

    // Device list and active device
    property var devices: []
    property string activeDeviceId: ""
    readonly property var activeDevice: {
        if (!devices || devices.length === 0)
            return null;
        if (activeDeviceId && activeDeviceId.length > 0) {
            const found = devices.find(d => d.id === activeDeviceId);
            if (found)
                return found;
        }
        return devices[0] ?? null;
    }
    readonly property bool hasConnectedDevice: !!activeDevice && activeDevice.isConnected

    // Mirroring process state tracking
    property var activeMirrors: ({}) // map: deviceId -> { isScreen: bool, isCamera: bool, app: string }

    // Apps list for active device
    property var apps: []
    property bool loadingApps: false

    // Files explorer state
    property var files: []
    property string currentPath: "/sdcard"
    property bool loadingFiles: false

    // AVD / Emulators
    property var avds: []
    property bool loadingAvds: false

    property list<var> customCommands: [
        { id: "1", name: "Take Screenshot", command: "screencap -p /sdcard/screenshot.png && echo 'Saved to /sdcard/screenshot.png'", isBackground: false },
        { id: "2", name: "Show IP Address", command: "ip addr show wlan0 | grep 'inet ' | awk '{print $2}'", isBackground: false },
        { id: "3", name: "Battery Info", command: "dumpsys battery", isBackground: false },
        { id: "4", name: "Dump Memory Info", command: "dumpsys meminfo", isBackground: false },
        { id: "5", name: "List Top Processes", command: "top -n 1 -b -m 10", isBackground: false }
    ]

    // Default Scrcpy Settings
    property var scrcpyConfig: ({
        newDisplay: false,
        flexDisplay: false,
        audioEnabled: false,
        keepActive: true,
        lockAspectRatio: true,
        borderless: false,
        maxFps: 60,
        bitRate: 8,
        maxSize: 0,
        cameraFacing: "back",
        cameraTorch: false,
        cameraZoom: 1.0
    })

    // Logging
    LoggingCategory {
        id: lc
        name: "caelestia.qml.services.androlaunch"
        defaultLogLevel: LoggingCategory.Info
    }

    // Command runner component
    Component {
        id: adbProcessComponent

        Process {
            id: proc

            property var callback: null

            environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

            stdout: StdioCollector {
                id: outCollector
            }

            stderr: StdioCollector {
                id: errCollector
            }

            onExited: code => { // qmllint disable signal-handler-parameters
                const outText = (outCollector && outCollector.text) ? outCollector.text.trim() : "";
                const errText = (errCollector && errCollector.text) ? errCollector.text.trim() : "";
                if (proc.callback) {
                    try {
                        proc.callback(code === 0, outText, errText);
                    } catch (e) {
                        console.warn(lc, "Error in ADBProcess callback:", e);
                    }
                }
                proc.destroy();
            }
        }
    }

    function runAdb(args: list<string>, callback = null, deviceId = ""): void {
        if (!available) {
            if (callback) callback(false, "", "ADB not found");
            return;
        }

        let fullArgs = [adbPath];
        const targetId = deviceId || (activeDevice ? activeDevice.id : "");
        if (targetId && !args.includes("-s") && !args[0].startsWith("connect") && !args[0].startsWith("pair") && !args[0].startsWith("devices") && !args[0].startsWith("start-server") && !args[0].startsWith("kill-server")) {
            fullArgs.push("-s", targetId);
        }
        fullArgs.push(...args);

        const obj = adbProcessComponent.createObject(root, {
            command: fullArgs,
            callback: callback,
            running: true
        });
    }

    function runCommand(cmd: list<string>, callback = null): void {
        const obj = adbProcessComponent.createObject(root, {
            command: cmd,
            callback: callback,
            running: true
        });
    }

    // Path Discovery
    function checkPaths(): void {
        runCommand(["sh", "-c", "which adb 2>/dev/null || find /usr /opt /home/$USER/Android /home/$USER/.local -name 'adb' -type f -executable 2>/dev/null | head -n 1"], (success, out) => {
            const path = out ? out.trim().split("\n")[0] : "";
            if (path && path.length > 0) {
                root.adbPath = path;
                root.scanDevices();
            } else {
                root.adbPath = "";
            }
        });

        runCommand(["sh", "-c", "which scrcpy 2>/dev/null || find /usr /opt /home/$USER/.local -name 'scrcpy' -type f -executable 2>/dev/null | head -n 1"], (success, out) => {
            const scPath = out ? out.trim().split("\n")[0] : "";
            root.scrcpyPath = scPath && scPath.length > 0 ? scPath : "";
        });
    }

    // Scan devices
    function scanDevices(): void {
        if (!adbPath || scanning)
            return;

        scanning = true;
        runAdb(["devices", "-l"], (success, output, err) => {
            scanning = false;
            if (!success) {
                daemonRunning = false;
                return;
            }
            daemonRunning = true;
            parseDevices(output);
        });
    }

    function parseDevices(output: string): void {
        const lines = output.split("\n");
        const list = [];
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.toLowerCase().includes("list of devices attached"))
                continue;

            // Pattern: <serial> <status> [details...]
            const parts = trimmed.split(/\s+/);
            if (parts.length >= 2) {
                const serial = parts[0];
                const status = parts[1];
                const isConnected = status === "device";
                let model = "";
                let product = "";
                let deviceName = serial;

                for (let i = 2; i < parts.length; i++) {
                    if (parts[i].startsWith("model:"))
                        model = parts[i].slice(6).replace(/_/g, " ");
                    if (parts[i].startsWith("device:"))
                        product = parts[i].slice(7);
                }

                if (model)
                    deviceName = model;

                const isWireless = serial.includes(":");
                const isEmulator = serial.startsWith("emulator-");

                const existing = root.devices ? root.devices.find(d => d.id === serial) : null;

                list.push({
                    id: serial,
                    serialNumber: serial,
                    name: deviceName,
                    model: model || product || (existing?.model ?? (isEmulator ? "Android Emulator" : "Android Device")),
                    status: status,
                    isConnected: isConnected,
                    isWireless: isWireless,
                    isEmulator: isEmulator,
                    androidVersion: existing?.androidVersion ?? "",
                    apiLevel: existing?.apiLevel ?? "",
                    batteryLevel: existing?.batteryLevel ?? -1,
                    isCharging: existing?.isCharging ?? false,
                    quickActions: existing?.quickActions ?? {
                        wifi: false,
                        bluetooth: false,
                        darkMode: false,
                        airplaneMode: false,
                        mobileData: false,
                        location: false,
                        dnd: false,
                        autoRotate: false,
                        brightness: 128,
                        volume: 50
                    }
                });
            }
        }

        // Check for offline wireless devices and auto-heal
        for (const dev of list) {
            if (dev.isWireless && dev.status === "offline") {
                runAdb(["disconnect", dev.id], () => {
                    root.autoDiscoverAndConnect();
                });
            }
        }

        // Only update if list membership or connection states changed
        const hasChanges = !root.devices || root.devices.length !== list.length || list.some((d, idx) => {
            const cur = root.devices[idx];
            return !cur || cur.id !== d.id || cur.status !== d.status;
        });

        if (hasChanges) {
            root.devices = list;
        }
        // Update previous devices list
        for (const dev of list) {
            if (dev.isConnected && !dev.isEmulator) {
                const existingIdx = root.previousDevices.findIndex(p => p.serialNumber === dev.serialNumber);
                const item = {
                    name: dev.name || dev.model || dev.serialNumber,
                    serialNumber: dev.serialNumber,
                    model: dev.model,
                    isWireless: dev.isWireless
                };
                if (existingIdx === -1) {
                    root.previousDevices = [...root.previousDevices, item];
                } else {
                    const updated = [...root.previousDevices];
                    updated[existingIdx] = item;
                    root.previousDevices = updated;
                }
            }
        }

        // Auto-select active device if not set or disconnected
        if (list.length > 0) {
            if (!activeDeviceId || !list.some(d => d.id === activeDeviceId)) {
                const firstConnected = list.find(d => d.isConnected);
                activeDeviceId = firstConnected ? firstConnected.id : list[0].id;
            }
            // Fetch detailed info for connected devices
            for (const dev of list) {
                if (dev.isConnected) {
                    fetchDeviceInfo(dev.id);
                }
            }
        } else {
            activeDeviceId = "";
        }
    }

    function selectDevice(id: string): void {
        activeDeviceId = id;
        if (hasConnectedDevice) {
            fetchDeviceInfo(id);
            fetchApps(id);
        }
    }

    // Fetch device info (battery, version, quick toggles)
    function fetchDeviceInfo(deviceId: string): void {
        const cmd = "echo \"MODEL:$(getprop ro.product.model)\"; echo \"VER:$(getprop ro.build.version.release)\"; echo \"SDK:$(getprop ro.build.version.sdk)\"; dumpsys battery | grep -E \"level:|powered:\"; echo \"WIFI:$(settings get global wifi_on 2>/dev/null)\"; echo \"BT:$(settings get global bluetooth_on 2>/dev/null)\"; echo \"DARK:$(cmd uimode night 2>/dev/null)\"; echo \"AIR:$(settings get global airplane_mode_on 2>/dev/null)\"; echo \"DATA:$(settings get global mobile_data 2>/dev/null)\"; echo \"LOC:$(settings get secure location_mode 2>/dev/null)\"; echo \"DND:$(cmd settings get global zen_mode 2>/dev/null || settings get global zen_mode 2>/dev/null)\"; echo \"ROT:$(settings get system accelerometer_rotation 2>/dev/null)\"; echo \"BRI:$(settings get system screen_brightness 2>/dev/null)\"; echo \"VOL:$(cmd media_session volume --stream 3 --get 2>/dev/null)\";";
        runAdb(["shell", cmd], (success, output) => {
            if (!success || !output) return;

            const lines = output.split("\n");
            let ver = "";
            let sdk = "";
            let batt = -1;
            let charging = false;
            let wifi = false;
            let bt = false;
            let dark = false;
            let air = false;
            let data = false;
            let loc = false;
            let dnd = false;
            let rot = false;
            let bri = 128;
            let vol = -1;
            for (const line of lines) {
                const l = line.trim();
                if (l.startsWith("VER:")) ver = l.slice(4).trim();
                else if (l.startsWith("SDK:")) sdk = l.slice(4).trim();
                else if (l.includes("level:")) {
                    const p = l.split(":");
                    if (p.length >= 2) batt = parseInt(p[1].trim(), 10) || -1;
                } else if (l.includes("powered:") && l.includes("true")) {
                    charging = true;
                } else if (l.startsWith("WIFI:")) wifi = l.includes("1");
                else if (l.startsWith("BT:")) bt = l.includes("1");
                else if (l.startsWith("DARK:")) dark = l.includes("yes");
                else if (l.startsWith("AIR:")) air = l.includes("1");
                else if (l.startsWith("DATA:")) data = l.includes("1");
                else if (l.startsWith("LOC:")) loc = parseInt(l.slice(4).trim(), 10) > 0;
                else if (l.startsWith("DND:")) dnd = parseInt(l.replace("DND:zen_mode =", "").replace("DND:", "").trim(), 10) > 0;
                else if (l.startsWith("ROT:")) rot = l.includes("1");
                else if (l.startsWith("BRI:")) bri = parseInt(l.slice(4).trim(), 10) || 128;
                else if (l.startsWith("VOL:") || l.includes("volume is")) {
                    const match = l.match(/volume is (\d+) in range \[(\d+)\.\.(\d+)\]/i);
                    if (match) {
                        const cur = parseInt(match[1], 10);
                        const min = parseInt(match[2], 10);
                        const max = parseInt(match[3], 10);
                        if (max > min) {
                            vol = Math.round(((cur - min) / (max - min)) * 100);
                        }
                    }
                }
            }
            // Update device in list only if properties changed
            const currentList = [...root.devices];
            const idx = currentList.findIndex(d => d.id === deviceId);
            if (idx !== -1) {
                const prev = currentList[idx];
                const prevQA = prev.quickActions || {};

                const qaChanged = prevQA.wifi !== wifi ||
                                  prevQA.bluetooth !== bt ||
                                  prevQA.darkMode !== dark ||
                                  prevQA.airplaneMode !== air ||
                                  prevQA.mobileData !== data ||
                                  prevQA.location !== loc ||
                                  prevQA.dnd !== dnd ||
                                  prevQA.autoRotate !== rot ||
                                  Math.abs((prevQA.brightness ?? 128) - bri) > 1 ||
                                  (vol >= 0 && Math.abs((prevQA.volume ?? 50) - vol) > 1);

                const infoChanged = prev.androidVersion !== (ver || prev.androidVersion) ||
                                    prev.batteryLevel !== (batt >= 0 ? batt : prev.batteryLevel) ||
                                    prev.isCharging !== charging ||
                                    qaChanged;

                if (infoChanged) {
                    const updated = Object.assign({}, prev, {
                        androidVersion: ver || prev.androidVersion,
                        apiLevel: sdk || prev.apiLevel,
                        batteryLevel: batt >= 0 ? batt : prev.batteryLevel,
                        isCharging: charging,
                        quickActions: {
                            wifi: wifi,
                            bluetooth: bt,
                            darkMode: dark,
                            airplaneMode: air,
                            mobileData: data,
                            location: loc,
                            dnd: dnd,
                            autoRotate: rot,
                            brightness: bri,
                            volume: vol >= 0 ? vol : (prevQA.volume ?? 50)
                        }
                    });
                    currentList[idx] = updated;
                    root.devices = currentList;
                }
            }
        }, deviceId);
    }

    // Quick Actions
    function toggleWifi(enable: bool, deviceId = ""): void {
        const state = enable ? "enable" : "disable";
        runAdb(["shell", "svc", "wifi", state], (success) => {
            if (success) {
                updateQuickActionLocal("wifi", enable, deviceId);
                Toaster.toast(qsTr("Wi-Fi %1").arg(enable ? qsTr("Enabled") : qsTr("Disabled")), qsTr("Android Wi-Fi status updated"), "wifi");
            }
        }, deviceId);
    }

    function toggleBluetooth(enable: bool, deviceId = ""): void {
        const state = enable ? "enable" : "disable";
        runAdb(["shell", "svc", "bluetooth", state], (success) => {
            if (success) {
                updateQuickActionLocal("bluetooth", enable, deviceId);
                Toaster.toast(qsTr("Bluetooth %1").arg(enable ? qsTr("Enabled") : qsTr("Disabled")), qsTr("Android Bluetooth status updated"), "bluetooth");
            }
        }, deviceId);
    }

    function toggleDarkMode(enable: bool, deviceId = ""): void {
        const state = enable ? "yes" : "no";
        runAdb(["shell", "cmd", "uimode", "night", state], (success) => {
            if (success) {
                updateQuickActionLocal("darkMode", enable, deviceId);
                Toaster.toast(qsTr("Dark Mode %1").arg(enable ? qsTr("Enabled") : qsTr("Disabled")), qsTr("Android UI theme updated"), "dark_mode");
            }
        }, deviceId);
    }

    function toggleAirplaneMode(enable: bool, deviceId = ""): void {
        const val = enable ? "1" : "0";
        runAdb(["shell", "settings put global airplane_mode_on " + val + " && am broadcast -a android.intent.action.AIRPLANE_MODE"], (success) => {
            if (success) {
                updateQuickActionLocal("airplaneMode", enable, deviceId);
                Toaster.toast(qsTr("Airplane Mode %1").arg(enable ? qsTr("Enabled") : qsTr("Disabled")), qsTr("Android airplane mode updated"), "airplanemode_active");
            }
        }, deviceId);
    }

    function toggleMobileData(enable: bool, deviceId = ""): void {
        const val = enable ? "1" : "0";
        runAdb(["shell", "settings put global mobile_data " + val + " && svc data " + (enable ? "enable" : "disable")], (success) => {
            if (success) {
                updateQuickActionLocal("mobileData", enable, deviceId);
                Toaster.toast(qsTr("Mobile Data %1").arg(enable ? qsTr("Enabled") : qsTr("Disabled")), qsTr("Android mobile data updated"), "signal_cellular_alt");
            }
        }, deviceId);
    }

    function toggleLocation(enable: bool, deviceId = ""): void {
        const val = enable ? "3" : "0";
        runAdb(["shell", "settings put secure location_mode " + val], (success) => {
            if (success) {
                updateQuickActionLocal("location", enable, deviceId);
                Toaster.toast(qsTr("Location %1").arg(enable ? qsTr("Enabled") : qsTr("Disabled")), qsTr("Android location status updated"), "location_on");
            }
        }, deviceId);
    }

    function toggleDnd(enable: bool, deviceId = ""): void {
        const val = enable ? "1" : "0";
        runAdb(["shell", "cmd settings put global zen_mode " + val + " || settings put global zen_mode " + val], (success) => {
            if (success) {
                updateQuickActionLocal("dnd", enable, deviceId);
                Toaster.toast(qsTr("DND %1").arg(enable ? qsTr("Enabled") : qsTr("Disabled")), qsTr("Do Not Disturb mode updated"), "do_not_disturb_on");
            }
        }, deviceId);
    }

    function toggleAutoRotate(enable: bool, deviceId = ""): void {
        const val = enable ? "1" : "0";
        runAdb(["shell", "settings put system accelerometer_rotation " + val], (success) => {
            if (success) {
                updateQuickActionLocal("autoRotate", enable, deviceId);
                Toaster.toast(qsTr("Auto Rotate %1").arg(enable ? qsTr("Enabled") : qsTr("Disabled")), qsTr("Screen auto-rotation updated"), "screen_rotation");
            }
        }, deviceId);
    }

    function setBrightness(val: int, deviceId = ""): void {
        const clamped = Math.max(0, Math.min(255, val));
        runAdb(["shell", "settings put system screen_brightness " + clamped], (success) => {
            if (success) {
                updateQuickActionLocal("brightness", clamped, deviceId);
            }
        }, deviceId);
    }

    function setVolume(val: int, stream = 3, deviceId = ""): void {
        const clamped = Math.max(0, Math.min(100, val));
        const targetIndex = Math.round((clamped / 100) * 150);
        updateQuickActionLocal("volume", clamped, deviceId);
        runAdb(["shell", "cmd", "media_session", "volume", "--stream", "" + stream, "--set", "" + targetIndex], (success) => {
            if (!success) {
                runAdb(["shell", "media", "volume", "--stream", "" + stream, "--set", "" + targetIndex]);
            }
        }, deviceId);
    }

    function setRingerMode(mode: string, deviceId = ""): void {
        // mode: normal, vibrate, silent
        runAdb(["shell", "cmd", "media_session", "set_volume_mode", mode], (success) => {
            if (success) {
                Toaster.toast(qsTr("Ringer: %1").arg(mode), qsTr("Android ringer mode updated"), "notifications");
            }
        }, deviceId);
    }

    // Screen & Camera Mirroring (Scrcpy)
    function startMirroring(customOpts = {}, deviceId = ""): void {
        const targetId = deviceId || (activeDevice ? activeDevice.id : "");
        if (!targetId) {
            Toaster.toast(qsTr("No Device"), qsTr("Connect an Android device to mirror"), "smartphone", Toast.Type.Warning);
            return;
        }

        const opts = Object.assign({}, scrcpyConfig, customOpts);
        let args = ["-s", targetId, "--window-title", "AndroLaunch - " + targetId];

        if (opts.newDisplay) {
            args.push("--new-display");
            if (opts.flexDisplay)
                args.push("--flex-display");
        } else if (opts.maxSize > 0) {
            args.push("-m", "" + opts.maxSize);
        }
        if (opts.maxFps > 0)
            args.push("--max-fps", "" + opts.maxFps);
        if (opts.bitRate > 0)
            args.push("-b", opts.bitRate + "M");
        if (!opts.audioEnabled)
            args.push("--no-audio");
        if (opts.keepActive)
            args.push("--stay-awake");
        if (opts.borderless)
            args.push("--window-borderless");
        if (!opts.lockAspectRatio)
            args.push("--no-window-aspect-ratio-lock");

        const bin = scrcpyPath && scrcpyPath.length > 0 ? scrcpyPath : "scrcpy";
        Toaster.toast(qsTr("Starting Mirror"), qsTr("Launching Scrcpy for %1...").arg(targetId), "screen_share");
        Quickshell.execDetached([bin, ...args]);

        const mirrors = Object.assign({}, activeMirrors, { [targetId]: { isScreen: true } });
        activeMirrors = mirrors;
    }

    function startCameraMirroring(customOpts = {}, deviceId = ""): void {
        const targetId = deviceId || (activeDevice ? activeDevice.id : "");
        if (!targetId) return;

        const opts = Object.assign({}, scrcpyConfig, customOpts);
        let args = [
            "-s", targetId,
            "--video-source=camera",
            "--window-title", "AndroLaunch Camera - " + targetId,
            "--camera-facing=" + (opts.cameraFacing || "back")
        ];

        if (opts.cameraTorch)
            args.push("--camera-torch");
        if (opts.cameraZoom && opts.cameraZoom !== 1.0)
            args.push("--camera-zoom", "" + opts.cameraZoom);
        if (opts.maxFps > 0)
            args.push("--max-fps", "" + opts.maxFps);
        if (opts.bitRate > 0)
            args.push("-b", opts.bitRate + "M");

        const bin = scrcpyPath && scrcpyPath.length > 0 ? scrcpyPath : "scrcpy";
        Toaster.toast(qsTr("Camera Mirror"), qsTr("Opening camera stream for %1...").arg(targetId), "videocam");
        Quickshell.execDetached([bin, ...args]);
    }

    function startAppMirroring(packageName: string, customOpts = {}, deviceId = ""): void {
        const targetId = deviceId || (activeDevice ? activeDevice.id : "");
        if (!targetId) return;

        const opts = Object.assign({}, scrcpyConfig, customOpts);
        let args = [
            "-s", targetId,
            "--start-app=" + packageName,
            "--window-title", "AndroLaunch - " + packageName
        ];

        if (opts.newDisplay) {
            args.push("--new-display");
            if (opts.flexDisplay)
                args.push("--flex-display");
        }

        if (opts.maxFps > 0) args.push("--max-fps", "" + opts.maxFps);
        if (opts.bitRate > 0) args.push("-b", opts.bitRate + "M");
        if (!opts.audioEnabled) args.push("--no-audio");
        if (opts.keepActive) args.push("--stay-awake");
        if (opts.borderless) args.push("--window-borderless");

        const bin = scrcpyPath && scrcpyPath.length > 0 ? scrcpyPath : "scrcpy";
        Toaster.toast(qsTr("Launching App"), qsTr("Opening %1 in Scrcpy...").arg(packageName), "apps");
        Quickshell.execDetached([bin, ...args]);
    }

    // App Management
    function fetchApps(deviceId = "", force = false): void {
        const targetId = deviceId || (activeDevice ? activeDevice.id : "");
        if (!targetId) return;

        loadingApps = true;
        const bin = scrcpyPath && scrcpyPath.length > 0 ? scrcpyPath : "scrcpy";
        runCommand([bin, "-s", targetId, "--list-apps"], (scrcpySuccess, scrcpyOutput) => {
            if (scrcpySuccess && scrcpyOutput && scrcpyOutput.includes("List of apps:")) {
                loadingApps = false;
                const lines = scrcpyOutput.split("\n");
                const result = [];
                let startParsing = false;
                for (const line of lines) {
                    const trimmed = line.trim();
                    if (trimmed.includes("List of apps:")) {
                        startParsing = true;
                        continue;
                    }
                    if (!startParsing) continue;

                    const match = trimmed.match(/^([\*\-])\s+(.+?)\s+([a-zA-Z0-9_\.]+)$/);
                    if (match) {
                        const isSystem = match[1] === "*";
                        const appName = match[2].trim();
                        const pkg = match[3].trim();
                        result.push({
                            id: pkg,
                            name: appName,
                            packageName: pkg,
                            isSystem: isSystem,
                            icon: "android"
                        });
                    }
                }
                if (result.length > 0) {
                    result.sort((a, b) => {
                        if (a.isSystem !== b.isSystem)
                            return a.isSystem ? 1 : -1;
                        return a.name.localeCompare(b.name);
                    });
                    root.apps = result;
                    return;
                }
            }

            // Fallback to pm list packages
            runAdb(["shell", "pm", "list", "packages", "-f", "-3"], (pmSuccess, pmOutput) => {
                loadingApps = false;
                if (!pmSuccess || !pmOutput) {
                    root.apps = [];
                    return;
                }

                const lines = pmOutput.split("\n");
                const result = [];
                for (const line of lines) {
                    const trimmed = line.trim();
                    if (!trimmed.startsWith("package:")) continue;

                    const clean = trimmed.slice(8);
                    const eqIdx = clean.lastIndexOf("=");
                    if (eqIdx !== -1) {
                        const apkPath = clean.slice(0, eqIdx);
                        const pkg = clean.slice(eqIdx + 1);
                        const lastSlash = apkPath.lastIndexOf("/");
                        const apkName = lastSlash !== -1 ? apkPath.slice(lastSlash + 1) : apkPath;
                        const displayName = apkName.replace(/\.apk$/i, "").replace(/[-_]/g, " ").replace(/\b\w/g, c => c.toUpperCase());

                        result.push({
                            id: pkg,
                            name: displayName || pkg,
                            packageName: pkg,
                            isSystem: false,
                            icon: "android"
                        });
                    }
                }

                result.sort((a, b) => a.name.localeCompare(b.name));
                root.apps = result;
            }, targetId);
        });
    }

    function launchApp(packageName: string, deviceId = ""): void {
        runAdb(["shell", "monkey", "-p", packageName, "-c", "android.intent.category.LAUNCHER", "1"], (success) => {
            if (success) {
                Toaster.toast(qsTr("App Launched"), qsTr("Launched %1 on device").arg(packageName), "launch");
            } else {
                // Fallback to am start
                runAdb(["shell", "monkey -p " + packageName + " 1 || am start -n $(pm dump " + packageName + " | grep -A 1 'android.intent.action.MAIN:' | grep -m 1 '    ' | awk '{print $1}')"], () => {});
            }
        }, deviceId);
    }

    function uninstallApp(packageName: string, deviceId = ""): void {
        Toaster.toast(qsTr("Uninstalling"), qsTr("Removing %1...").arg(packageName), "delete");
        runAdb(["uninstall", packageName], (success, out, err) => {
            if (success) {
                Toaster.toast(qsTr("Uninstalled"), qsTr("%1 successfully removed").arg(packageName), "check_circle", Toast.Type.Success);
                fetchApps(deviceId, true);
            } else {
                Toaster.toast(qsTr("Uninstall Failed"), err || out || qsTr("Could not uninstall app"), "error", Toast.Type.Error);
            }
        }, deviceId);
    }

    function clearAppData(packageName: string, deviceId = ""): void {
        runAdb(["shell", "pm", "clear", packageName], (success, out, err) => {
            if (success) {
                Toaster.toast(qsTr("App Data Cleared"), qsTr("Cleared data for %1").arg(packageName), "cleaning_services", Toast.Type.Success);
            } else {
                Toaster.toast(qsTr("Clear Data Failed"), err || out || qsTr("Failed to clear data"), "error", Toast.Type.Error);
            }
        }, deviceId);
    }

    function installApk(apkPath: string, deviceId = ""): void {
        Toaster.toast(qsTr("Installing APK"), qsTr("Installing %1...").arg(apkPath.split("/").pop()), "download");
        runAdb(["install", "-r", apkPath], (success, out, err) => {
            if (success && out.includes("Success")) {
                Toaster.toast(qsTr("APK Installed"), qsTr("Successfully installed %1").arg(apkPath.split("/").pop()), "check_circle", Toast.Type.Success);
                fetchApps(deviceId, true);
            } else {
                Toaster.toast(qsTr("Installation Failed"), err || out || qsTr("Could not install APK"), "error", Toast.Type.Error);
            }
        }, deviceId);
    }

    // Wireless ADB & Pairing
    function connectWireless(ip: string, port = "5555"): void {
        if (!ip) return;
        const target = port ? (ip + ":" + port) : ip;
        Toaster.toast(qsTr("Connecting"), qsTr("Connecting to %1...").arg(target), "wifi");
        runAdb(["connect", target], (success, out, err) => {
            if (success && out.includes("connected")) {
                Toaster.toast(qsTr("Connected"), qsTr("Connected to %1 wirelessly").arg(target), "check_circle", Toast.Type.Success);
                scanDevices();
            } else {
                Toaster.toast(qsTr("Connection Failed"), out || err || qsTr("Failed to connect"), "error", Toast.Type.Error);
            }
        });
    }

    function pairWireless(ip: string, port: string, code: string): void {
        if (!ip || !port || !code) {
            Toaster.toast(qsTr("Missing Info"), qsTr("IP, port and 6-digit code are required"), "warning", Toast.Type.Warning);
            return;
        }
        const target = ip + ":" + port;
        Toaster.toast(qsTr("Pairing Device"), qsTr("Pairing with %1...").arg(target), "sync");
        runAdb(["pair", target, code], (success, out, err) => {
            if (success && out.includes("Successfully paired")) {
                Toaster.toast(qsTr("Pairing Succeeded"), qsTr("Successfully paired with %1").arg(target), "check_circle", Toast.Type.Success);
                scanDevices();
            } else {
                Toaster.toast(qsTr("Pairing Failed"), out || err || qsTr("Failed to pair with device"), "error", Toast.Type.Error);
            }
        });
    }

    // QR Code Auto Pairing Workflow
    function startQRPairing(): void {
        stopQRPairing();
        const code = String(Math.floor(100000 + Math.random() * 900000));
        pairingPassword = code;
        qrString = "WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:" + code + ";;";
        isQRPairingActive = true;
        qrPairingStatus = qsTr("Waiting for device to scan QR code...");
        qrPairTimer.restart();
    }

    function stopQRPairing(): void {
        isQRPairingActive = false;
        qrPairingStatus = qsTr("Pairing stopped");
        qrPairTimer.stop();
    }

    function checkMdnsPairing(): void {
        if (!isQRPairingActive || !pairingPassword) return;

        // Use avahi-browse (Linux mDNS) with fallback to adb mdns
        runCommand(["sh", "-c", "avahi-browse -rpt -t _adb-tls-pairing._tcp 2>/dev/null || adb mdns services 2>/dev/null || true"], (success, output) => {
            if (!success || !output) return;
            const lines = output.split("\n");
            for (const line of lines) {
                if (line.startsWith("=") && line.includes("_adb-tls-pairing._tcp")) {
                    const fields = line.split(";");
                    if (fields.length >= 9) {
                        const ip = fields[7];
                        const port = fields[8];
                        if (ip && port && !ip.includes(":")) {
                            qrPairingStatus = qsTr("Found device (%1:%2)! Pairing...").arg(ip).arg(port);
                            pairWireless(ip, port, pairingPassword);
                            stopQRPairing();
                            Qt.callLater(() => autoConnectAfterPair(ip), 2500);
                            break;
                        }
                    }
                } else if (line.includes("_adb-tls-pairing._tcp")) {
                    const parts = line.trim().split(/\s+/);
                    const endpoint = parts.find(p => p.includes(":") && !p.includes("_"));
                    if (endpoint) {
                        const [ip, port] = endpoint.split(":");
                        qrPairingStatus = qsTr("Found device (%1:%2)! Pairing...").arg(ip).arg(port);
                        pairWireless(ip, port, pairingPassword);
                        stopQRPairing();
                        Qt.callLater(() => autoConnectAfterPair(ip), 2500);
                        break;
                    }
                }
            }
        });
    }

    function autoConnectAfterPair(ip: string): void {
        runCommand(["sh", "-c", "avahi-browse -rpt -t _adb-tls-connect._tcp 2>/dev/null | grep \"" + ip + "\" || true"], (success, output) => {
            if (success && output) {
                const lines = output.split("\n");
                for (const line of lines) {
                    if (line.startsWith("=") && line.includes(ip)) {
                        const fields = line.split(";");
                        if (fields.length >= 9) {
                            connectPort = fields[8] || "5555";
                            break;
                        }
                    }
                }
            }
            connectWireless(ip, connectPort);
        });
    }

    function autoDiscoverAndConnect(): void {
        runCommand(["sh", "-c", "avahi-browse -rpt -t _adb-tls-connect._tcp 2>/dev/null || true"], (success, output) => {
            if (!success || !output) return;
            const lines = output.split("\n");
            for (const line of lines) {
                if (line.startsWith("=") && line.includes("_adb-tls-connect._tcp")) {
                    const fields = line.split(";");
                    if (fields.length >= 9) {
                        const ip = fields[7];
                        const port = fields[8];
                        if (ip && port && !ip.includes(":")) {
                            const fullEndpoint = ip + ":" + port;
                            const alreadyConnected = root.devices && root.devices.some(d => d.id === fullEndpoint && d.isConnected);
                            if (!alreadyConnected) {
                                runAdb(["connect", fullEndpoint], (connSuccess, connOut) => {
                                    if (connSuccess && connOut.includes("connected")) {
                                        scanDevices();
                                    }
                                });
                            }
                        }
                    }
                }
            }
        });
    }

    Timer {
        id: qrPairTimer
        interval: 2000
        running: root.isQRPairingActive
        repeat: true
        onTriggered: root.checkMdnsPairing()
    }
    function enableTcpip(port = "5555", deviceId = ""): void {
        runAdb(["tcpip", port], (success, out, err) => {
            if (success) {
                Toaster.toast(qsTr("TCP/IP Enabled"), qsTr("ADB wireless enabled on port %1. You can now disconnect USB and connect via Wi-Fi IP.").arg(port), "wifi", Toast.Type.Success);
            } else {
                Toaster.toast(qsTr("TCP/IP Failed"), err || out || qsTr("Failed to restart in TCP/IP mode"), "error", Toast.Type.Error);
            }
        }, deviceId);
    }

    function disconnect(deviceId = ""): void {
        const targetId = deviceId || (activeDevice ? activeDevice.id : "");
        if (!targetId) return;
        runAdb(["disconnect", targetId], (success) => {
            if (success) {
                Toaster.toast(qsTr("Disconnected"), qsTr("Device %1 disconnected").arg(targetId), "link_off");
                scanDevices();
            }
        });
    }

    // File Explorer
    function browsePath(path = "/sdcard", deviceId = ""): void {
        currentPath = path;
        loadingFiles = true;
        runAdb(["shell", "ls", "-la", path], (success, output) => {
            loadingFiles = false;
            if (!success || !output) {
                root.files = [];
                return;
            }

            const lines = output.split("\n");
            const result = [];
            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed || trimmed.startsWith("total ")) continue;

                const parts = trimmed.split(/\s+/);
                if (parts.length >= 6) {
                    const perms = parts[0];
                    const isDir = perms.startsWith("d");
                    const size = parseInt(parts[4], 10) || 0;
                    const date = parts[5];
                    const name = parts.slice(6).join(" ");

                    if (name === "." || name === "..") continue;

                    const fullPath = path.endsWith("/") ? (path + name) : (path + "/" + name);
                    result.push({
                        name: name,
                        path: fullPath,
                        isDirectory: isDir,
                        size: size,
                        formattedSize: isDir ? "--" : formatBytes(size),
                        date: date,
                        permissions: perms
                    });
                }
            }

            result.sort((a, b) => {
                if (a.isDirectory !== b.isDirectory)
                    return a.isDirectory ? -1 : 1;
                return a.name.localeCompare(b.name);
            });
            root.files = result;
        }, deviceId);
    }

    function pushFile(localPath: string, remotePath: string, deviceId = ""): void {
        Toaster.toast(qsTr("Uploading File"), qsTr("Sending %1 to device...").arg(localPath.split("/").pop()), "upload");
        runAdb(["push", localPath, remotePath], (success, out, err) => {
            if (success) {
                Toaster.toast(qsTr("Upload Complete"), qsTr("File saved to %1").arg(remotePath), "check_circle", Toast.Type.Success);
                browsePath(currentPath, deviceId);
            } else {
                Toaster.toast(qsTr("Upload Failed"), err || out || qsTr("Failed to push file"), "error", Toast.Type.Error);
            }
        }, deviceId);
    }

    function pullFile(remotePath: string, localPath: string, deviceId = ""): void {
        Toaster.toast(qsTr("Downloading File"), qsTr("Downloading %1...").arg(remotePath.split("/").pop()), "download");
        runAdb(["pull", remotePath, localPath], (success, out, err) => {
            if (success) {
                Toaster.toast(qsTr("Download Complete"), qsTr("File saved to %1").arg(localPath), "check_circle", Toast.Type.Success);
            } else {
                Toaster.toast(qsTr("Download Failed"), err || out || qsTr("Failed to pull file"), "error", Toast.Type.Error);
            }
        }, deviceId);
    }

    function deleteFile(remotePath: string, deviceId = ""): void {
        runAdb(["shell", "rm", "-rf", remotePath], (success, out, err) => {
            if (success) {
                Toaster.toast(qsTr("Deleted"), qsTr("Removed %1").arg(remotePath.split("/").pop()), "delete");
                browsePath(currentPath, deviceId);
            } else {
                Toaster.toast(qsTr("Delete Failed"), err || out || qsTr("Failed to delete"), "error", Toast.Type.Error);
            }
        }, deviceId);
    }

    function createDirectory(remotePath: string, deviceId = ""): void {
        runAdb(["shell", "mkdir", "-p", remotePath], (success) => {
            if (success) {
                Toaster.toast(qsTr("Created Folder"), qsTr("Folder created"), "create_new_folder");
                browsePath(currentPath, deviceId);
            }
        }, deviceId);
    }

    function formatBytes(bytes: real): string {
        if (bytes === 0) return "0 B";
        const k = 1024;
        const sizes = ["B", "KB", "MB", "GB", "TB"];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
    }

    // Terminal & Shell Execution
    function openTerminal(deviceId = ""): void {
        const targetId = deviceId || (activeDevice ? activeDevice.id : "");
        const termCmd = [...GlobalConfig.general.apps.terminal, Quickshell.shellDir + "/assets/wrap_term_launch.sh", adbPath];
        if (targetId) termCmd.push("-s", targetId);
        termCmd.push("shell");

        Quickshell.execDetached(termCmd);
        Toaster.toast(qsTr("Terminal Launched"), qsTr("ADB shell opened in terminal"), "terminal");
    }

    function openLogcat(deviceId = ""): void {
        const targetId = deviceId || (activeDevice ? activeDevice.id : "");
        const termCmd = [...GlobalConfig.general.apps.terminal, Quickshell.shellDir + "/assets/wrap_term_launch.sh", adbPath];
        if (targetId) termCmd.push("-s", targetId);
        termCmd.push("logcat", "-v", "color");

        Quickshell.execDetached(termCmd);
        Toaster.toast(qsTr("Logcat Launched"), qsTr("ADB logcat stream opened in terminal"), "receipt_long");
    }

    function connectPrevious(serial: string): void {
        if (!serial) return;
        connectingDeviceId = serial;
        Toaster.toast(qsTr("Reconnecting"), qsTr("Connecting to %1...").arg(serial), "sync");
        runAdb(["connect", serial], (success, out, err) => {
            connectingDeviceId = "";
            if (success && out.includes("connected")) {
                Toaster.toast(qsTr("Connected"), qsTr("Reconnected to %1").arg(serial), "check_circle", Toast.Type.Success);
                scanDevices();
            } else {
                Toaster.toast(qsTr("Connection Failed"), out || err || qsTr("Failed to connect"), "error", Toast.Type.Error);
            }
        });
    }

    function executeShell(command: string, callback = null, deviceId = ""): void {
        runAdb(["shell", command], callback, deviceId);
    }

    function addCustomCommand(name: string, cmd: string, isBg = false): void {
        const list = [...customCommands, {
            id: String(Date.now()),
            name: name,
            command: cmd,
            isBackground: isBg
        }];
        customCommands = list;
    }

    function removeCustomCommand(id: string): void {
        customCommands = customCommands.filter(c => c.id !== id);
    }

    // Clipboard Sync
    function syncHostToDevice(text: string, deviceId = ""): void {
        if (!text) return;
        // Escape quotes
        const escaped = text.replace(/'/g, "'\\''");
        runAdb(["shell", "am broadcast -a ch.pete.adbclipboard.set -e text '" + escaped + "' || input text '" + escaped + "'"], (success) => {
            if (success) {
                Toaster.toast(qsTr("Clipboard Synced"), qsTr("Sent text to Android clipboard"), "content_paste", Toast.Type.Success);
            }
        }, deviceId);
    }

    function syncDeviceToHost(deviceId = ""): void {
        runAdb(["shell", "am broadcast -a ch.pete.adbclipboard.get"], (success, out) => {
            if (success && out) {
                Toaster.toast(qsTr("Clipboard Retrieved"), out, "content_copy");
            }
        }, deviceId);
    }

    // AVD Emulator Controls
    function fetchAvds(): void {
        loadingAvds = true;
        runCommand(["sh", "-c", "which emulator 2>/dev/null && emulator -list-avds || true"], (success, output) => {
            loadingAvds = false;
            if (!success || !output) {
                root.avds = [];
                return;
            }
            const lines = output.split("\n");
            const result = [];
            for (const line of lines) {
                const name = line.trim();
                if (!name) continue;
                const isRunning = root.devices && root.devices.some(d => d.isEmulator && d.name.includes(name));
                result.push({
                    name: name,
                    isRunning: isRunning
                });
            }
            root.avds = result;
        });
    }

    function startAvd(name: string): void {
        Toaster.toast(qsTr("Starting Emulator"), qsTr("Launching %1...").arg(name), "phone_android");
        Quickshell.execDetached(["emulator", "-avd", name]);
        Qt.callLater(() => scanDevices(), 3000);
    }

    // Initialization & Polling
    Component.onCompleted: {
        checkPaths();
        startQRPairing();
    }

    Timer {
        id: pollTimer
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            if (root.adbPath.length > 0) {
                root.scanDevices();
                if (!root.hasConnectedDevice) {
                    root.autoDiscoverAndConnect();
                }
            } else {
                root.checkPaths();
            }
        }
    }

    // IPC Handler for CLI
    IpcHandler {
        target: "androlaunch"

        function isAvailable(): bool {
            return root.available;
        }

        function listDevices(): string {
            return JSON.stringify(root.devices);
        }

        function getActiveDevice(): string {
            return JSON.stringify(root.activeDevice);
        }

        function scan(): void {
            root.scanDevices();
        }

        function select(id: string): void {
            root.selectDevice(id);
        }

        function mirror(): void {
            root.startMirroring();
        }

        function camera(): void {
            root.startCameraMirroring();
        }
        function launchApp(pkg: string): void {
            root.startAppMirroring(pkg);
        }

        function launchOnDevice(pkg: string): void {
            root.launchApp(pkg);
        }
        function reboot(mode: string): void {
            root.reboot(mode);
        }

        function toggle(action: string): void {
            if (action === "wifi") root.toggleWifi(!root.activeDevice?.quickActions?.wifi);
            else if (action === "bluetooth") root.toggleBluetooth(!root.activeDevice?.quickActions?.bluetooth);
            else if (action === "darkmode") root.toggleDarkMode(!root.activeDevice?.quickActions?.darkMode);
            else if (action === "airplane") root.toggleAirplaneMode(!root.activeDevice?.quickActions?.airplaneMode);
            else if (action === "data") root.toggleMobileData(!root.activeDevice?.quickActions?.mobileData);
            else if (action === "location") root.toggleLocation(!root.activeDevice?.quickActions?.location);
            else if (action === "dnd") root.toggleDnd(!root.activeDevice?.quickActions?.dnd);
            else if (action === "rotate") root.toggleAutoRotate(!root.activeDevice?.quickActions?.autoRotate);
        }

        function connect(ip: string, port: string): void {
            root.connectWireless(ip, port);
        }

        function openTerminal(): void {
            root.openTerminal();
        }
    }
}
