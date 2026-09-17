import Foundation

// All calls are made on CameraController's serial USB queue (also used by the diagnostic CLI).
final class CC3000eController: PTZCameraController, @unchecked Sendable {
    private let presetStore: PTZPresetStore
    private let transport: USBTransport
    private var connected = false
    init(transport: USBTransport = IOKitUSBTransport(), presetStore: PTZPresetStore = DefaultsPresetStore()) { self.transport = transport; self.presetStore = presetStore }
    private var camera: Camera?
    private var descriptors: UVCDescriptors?
    private var log: [String] = []
    private struct Control {
        let entity: UVCEntity; let selector: UInt8; let length: Int; let info: UInt8
    }
    private var zoomControl: Control?
    private var relative: Control?
    private var absolute: Control?
    private var xuMotion: Control?
    private var xuMode: Control?
    private var moving = false
    private(set) var supportedMovementSpeeds: ClosedRange<Int>?
    var speed: UInt8 = 1
    var experimentalHardwarePresets = false
    // CC3000e is absent from cameractrls' preset allowlist. Use software positions
    // when GET_CUR/SET_CUR absolute controls exist; never guess vendor preset support.
    private let vendorPresetProducts: Set<UInt16> = [0x0853,0x0858,0x085f,0x0866,0x0881,0x0888,0x0889]

