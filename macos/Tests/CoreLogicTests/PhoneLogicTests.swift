//
//  PhoneLogicTests.swift
//  CoreLogicTests
//
//  Plain-executable tests for the phone-companion protocol layer. No XCTest:
//  `main.swift` owns the harness and calls `runPhoneLogicTests()`.
//
//  Everything here compiles against Foundation-only sources:
//    - Data/Services/Phone/PhoneProtocolModels.swift
//    - Data/Services/Notifications/NotificationDumpParser.swift (record type)
//
//  Add both files to scripts/test-macos-logic.sh and call runPhoneLogicTests()
//  from main.swift.
//

import Foundation

func runPhoneLogicTests() {

    // MARK: - call.state

    suite("CompanionCallState.decode") {
        let json = """
            {"supported":true,"permission":true,"enabled":true,"control":true,
             "state":"ringing","incoming":true,"since":1762345678901}
            """
        let ringing = CompanionCallState.decode(json)
        expect(ringing != nil, "ringing payload decodes")
        expect(ringing?.isRinging == true, "state is ringing")
        expect(ringing?.incoming == true, "incoming flag survives")
        expect(ringing?.controlAvailable == true, "control flag survives")
        expect(ringing?.supported == true && ringing?.permission == true && ringing?.enabled == true,
               "capability flags survive")
        expect(ringing?.sinceMillis == 1_762_345_678_901, "since is epoch millis")
        expect(ringing?.displayName == "Incoming call", "incoming display name")
        expect(
            ringing?.detailText.lowercased().contains("audio stays on your phone") == true,
            "copy never promises Mac audio")

        let idle = CompanionCallState.decode(
            "{\"supported\":true,\"permission\":true,\"enabled\":true,\"control\":false,\"state\":\"idle\",\"incoming\":false,\"since\":1}")
        expect(idle?.isIdle == true, "idle decodes")
        expect(idle?.controlAvailable == false, "control can be unavailable on an idle device")
        expect(idle?.displayName == "Idle", "idle display name")

        let offhook = CompanionCallState.decode("{\"state\":\"offhook\"}")
        expect(offhook?.isInCall == true, "missing optional fields still decode")
        expect(offhook?.supported == false, "absent booleans default to false")

        expect(CompanionCallState.decode("not json") == nil, "garbage is rejected")
        expect(CompanionCallState.decode("[]") == nil, "an array is not a call state")
    }

    // MARK: - media.state

    suite("CompanionMediaState.decode") {
        let json = """
            {"available":true,"app":"com.spotify.music","title":"Midnight City",
             "artist":"M83","album":"Hurry Up","playing":true,"canNext":true,"canPrev":false}
            """
        let state = CompanionMediaState.decode(json)
        expect(state != nil, "media payload decodes")
        expect(state?.available == true, "available flag")
        expect(state?.title == "Midnight City", "title")
        expect(state?.artist == "M83", "artist")
        expect(state?.isPlaying == true, "playing")
        expect(state?.canNext == true && state?.canPrevious == false, "transport capability flags")
        expect(state?.artworkPNG == nil, "no artwork unless requested")

        // Artwork is accepted only inside the size budget.
        let smallArtwork = Data(repeating: 0x42, count: 64).base64EncodedString()
        let withArtwork = CompanionMediaState.decode(
            "{\"available\":true,\"title\":\"x\",\"artwork\":{\"mime\":\"image/png\",\"data\":\"\(smallArtwork)\"}}")
        expect(withArtwork?.artworkPNG?.count == 64, "small artwork decodes")

        let unavailable = CompanionMediaState.decode("{\"available\":false}")
        expect(unavailable?.available == false, "unavailable is a normal answer")
        expect(CompanionMediaState.decode("nope") == nil, "garbage media payload is rejected")

        expect(state?.trackIdentity.contains("Midnight City") == true, "track identity keys on metadata")
        expect(state?.trackIdentity != unavailable?.trackIdentity, "different tracks differ")
    }

    // MARK: - storage.info

    suite("CompanionStorageState.decode") {
        let json = """
            {"total":128000000000,"used":96000000000,"free":32000000000,
             "path":"/data","externalTotal":1,"externalFree":1,"scannedAt":1762345678901,
             "complete":false,
             "folders":[{"name":"DCIM","bytes":5000},{"name":"Download","bytes":9000},
                        {"name":"Pictures","bytes":1000}]}
            """
        let state = CompanionStorageState.decode(json)
        expect(state != nil, "storage payload decodes")
        expect(state?.totalBytes == 128_000_000_000, "total")
        expect(state?.usedBytes == 96_000_000_000, "used")
        expect(state?.folderListComplete == false, "partial scans are labelled")
        expect(state?.folders.count == 3, "all folders decoded")
        expect(state?.folders.first?.name == "Download", "folders sorted bytes descending")
        expect(abs((state?.usedFraction ?? 0) - 0.75) < 0.001, "used fraction is used/total")

        let clamped = CompanionStorageState.decode(
            "{\"total\":10,\"used\":20,\"free\":0,\"folders\":[]}")
        expect(clamped?.usedFraction == 1, "used fraction clamps at 1")

        let empty = CompanionStorageState.decode("{\"total\":0}")
        expect(empty?.usedFraction == 0, "zero total cannot divide by zero")
        expect(CompanionStorageState.decode("garbage") == nil, "garbage storage payload rejected")
    }

    // MARK: - notif.list

    suite("CompanionNotification.decodeList") {
        let v3 = """
            [{"key":"0|com.whatsapp|1|null|10","pkg":"com.whatsapp","title":"Ada",
              "text":"Are you there?","time":1762345678901,"ongoing":false,
              "sensitive":false,"replyIndex":1,
              "actions":[{"index":0,"title":"Mark as read","hasReply":false},
                         {"index":1,"title":"Reply","hasReply":true}]}]
            """
        let items = CompanionNotification.decodeList(v3)
        expect(items?.count == 1, "one notification decodes")
        let message = items?.first
        expect(message?.key == "0|com.whatsapp|1|null|10", "key survives")
        expect(message?.packageName == "com.whatsapp", "package survives")
        expect(message?.hasReply == true, "reply action is detected")
        expect(message?.replyActionIndex == 1, "reply index is the reply action index")
        expect(message?.actions.count == 2, "all actions are kept")
        expect(message?.isSensitive == false, "sensitivity flag survives")
        expect(message?.fingerprint.contains("|") == true, "fingerprint is key plus post time")

        // A v2 companion sends no actions/sensitive fields at all.
        let v2 = """
            [{"key":"k2","pkg":"com.android.mms","title":"","text":"hello","time":5,"ongoing":true}]
            """
        let legacy = CompanionNotification.decodeList(v2)?.first
        expect(legacy?.actions.isEmpty == true, "v2 payload has no actions")
        expect(legacy?.hasReply == false, "v2 payload has no reply")
        expect(legacy?.replyActionIndex == -1, "v2 payload reply index is -1")
        expect(legacy?.isOngoing == true, "ongoing survives for the v2 shape")

        expect(CompanionNotification.decodeList("{}") == nil, "an object is not a list")
        expect(CompanionNotification.decodeList("nope") == nil, "garbage list rejected")
        expect(CompanionNotification.decodeList("[{\"key\":\"\"}]")?.isEmpty == true,
               "entries without a key are dropped")
    }

    // MARK: - Verification code extraction

    suite("VerificationCode.extract") {
        expect(VerificationCode.extract(from: "Your code is 482913") == "482913", "code after keyword")
        expect(VerificationCode.extract(from: "G-123456 is your Google verification code") == "123456",
               "code in a longer sentence")
        expect(VerificationCode.extract(from: "Login code: 123 456") == "123456", "grouped code joins")
        expect(VerificationCode.extract(from: "Your one-time code: 1234 5678") == "12345678",
               "grouped 4+4 code joins")
        expect(VerificationCode.extract(from: "See you in 2026") == nil, "a bare year is not a code")
        expect(VerificationCode.extract(from: "Your security code for 2026: 5521") == "5521",
               "a year with code vocabulary does not win over the real code")
        expect(VerificationCode.extract(from: "Call me on 5551234") == nil,
               "a phone number without code vocabulary is ignored")
        expect(VerificationCode.extract(from: "OTP 5551234") == "5551234",
               "a 7-digit code is accepted with vocabulary")
        expect(VerificationCode.extract(from: "v1.2.3 build 45") == nil, "version strings are ignored")
        expect(VerificationCode.extract(from: "") == nil, "empty text has no code")
        expect(VerificationCode.extract(from: "Order 12345 shipped") == "12345",
               "an order number is the best available candidate")
    }

    // MARK: - Byte formatting

    suite("PhoneFormat.bytes") {
        expect(PhoneFormat.bytes(0) == "0 B", "zero bytes")
        expect(PhoneFormat.bytes(900) == "900 B", "bytes stay bytes")
        expect(PhoneFormat.bytes(1024) == "1.0 KB", "one kilobyte")
        expect(PhoneFormat.bytes(1536) == "1.5 KB", "fractional kilobytes")
        expect(PhoneFormat.bytes(5 * 1024 * 1024 * 1024) == "5.0 GB", "five gigabytes")
        expect(
            PhoneFormat.usedOfTotal(used: 3 * 1024 * 1024 * 1024, total: 4 * 1024 * 1024 * 1024)
                == "3.0 GB of 4.0 GB used",
            "used-of-total sentence")
    }

    // MARK: - Storage shell parsers

    suite("StorageParsers.parseDF") {
        let df = """
            Filesystem      1K-blocks      Used Available Use% Mounted on
            /dev/block/dm-5 121927680 102334464  19607040  84% /data
            """
        let capacity = StorageParsers.parseDF(df)
        expect(capacity != nil, "df row decodes")
        expect(capacity?.total == 121_927_680 * 1024, "total is KB converted to bytes")
        expect(capacity?.used == 102_334_464 * 1024, "used is KB converted to bytes")
        expect(capacity?.free == 19_607_040 * 1024, "free is KB converted to bytes")
        expect(StorageParsers.parseDF("") == nil, "no row means no data")
        expect(StorageParsers.parseDF(nil) == nil, "nil output means no data")
        expect(StorageParsers.parseDF("garbage") == nil, "garbage df is rejected")
    }

    suite("StorageParsers.parseDU") {
        let output = """
            12345\t/storage/emulated/0/DCIM
            800\t/storage/emulated/0/Download
            0\t/storage/emulated/0/Movies
            2048 /storage/emulated/0/Pictures
            du: cannot read /storage/emulated/0/Android: Permission denied
            """
        let folders = StorageParsers.parseDU(output)
        expect(folders.count == 3, "valid rows decoded, unreadable rows dropped")
        expect(folders.first?.name == "DCIM", "sorted by size descending")
        expect(folders.first?.bytes == 12_345 * 1024, "kilobytes converted to bytes")
        expect(folders.contains { $0.name == "Movies" } == false, "zero-byte folders are dropped")
        expect(folders.contains { $0.name == "Pictures" } == true, "space-separated du output is accepted")
        expect(StorageParsers.parseDU(nil).isEmpty, "nil du output is an empty list")
    }

    suite("StorageParsers.parseMediaQuery") {
        let output = """
            Row: 0 _display_name=IMG_20260101_120000.jpg, _size=24117248
            Row: 1 _display_name=VID_20260101_130000.mp4, _size=104857600
            Row: 2 _display_name=no_size.jpg
            Row: 3 _display_name=small.jpg, _size=100
            """
        let items = StorageParsers.parseMediaQuery(output, limit: 2)
        expect(items.count == 2, "limit is respected")
        expect(items.first?.name == "VID_20260101_130000.mp4", "largest first")
        expect(items.first?.bytes == 104_857_600, "byte size parsed")
        expect(items.contains { $0.name == "no_size.jpg" } == false, "rows without a size are dropped")
        expect(StorageParsers.parseMediaQuery("", limit: 5).isEmpty, "empty output is empty")
    }

    // MARK: - notif.reply argument

    suite("CompanionReplyArgument.make") {
        let json = CompanionReplyArgument.make(key: "0|com.whatsapp|1||10", actionIndex: 2, text: "On my way")
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            expect(false, "reply argument is valid JSON")
            return
        }
        expect(object["key"] as? String == "0|com.whatsapp|1||10", "key is carried")
        expect(object["action"] as? Int == 2, "action index is carried")
        expect(object["text"] as? String == "On my way", "reply text is carried")

        let escaped = CompanionReplyArgument.make(
            key: "k", actionIndex: -1, text: "quote \" and newline \n and tab \t")
        guard let escapedData = escaped.data(using: .utf8),
            let escapedObject = try? JSONSerialization.jsonObject(with: escapedData) as? [String: Any]
        else {
            expect(false, "escaped reply argument is valid JSON")
            return
        }
        expect(
            escapedObject["text"] as? String == "quote \" and newline \n and tab \t",
            "special characters survive encoding")
    }

    // MARK: - Record mapping

    suite("AndroidNotificationRecord companion fields") {
        let record = AndroidNotificationRecord(
            packageName: "com.whatsapp",
            key: "k",
            postTime: 1,
            title: "Ada",
            text: "hi",
            flags: 0,
            isMedia: false,
            actions: [
                AndroidNotificationAction(index: 0, title: "Read", hasReply: false),
                AndroidNotificationAction(index: 1, title: "Reply", hasReply: true),
            ],
            isSensitive: true)
        expect(record.hasReply, "hasReply follows the action set")
        expect(record.replyActionIndex == 1, "reply action index is found")
        expect(record.isSensitive, "sensitivity is stored")

        let plain = AndroidNotificationRecord(
            packageName: "com.example",
            key: "k2",
            postTime: 2,
            title: nil,
            text: "hello",
            flags: 0,
            isMedia: false)
        expect(plain.hasReply == false, "no actions means no reply")
        expect(plain.replyActionIndex == -1, "no actions means -1")
        expect(plain.isSensitive == false, "default is not sensitive")
        expect(plain.displayText == "hello", "display text uses the available field")
    }
}
