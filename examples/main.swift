import Kiln

let point = Schema.structure([("x", .i32), ("y", .i32)])
let value = Value.object(["x": .int(9), "y": .int(-4)])
let writer = Writer(capacity: 64)
let raw = try writer.encode(point, value)
let back = try decode(point, Array(raw))
print(back == value ? "ok" : "mismatch", raw.count)
