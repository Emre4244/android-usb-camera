import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import CoreImage
import Metal

/// Sends decoded Android frames to the installed OBS camera extension's sink.
/// OBS must not simultaneously run its own virtual-camera output.
final class CameraSink {
    private(set) var device: CMIODeviceID = 0
    private var stream: CMIOStreamID = 0
    private var queue: CMSimpleQueue?
    private let context: CIContext
    private var pool: CVPixelBufferPool?
    private var format: CMVideoFormatDescription?
    private var latestOutput: CVPixelBuffer?
    private(set) var sent = 0
    private(set) var dropped = 0
    private let width = 1920, height = 1080

    init() throws {
        guard let gpu = MTLCreateSystemDefaultDevice() else { throw Self.error("Metal GPU unavailable") }
        context = CIContext(mtlDevice: gpu, options: [.cacheIntermediates: false])
        var address = CMIOObjectPropertyAddress(mSelector: UInt32(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, 4, &allow)
        let devices: [UInt32] = Self.ids(CMIOObjectID(kCMIOObjectSystemObject), UInt32(kCMIOHardwarePropertyDevices))
        for id in devices {
            let name = Self.name(id)
            print("CAMERA", id, name)
            if name == "OBS Virtual Camera" { device = id }
        }
        guard device != 0 else { throw Self.error("OBS Virtual Camera is not enabled. Install OBS and enable its camera extension first.") }
        let streams = Self.ids(device, UInt32(kCMIODevicePropertyStreams))
        for id in streams {
            var address = CMIOObjectPropertyAddress(mSelector: UInt32(kCMIOStreamPropertyDirection),
                mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
            var direction: UInt32 = 99, used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(id, &address, 0, nil, 4, &used, &direction)
            print("STREAM", id, "direction", direction, "status", status)
            // Input (1) is the camera's source; output (0) is the producer sink.
            if status == noErr && direction == 0 { stream = id }
        }
        guard stream != 0 else { throw Self.error("Compatible camera input stream not found") }
        var unmanaged: Unmanaged<CMSimpleQueue>?
        let result = CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &unmanaged)
        guard result == noErr, let unmanaged else { throw Self.error("Cannot open camera queue: \(result)") }
        queue = unmanaged.takeRetainedValue()
        let attributes: [CFString: Any] = [kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else {
            throw Self.error("Cannot allocate GPU frame pool")
        }
        CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCVPixelFormatType_32BGRA,
            width: Int32(width), height: Int32(height), extensions: nil, formatDescriptionOut: &format)
        let start = CMIODeviceStartStream(device, stream)
        guard start == noErr else { throw Self.error("Camera input is busy or unavailable. Stop OBS virtual-camera output and retry. Status: \(start)") }
        print("SINK_READY", device, stream, "1920x1080 GPU aspect-fit")
    }

    deinit {
        if device != 0 && stream != 0 { CMIODeviceStopStream(device, stream) }
    }

    func prepare(_ pixel: CVPixelBuffer) {
        guard let pool else { return }
        var output: CVPixelBuffer?
        let limits = [kCVPixelBufferPoolAllocationThresholdKey: 5] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits, &output) == kCVReturnSuccess,
              let output else { dropped += 1; return }
        let image = CIImage(cvPixelBuffer: pixel)
        let scale = min(CGFloat(width) / image.extent.width, CGFloat(height) / image.extent.height)
        let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = (CGFloat(width) - resized.extent.width) / 2
        let y = (CGFloat(height) - resized.extent.height) / 2
        let centered = resized.transformed(by: CGAffineTransform(translationX: x, y: y))
        let frame = centered.composited(over: CIImage(color: .black))
        context.render(frame, to: output, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        latestOutput = output
    }

    func sendLatest() {
        guard let queue, let output = latestOutput, let format else { return }
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { dropped += 1; return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let result = CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: output,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        guard result == noErr, let sample else { dropped += 1; return }
        let retained = Unmanaged.passRetained(sample)
        let enqueue = CMSimpleQueueEnqueue(queue, element: retained.toOpaque())
        if enqueue != noErr { retained.release(); dropped += 1 }
        else { sent += 1 }
    }

    private static func ids(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> [UInt32] {
        var address = CMIOObjectPropertyAddress(mSelector: selector,
            mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0, used: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var values = [UInt32](repeating: 0, count: Int(size) / 4)
        let status = values.withUnsafeMutableBytes {
            CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, $0.baseAddress!)
        }
        return status == noErr ? values : []
    }

    private static func name(_ object: CMIOObjectID) -> String {
        var address = CMIOObjectPropertyAddress(mSelector: UInt32(kCMIOObjectPropertyName),
            mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
        let storage = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        storage.initialize(to: nil)
        defer { storage.deinitialize(count: 1); storage.deallocate() }
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(object, &address, 0, nil,
            UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, storage)
        guard status == noErr, let result = storage.pointee else { return "unknown" }
        return result.takeUnretainedValue() as String
    }

    private static func error(_ text: String) -> NSError {
        NSError(domain: "AstraCameraSink", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
