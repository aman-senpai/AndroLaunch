.pragma library

// Themed icon name for an Android battery level (Breeze ships 10% steps).
function batteryIcon(level, charging) {
    if (level === undefined || level === null || level < 0)
        return charging ? "battery-100-charging" : "";
    var step = Math.max(0, Math.min(10, Math.round(level / 10))) * 10;
    var name = "battery-" + ("00" + step).slice(-3);
    return charging ? name + "-charging" : name;
}

function deviceIcon(device) {
    if (!device)
        return "smartphone";
    if (device.emulator)
        return "computer";
    if (device.wireless)
        return "network-wireless";
    return "smartphone";
}

function statusLabel(device) {
    if (!device)
        return "No device";
    if (device.connected)
        return device.wireless ? "Wi-Fi" : "USB";
    if (device.status === "unauthorized")
        return "Unauthorized";
    if (device.status === "offline")
        return "Offline";
    return device.status || "Unknown";
}

function formatBytes(bytes) {
    if (!bytes || bytes <= 0)
        return "0 B";
    var units = ["B", "KB", "MB", "GB", "TB"];
    var index = 0;
    var value = bytes;
    while (value >= 1024 && index < units.length - 1) {
        value = value / 1024;
        index += 1;
    }
    return value.toFixed(value < 10 && index > 0 ? 1 : 0) + " " + units[index];
}

function shortLabel(text, max) {
    if (!text)
        return "";
    var limit = max || 28;
    return text.length > limit ? text.slice(0, limit - 1) + "…" : text;
}

function parentPath(path) {
    if (!path || path === "/" || path === "/sdcard" || path === "/sdcard/")
        return "/sdcard";
    var trimmed = path.replace(/\/+$/, "");
    var index = trimmed.lastIndexOf("/");
    if (index <= 0)
        return "/sdcard";
    var parent = trimmed.slice(0, index);
    return parent.length ? parent : "/sdcard";
}
