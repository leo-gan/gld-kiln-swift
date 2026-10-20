import Foundation
import Kiln

let point = Schema.structure([("x", .i32), ("y", .i32), ("label", .str)])
let value = Value.object([
    "x": .int(9),
    "y": .int(-4),
    "label": .string("item"),
])
var payload = [UInt8](repeating: 0, count: 1024 * 4)
for index in 0..<1024 {
    var bits = Float(1).bitPattern.littleEndian
    withUnsafeBytes(of: &bits) { raw in
        for offset in 0..<4 {
            payload[index * 4 + offset] = raw[offset]
        }
    }
}
let tensor = Tensor(dtype: 2, dtypeName: "f32", shape: [1024], data: payload)

func bench(_ count: Int, warm: Int, _ body: () throws -> Void) rethrows -> Int {
    for _ in 0..<warm { try body() }
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<count { try body() }
    return Int((DispatchTime.now().uptimeNanoseconds - start) / UInt64(count))
}

let writer = Writer(capacity: 256)
let encodeNs = try bench(2000, warm: 100) {
    _ = try writer.encode(point, value)
}
let encoded = Array(try writer.encode(point, value))
let decodeNs = try bench(2000, warm: 100) {
    _ = try decode(point, encoded)
}
let block = try encodeTensors([tensor])
let tensorEncodeNs = try bench(200, warm: 20) {
    _ = try encodeTensors([tensor])
}
let tensorDecodeNs = try bench(200, warm: 20) {
    _ = try decodeTensors(block)
}
print("struct_encode_ns", encodeNs)
print("struct_decode_ns", decodeNs)
print("struct_bytes", encoded.count)
print("tensor_encode_ns", tensorEncodeNs)
print("tensor_decode_ns", tensorDecodeNs)
print("tensor_bytes", block.count)
