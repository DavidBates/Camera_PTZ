import Foundation

extension Array where Element == UInt8 {
    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
    func le16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i+1]) << 8 }
    func le32(_ i: Int) -> Int32 { Int32(bitPattern: UInt32(self[i]) | UInt32(self[i+1]) << 8 | UInt32(self[i+2]) << 16 | UInt32(self[i+3]) << 24) }
}
struct UVCEntity {
    let interface: UInt8
    let id: UInt8
    let subtype: UInt8
    let controls: [UInt8]
    let guid: [UInt8]
    func has(_ bit: Int) -> Bool { bit >= 0 && bit / 8 < controls.count && controls[bit / 8] & (1 << (bit % 8)) != 0 }
}
struct UVCDescriptors {
    static let logitechGUID: [UInt8] = [0x21,0x2d,0xe5,0xff,0x30,0x80,0x2c,0x4e,0x82,0xd9,0xf5,0x87,0xd0,0x05,0x40,0xbd]
    var entities: [UVCEntity] = []
    var notes: [String] = []
    init(_ data: [UInt8]) throws {
        guard data.count >= 9, data[1] == 2, Int(data.le16(2)) == data.count else { throw PTZError.message("Invalid configuration descriptor") }
        var offset = 0; var vc: UInt8?
        while offset < data.count {
            let length = Int(data[offset])
            guard length >= 2, offset + length <= data.count else { throw PTZError.message("Malformed descriptor at \(offset)") }
            let d = Array(data[offset..<offset+length]); defer { offset += length }
            notes.append("descriptor @\(offset): \(d.hexString)")
            if d[1] == 4 {
                guard d.count >= 9 else { throw PTZError.message("Truncated interface") }
                notes.append("Interface \(d[2]) alt=\(d[3]) class=\(d[5]) subclass=\(d[6])")
                vc = d[5] == 14 && d[6] == 1 && d[3] == 0 ? d[2] : nil
            }
            guard d[1] == 0x24, d.count >= 4, let interface = vc else { continue }
            var controls: [UInt8] = []; var guid: [UInt8] = []
            switch d[2] {
            case 2:
                guard d.count >= 8 else { throw PTZError.message("Truncated input terminal") }
                notes.append(String(format: "Input terminal %u type=0x%04X", d[3], d.le16(4)))
                guard d.le16(4) == 0x0201 else { continue }
                guard d.count >= 15, d.count >= 15 + Int(d[14]) else { throw PTZError.message("Truncated camera terminal bitmap") }
                controls = Array(d[15..<15+Int(d[14])])
            case 5:
                guard d.count >= 8, d.count >= 8 + Int(d[7]) else { throw PTZError.message("Truncated processing unit") }
                controls = Array(d[8..<8+Int(d[7])])
                notes.append("Processing unit \(d[3]) source=\(d[4])")
            case 6:
                guard d.count >= 23 else { throw PTZError.message("Truncated extension unit") }
                guid = Array(d[4..<20]); let sizeOffset = 22 + Int(d[21])
                guard sizeOffset < d.count, sizeOffset + 1 + Int(d[sizeOffset]) < d.count else { throw PTZError.message("Truncated extension unit bitmap") }
                controls = Array(d[(sizeOffset+1)..<(sizeOffset+1+Int(d[sizeOffset]))])
                notes.append("XU \(d[3]) GUID(wire)=\(guid.hexString) controls=\(d[20]) sources=\(Array(d[22..<sizeOffset]).hexString)")
            default: continue
            }
            let entity = UVCEntity(interface: interface, id: d[3], subtype: d[2], controls: controls, guid: guid)
            if d[2] == 6 {
                notes.append("XU \(entity.id) advertised selectors=\((0..<controls.count*8).filter { entity.has($0) }.map { $0 + 1 })")
            }
            entities.append(entity)
            notes.append("Entity \(entity.id) interface=\(interface) bmControls=\(controls.hexString) supported bits=\((0..<controls.count*8).filter { entity.has($0) })")
        }
    }
}
enum PTZError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
