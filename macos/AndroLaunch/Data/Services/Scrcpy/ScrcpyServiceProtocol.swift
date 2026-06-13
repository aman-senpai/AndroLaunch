//
//  ScrcpyServiceProtocol.swift
//  AndroLaunch
//
//  Created by Aman Raj on 22/4/25.
//

import Combine
import Foundation

protocol ScrcpyServiceProtocol {
    var scrcpyPath: String? { get }
    var error: PassthroughSubject<String?, Never> { get }

    func detectScrcpyPath() -> String?

    func mirrorDevice(
        deviceID: String,
        adbPath: String?,
        audioEnabled: Bool,
        clipboardEnabled: Bool,
        maxSize: Int?,
        maxFPS: Int?,
        bitRate: Int?,
        orientation: String?,
        borderless: Bool,
        flexDisplay: Bool,
        keepActive: Bool,
        backgroundColor: String?,
        renderFit: String?,
        lockAspectRatio: Bool,
        minSizeAlignment: Int?
    )

    func mirrorCamera(
        deviceID: String,
        adbPath: String?,
        audioEnabled: Bool,
        facing: String?,
        fps: Int?,
        size: Int?,
        bitRate: Int?,
        orientation: String?,
        aspectRatio: String?,
        cameraTorch: Bool,
        cameraZoom: Double?
    )

    func launchApp(
        packageID: String,
        deviceID: String,
        adbPath: String?,
        audioEnabled: Bool,
        resolution: Int,
        keepActive: Bool,
        flexDisplay: Bool,
        backgroundColor: String?,
        renderFit: String?,
        lockAspectRatio: Bool,
        bitRate: Int?
    )

    func stopMirroring(deviceID: String)
    func stopAll()
}
