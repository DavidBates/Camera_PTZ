import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() { print("PASS: \(name)") } else { failures += 1; print("FAIL: \(name)") }
}
func fixture(bitmap: UInt8 = 0x1a) -> [UInt8] {
    var d: [UInt8] = [9,2,0,0,1,1,0,0x80,50]
    d += [9,4,2,0,0,14,1,0,0] // Deliberately nonzero interface 2.
    d += [18,0x24,2,3,1,2,0,0,0,0,0,0,0,0,3,0,bitmap,0] // CT unit 3.
    d += [9,0x24,5,4,3,0,0,1,1]
    d += [26,0x24,6,9] + UVCDescriptors.logitechGUID + [2,1,4,1,3,0]
    d[2] = UInt8(d.count); return d
}
struct Packet { let type: UInt8; let request: UInt8; let value: UInt16; let index: UInt16; let bytes: [UInt8] }
class FakeUSB: USBTransport {
    var data = fixture()
    var packets: [Packet] = []
    var zoom: UInt16 = 100
    var failMotion = false
    var shortZoom = false
    var xuLength: UInt16 = 1
    func connect(_ id: UInt64) throws {}
    func disconnect() {}
    func configuration() throws -> [UInt8] { data }
    func request(type: UInt8, request: UInt8, value: UInt16, index: UInt16, bytes: inout [UInt8]) -> (Int32, UInt32) {
        packets.append(Packet(type:type,request:request,value:value,index:index,bytes:bytes))
        if request == 0x86 { bytes = [3] }
        else if request == 0x85 { bytes = value == 0x100 ? [4,0] : [UInt8(xuLength),0] }
        else if value == 0x0b00 {
            if request == 1 { zoom = bytes.le16(0) }
            else {
                let v: UInt16 = request == 0x82 ? 10 : request == 0x83 ? 200 : request == 0x84 ? 5 : zoom
                bytes = [UInt8(v & 255),UInt8(v >> 8)]
            }
            if shortZoom && request == 0x81 { return (0,1) }
        } else if value == 0x0e00 {
            if request == 1, failMotion, bytes != [0,0,0,0] { return (Int32(bitPattern:0xe00002ed),0) }
            if request != 1 { bytes = [0,1,0,1] }
        } else if value == 0x0d00, request != 1 {
            let v: Int32 = request == 0x82 ? -3600 : request == 0x83 ? 3600 : request == 0x84 ? 100 : 0
            bytes = withUnsafeBytes(of: v.littleEndian) { Array($0) }; bytes += bytes
        }
        return (0,UInt32(bytes.count))
    }
}
final class ImageUSB: FakeUSB {
    var values: [ImageControl: Int] = [.brightness: 0, .contrast: 20, .saturation: 20, .whiteBalance: 4500, .autoWhiteBalance: 1, .focus: 10, .autoFocus: 1, .antiFlicker: 2]
    var failBrightness = false
    override init() {
        super.init()
        // CT: focus absolute bit 5 + autofocus bit 17. PU: all requested controls.
        data[33] |= 0x20; data[35] |= 2
        data.replaceSubrange(36..<45, with: [10,0x24,5,4,3,0,0,2,0x4b,0x14])
        data[2] = UInt8(data.count)
    }
    override func request(type: UInt8, request: UInt8, value: UInt16, index: UInt16, bytes: inout [UInt8]) -> (Int32, UInt32) {
        guard let kind = ImageControl.allCases.first(where: { $0.selector == UInt8(value >> 8) && index == ($0.terminal ? 0x0302 : 0x0402) }) else {
            return super.request(type: type, request: request, value: value, index: index, bytes: &bytes)
        }
        packets.append(Packet(type: type, request: request, value: value, index: index, bytes: bytes))
        if request == 0x86 {
            let automatic = kind.autoPartner.map { values[$0] == 1 } ?? false
            bytes = [automatic ? 7 : 3]
        } else if request == 1 {
            if kind == .brightness && failBrightness { return (Int32(bitPattern: 0xe00002ed), 0) }
            values[kind] = kind.decode(bytes)
        } else {
            let v: Int
            switch request {
            case 0x82: v = kind == .brightness ? -64 : kind == .whiteBalance ? 2000 : 0
            case 0x83: v = kind == .brightness ? 64 : kind == .whiteBalance ? 6500 : 100
            case 0x84: v = 1
            case 0x87: v = kind.isAuto ? 1 : kind == .whiteBalance ? 4500 : kind == .antiFlicker ? 2 : 0
            default: v = values[kind] ?? 0
            }
            bytes = kind.encode(v)
        }
        return (0, UInt32(bytes.count))
    }
}
let camera = Camera(id:1,name:"CC3000e test fixture",vendor:0x046d,product:0x0848,location:1)
do {
    let parsed = try UVCDescriptors(fixture())
    check(parsed.entities.count == 3, "camera terminal, processing unit, and extension unit parsed")
    check(parsed.entities.last?.guid == UVCDescriptors.logitechGUID, "wire GUID byte order")
    check(parsed.entities.first?.interface == 2, "nonzero VideoControl interface retained")
    var malformed = fixture(); malformed[9] = 0
    do { _ = try UVCDescriptors(malformed); check(false,"reject zero length descriptor") } catch { check(true,"reject zero length descriptor") }
    var truncated = fixture(); truncated.removeLast(); truncated[2] = UInt8(truncated.count)
    do { _ = try UVCDescriptors(truncated); check(false,"reject truncated XU") } catch { check(true,"reject truncated XU") }
    let usb = FakeUSB(); let c = CC3000eController(transport:usb)
    try c.connect(camera)
    check(!usb.packets.contains { $0.request == 1 }, "connect and probing never move camera")
    check(usb.packets.filter { $0.value == 0xb00 }.allSatisfy { $0.index == 0x0302 }, "entity high byte / interface low byte")
    try c.zoom(.in)
    check(usb.zoom == 105, "zoom increments by advertised resolution")
    check(usb.packets.contains { $0.type == 0x21 && $0.request == 1 && $0.value == 0xb00 && $0.bytes == [105,0] }, "standard zoom SET_CUR packet")
    usb.zoom = 200; try c.zoom(.in); check(usb.zoom == 200,"zoom clamps at upper bound")
    usb.shortZoom = true
    do { try c.zoom(.out); check(false,"short reads fail") } catch { check(true,"short reads fail") }
    usb.shortZoom = false
    usb.packets = []; try c.pan(.right,milliseconds:30,preferLogitech:false)
    let motion = usb.packets.filter { $0.request == 1 }
    check(motion.map(\.bytes) == [[1,1,0,0],[0,0,0,0]], "relative pan pulse followed by stop")
    usb.failMotion = true; usb.packets = []
    do { try c.tilt(.up,milliseconds:30,preferLogitech:false); check(false,"motion failure surfaced") } catch { check(true,"motion failure surfaced") }
    check(usb.packets.last?.bytes == [0,0,0,0],"stop attempted after failed movement SET")
    usb.failMotion = false; usb.packets = []
    try c.pan(.right,milliseconds:30,preferLogitech:true)
    check(usb.packets.last?.bytes == [255,254,0,0] && usb.packets.last?.index == 0x0902,"Logitech XU step payload and discovered unit")
    usb.packets = []; try c.home()
    check(usb.packets.contains { $0.value == 0x200 && $0.bytes == [3] },"home XU uses one byte")
    let zoomRange = ZoomState(current:180, minimum:100, maximum:1000, resolution:1)
    check(zoomRange.stops(count:19) == Array(stride(from:100, through:1000, by:50)), "19 zoom stops map to half-x spacing")
    check(zoomRange.adjacent(direction:.in, stopCount:19) == 200 && zoomRange.adjacent(direction:.out, stopCount:19) == 150, "buttons use adjacent slider stops from an off-notch zoom")
    let quantized = ZoomState(current:10, minimum:10, maximum:198, resolution:5)
    check(quantized.stops(count:91).allSatisfy { ($0-10) % 5 == 0 && $0 <= 198 }, "zoom stops respect hardware resolution")
    check(quantized.clamped(1000) == 195 && quantized.clamped(-10) == 10, "zoom target clamps without off-grid upper bound")
    check(ZoomState(current:10, minimum:10, maximum:10, resolution:1).stops(count:19) == [10], "fixed zoom range produces one stop")
    try c.setZoom(107)
    check(usb.zoom == 105, "arbitrary zoom targets quantize to device resolution")
    try c.setZoom(9000)
    check(usb.zoom == 200, "arbitrary zoom target clamps to device maximum")
    let noControls = FakeUSB(); noControls.data = fixture(bitmap:0)
    let empty = CC3000eController(transport:noControls); try empty.connect(camera)
    check(!noControls.packets.contains { $0.index == 0x0302 },"unadvertised CT controls are not probed")
    do { try empty.zoom(.in); check(false,"unsupported zoom rejected") } catch { check(true,"unsupported zoom rejected") }
    let wrongLength = FakeUSB(); wrongLength.xuLength = 4
    let wrong = CC3000eController(transport:wrongLength); try wrong.connect(camera); wrongLength.packets = []; try wrong.home()
    check(!wrongLength.packets.contains { $0.value == 0x200 && $0.request == 1 },"unexpected XU length never written")
} catch { failures += 1; print("UNEXPECTED: \(error)") }
do {
    let usb = ImageUSB()
    let c = CC3000eController(transport: usb); try c.connect(camera)
    let controls = c.readImageControls()
    check(controls.count == 8, "all eight advertised image controls discovered")
    check(controls.first { $0.control == .focus }?.writable == false, "manual focus remains visible while autofocus disables writes")
    usb.packets = []
    do { try c.setImageControl(.focus, value: 30); check(false, "manual focus rejected while auto is on") }
    catch { check(!usb.packets.contains { $0.request == 1 }, "manual focus rejected without writing while auto is on") }
    try c.setImageControl(.autoFocus, value: 0)
    try c.setImageControl(.focus, value: 30)
    check(usb.packets.contains { $0.request == 1 && $0.index == 0x0302 && $0.value == 0x0600 && $0.bytes == [30,0] }, "manual focus addresses discovered camera terminal")
    try c.setImageControl(.brightness, value: -20)
    check(usb.packets.contains { $0.request == 1 && $0.index == 0x0402 && $0.value == 0x0200 && $0.bytes == [236,255] }, "brightness addresses processing unit with signed payload")
    usb.packets = []; try c.restoreImageDefaults()
    check(usb.values[.autoFocus] == 1 && usb.values[.autoWhiteBalance] == 1, "restore returns automatic modes to camera defaults")
    check(!usb.packets.contains { $0.request == 1 && ($0.index == 0x0902 || $0.value == 0x0b00 && $0.index == 0x0302 || $0.value == 0x0e00) }, "restore image defaults never changes PTZ or vendor presets")
    usb.failBrightness = true
    do { try c.restoreImageDefaults(); check(false, "partial restore failure surfaced") }
    catch { check(usb.values[.autoFocus] == 1, "partial restore failure surfaced while auto modes still restored") }
} catch { failures += 1; print("IMAGE TEST ERROR: \(error)") }
// Signed UVC brightness and control routing must not be confused with zoom/XU selectors.
check(ImageControl.brightness.decode([0xff,0xff]) == -1, "brightness decodes signed little endian")
check(ImageControl.brightness.encode(-128) == [128,255], "negative brightness encoding")
check(ImageControl.focus.selector == 6 && ImageControl.focus.bit == 5 && ImageControl.focus.terminal, "manual focus uses CT selector 6, bitmap bit 5")
check(ImageControl.autoFocus.selector == 8 && ImageControl.autoFocus.bit == 17, "autofocus uses CT selector 8, bitmap bit 17")
check(ImageControl.antiFlicker.encode(2) == [2], "60 Hz uses one-byte 02")
check(ImageControl.whiteBalance.encode(4500) == [148,17], "Kelvin uses unsigned two-byte payload")
let imageRange = ImageControlState(control: .brightness, current: 0, minimum: -64, maximum: 64, resolution: 2, defaultValue: 0, writable: true)
check(imageRange.clamped(-999) == -64 && imageRange.clamped(999) == 64 && imageRange.clamped(3) == 2, "signed image range clamps and quantizes")
print("Protocol tests: \(failures) failures")
exit(failures == 0 ? 0 : 1)
