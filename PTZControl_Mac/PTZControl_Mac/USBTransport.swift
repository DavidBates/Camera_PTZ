import Foundation

protocol USBTransport: AnyObject {
    func connect(_ registryID: UInt64) throws
    func disconnect()
    func configuration() throws -> [UInt8]
    func request(type: UInt8, request: UInt8, value: UInt16, index: UInt16, bytes: inout [UInt8]) -> (Int32, UInt32)
}
final class IOKitUSBTransport: USBTransport {
    private var handle: OpaquePointer?
    func connect(_ registryID: UInt64) throws {
        disconnect()
        var result: Int32 = 0
        handle = PTZUSBConnect(registryID, &result)
        guard handle != nil else { throw PTZError.message(String(format: "USB user client creation failed: 0x%08X. Check console, USB entitlement, and runtime restrictions; no requests sent.", UInt32(bitPattern: result))) }
    }
    func disconnect() { PTZUSBDisconnect(handle); handle = nil }
    func configuration() throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 65535)
        let count = Int(PTZUSBDescriptor(handle, &bytes, Int32(bytes.count)))
        guard count > 0 else { throw PTZError.message("Cannot read active USB configuration descriptors") }
        return Array(bytes.prefix(count))
    }
    func request(type: UInt8, request: UInt8, value: UInt16, index: UInt16, bytes: inout [UInt8]) -> (Int32, UInt32) {
        var actual: UInt32 = 0
        let result = PTZUSBRequest(handle, type, request, value, index, &bytes, UInt16(bytes.count), &actual)
        return (result, actual)
    }
    deinit { disconnect() }
}
