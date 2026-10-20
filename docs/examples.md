# Examples

`Point` has two `i32` fields. Kiln writes them in that order. Eight little-endian bytes, and no names.

```swift
import Kiln

let point = Schema.structure([("x", .i32), ("y", .i32)])
let writer = Writer(capacity: 64)
let raw = try writer.encode(point, .object(["x": .int(9), "y": .int(-4)]))
print(try decode(point, Array(raw)), raw.count)
```

`raw.count` is 8.

A tensor directory keeps the numeric payload as the array. `data` on a decoded tensor is a copy; the directory also keeps a view of the input until that copy is made.

```swift
import Kiln

let block = try encodeTensors([
    try tensor("f32", shape: [2], data: [0x00, 0x00, 0x80, 0x3f, 0x00, 0x00, 0x00, 0xc0]),
])
let (directory, length) = try decodeTensors(block)
print(length, directory.tensors[0].data)
```

`examples/main.swift` is the `kiln-example` executable. `benches/main.swift` is `kiln-bench`.
