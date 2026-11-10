//
//  CameraStream.swift
//  AndroLaunch Camera Extension
//
//  A self-contained video source. It emits a moving colour-bar test pattern at
//  30 fps so the camera extension can be verified in FaceTime/QuickTime/Zoom
//  immediately after local signing. Android frame delivery can replace the
//  pattern generator without changing the CMIO plumbing.
//

import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation

final class AndroLaunchCameraStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private let width: Int
    private let height: Int
    private let frameRate: Int
    private var timer: DispatchSourceTimer?
    private var frameIndex: UInt64 = 0
    private let queue = DispatchQueue(label: "com.senpai.AndroLaunch.camera.frames")

    init(
        localizedName: String,
        streamID: UUID,
        streamFormat: CMIOExtensionStreamFormat,
        width: Int,
        height: Int,
        frameRate: Int,
        device: CMIOExtensionDevice
    ) {
        self.format = streamFormat
        self.width = width
        self.height = height
        self.frameRate = frameRate
        super.init()
        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionStreamProperties
    {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            props.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            let interval = DispatchTimeInterval.nanoseconds(1_000_000_000 / self.frameRate)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.emitFrame() }
            self.timer = timer
            timer.resume()
        }
    }

    func stopStream() throws {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    private func emitFrame() {
        guard let buffer = makeFrame(index: frameIndex) else { return }
        frameIndex &+= 1
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescriptionOut: &format)
        guard let format else { return }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            presentationTimeStamp: CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(frameRate)),
            decodeTimeStamp: .invalid)
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample)
        guard status == noErr, let sample else { return }
        let hostTime = DispatchTime.now().uptimeNanoseconds
        stream.send(sample, discontinuity: [], hostTimeInNanoseconds: hostTime)
    }

    private func makeFrame(index: UInt64) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let context else { return nil }
        let colors: [CGColor] = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 1, green: 1, blue: 0, alpha: 1),
            CGColor(red: 0, green: 1, blue: 1, alpha: 1),
            CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            CGColor(red: 1, green: 0, blue: 1, alpha: 1),
            CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            CGColor(red: 0, green: 0, blue: 1, alpha: 1),
        ]
        let barWidth = CGFloat(width) / CGFloat(colors.count)
        for (i, color) in colors.enumerated() {
            context.setFillColor(color)
            context.fill(CGRect(x: CGFloat(i) * barWidth, y: 0, width: barWidth, height: CGFloat(height)))
        }
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
        context.fill(CGRect(x: 0, y: CGFloat(height) * 0.12, width: CGFloat(width), height: CGFloat(height) * 0.22))
        let travel = CGFloat(width) - 240
        let x = CGFloat((index * 24) % UInt64(max(1, Int(travel))))
        context.setFillColor(CGColor(red: 0.92, green: 0.92, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: x, y: 32, width: 180, height: 10))
        context.setFillColor(CGColor(red: 0.18, green: 0.78, blue: 0.42, alpha: 1))
        context.fill(CGRect(x: 32, y: CGFloat(height) * 0.12 + 24, width: 16, height: 16))
        return pixelBuffer
    }
}
