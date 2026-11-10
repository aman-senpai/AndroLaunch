//
//  StoragePermissionLogicTests.swift
//  CoreLogicTests
//
//  Plain-executable tests for protocol v5: storage-permission decoding and the
//  `notif.action` argument format. No XCTest: `main.swift` owns the harness and
//  calls `runStoragePermissionLogicTests()`.
//
//  Compiles against Foundation-only sources:
//    - macos/AndroLaunch/Data/Services/StorageAccess/StorageAccessModels.swift
//    - macos/AndroLaunch/Data/Services/Phone/PhoneProtocolModels.swift (PhoneJSON)
//
//  Register both in scripts/test-macos-logic.sh and call
//  runStoragePermissionLogicTests() from main.swift.
//

import Foundation

func runStoragePermissionLogicTests() {

    // MARK: - storage.access decoding

    suite("StorageAccessState.decode") {
        let full = """
            {"granted":true,"manager":true,"read":false,"media":false,
             "detail":"All files access is granted, so folder totals are complete."}
            """
        let state = StorageAccessState.decode(full)
        expect(state != nil, "full storage.access payload decodes")
        expect(state?.granted == true, "granted survives")
        expect(state?.manager == true, "manager survives")
        expect(state?.read == false, "read survives")
        expect(state?.media == false, "media survives")
        expect(state?.detail.contains("All files access") == true, "detail survives")
        expect(state?.needsGrant == false, "granted state needs no action")
        expect(state?.summary == "All files access", "manager summary")

        let mediaOnly = StorageAccessState.decode(
            "{\"granted\":false,\"manager\":false,\"read\":false,\"media\":true,\"detail\":\"Media only.\"}")
        expect(mediaOnly?.granted == false, "media-only is not full access")
        expect(mediaOnly?.media == true, "media flag survives")
        expect(mediaOnly?.needsGrant == true, "media-only still needs a grant")
        expect(mediaOnly?.summary == "Media only", "media summary")

        let legacyRead = StorageAccessState.decode(
            "{\"granted\":true,\"manager\":false,\"read\":true,\"media\":false,\"detail\":\"ok\"}")
        expect(legacyRead?.summary == "Storage access", "legacy read summary")

        let none = StorageAccessState.decode(
            "{\"granted\":false,\"manager\":false,\"read\":false,\"media\":false,\"detail\":\"\"}")
        expect(none?.summary == "No storage access", "no-access summary")
        expect(none?.detail.isEmpty == false, "empty detail is replaced by a derived sentence")

        expect(StorageAccessState.decode("") == nil, "empty payload is rejected")
        expect(StorageAccessState.decode("not json") == nil, "non-JSON is rejected")
        expect(StorageAccessState.decode("[]") == nil, "an array is not a storage state")
    }

    suite("StorageAccessState.decode fallbacks") {
        // `granted` missing: derive from manager/read, never from media alone.
        let managerOnly = StorageAccessState.decode("{\"manager\":true}")
        expect(managerOnly?.granted == true, "manager implies granted")
        expect(managerOnly?.detail.contains("All files access") == true,
               "manager derives the detail sentence")

        let readOnly = StorageAccessState.decode("{\"read\":true}")
        expect(readOnly?.granted == true, "legacy read implies granted")
        expect(readOnly?.manager == false, "legacy read is not manager access")

        let mediaOnly = StorageAccessState.decode("{\"media\":true}")
        expect(mediaOnly?.granted == false, "media alone does not imply granted")
        expect(mediaOnly?.detail.contains("Media access only") == true, "media derives its detail")

        let empty = StorageAccessState.decode("{}")
        expect(empty != nil, "an empty object still decodes")
        expect(empty?.granted == false, "missing flags default to false")
        expect(empty?.detail.isEmpty == false, "missing detail is filled in")

        // Numeric and string booleans are tolerated for future companions.
        let numeric = StorageAccessState.decode(
            "{\"granted\":1,\"manager\":1,\"read\":0,\"media\":0}")
        expect(numeric?.granted == true && numeric?.manager == true, "numeric booleans decode")
        expect(numeric?.read == false, "numeric false decodes")

        let stringly = StorageAccessState.decode(
            "{\"granted\":\"true\",\"manager\":\"true\",\"read\":\"false\"}")
        expect(stringly?.granted == true, "string boolean decodes")
        expect(stringly?.read == false, "string false decodes")

        // Unknown extra fields must not break decoding.
        let extra = StorageAccessState.decode(
            "{\"granted\":false,\"manager\":false,\"read\":false,\"media\":false,\"sdk\":34,\"detail\":\"No.\"}")
        expect(extra?.detail == "No.", "extra fields are ignored")
    }

    // MARK: - storage.requestAccess

    suite("StorageAccessLogic.didOpenSettings") {
        expect(StorageAccessLogic.didOpenSettings("opened"), "opened payload means opened")
        expect(StorageAccessLogic.didOpenSettings(" opened\n"), "payload is trimmed")
        expect(StorageAccessLogic.didOpenSettings("failed") == false, "failed means not opened")
        expect(StorageAccessLogic.didOpenSettings("") == false, "empty means not opened")
    }

    suite("StorageAccessLogic.friendlyError") {
        let legacy = StorageAccessLogic.friendlyError("unknown_command:storage.access")
        expect(legacy.contains("Update AndroLaunch Comp"), "legacy companion asks for an update")
        let blocked = StorageAccessLogic.friendlyError("failed")
        expect(blocked.contains("settings screen"), "blocked settings explains the phone path")
        expect(StorageAccessLogic.friendlyError("something else") == "something else",
               "unknown errors pass through")
        expect(StorageAccessLogic.friendlyError(nil).isEmpty == false, "nil error has copy")
        expect(StorageAccessLogic.friendlyError("").isEmpty == false, "empty error has copy")
    }

    // MARK: - notif.action argument

    suite("CompanionNotificationActionArgument.make") {
        expect(
            CompanionNotificationActionArgument.make(key: "0|com.app|1|null|10", actionIndex: 0)
                == "0|com.app|1|null|10\n0",
            "argument is key newline index")
        expect(
            CompanionNotificationActionArgument.make(key: "key with newline\ninside", actionIndex: 2)
                == "key with newlineinside\n2",
            "newlines in the key cannot break the framing")
        expect(
            CompanionNotificationActionArgument.make(key: "  key  ", actionIndex: 1)
                == "key\n1",
            "key is trimmed")
        expect(
            CompanionNotificationActionArgument.make(key: "", actionIndex: 1) == nil,
            "an empty key cannot be built")
        expect(
            CompanionNotificationActionArgument.make(key: "   ", actionIndex: 1) == nil,
            "a blank key cannot be built")
        expect(
            CompanionNotificationActionArgument.make(key: "k", actionIndex: -1) == nil,
            "a negative index cannot be built")
    }

    suite("CompanionNotificationActionArgument.parse") {
        let parsed = CompanionNotificationActionArgument.parse("0|com.app|1|null|10\n3")
        expect(parsed?.key == "0|com.app|1|null|10", "key parses")
        expect(parsed?.actionIndex == 3, "index parses")
        expect(CompanionNotificationActionArgument.parse("key") == nil, "no newline means no argument")
        expect(CompanionNotificationActionArgument.parse("\n3") == nil, "missing key is rejected")
        expect(CompanionNotificationActionArgument.parse("key\nnotanumber") == nil,
               "non-numeric index is rejected")
        expect(CompanionNotificationActionArgument.parse("key\n-1") == nil,
               "negative index is rejected")
        expect(CompanionNotificationActionArgument.parse("key\n 2 ")?.actionIndex == 2,
               "whitespace around the index is tolerated")
        expect(CompanionNotificationActionArgument.parse("key\n2\nextra") == nil,
               "trailing content makes the index unparseable")

        // Round-trip.
        if let argument = CompanionNotificationActionArgument.make(key: "a|b|c", actionIndex: 2),
            let roundTrip = CompanionNotificationActionArgument.parse(argument)
        {
            expect(roundTrip.key == "a|b|c" && roundTrip.actionIndex == 2, "argument round-trips")
        } else {
            expect(false, "argument round-trips")
        }
    }

    // MARK: - Action failure copy

    suite("NotificationActionFailureText.message") {
        expect(
            NotificationActionFailureText.message(for: "unknown_command:notif.action")
                .contains("Update AndroLaunch Comp"),
            "legacy companion action error asks for an update")
        expect(
            NotificationActionFailureText.message(for: "gone").contains("no longer"),
            "gone is explained")
        expect(
            NotificationActionFailureText.message(for: "no_action").contains("does not offer"),
            "no_action is explained")
        expect(
            NotificationActionFailureText.message(for: "action_failed").contains("refused"),
            "action_failed is explained")
        expect(
            NotificationActionFailureText.message(for: "permission_required").contains(
                "notification access"),
            "permission_required is explained")
        expect(
            NotificationActionFailureText.message(for: nil).isEmpty == false,
            "nil gets fallback copy")
        expect(
            NotificationActionFailureText.message(for: "transport broke") == "transport broke",
            "unknown errors pass through unchanged")
    }
}
