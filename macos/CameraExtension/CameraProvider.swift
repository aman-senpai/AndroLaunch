//
//  CameraProvider.swift
//  AndroLaunch Camera Extension
//

import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation

final class AndroLaunchCameraProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: AndroLaunchCameraDeviceSource!

    override init() {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: nil)
        deviceSource = AndroLaunchCameraDeviceSource(localizedName: "AndroLaunch Camera")
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            NSLog("AndroLaunchCamera: addDevice failed: \(error)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer, .providerName]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionProviderProperties
    {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            props.manufacturer = "AndroLaunch"
        }
        if properties.contains(.providerName) {
            props.name = "AndroLaunch Camera"
        }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

final class AndroLaunchCameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var streamSource: AndroLaunchCameraStreamSource!

    private let width = 1280
    private let height = 720
    private let frameRate = 30

    init(localizedName: String) {
        super.init()
        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: UUID(),
            legacyDeviceID: nil,
            source: self)

        guard
            let format = Self.makeFormatDescription(width: width, height: height)
        else {
            NSLog("AndroLaunchCamera: could not create format description")
            return
        }
        let streamFormat = CMIOExtensionStreamFormat(
            formatDescription: format,
            maxFrameDuration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            minFrameDuration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            validFrameDurations: nil)
        streamSource = AndroLaunchCameraStreamSource(
            localizedName: "\(localizedName) Stream",
            streamID: UUID(),
            streamFormat: streamFormat,
            width: width,
            height: height,
            frameRate: frameRate,
            device: device)
        do {
            try device.addStream(streamSource.stream)
        } catch {
            NSLog("AndroLaunchCamera: addStream failed: \(error)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionDeviceProperties
    {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            // kIOAudioDeviceTransportTypeVirtual
            props.setPropertyState(
                CMIOExtensionPropertyState(value: 1937339512 as NSNumber),
                forProperty: .deviceTransportType)
        }
        if properties.contains(.deviceModel) {
            props.model = "AndroLaunch Camera"
        }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    private static func makeFormatDescription(width: Int, height: Int) -> CMFormatDescription? {
        var format: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(width),
            height: Int32(height),
            extensions: nil,
            formatDescriptionOut: &format)
        return status == noErr ? format : nil
    }
}