    static func discover() -> [Camera] {
        var identities = [PTZUSBIdentity](repeating: PTZUSBIdentity(), count: 64)
        let count = Int(PTZUSBEnumerate(&identities, 64))
        return identities.prefix(count).map { value in
            var d = value
            let name = withUnsafeBytes(of: &d.name) { bytes in String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
            return Camera(id: d.registryID, name: name, vendor: d.vendor, product: d.product, location: d.location)
        }.filter { $0.name.localizedCaseInsensitiveContains("camera") || $0.name.localizedCaseInsensitiveContains("PTZ") }
    }
    private func record(_ message: String) {
        let line = "[PTZ \(ISO8601DateFormatter().string(from: Date()))] \(message)"
        print(line); log.append(line)
        if log.count > 3000 { log.removeFirst(log.count - 3000) }
    }
    func diagnosticReport() -> String { log.joined(separator: "\n") }
    func connect(_ camera: Camera) throws {
        disconnect(); log = []; self.camera = camera
        record(String(format: "Connect %@ VID=%04X PID=%04X location=%08X registry=%llu", camera.name, camera.vendor, camera.product, camera.location, camera.id))
        do {
            try transport.connect(camera.id)
            connected = true
            let parsed = try UVCDescriptors(transport.configuration()); descriptors = parsed
            parsed.notes.forEach { record($0) }
            let terminals = parsed.entities.filter { $0.subtype == 2 }
            guard terminals.count == 1 else { throw PTZError.message("Expected one camera terminal; refusing ambiguous routing") }
            let ct = terminals[0]
            zoomControl = probe(ct, selector: 0x0b, bit: 9, length: 2)
            relative = probe(ct, selector: 0x0e, bit: 12, length: 4)
            absolute = probe(ct, selector: 0x0d, bit: 11, length: 8)
            if let relative, let low = try? get(relative, 0x82), let high = try? get(relative, 0x83) {
                let lower = max(1, Int(low[1]), Int(low[3])), upper = min(Int(high[1]), Int(high[3]))
                if upper >= lower { supportedMovementSpeeds = lower...upper }
            }
            let units = parsed.entities.filter { $0.guid == UVCDescriptors.logitechGUID }
            if units.count == 1 {
                xuMotion = probe(units[0], selector: 1, bit: 0, length: 4, extensionUnit: true)
                xuMode = probe(units[0], selector: 2, bit: 1, length: 1, extensionUnit: true)
            }
            record("Capabilities zoom=\(zoomControl != nil) relativePT=\(relative != nil) absolutePT=\(absolute != nil) LogitechStep=\(xuMotion != nil) LogitechReset=\(xuMode != nil)")
            guard zoomControl != nil || relative != nil || absolute != nil || xuMotion != nil || xuMode != nil else { throw PTZError.message("No writable PTZ controls verified; inspect probe failures") }
            record("No capture session, device seize, interface claim, configuration change, or startup movement performed.")
        } catch { record("Connection failed: \(error.localizedDescription)"); transport.disconnect(); connected = false; throw error }
    }
    func disconnect() {
        if moving { try? stop() }
        transport.disconnect(); connected = false; moving = false
        supportedMovementSpeeds = nil
        descriptors = nil; zoomControl = nil; relative = nil; absolute = nil; xuMotion = nil; xuMode = nil; camera = nil
    }
    deinit { disconnect() }
    private func transfer(_ e: UVCEntity, _ selector: UInt8, _ request: UInt8, _ payload: [UInt8]) throws -> [UInt8] {
        guard connected else { throw PTZError.message("Camera disconnected") }
        var bytes = payload
        let type: UInt8 = request & 0x80 == 0 ? 0x21 : 0xa1
        let value = UInt16(selector) << 8
        let index = UInt16(e.id) << 8 | UInt16(e.interface)
        record(String(format: "USB bmRequestType=%02X bRequest=%02X wValue=%04X wIndex=%04X wLength=%d OUT=[%@]", type, request, value, index, bytes.count, type == 0x21 ? bytes.hexString : ""))
        let start = Date()
        let (result, actual) = transport.request(type: type, request: request, value: value, index: index, bytes: &bytes)
        record(String(format: "USB IOReturn=0x%08X actual=%u elapsed=%.3fs IN=[%@]", UInt32(bitPattern: result), actual, Date().timeIntervalSince(start), type == 0xa1 ? Array(bytes.prefix(Int(min(actual, UInt32(bytes.count))))).hexString : ""))
        guard result == 0 else { throw PTZError.message(String(format: "USB request failed 0x%08X (entity %u selector %u); see full console log", UInt32(bitPattern: result), e.id, selector)) }
        guard actual == bytes.count else { throw PTZError.message("Short USB transfer: \(actual)/\(bytes.count)") }
        return bytes
    }
    private func probe(_ e: UVCEntity, selector: UInt8, bit: Int, length: Int, extensionUnit: Bool = false) -> Control? {
        guard e.has(bit) else { record("Not advertised: entity \(e.id) selector \(selector)"); return nil }
        do {
            let info = try transfer(e, selector, 0x86, [0])[0]
            guard info & 2 != 0, info & 4 == 0 else { record("Control not writable or disabled: \(selector)"); return nil }
            if extensionUnit {
                let len = try transfer(e, selector, 0x85, [0,0]).le16(0)
                guard len == length else { record("Unsupported XU payload length \(len), expected \(length)"); return nil }
            }
            let c = Control(entity: e, selector: selector, length: length, info: info)
            if !extensionUnit && info & 1 != 0 {
                for request: UInt8 in [0x81,0x82,0x83,0x84,0x87] { _ = try? get(c, request) }
            }
            return c
        } catch { record("Probe failed: \(error.localizedDescription)"); return nil }
    }
    private func get(_ c: Control, _ request: UInt8 = 0x81) throws -> [UInt8] {
        guard c.info & 1 != 0 else { throw PTZError.message("GET unsupported") }
        return try transfer(c.entity, c.selector, request, [UInt8](repeating: 0, count: c.length))
    }
    private func set(_ c: Control, _ bytes: [UInt8]) throws {
        guard bytes.count == c.length else { throw PTZError.message("Internal payload length mismatch") }
        _ = try transfer(c.entity, c.selector, 1, bytes)
    }
    private func encoded<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
    func readZoom() throws -> ZoomState {
        guard let c = zoomControl else { throw PTZError.message("Standard absolute zoom unavailable") }
        let current = Int(try get(c).le16(0)), low = Int(try get(c, 0x82).le16(0)), high = Int(try get(c, 0x83).le16(0))
        let resolution = Int(try get(c, 0x84).le16(0))
        guard low <= high, current >= low, current <= high, resolution > 0 else { throw PTZError.message("Invalid zoom range/resolution") }
        return ZoomState(current: current, minimum: low, maximum: high, resolution: resolution)
    }
    func setZoom(_ value: Int) throws {
        guard let c = zoomControl else { throw PTZError.message("Standard absolute zoom unavailable") }
        let state = try readZoom()
        let target = state.clamped(value)
        try set(c, encoded(UInt16(target)))
        let readback = Int(try get(c).le16(0))
        record("Zoom readback=\(readback) target=\(target)")
        guard readback == target else { throw PTZError.message("Camera reports zoom \(readback), requested \(target)") }
    }
    func zoom(_ direction: ZoomDirection) throws {
        let state = try readZoom()
        try setZoom(state.current + (direction == .in ? state.resolution : -state.resolution))
    }
    private var hardwarePresetsAvailable: Bool {
        guard let camera, xuMode != nil else { return false }
        return vendorPresetProducts.contains(camera.product) || (camera.product == 0x0848 && experimentalHardwarePresets)
    }
    func pan(_ direction: PanDirection, milliseconds: Int, preferLogitech: Bool) throws { try move(x: direction == .left ? -1 : 1, y: 0, milliseconds: milliseconds, preferLogitech: preferLogitech) }
    func tilt(_ direction: TiltDirection, milliseconds: Int, preferLogitech: Bool) throws { try move(x: 0, y: direction == .up ? 1 : -1, milliseconds: milliseconds, preferLogitech: preferLogitech) }
    private func move(x: Int, y: Int, milliseconds: Int, preferLogitech: Bool) throws {
        if let c = xuMotion, preferLogitech || (relative == nil && absolute == nil) {
            // Exact one-step byte sequences from cameractrls; these are NOT the UVC direction/speed packet.
            let pan: [UInt8] = x < 0 ? [0,1] : x > 0 ? [0xff,0xfe] : [0,0]
            let tilt: [UInt8] = y > 0 ? [0xff,0xfe] : y < 0 ? [0,1] : [0,0]
            try set(c, pan + tilt); return
        }
        if let c = relative {
            let low = try get(c, 0x82), high = try get(c, 0x83), resolution = try get(c, 0x84)
            func supportedSpeed(_ offset: Int) throws -> UInt8 {
                let minimum = max(1, Int(low[offset])), maximum = Int(high[offset]), step = max(1, Int(resolution[offset]))
                guard minimum <= maximum else { throw PTZError.message("Invalid relative speed range") }
                return UInt8(minimum + (max(minimum, min(maximum, Int(speed))) - minimum) / step * step)
            }
            let sx = try supportedSpeed(1), sy = try supportedSpeed(3)
            moving = true
            do {
                try set(c, [UInt8(bitPattern: Int8(x)), x == 0 ? 0 : sx, UInt8(bitPattern: Int8(y)), y == 0 ? 0 : sy])
                // Preserve click-to-nudge UI. Bounded pulse on USB worker; every pulse ends with STOP.
                Thread.sleep(forTimeInterval: Double(max(30, min(500, milliseconds))) / 1000)
                try stop()
            } catch { try? stop(); throw error }
            return
        }
        if let c = absolute {
            let cur = try get(c), low = try get(c,0x82), high = try get(c,0x83), res = try get(c,0x84)
            func next(_ offset: Int, _ direction: Int) throws -> Int32 {
                let l = Int64(low.le32(offset)), h = Int64(high.le32(offset)), v = Int64(cur.le32(offset)), step = Int64(res.le32(offset))
                guard l <= h, v >= l, v <= h, step > 0 else { throw PTZError.message("Invalid absolute pan/tilt range") }
                return Int32(max(l,min(h,v + Int64(direction) * step)))
            }
            try set(c, encoded(try next(0,x)) + encoded(try next(4,y))); return
        }
        throw PTZError.message("No verified pan/tilt control available")
    }
    func stop() throws {
        if let c = relative {
            // Keep moving=true on failure so disconnect retries the stop.
            try set(c, [0,0,0,0]); moving = false
        } else { record("No advertised continuous STOP control; an already submitted absolute/XU step cannot be cancelled by this backend") }
    }
    func home() throws {
        try stop()
        if let c = xuMode { try set(c, [3]) }
        else if let c = absolute { let value = try get(c,0x87); try set(c,value) }
        else { throw PTZError.message("No verified home/reset control") }
        if let c = zoomControl { let value = try get(c,0x87); try set(c,value) }
    }
    private func presetKey(_ slot: Int) throws -> String {
        guard (1...8).contains(slot), let camera else { throw PTZError.message("Invalid preset or no camera") }
        return "UVCPosition_\(camera.vendor)_\(camera.product)_\(camera.location)_\(slot)"
    }
    func savePreset(_ slot: Int) throws {
        let key = try presetKey(slot)
        try stop()
        if hardwarePresetsAvailable, let c = xuMode {
            try set(c,[UInt8(slot+3)])
            record("Hardware preset \(slot) SAVE accepted; recall still requires physical verification")
            return
        }
        guard let p = absolute, let z = zoomControl else { throw PTZError.message("Hardware presets unverified for CC3000e; software presets need readable absolute pan/tilt and zoom") }
        let position = try get(p) + get(z)
        presetStore.save(Data(position), key: key)
        record("Saved software preset \(slot) for this USB location")
    }
    func recallPreset(_ slot: Int) throws {
        let key = try presetKey(slot)
        try stop()
        if hardwarePresetsAvailable, let c = xuMode {
            try set(c,[UInt8(slot+11)])
            record("Hardware preset \(slot) RECALL accepted")
            return
        }
        guard let p = absolute, let z = zoomControl, let stored = presetStore.load(key: key), stored.count == 10 else { throw PTZError.message("No software preset saved, or absolute controls unavailable") }
        let bytes = Array(stored)
        let low = try get(p,0x82), high = try get(p,0x83)
        for i in [0,4] { guard bytes.le32(i) >= low.le32(i), bytes.le32(i) <= high.le32(i) else { throw PTZError.message("Saved preset outside current range") } }
        let zl = try get(z,0x82).le16(0), zh = try get(z,0x83).le16(0)
        guard bytes.le16(8) >= zl, bytes.le16(8) <= zh else { throw PTZError.message("Saved zoom outside range") }
        try set(p,Array(bytes.prefix(8))); try set(z,Array(bytes.suffix(2)))
    }
}
