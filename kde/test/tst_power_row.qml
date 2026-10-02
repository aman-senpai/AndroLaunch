/*
 * Guards the Device tab power row. Plasma's own button content left-aligns the
 * label whenever an icon is visible, so the three wide buttons used to look
 * ragged: equal thirds, but every icon + label pair hugging the left edge of its
 * own third. This pins the centred layout instead.
 *
 *   QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_power_row.qml
 */
import QtQuick
import QtQuick.Window
import QtTest
import org.kde.kirigami as Kirigami

TestCase {
    id: testCase

    name: "AndroLaunchPowerRow"
    when: true

    Window {
        id: win
        visible: true
        width: 620
        height: 700
        color: Kirigami.Theme.backgroundColor
    }

    readonly property var backend: QtObject {
        property bool hasDevice: true
        property string activeId: "dev"
        property var uiDevices: []
        property var activeDevice: null
        property var quick: ({})
        property var effectiveQuick: ({})
        property var mirrors: []
        property int activeBattery: -1
        property bool activeCharging: false
        property int connectedCount: 1
        property bool busy: false
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
    }

    property var tab: null
    property var buttons: []

    function collect(item, parent) {
        if (item.hasOwnProperty("text") && typeof item.clicked === "function"
            && parent && parent.objectName === "rebootButtons")
            buttons.push(item);
        for (let i = 0; i < item.children.length; ++i)
            collect(item.children[i], item);
    }

    // The button's own icon + label, i.e. the pieces that have to sit in the
    // middle. Only the content subtree is walked: the background fills the button
    // by definition, so it would measure as centred whatever the layout does.
    function collectContent(item, out) {
        const isIcon = item.toString().indexOf("Icon") !== -1 && item.hasOwnProperty("source");
        const isLabel = item.hasOwnProperty("font") && typeof item.text === "string" && item.text !== "";
        if (isIcon || isLabel)
            out.push(item);
        for (let i = 0; i < item.children.length; ++i)
            collectContent(item.children[i], out);
    }

    // left and right gap of a button's icon + label group, in button coordinates
    function gaps(button) {
        const content = [];
        collectContent(button.contentItem, content);
        if (content.length === 0)
            return null;
        let left = Infinity;
        let right = -Infinity;
        for (let i = 0; i < content.length; ++i) {
            const x = content[i].mapToItem(button, 0, 0).x;
            left = Math.min(left, x);
            right = Math.max(right, x + content[i].width);
        }
        return { "left": left, "right": button.width - right };
    }

    function init() {
        const component = Qt.createComponent(Qt.resolvedUrl("../plasma/contents/ui/QuickTab.qml"));
        verify(component.status === Component.Ready, "QuickTab loads: " + component.errorString());
        tab = component.createObject(win.contentItem, { "x": 0, "y": 0, "width": 600, "height": 660, "backend": backend });
        verify(tab !== null, "QuickTab created");
        wait(400);

        buttons = [];
        collect(tab, null);
        compare(buttons.length, 3, "three power buttons");
    }

    function cleanup() {
        if (tab) {
            tab.destroy();
            tab = null;
        }
    }

    function test_buttons_share_the_row_equally() {
        const widths = buttons.map(b => b.width);
        verify(Math.abs(widths[0] - widths[1]) <= 1 && Math.abs(widths[1] - widths[2]) <= 1,
            "equal thirds, got " + widths.join("/"));
    }

    function test_icon_and_label_are_centred_in_each_button() {
        for (let i = 0; i < buttons.length; ++i) {
            const button = buttons[i];
            const gap = gaps(button);
            verify(gap !== null, "icon + label found in " + button.text);
            verify(Math.abs(gap.left - gap.right) <= 2,
                button.text + " is centred (left=" + Math.round(gap.left) + " right=" + Math.round(gap.right) + ")");
        }
    }
}
