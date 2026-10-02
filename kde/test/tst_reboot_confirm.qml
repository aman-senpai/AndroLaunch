/*
 * Guards the Device tab power buttons: a single click must never reboot the
 * device, because bootloader/recovery cost the session (and, on locked devices,
 * the ADB authorization) and there is no undo. The mode is buffered and only
 * `backend.reboot()` after an explicit confirmation may reach the helper.
 *
 *   QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_reboot_confirm.qml
 */
import QtQuick
import QtTest

TestCase {
    id: testCase

    name: "AndroLaunchRebootConfirm"
    when: true

    // Every reboot() that reaches the backend, in order.
    readonly property var recorder: QtObject {
        property var calls: []
    }

    readonly property var backend: QtObject {
        property bool hasDevice: true
        property string activeId: "PIXEL8"
        property var uiDevices: []
        property var activeDevice: ({ "name": "Pixel 8", "model": "Pixel 8", "android": "15", "id": "PIXEL8" })
        property var quick: ({})
        property var effectiveQuick: ({})
        property var mirrors: []
        property int activeBattery: -1
        property bool activeCharging: false
        property int connectedCount: 0
        property var previous: []

        function reboot(mode) { recorder.calls.push(mode); }
        function refresh() {}
        function selectDevice() {}
        function toggle() {}
        function setBrightness() {}
        function setVolume() {}
        function mirror() {}
        function camera() {}
        function stopMirror() {}
        function stopMirrors() {}
        function openTerminal() {}
        function openLogcat() {}
        function disconnectDevice() {}
        function connectPrevious() {}
    }

    property var tab: null
    property var buttonsRow: null
    property var confirmRow: null

    // Depth-first search for the item carrying `name` as its objectName.
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

    // Depth-first search for the clickable item carrying `label`.
    function findClickable(item, label) {
        for (let i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if (child.hasOwnProperty("text") && child.text === label
                && typeof child.clicked === "function")
                return child;
            const nested = findClickable(child, label);
            if (nested)
                return nested;
        }
        return null;
    }

    // The power buttons and the confirmation row are mutually exclusive, so the
    // target is addressed through its row rather than by text alone.
    function clickPower(label) {
        const button = findClickable(buttonsRow, label);
        verify(button !== null, "found power button: " + label);
        button.clicked();
        wait(20);
    }

    function clickConfirm(label) {
        const button = findClickable(confirmRow, label);
        verify(button !== null, "found confirmation button: " + label);
        button.clicked();
        wait(20);
    }

    function init() {
        recorder.calls = [];
        backend.hasDevice = true;
        backend.activeId = "PIXEL8";
        backend.activeDevice = { "name": "Pixel 8", "model": "Pixel 8", "android": "15", "id": "PIXEL8" };

        const component = Qt.createComponent(Qt.resolvedUrl("../plasma/contents/ui/QuickTab.qml"));
        verify(component.status === Component.Ready, "QuickTab loads: " + component.errorString());
        tab = component.createObject(null, {
            "backend": backend,
            "width": 400,
            "height": 800
        });
        verify(tab !== null, "QuickTab created");
        wait(20);

        buttonsRow = findByName(tab, "rebootButtons");
        confirmRow = findByName(tab, "rebootConfirm");
        verify(buttonsRow !== null, "power button row present");
        verify(confirmRow !== null, "confirmation row present");
    }

    function cleanup() {
        if (tab) {
            tab.destroy();
            tab = null;
        }
    }

    function test_click_buffers_mode_without_rebooting() {
        compare(buttonsRow.visible, true, "power buttons shown first");
        compare(confirmRow.visible, false, "confirmation hidden first");

        clickPower("Bootloader");
        compare(recorder.calls.length, 0, "bootloader click fires nothing");
        compare(tab.pendingReboot, "bootloader", "mode buffered");
        compare(tab.rebootConfirmationText, "Reboot Pixel 8 into bootloader?", "confirmation names the device and mode");
        compare(buttonsRow.visible, false, "power buttons yield to the confirmation");
        compare(confirmRow.visible, true, "confirmation shown");

        clickConfirm("Cancel");
        compare(recorder.calls.length, 0, "cancel fires nothing");
        compare(tab.pendingReboot, "", "cancel clears the buffer");
        compare(confirmRow.visible, false, "confirmation dismissed");
    }

    function test_confirmation_reboots_into_selected_mode() {
        clickPower("Recovery");
        clickConfirm("Reboot");
        compare(recorder.calls.length, 1, "confirmation fires once");
        compare(recorder.calls[0], "recovery", "fires the buffered mode");
        compare(tab.pendingReboot, "", "buffer cleared after firing");

        // A second confirmation must need a fresh first click.
        clickPower("Recovery");
        clickConfirm("Cancel");
        compare(recorder.calls.length, 1, "cancel does not fire a second reboot");
    }

    function test_normal_mode_restarts_android() {
        clickPower("Reboot");
        compare(tab.rebootConfirmationText, "Restart Android on Pixel 8?", "normal mode wording");
        compare(tab.rebootIsDestructive, false, "plain restart is not destructive");
        clickConfirm("Reboot");
        compare(recorder.calls[0], "normal", "system reboot still fires normal");
    }

    function test_destructive_modes_are_flagged() {
        clickPower("Bootloader");
        compare(tab.rebootIsDestructive, true, "bootloader is destructive");
        clickConfirm("Cancel");
        clickPower("Recovery");
        compare(tab.rebootIsDestructive, true, "recovery is destructive");
    }

    function test_wording_falls_back_without_device_name() {
        backend.activeDevice = null;
        wait(20);
        clickPower("Bootloader");
        compare(tab.rebootConfirmationText, "Reboot into bootloader?", "fallback wording");
    }

    function test_pending_confirmation_is_dropped_on_disconnect() {
        clickPower("Bootloader");
        compare(tab.pendingReboot, "bootloader", "buffered while connected");
        backend.hasDevice = false;
        wait(20);
        compare(tab.pendingReboot, "", "disconnect clears the buffer");
    }

    function test_pending_confirmation_is_dropped_on_device_switch() {
        clickPower("Recovery");
        backend.activeId = "OTHER";
        backend.activeDevice = { "name": "Other phone", "id": "OTHER" };
        wait(20);
        compare(tab.pendingReboot, "", "switch clears the buffer");
        compare(recorder.calls.length, 0, "nothing rebooted during the switch");
    }
}
