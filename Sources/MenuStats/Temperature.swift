// persuara

import Foundation
import IOKit

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<CFTypeRef>?

final class TemperatureReader {
    private let client: AnyObject?

    init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        if let client {
            let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
            _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        }
    }

    func read() -> Double? {
        guard let client,
              let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject]
        else { return nil }

        var dieTemps: [Double] = [], allTemps: [Double] = []
        for service in services {
            guard let event = IOHIDServiceClientCopyEvent(service, 15, 0, 0)?.takeRetainedValue()
            else { continue }
            let t = IOHIDEventGetFloatValue(event, 15 << 16)
            guard t > 0, t < 150 else { continue }
            allTemps.append(t)
            let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String ?? ""
            if name.localizedCaseInsensitiveContains("tdie") { dieTemps.append(t) }
        }
        let pool = dieTemps.isEmpty ? allTemps : dieTemps
        guard !pool.isEmpty else { return nil }
        return pool.reduce(0, +) / Double(pool.count)
    }
}
