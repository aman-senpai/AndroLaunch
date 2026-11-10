//
//  AppIconLogicTests.swift
//  CoreLogicTests
//
//  Plain-executable tests for the real app-icon pipeline (protocol v4). No
//  XCTest: `main.swift` owns the harness and calls `runAppIconLogicTests()`.
//
//  Compiles against Foundation-only sources:
//    - macos/AndroLaunch/Data/Services/AppIcons/AppIconModels.swift
//
//  Register both in scripts/test-macos-logic.sh and call runAppIconLogicTests()
//  from main.swift.
//

import Foundation

func runAppIconLogicTests() {

    // A PNG signature is all the model validates before handing bytes to NSImage;
    // the real payload is a full PNG produced by the phone.
    func pngBytes(_ extra: Int = 4) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(contentsOf: [UInt8](repeating: 0x42, count: extra))
        return data
    }

    func base64(_ data: Data) -> String {
        data.base64EncodedString()
    }

    func payload(_ entries: [[String: Any]]) -> String {
        let object: [String: Any] = ["c": "app-icons", "icons": entries]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Response decoding

    suite("AppIconPayload.decode") {
        let icon = base64(pngBytes())
        let json = payload([
            ["package": "com.example.app", "label": "Example", "pngBase64": icon],
            ["package": "com.example.second", "label": "Second", "pngBase64": icon],
        ])
        let decoded = AppIconPayload.decode(json)
        expect(decoded?.count == 2, "valid icons decode")
        expect(decoded?.first?.packageName == "com.example.app", "package name is kept")
        expect(decoded?.first?.label == "Example", "label is kept")
        expect(decoded?.first?.pngData == pngBytes(), "PNG bytes round-trip exactly")

        let empty = AppIconPayload.decode("{\"c\":\"app-icons\",\"icons\":[]}")
        expect(empty?.isEmpty == true, "empty icon list is a valid answer")

        expect(AppIconPayload.decode("") == nil, "empty payload is rejected")
        expect(AppIconPayload.decode("not json") == nil, "non-JSON is rejected")
        expect(AppIconPayload.decode("[]") == nil, "an array is not an envelope")
        expect(AppIconPayload.decode("{}") == nil, "missing icons array is rejected")
        expect(
            AppIconPayload.decode("{\"c\":\"something-else\",\"icons\":[]}") == nil,
            "a foreign command envelope is rejected")
        expect(
            AppIconPayload.decode("{\"icons\":[]}")?.isEmpty == true,
            "the command field is optional for forward compatibility")
    }

    suite("AppIconPayload.decode entry validation") {
        let good = base64(pngBytes())
        // Each of these entries is individually unusable and must be skipped,
        // without discarding the valid one.
        let json = payload([
            ["label": "No package", "pngBase64": good],
            ["package": "com.empty.base64", "pngBase64": ""],
            ["package": "com.invalid.base64", "pngBase64": "@@@not-base64@@@"],
            ["package": "com.not.png", "pngBase64": base64(Data([0x00, 0x01, 0x02]))],
            ["package": "com.valid", "label": "Valid", "pngBase64": good],
        ])
        let decoded = AppIconPayload.decode(json)
        expect(decoded?.count == 1, "only the valid entry survives")
        expect(decoded?.first?.packageName == "com.valid", "the valid package is returned")

        let oversized = Data(repeating: 0x41, count: AppIconPayload.maxIconBytes + 1)
        let oversizeJson = payload([
            ["package": "com.oversize", "pngBase64": oversized.base64EncodedString()]
        ])
        expect(AppIconPayload.decode(oversizeJson)?.isEmpty == true, "oversized icons are dropped")

        let truncated = Data([0x89, 0x50, 0x4E, 0x47])
        expect(AppIconPayload.isPNG(truncated) == false, "a short signature is not a PNG")
        expect(AppIconPayload.isPNG(pngBytes()) == true, "a full signature is a PNG")
        expect(AppIconPayload.isPNG(Data()) == false, "empty data is not a PNG")
    }

    suite("AppIconPayload.decode dedupe and bound") {
        var entries: [[String: Any]] = []
        for index in 0..<70 {
            entries.append([
                "package": "com.example.app\(index)",
                "pngBase64": base64(pngBytes()),
            ])
        }
        let decoded = AppIconPayload.decode(payload(entries))
        expect(decoded?.count == AppIconPayload.maxIconCount, "icon count is capped")

        let duplicate = base64(pngBytes())
        let dupJson = payload([
            ["package": "com.same", "label": "First", "pngBase64": duplicate],
            ["package": "com.same", "label": "Second", "pngBase64": duplicate],
        ])
        let dupDecoded = AppIconPayload.decode(dupJson)
        expect(dupDecoded?.count == 1, "duplicate packages collapse to one")
        expect(dupDecoded?.first?.label == "First", "the first duplicate wins")

        let whitespaceJson = payload([
            ["package": "  com.trimmed  ", "label": "  Trim  ", "pngBase64": duplicate]
        ])
        expect(
            AppIconPayload.decode(whitespaceJson)?.first?.packageName == "com.trimmed",
            "package names are trimmed")
        expect(
            AppIconPayload.decode(whitespaceJson)?.first?.label == "Trim",
            "labels are trimmed")
    }

    // MARK: - Cache keys

    suite("AppIconCacheKey.relativePath") {
        let path = AppIconCacheKey.relativePath(
            deviceID: "R58M12345AB", packageName: "com.example.app")
        expect(path == "r58m12345ab/com.example.app.png", "device and package form the path")
        expect(path.contains("/") == true, "path uses one directory separator")

        let wireless = AppIconCacheKey.relativePath(
            deviceID: "192.168.1.5:5555", packageName: "com.example.app")
        expect(wireless.hasPrefix("192.168.1.5-5555/"), "colon is sanitised in the device name")

        let traversal = AppIconCacheKey.relativePath(
            deviceID: "../../etc", packageName: "../../passwd")
        expect(!traversal.contains(".."), "parent traversal is removed")
        expect(traversal.components(separatedBy: "/").count == 2, "only one separator remains")
        expect(!(traversal as NSString).lastPathComponent.hasPrefix("."), "no hidden file names")

        let slashPackage = AppIconCacheKey.fileComponent("com/example/app")
        expect(!slashPackage.contains("/"), "slashes never appear in a file component")
        expect(slashPackage.hasSuffix(".png"), "file component carries the PNG extension")

        let empty = AppIconCacheKey.fileComponent("")
        expect(empty == "app.png", "empty package falls back to a stable name")
        expect(AppIconCacheKey.deviceComponent("") == "device", "empty device falls back")

        let longDevice = String(repeating: "a", count: 200)
        expect(
            AppIconCacheKey.deviceComponent(longDevice).count <= AppIconCacheKey.maxComponentLength,
            "long device names are bounded")
        let longPackage = String(repeating: "b", count: 200) + ".app"
        expect(
            AppIconCacheKey.fileComponent(longPackage).count
                <= AppIconCacheKey.maxComponentLength + 4,
            "long package names are bounded")

        expect(
            AppIconCacheKey.memoryKey(deviceID: "A", packageName: "com.x")
                != AppIconCacheKey.memoryKey(deviceID: "B", packageName: "com.x"),
            "memory keys are device scoped")
        expect(
            AppIconCacheKey.memoryKey(deviceID: "A", packageName: "com.x")
                == AppIconCacheKey.memoryKey(deviceID: "A", packageName: "com.x"),
            "memory keys are stable")
        expect(
            AppIconCacheKey.memoryKey(deviceID: "A", packageName: "com.x") == "A|com.x",
            "memory key format is explicit")
    }

    // MARK: - Batching

    suite("AppIconBatches.split") {
        expect(AppIconBatches.split([]).isEmpty, "no packages means no batches")
        expect(AppIconBatches.split(["", "   "]).isEmpty, "blank packages are dropped")
        expect(
            AppIconBatches.split(["com.one", "com.one", "com.two"]) == [["com.one", "com.two"]],
            "duplicates collapse and order is preserved")

        let many = (0..<50).map { "com.example.app\($0)" }
        let batches = AppIconBatches.split(many)
        expect(batches.count == 3, "50 packages become 3 batches")
        expect(batches[0].count == AppIconBatches.defaultBatchSize, "first batch is full")
        expect(batches[2].count == 2, "remainder batch keeps the rest")

        let even = AppIconBatches.split((0..<48).map { "com.p\($0)" })
        expect(even.count == 2 && even.allSatisfy { $0.count == 24 }, "48 packages split evenly")

        let clampedSmall = AppIconBatches.split(["a", "b", "c"], size: 0)
        expect(clampedSmall.count == 3, "a zero batch size clamps to one")

        let clampedLarge = AppIconBatches.split((0..<130).map { "com.p\($0)" }, size: 999)
        expect(
            clampedLarge.count == 3 && clampedLarge[0].count == AppIconBatches.maximumBatchSize,
            "an oversized batch size clamps to 64")

        expect(
            AppIconBatches.split(["  com.trimmed  "]) == [["com.trimmed"]],
            "batch entries are trimmed")
    }
}
