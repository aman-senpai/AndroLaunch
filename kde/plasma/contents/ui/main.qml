import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Backend {
        id: backendItem

        plasmoidItem: root
        helperPath: plasmoid.configuration.helperPath
        pollInterval: Math.max(2, plasmoid.configuration.pollInterval) * 1000
        mirrorOptions: ({
            newDisplay: plasmoid.configuration.newDisplay,
            flexDisplay: plasmoid.configuration.flexDisplay,
            audio: plasmoid.configuration.audio,
            stayAwake: plasmoid.configuration.stayAwake,
            aspectRatioLock: plasmoid.configuration.aspectRatioLock,
            borderless: plasmoid.configuration.borderless,
            maxFps: plasmoid.configuration.maxFps,
            bitRate: plasmoid.configuration.bitRate,
            maxSize: plasmoid.configuration.maxSize,
            cameraFacing: plasmoid.configuration.cameraFacing,
            cameraTorch: plasmoid.configuration.cameraTorch,
            cameraZoom: plasmoid.configuration.cameraZoom
        })
    }

    compactRepresentation: CompactRepresentation {
        backend: backendItem
        plasmoidItem: root
    }

    fullRepresentation: FullRepresentation {
        backend: backendItem
    }

    preferredRepresentation: compactRepresentation
    preloadFullRepresentation: false

    toolTipMainText: "AndroLaunch"
    toolTipSubText: {
        if (!backendItem.helperReady)
            return backendItem.helperError || "Backend not available";
        if (backendItem.adbMissing)
            return "adb not installed (sudo dnf install android-tools scrcpy)";
        const device = backendItem.activeDevice;
        if (!device)
            return backendItem.devices.length === 0 ? "No device connected" : "No device selected";
        const parts = [device.name || device.id];
        if (device.connected)
            parts.push(device.wireless ? "Wi-Fi" : "USB");
        if (backendItem.activeBattery >= 0)
            parts.push(backendItem.activeBattery + "%" + (backendItem.activeCharging ? " ⚡" : ""));
        if (device.android)
            parts.push("Android " + device.android);
        return parts.join(" • ");
    }
}
