//
//  main.swift
//  CoreLogicTests
//
//  Plain-executable tests for the Foundation-only continuity layer. There is no
//  XCTest target in this project yet, so these compile straight against the app
//  sources with swiftc (see scripts/test-macos-logic.sh).
//

import Foundation

var failures = 0
var checks = 0

func expect(_ condition: Bool, _ message: String, line: UInt = #line) {
    checks += 1
    if condition {
        print("  ok    \(message)")
    } else {
        failures += 1
        print("  FAIL  \(message)  (line \(line))")
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("\n\(name)")
    body()
}

func freshDefaults(_ label: String) -> UserDefaults {
    let name = "com.senpai.AndroLaunch.tests.\(label).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

// MARK: - Transport classification

suite("TransportKind.classify") {
    expect(TransportKind.classify("R58M12345AB") == .usb, "USB serial is usb")
    expect(TransportKind.classify("emulator-5554") == .usb, "emulator is usb")
    expect(TransportKind.classify("192.168.1.5:5555") == .wireless, "LAN address is wireless")
    expect(TransportKind.classify("100.64.0.7:5555") == .wireless, "VPN address is wireless")
    expect(TransportKind.classify("phone.local:5555") == .wireless, "hostname:port is wireless")
    expect(
        TransportKind.classify("adb-R58M12345-xyzw._adb-tls-connect._tcp") == .mdns,
        "Bonjour service is mdns")
    expect(TransportKind.isHostAndPort("192.168.1.5:notaport") == false, "non-numeric port rejected")
    expect(TransportKind.isHostAndPort(":5555") == false, "empty host rejected")
    expect(TransportKind.classify("192.168.1.5:5555").isWireless, "wireless is wireless")
    expect(!TransportKind.classify("R58M12345AB").isWireless, "usb is not wireless")
}

suite("TransportKind.raceRank") {
    expect(TransportKind.usb.raceRank < TransportKind.mdns.raceRank, "usb before bonjour")
    expect(TransportKind.mdns.raceRank < TransportKind.wireless.raceRank, "bonjour before stored IP")
    expect(TransportKind.wireless.raceRank < TransportKind.manual.raceRank, "stored IP before manual")
}

suite("AndroidDevice.stableID") {
    let usb = AndroidDevice(id: "R58M12345AB", name: "Pixel", isConnected: true, serialNumber: "R58M12345AB")
    let wifi = AndroidDevice(id: "192.168.1.5:5555", name: "Pixel", isConnected: true, serialNumber: "R58M12345AB")
    expect(usb.stableID == wifi.stableID, "same phone keeps one identity across transports")
    expect(usb.stableID == "R58M12345AB", "identity is the hardware serial")
    let unknown = AndroidDevice(id: "192.168.1.9:5555", name: "Unknown", isConnected: true)
    expect(unknown.stableID == "192.168.1.9:5555", "falls back to transport ID")
    expect(wifi.isWirelessTransport && !usb.isWirelessTransport, "transport detection")
}

// MARK: - Device scoped preferences

suite("DeviceScopedPreferences") {
    let defaults = freshDefaults("prefs")
    let prefs = DeviceScopedPreferences(defaults: defaults)

    expect(prefs.integer("maxSize", for: "SERIAL", default: 0) == 0, "missing int returns fallback")
    expect(prefs.bool("clipboard", for: "SERIAL", default: false) == false, "missing bool returns fallback")
    expect(prefs.string("cameraFacing", for: "SERIAL", default: "Auto") == "Auto", "missing string returns fallback")

    prefs.setInteger(1024, "maxSize", for: "SERIAL")
    prefs.setBool(true, "clipboard", for: "SERIAL")
    prefs.setString("back", "cameraFacing", for: "SERIAL")
    expect(prefs.integer("maxSize", for: "SERIAL", default: 0) == 1024, "int round-trips")
    expect(prefs.bool("clipboard", for: "SERIAL", default: false) == true, "bool round-trips")
    expect(prefs.string("cameraFacing", for: "SERIAL", default: "Auto") == "back", "string round-trips")
    expect(prefs.integer("maxSize", for: "OTHER", default: 0) == 0, "values are per identity")

    prefs.setBool(false, "clipboard", for: "SERIAL")
    expect(prefs.bool("clipboard", for: "SERIAL", default: true) == false, "false is stored, not treated as missing")

    prefs.register(transportID: "192.168.1.5:5555", identity: "SERIAL")
    expect(
        prefs.identity(forTransportID: "192.168.1.5:5555") == "SERIAL",
        "transport resolves to identity")
    expect(
        prefs.identity(forTransportID: "unseen") == "unseen",
        "unknown transport stays itself")
}

suite("DeviceScopedPreferences legacy migration") {
    let defaults = freshDefaults("migration")
    // Old layout: one dictionary per preference, keyed by the transport ID.
    defaults.set(["192.168.1.5:5555": 1024], forKey: "mirror_max_size")
    defaults.set(["192.168.1.5:5555": true], forKey: "mirror_flex_display")
    defaults.set(["192.168.1.5:5555": 30], forKey: "mirror_max_fps")

    let prefs = DeviceScopedPreferences(defaults: defaults)
    prefs.register(transportID: "192.168.1.5:5555", identity: "R58M12345AB")
    prefs.migrateLegacyDictionaries()

    expect(prefs.integer("maxSize", for: "R58M12345AB", default: 0) == 1024, "maxSize migrates to serial")
    expect(prefs.bool("flexDisplay", for: "R58M12345AB", default: false) == true, "flexDisplay migrates")
    expect(prefs.integer("maxFPS", for: "R58M12345AB", default: 0) == 30, "maxFPS migrates")

    // A newer value must never be clobbered by the migration.
    prefs.setInteger(2048, "maxSize", for: "R58M12345AB")
    prefs.migrateLegacyDictionaries()
    expect(prefs.integer("maxSize", for: "R58M12345AB", default: 0) == 2048, "migration never overwrites")
}

// MARK: - Endpoint store

suite("EndpointStore") {
    let defaults = freshDefaults("endpoints")
    let store = EndpointStore(defaults: defaults)
    let identity = "R58M12345AB"

    expect(store.endpoints(for: identity).isEmpty, "starts empty")

    store.upsert(DeviceEndpoint(address: "192.168.1.5:5555"), for: identity)
    expect(store.endpoints(for: identity).count == 1, "upsert inserts")

    store.recordSuccess(address: "192.168.1.5:5555", for: identity)
    store.recordSuccess(address: "192.168.1.5:5555", for: identity)
    expect(
        store.endpoint(address: "192.168.1.5:5555", for: identity)?.successfulConnections == 2,
        "successes accumulate")

    store.recordFailure(address: "192.168.1.5:5555", for: identity)
    expect(
        store.endpoint(address: "192.168.1.5:5555", for: identity)?.failedAttempts == 1,
        "failures accumulate")

    store.recordSuccess(address: "192.168.1.5:5555", for: identity)
    expect(
        store.endpoint(address: "192.168.1.5:5555", for: identity)?.failedAttempts == 0,
        "a success clears the failure count")

    store.upsert(DeviceEndpoint(address: "R58M12345AB"), for: identity)
    let candidates = store.candidates(for: identity)
    expect(candidates.first?.address == "R58M12345AB", "usb is raced first")
    expect(candidates.count == 2, "both endpoints are candidates")

    // Repeatedly failing endpoints age out of the race list.
    let stale = DeviceEndpoint(
        address: "10.0.0.9:5555",
        lastSeen: Date().addingTimeInterval(-60 * 60 * 48),
        successfulConnections: 2,
        failedAttempts: 4)
    store.upsert(stale, for: identity)
    expect(
        store.candidates(for: identity).contains { $0.address == "10.0.0.9:5555" } == false,
        "stale repeatedly-failing endpoint is dropped")
    expect(
        store.endpoints(for: identity).contains { $0.address == "10.0.0.9:5555" },
        "stale endpoint is still remembered")

    store.migrate(legacyHost: "192.168.1.44:5555", for: identity)
    expect(
        store.endpoints(for: identity).contains { $0.address == "192.168.1.44:5555" },
        "legacy host is imported")
    store.migrate(legacyHost: "192.168.1.44:5555", for: identity)
    expect(
        store.endpoints(for: identity).filter { $0.address == "192.168.1.44:5555" }.count == 1,
        "legacy migration is idempotent")

    store.remove(address: "192.168.1.44:5555", for: identity)
    expect(
        store.endpoints(for: identity).contains { $0.address == "192.168.1.44:5555" } == false,
        "remove deletes an endpoint")

    // Persistence survives a new store instance over the same defaults.
    let reopened = EndpointStore(defaults: defaults)
    expect(reopened.endpoints(for: identity).count == store.endpoints(for: identity).count, "store persists")
}

runNotificationParserTests()
runSDKToolsDetectionTests()
runMCPLogicTests()
runPhoneLogicTests()
runConnectionLogicTests()
runAppsLogicTests()
runPlatformLogicTests()
runDashboardLogicTests()
runMirrorControlsLogicTests()
runStorageLogicTests()
runAppIconLogicTests()
runStoragePermissionLogicTests()
runMenuBarPanelLogicTests()
runNotificationGroupingLogicTests()

// MARK: - Result

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("FAILED: \(failures)")
    exit(1)
}
print("OK")
