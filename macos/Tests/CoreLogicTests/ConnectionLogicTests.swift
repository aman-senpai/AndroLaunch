//
//  ConnectionLogicTests.swift
//  CoreLogicTests
//
//  Pure-logic rules for the Wi-Fi connection surfaces: address validation,
//  pairing-code shape, the QR payload Android expects, interpretation of adb's
//  text responses, and the `adb devices -l` transport parser.
//
//  Run through `scripts/test-macos-logic.sh` together with
//  `WirelessConnectionLogic.swift`; every assertion here is Foundation-only.
//

import Foundation

func runConnectionLogicTests() {

    // MARK: - Wireless addresses

    suite("WirelessEndpoint.parse accepts IPv4") {
        expect(parse("192.168.1.23:5555")?.displayValue == "192.168.1.23:5555", "LAN IPv4")
        expect(parse("10.0.0.2:1")?.displayValue == "10.0.0.2:1", "lowest valid port")
        expect(parse("255.255.255.255:65535")?.displayValue == "255.255.255.255:65535", "highest port")
        expect(parse("127.0.0.1:5555")?.displayValue == "127.0.0.1:5555", "loopback IPv4")
        expect(parse("192.168.1.23:5555")?.host == "192.168.1.23", "host is preserved")
        expect(parse("192.168.1.23:5555")?.port == 5555, "port is preserved")
        expect(parse("  192.168.1.23:5555\n")?.displayValue == "192.168.1.23:5555", "outer whitespace is trimmed")
        expect(WirelessEndpoint.isValid("192.168.1.23:5555"), "isValid mirrors parse")
    }

    suite("WirelessEndpoint.parse accepts bracketed IPv6") {
        expect(parse("[2001:db8::1]:5555")?.displayValue == "[2001:db8::1]:5555", "global IPv6")
        expect(parse("[::1]:5555")?.displayValue == "[::1]:5555", "loopback IPv6")
        expect(parse("[FE80::1]:5555")?.displayValue == "[FE80::1]:5555", "uppercase IPv6 is preserved")
        expect(parse("[fe80::1%en0]:5555")?.displayValue == "[fe80::1%en0]:5555", "scoped link-local IPv6")
        expect(parse("[2001:db8::1]:5555")?.isIPv6 == true, "IPv6 flag")
        expect(parse("192.168.1.23:5555")?.isIPv6 == false, "IPv4 is not IPv6")
    }

    suite("WirelessEndpoint.parse rejects bad input") {
        expect(failure("") == .empty, "empty string")
        expect(failure("   ") == .empty, "whitespace only")
        expect(failure("192.168.1.23") == .portRequired, "missing port")
        expect(failure("192.168.1.23:") == .portRequired, "empty port")
        expect(failure("192.168.1.23:0") == .invalidPort, "port zero")
        expect(failure("192.168.1.23:65536") == .invalidPort, "port too large")
        expect(failure("192.168.1.23:abc") == .invalidPort, "non-numeric port")
        expect(failure("192.168.1.23:55 55") == .unsupported, "space inside address")
        expect(failure("999.1.1.1:5555") == .invalidIPv4, "invalid IPv4 octet")
        expect(failure("192.168.1:5555") == .invalidIPv4, "short IPv4")
        expect(failure("phone.local:5555") == .unsupported, "hostname is rejected intentionally")
        expect(failure("2001:db8::1:5555") == .invalidIPv6, "bare IPv6 with port needs brackets")
        expect(failure("[192.168.1.1]:5555") == .invalidIPv6, "IPv4 in brackets is rejected")
        expect(failure("[2001:db8::1]") == .portRequired, "bracketed IPv6 without port")
        expect(failure("[2001:db8::1]:0") == .invalidPort, "bracketed IPv6 with port zero")
        expect(failure("[::1") == .invalidIPv6, "unterminated bracket")
        expect(!WirelessEndpoint.isValid("not-an-address"), "isValid mirrors failures")
    }

    suite("WirelessEndpoint error copy") {
        expect(WirelessEndpoint.AddressError.empty.message == "Enter an address.", "empty copy")
        expect(
            WirelessEndpoint.AddressError.invalidIPv6.message
                == "Enter IPv6 addresses as [address]:port.",
            "IPv6 copy explains brackets")
        expect(
            WirelessEndpoint.AddressError.unsupported.guidance?.contains("Hostnames") == true,
            "hostname rejection is explained")
        expect(WirelessEndpoint.AddressError.invalidPort.guidance != nil, "port error has guidance")
    }

    // MARK: - Pairing codes

    suite("WirelessPairingCode") {
        expect(WirelessPairingCode.isValid("123456"), "six digits")
        expect(WirelessPairingCode.isValid(" 123456 "), "surrounding whitespace is tolerated")
        expect(WirelessPairingCode.isValid("000000"), "leading zeros are digits")
        expect(!WirelessPairingCode.isValid("12345"), "five digits rejected")
        expect(!WirelessPairingCode.isValid("1234567"), "seven digits rejected")
        expect(!WirelessPairingCode.isValid("12 456"), "internal space rejected")
        expect(!WirelessPairingCode.isValid("abcdef"), "letters rejected")
        expect(!WirelessPairingCode.isValid(""), "empty rejected")
        expect(WirelessPairingCode.normalized(" 123456\n") == "123456", "normalize trims")
    }

    // MARK: - QR payload

    suite("ADBQRCode") {
        let service = ADBQRCode.randomServiceName()
        expect(service.hasPrefix("studio-"), "QR service names use the studio prefix")
        expect(service.count == "studio-".count + 10, "QR service names carry 10 random chars")
        expect(
            ADBQRCode.payload(password: "123456", serviceName: service)
                == "WIFI:T:ADB;S:\(service);P:123456;;",
            "QR payload embeds the exact service name")
        let generated = ADBQRCode.randomPassword()
        expect(
            WirelessPairingCode.isValid(generated),
            "generated password is always six digits")
    }

    // MARK: - adb response interpretation

    suite("ADBCommandInterpreter pair") {
        expect(
            ADBCommandInterpreter.pairSucceeded("Successfully paired to 192.168.1.5:37123 [guid=adb-x]"),
            "success text")
        expect(ADBCommandInterpreter.pairSucceeded("Already paired to 192.168.1.5:37123"), "already paired")
        expect(
            !ADBCommandInterpreter.pairSucceeded(
                "Failed: Wrong password or connection was dropped."),
            "wrong password is not success")
        expect(!ADBCommandInterpreter.pairSucceeded(""), "empty output is not success")
        expect(
            ADBCommandInterpreter.pairFailureMessage(output: "Failed: Wrong password or connection was dropped."
            ).contains("incorrect or expired"),
            "wrong password explains a new code is needed")
        expect(
            ADBCommandInterpreter.pairFailureMessage(output: "Failed: Unable to start pairing client."
            ).contains("pairing dialog"),
            "pairing client failure keeps the dialog advice")
        expect(
            ADBCommandInterpreter.pairFailureMessage(output: "").contains("Could not pair"),
            "empty output still yields a real failure")
    }

    suite("ADBCommandInterpreter connect") {
        expect(
            ADBCommandInterpreter.connectSucceeded(
                "connected to 192.168.1.5:5555"), "success text")
        expect(
            ADBCommandInterpreter.connectSucceeded(
                "already connected to 192.168.1.5:5555"), "already connected")
        expect(
            !ADBCommandInterpreter.connectSucceeded(
                "failed to connect to '192.168.1.5:5555': Connection refused"),
            "failed text wins over the substring 'connect'")
        expect(
            !ADBCommandInterpreter.connectSucceeded("cannot connect to 192.168.1.5:5555"),
            "cannot connect is a failure")
        expect(
            ADBCommandInterpreter.connectFailureMessage(output: "failed to connect to '192.168.1.5:5555': Connection refused"
            ).contains("port may have changed"),
            "refused explains the changing port")
        expect(
            ADBCommandInterpreter.connectFailureMessage(output: "failed to connect to '10.0.0.9:5555': No route to host"
            ).contains("same Wi-Fi"),
            "unreachable explains the network requirement")
        expect(
            ADBCommandInterpreter.connectFailureMessage(output: "").contains("Could not connect"),
            "empty output still yields a real failure")
    }

    // MARK: - `adb devices -l` parser

    suite("ADBDeviceListParser") {
        let output = """
            List of devices attached
            R58M12ABCDE            device usb:338821120X product:husky model:Pixel_9_Pro device:husky transport_id:1
            192.168.1.23:5555      device product:SM-S938B model:SM_S938B device:e2q transport_id:2
            R58M99OFFLINE          unauthorized usb:1-2 transport_id:3
            10.0.0.9:5555          offline transport_id:4
            emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 transport_id:5

            """
        let entries = ADBDeviceListParser.parse(output)
        expect(entries.count == 5, "parses every transport line")
        expect(entries[0].state == .connected, "device state")
        expect(entries[0].displayName == "Pixel 9 Pro", "model underscores become spaces")
        expect(entries[0].id == "R58M12ABCDE", "serial is the id")
        expect(entries[1].id == "192.168.1.23:5555", "wireless transport keeps host:port")
        expect(entries[2].state == .unauthorized, "unauthorized is preserved")
        expect(entries[2].state.needsAttention, "unauthorized needs attention")
        expect(entries[3].state == .offline, "offline is preserved")
        expect(entries[4].id == "emulator-5554", "emulator transport parsed")
        expect(entries.allSatisfy { $0.id != "*" }, "daemon banner lines are ignored")
    }

    suite("ADBDeviceListParser edge cases") {
        let none = ADBDeviceListParser.parse(
            """
            List of devices attached
            * daemon not running; starting now at tcp:5037
            * daemon started successfully

            """)
        expect(none.isEmpty, "no devices yields no entries")

        let noPermissions = ADBDeviceListParser.parse(
            """
            List of devices attached
            192.168.1.9:5555    no permissions (user in plugdev group; are your udev rules wrong?); see [http://developer.android.com/tools/device.html]
            """)
        expect(noPermissions.count == 1, "no permissions line parsed")
        expect(noPermissions.first?.state == .noPermissions, "no permissions state")
        expect(noPermissions.first?.state.displayName == "No permission", "no permission label")

        let unknown = ADBDeviceListParser.parse("List of devices attached\nSERIAL recovery transport_id:9\n")
        expect(unknown.first?.state == .recovery, "recovery state")

        let authorized = ADBDeviceListParser.parse(
            "List of devices attached\nR58M12ABCDE\tdevice\tusb:1\tmodel:Pixel_9_Pro\t\n")
        expect(authorized.first?.model == "Pixel_9_Pro", "tab-separated model")
        expect(authorized.first?.state.displayName == "Connected", "connected label")
    }
}

// MARK: - Helpers

private func parse(_ raw: String) -> WirelessEndpoint? {
    if case .success(let endpoint) = WirelessEndpoint.parse(raw) { return endpoint }
    return nil
}

private func failure(_ raw: String) -> WirelessEndpoint.AddressError? {
    if case .failure(let error) = WirelessEndpoint.parse(raw) { return error }
    return nil
}
