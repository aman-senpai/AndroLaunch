/*
 * Guards the Device tab toggle tiles. The tile must never claim a state the
 * device did not report: it shows the requested state only until the poll
 * echoes it back, and drops that optimistic state after `pendingTimeout` so a
 * failed `svc` call cannot leave a toggle lying.
 *
 *   QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_toggle_chip.qml
 */
import QtQuick
import QtQuick.Window
import QtTest

TestCase {
    id: testCase

    name: "AndroLaunchToggleChip"
    when: true

    // Requests emitted by the tile, in order.
    readonly property var recorder: QtObject {
        property var requests: []
    }

    property var chip: null
    property var button: null

    function findButton(item) {
        for (let i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if (typeof child.clicked === "function" && child.hasOwnProperty("text"))
                return child;
            const nested = findButton(child);
            if (nested)
                return nested;
        }
        return null;
    }

    function init() {
        recorder.requests = [];
        const component = Qt.createComponent(Qt.resolvedUrl("../plasma/contents/ui/components/ToggleChip.qml"));
        verify(component.status === Component.Ready, "ToggleChip loads: " + component.errorString());
        chip = component.createObject(null, {
            "iconName": "network-wireless",
            "label": "Wi-Fi",
            "pendingTimeout": 200
        });
        verify(chip !== null, "chip created");
        chip.toggled.connect(requested => recorder.requests.push(requested));
        button = findButton(chip);
        verify(button !== null, "tile click surface found");
        wait(20);
    }

    function cleanup() {
        if (chip) {
            chip.destroy();
            chip = null;
        }
    }

    function test_click_requests_inverse_and_shows_it_immediately() {
        compare(chip.active, false, "starts off");
        compare(chip.shownState, false, "starts showing the device state");

        button.clicked();
        compare(recorder.requests, [true], "requests the inverse state");
        compare(chip.active, false, "does not touch the device state itself");
        compare(chip.shownState, true, "shows the request straight away");
        compare(chip.pending, true, "request is still unconfirmed");
    }

    function test_device_echo_confirms_and_stops_optimism() {
        button.clicked();
        chip.active = true;
        wait(20);
        compare(chip.pending, false, "echo retires the optimistic state");
        compare(chip.shownState, true, "keeps showing the confirmed state");
    }

    function test_failed_toggle_snaps_back_after_timeout() {
        button.clicked();
        compare(chip.shownState, true, "optimistic while unconfirmed");
        tryVerify(function () { return !chip.pending; }, 3000, "optimism expires");
        compare(chip.shownState, false, "falls back to the device state");
        compare(chip.active, false, "device state untouched");
    }

    function test_pending_request_follows_the_last_click() {
        button.clicked();
        compare(chip.pendingValue, true, "first click asks for on");
        button.clicked();
        compare(recorder.requests, [true, false], "second click asks for off");
        compare(chip.pendingValue, false, "optimism follows the newest request");
    }
}
