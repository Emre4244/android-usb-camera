import AppKit
import Foundation

@main
final class AndroidBridgeApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var status: NSTextField!
    private var counters: NSTextField!
    private var button: NSButton!
    private var devicePicker: NSPopUpButton!
    private var receiver: ScreenReceiver?
    private var sink: CameraSink?
    private let videoQueue = DispatchQueue(label: "Astra.Camera.GPU", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var statsTimer: Timer?
    private var deviceTimer: Timer?
    private var scanning = false
    private var startWhenConnected = true
    private var decoded = 0
    private var lastDecoded = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = AndroidBridgeApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        let menu = NSMenu(), applicationMenu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        item.submenu = applicationMenu
        applicationMenu.addItem(withTitle: "Quit Android USB Camera",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.mainMenu = menu
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 250),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Android USB Camera"
        window.isReleasedWhenClosed = false
        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root
        let heading = label("Android screen → OBS video device", y: 200)
        heading.font = .boldSystemFont(ofSize: 18)
        root.addSubview(heading)
        root.addSubview(label("OBS: Video Capture Device → OBS Virtual Camera", y: 162))
        root.addSubview(label("Keep OBS’s Start Virtual Camera output OFF.", y: 134))
        status = label("Preparing connection…", y: 99)
        root.addSubview(status)
        counters = label("Hardware video · Apple VideoToolbox · Metal", y: 70)
        root.addSubview(counters)
        button = NSButton(title: "Stop", target: self, action: #selector(toggle))
        button.frame = NSRect(x: 24, y: 20, width: 120, height: 32)
        root.addSubview(button)
        devicePicker = NSPopUpButton(frame: NSRect(x: 157, y: 23, width: 280, height: 28))
        devicePicker.target = self
        devicePicker.action = #selector(deviceChanged)
        root.addSubview(devicePicker)
        let refresh = NSButton(title: "Refresh devices", target: self, action: #selector(refreshDevices))
        refresh.frame = NSRect(x: 442, y: 20, width: 125, height: 32)
        root.addSubview(refresh)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        refreshDevices()
        deviceTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let stats = self.videoQueue.sync { (self.decoded, self.sink?.sent ?? 0, self.sink?.dropped ?? 0) }
            let fps = stats.0 - self.lastDecoded
            self.lastDecoded = stats.0
            self.counters.stringValue = "New frames: \(fps)/s · Sent: \(stats.1) · Queue drops: \(stats.2)"
        }
    }

    private func label(_ value: String, y: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.frame = NSRect(x: 24, y: y, width: 545, height: 26)
        return field
    }

    private func start() {
        guard receiver == nil, let resources = Bundle.main.resourceURL else { return }
        guard let serial = devicePicker.selectedItem?.representedObject as? String else {
            status.stringValue = "No authorized Android device. Enable USB debugging and refresh."
            button.title = "Start"
            return
        }
        do {
            let camera = try videoQueue.sync { try CameraSink() }
            sink = camera
            let source = ScreenReceiver()
            receiver = source
            source.onStatus = { [weak self, weak source] text in
                DispatchQueue.main.async {
                    guard let self, self.receiver === source else { return }
                    self.status.stringValue = text
                }
            }
            source.onEnded = { [weak self, weak source] reason in
                DispatchQueue.main.async {
                    guard let self, self.receiver === source else { return }
                    self.stop()
                    self.status.stringValue = reason ?? "Disconnected. Refresh devices and retry."
                }
            }
            source.onFrame = { [weak self] pixel in
                guard let self else { return }
                self.videoQueue.sync {
                    self.decoded += 1
                    self.sink?.prepare(pixel)
                }
            }
            let timer = DispatchSource.makeTimerSource(queue: videoQueue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 60.0, leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.sink?.sendLatest() }
            self.timer = timer
            timer.resume()
            source.start(adb: resources.appendingPathComponent("adb"),
                serverJar: resources.appendingPathComponent("scrcpy-server"), serial: serial)
            button.title = "Stop"
        } catch {
            status.stringValue = error.localizedDescription
            button.title = "Retry"
        }
    }

    private func stop() {
        receiver?.stop()
        receiver = nil
        timer?.cancel(); timer = nil
        videoQueue.sync { sink = nil }
        status.stringValue = "Stopped"
        button.title = "Start"
    }

    @objc private func toggle() {
        startWhenConnected = receiver == nil
        receiver == nil ? start() : stop()
    }

    @objc private func deviceChanged() {
        startWhenConnected = true
        stop()
        // Let the previous device's server close its socket before reconnecting.
        button.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.button.isEnabled = true
            self?.start()
        }
    }

    @objc private func refreshDevices() {
        guard !scanning, let resources = Bundle.main.resourceURL else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process(), output = Pipe()
            process.executableURL = resources.appendingPathComponent("adb")
            process.arguments = ["devices", "-l"]
            process.standardOutput = output
            process.standardError = FileHandle.standardError
            var devices: [(String, String)] = []
            var errorMessage: String?
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 { throw NSError(domain: "ADB", code: 1) }
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    guard fields.count > 1, fields[1] == "device" else { continue }
                    let model = fields.first(where: { $0.hasPrefix("model:") })?.dropFirst(6) ?? "Android"
                    devices.append((fields[0], String(model).replacingOccurrences(of: "_", with: " ")))
                }
            } catch { errorMessage = "ADB unavailable. Please restart the app." }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                let previous = self.devicePicker.selectedItem?.representedObject as? String
                self.devicePicker.removeAllItems()
                for (serial, model) in devices {
                    self.devicePicker.addItem(withTitle: model)
                    self.devicePicker.lastItem?.representedObject = serial
                    if serial == previous { self.devicePicker.select(self.devicePicker.lastItem) }
                }
                if devices.isEmpty && self.receiver == nil {
                    self.status.stringValue = errorMessage ?? "Connect a device and authorize USB debugging."
                } else if self.receiver == nil && self.startWhenConnected && previous == nil {
                    self.start()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
        statsTimer?.invalidate()
        deviceTimer?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
