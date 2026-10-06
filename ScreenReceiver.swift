import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import Darwin

/// scrcpy 5.0 framed protocol; H.264 hardware decode with no screen/window capture.
final class ScreenReceiver {
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onStatus: ((String) -> Void)?
    var onEnded: ((String?) -> Void)?
    private let lock = NSLock()
    private var stopped = false
    private var fd: Int32 = -1
    private var server: Process?
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var sps: [UInt8] = []
    private var pps: [UInt8] = []
    private var adbURL: URL?
    private var port: UInt16 = 0
    private var remoteJar: String?

    func start(adb: URL, serverJar: URL, serial: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var reason: String?
            do { try self.run(adb: adb, serverJar: serverJar, serial: serial) }
            catch { if !self.isStopped { reason = error.localizedDescription } }
            self.cleanup(serial: serial)
            self.onEnded?(reason)
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
        let process = server
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }; return stopped
    }

    private func command(_ executable: URL, _ arguments: [String]) throws -> String {
        let task = Process(), pipe = Pipe()
        task.executableURL = executable
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = FileHandle.standardError
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw failure("ADB command failed") }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(adb: URL, serverJar: URL, serial: String) throws {
        adbURL = adb
        onStatus?("Checking device hardware encoders…")
        let remote = "/data/local/tmp/android-camera-" + UUID().uuidString + ".jar"
        remoteJar = remote
        _ = try command(adb, ["-s", serial, "push", serverJar.path, remote])
        let encoder = try discoverEncoder(adb, remote: remote, serial: serial)
        if isStopped { return }
        let sessionID = String(format: "%08x", UInt32.random(in: 1...0x7fffffff))
        let socketName = "scrcpy_" + sessionID
        let assigned = try command(adb, ["-s", serial, "forward", "tcp:0", "localabstract:\(socketName)"])
        guard let assignedPort = UInt16(assigned) else { throw failure("Cannot read the ADB port") }
        port = assignedPort
        let task = Process()
        task.executableURL = adb
        task.arguments = ["-s", serial, "shell", "CLASSPATH=\(remote)", "app_process", "/",
                          "com.genymobile.scrcpy.Server", "5.0", "scid=\(sessionID)",
                          "tunnel_forward=true", "audio=false", "control=false", "cleanup=false",
                          "send_device_meta=false", "send_dummy_byte=false",
                          "video_codec=h264", "video_encoder=\(encoder)",
                          "max_size=2400", "max_fps=60", "video_bit_rate=24000000"]
        task.standardOutput = FileHandle.standardError
        task.standardError = FileHandle.standardError
        lock.lock(); server = task; lock.unlock()
        try task.run()
        var connected = false
        for _ in 0..<100 {
            if isStopped { return }
            let candidate = socket(AF_INET, SOCK_STREAM, 0)
            guard candidate >= 0 else { throw failure("Cannot open the video socket") }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(candidate, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 {
                lock.lock(); fd = candidate; lock.unlock()
                // ADB can accept the local socket before the device server is listening.
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(candidate, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                if let codec = try? read(4), codec == Array("h264".utf8) {
                    timeout.tv_sec = 0
                    setsockopt(candidate, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    connected = true; break
                }
                lock.lock(); fd = -1; lock.unlock()
            }
            close(candidate)
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard connected else { throw failure("Cannot connect to the Android video server") }
        while !isStopped {
            let header = try read(12)
            if header[0] & 0x80 != 0 {
                resetDecoder()
                onStatus?("Android H.264: \(integer(header[4..<8]))×\(integer(header[8..<12]))")
                continue
            }
            let length = Int(integer(header[8..<12]))
            guard length > 0 && length <= 32 * 1024 * 1024 else { throw failure("Invalid video packet") }
            let payload = try read(length)
            let nals = Self.splitNALs(payload)
            if header[0] & 0x40 != 0 {
                for nal in nals {
                    if nal.first.map({ $0 & 31 }) == 7 { sps = nal }
                    if nal.first.map({ $0 & 31 }) == 8 { pps = nal }
                }
                try configureDecoder()
            } else if session != nil {
                try decode(nals)
            }
        }
    }

    private func discoverEncoder(_ executable: URL, remote: String, serial: String) throws -> String {
        let task = Process(), pipe = Pipe()
        task.executableURL = executable
        task.arguments = ["-s", serial, "shell", "CLASSPATH=\(remote)", "app_process", "/",
            "com.genymobile.scrcpy.Server", "5.0", "list_encoders=true", "cleanup=false"]
        task.standardOutput = pipe
        task.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = adbURL?.path
        task.environment = environment
        try task.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw failure("Cannot query this device. Unlock it and authorize USB debugging, then retry.")
        }
        guard let encoder = Self.selectHardwareEncoder(output) else {
            throw failure("No H.264 hardware encoder was reported. This device is not supported in hardware-only mode.")
        }
        onStatus?("Hardware encoder selected")
        return encoder
    }

    static func selectHardwareEncoder(_ listing: String) -> String? {
        let candidates = listing.split(separator: "\n").compactMap { line -> (String, Int)? in
            guard line.contains("--video-codec=h264"), line.contains("(hw)"),
                  !line.contains("(alias for"), let range = line.range(of: "--video-encoder=") else { return nil }
            let name = String(line[range.upperBound...].prefix(while: { !$0.isWhitespace }))
            guard !name.isEmpty else { return nil }
            // Prefer native Codec2 vendor hardware, then other vendor hardware.
            let score = (line.contains("[vendor]") ? 2 : 0) + (name.hasPrefix("c2.") ? 1 : 0)
            return (name, score)
        }
        return candidates.sorted { $0.1 > $1.1 }.first?.0
    }

    private func read(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        var total = 0
        while total < count {
            let result = bytes.withUnsafeMutableBytes {
                recv(fd, $0.baseAddress!.advanced(by: total), count - total, 0)
            }
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw failure("Device disconnected or video stream ended") }
            total += result
        }
        return bytes
    }

    private func integer(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    static func splitNALs(_ bytes: [UInt8]) -> [[UInt8]] {
        var starts: [(Int, Int)] = [], i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0 && bytes[i+1] == 0 {
                if bytes[i+2] == 1 { starts.append((i, 3)); i += 3; continue }
                if i + 3 < bytes.count && bytes[i+2] == 0 && bytes[i+3] == 1 {
                    starts.append((i, 4)); i += 4; continue
                }
            }
            i += 1
        }
        return starts.enumerated().compactMap { index, start in
            let end = index + 1 < starts.count ? starts[index+1].0 : bytes.count
            let begin = start.0 + start.1
            return end > begin ? Array(bytes[begin..<end]) : nil
        }
    }

    private func configureDecoder() throws {
        guard !sps.isEmpty && !pps.isEmpty else { return }
        if let session { VTDecompressionSessionInvalidate(session); self.session = nil }
        var description: CMFormatDescription?
        let status = sps.withUnsafeBufferPointer { sp in
            pps.withUnsafeBufferPointer { pp in
                var pointers = [sp.baseAddress!, pp.baseAddress!]
                var sizes = [sp.count, pp.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2,
                    parameterSetPointers: &pointers, parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &description)
            }
        }
        guard status == noErr, let description else { throw failure("Cannot create H.264 format: \(status)") }
        format = description
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: {
            ref, _, status, _, buffer, _, _ in
            guard status == noErr, let buffer, let ref else { return }
            let receiver = Unmanaged<ScreenReceiver>.fromOpaque(ref).takeUnretainedValue()
            receiver.onFrame?(buffer)
        }, decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        let spec = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true] as CFDictionary
        let attributes = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                          kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        let result = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
            formatDescription: description, decoderSpecification: spec,
            imageBufferAttributes: attributes, outputCallback: &callback,
            decompressionSessionOut: &session)
        guard result == noErr, let session else { throw failure("Cannot create hardware decoder: \(result)") }
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        let property = UnsafeMutablePointer<Unmanaged<CFTypeRef>?>.allocate(capacity: 1)
        property.initialize(to: nil)
        defer { property.deinitialize(count: 1); property.deallocate() }
        let propertyStatus = VTSessionCopyProperty(session,
            key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: kCFAllocatorDefault, valueOut: property)
        let hardware = property.pointee?.takeRetainedValue()
        guard propertyStatus == noErr, (hardware as? NSNumber)?.boolValue == true else {
            throw failure("Hardware decoding could not be verified")
        }
        onStatus?("Hardware decoding active (VideoToolbox)")
    }

    private func decode(_ nals: [[UInt8]]) throws {
        guard let session, let format else { return }
        var data = Data()
        for nal in nals {
            var size = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
            data.append(contentsOf: nal)
        }
        guard !data.isEmpty else { return }
        var block: CMBlockBuffer?
        var result = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
            memoryBlock: nil, blockLength: data.count, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0,
            blockBufferOut: &block)
        guard result == noErr, let block else { throw failure("Cannot allocate video buffer") }
        result = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                         offsetIntoDestination: 0, dataLength: data.count)
        }
        guard result == noErr else { throw failure("Cannot copy compressed video packet") }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var size = data.count
        result = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample)
        guard result == noErr, let sample else { throw failure("Cannot create video sample") }
        result = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [],
                                                   frameRefcon: nil, infoFlagsOut: nil)
        guard result == noErr else { throw failure("Hardware decode failed: \(result)") }
    }

    private func resetDecoder() {
        if let session { VTDecompressionSessionWaitForAsynchronousFrames(session); VTDecompressionSessionInvalidate(session) }
        session = nil; format = nil; sps = []; pps = []
    }

    private func cleanup(serial: String) {
        resetDecoder()
        lock.lock()
        if fd >= 0 { close(fd); fd = -1 }
        let process = server
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
        if let adbURL {
            if port != 0 { _ = try? command(adbURL, ["-s", serial, "forward", "--remove", "tcp:\(port)"]) }
            if let remoteJar { _ = try? command(adbURL, ["-s", serial, "shell", "rm", remoteJar]) }
        }
    }

    private func failure(_ text: String) -> NSError {
        NSError(domain: "AstraCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
