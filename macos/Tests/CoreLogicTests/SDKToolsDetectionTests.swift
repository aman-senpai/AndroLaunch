//
//  SDKToolsDetectionTests.swift
//  CoreLogicTests
//
//  Regression cover for the "avdmanager not found" loop: a stored tools path used
//  to be trusted forever, so a moved or never-installed SDK kept failing on every
//  AVD poll. A directory only counts as configured while both binaries exist, and
//  versioned cmdline-tools layouts must be discovered, not just `latest`.
//

import Foundation

private func makeToolsDirectory(
    _ label: String, binaries: [String]
) -> String {
    let root = NSTemporaryDirectory() + "androlaunch-sdk-\(label)-\(UUID().uuidString)"
    let bin = root + "/cmdline-tools/latest/bin"
    try? FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
    for binary in binaries {
        let path = bin + "/" + binary
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }
    return root
}

func runSDKToolsDetectionTests() {
    suite("Command-line tools validation") {
        let complete = makeToolsDirectory("complete", binaries: ["sdkmanager", "avdmanager"])
        expect(
            AppConstants.isValidCmdlineToolsDirectory(complete + "/cmdline-tools/latest/bin"),
            "a directory with both binaries is usable")

        let partial = makeToolsDirectory("partial", binaries: ["sdkmanager"])
        expect(
            !AppConstants.isValidCmdlineToolsDirectory(partial + "/cmdline-tools/latest/bin"),
            "a directory missing avdmanager is not usable")

        let empty = makeToolsDirectory("empty", binaries: [])
        expect(
            !AppConstants.isValidCmdlineToolsDirectory(empty + "/cmdline-tools/latest/bin"),
            "an empty directory is not usable")
        expect(
            !AppConstants.isValidCmdlineToolsDirectory(""),
            "an empty path is not usable")
        expect(
            !AppConstants.isValidCmdlineToolsDirectory("/Users/nobody/Library/Android/sdk/cmdline-tools/latest/bin"),
            "a path that does not exist is not usable")
    }

    suite("Command-line tools discovery") {
        let complete = makeToolsDirectory("discover", binaries: ["sdkmanager", "avdmanager"])
        let directories = AppConstants.cmdlineToolsBinDirectories(inRoot: complete)
        expect(
            directories.first == complete + "/cmdline-tools/latest/bin",
            "latest is tried first")
        expect(
            AppConstants.detectCmdlineToolsPath(additionalRoots: [complete]) != nil,
            "a usable root is detected")

        // Versioned layout without a `latest` symlink.
        let versionedRoot = NSTemporaryDirectory() + "androlaunch-sdk-versioned-\(UUID().uuidString)"
        let versionedBin = versionedRoot + "/cmdline-tools/18.1/bin"
        try? FileManager.default.createDirectory(
            atPath: versionedBin, withIntermediateDirectories: true)
        for binary in ["sdkmanager", "avdmanager"] {
            let path = versionedBin + "/" + binary
            FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8))
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: path)
        }
        expect(
            AppConstants.cmdlineToolsBinDirectories(inRoot: versionedRoot)
                .contains(versionedBin),
            "versioned cmdline-tools installs are discovered")
        // Detection may legitimately prefer a real SDK on the build machine, so assert
        // that what comes back is usable rather than that it is this fixture.
        let detected = AppConstants.detectCmdlineToolsPath(additionalRoots: [versionedRoot])
        expect(
            detected.map(AppConstants.isValidCmdlineToolsDirectory) == true,
            "detection returns a usable directory")
    }
}
