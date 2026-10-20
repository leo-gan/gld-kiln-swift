# gld-kiln-swift

A from-scratch Kiln codec for Swift. The runtime and the code generator are Swift. They do not wrap, link, or vendor another language's Kiln library.

`testdata/reference/kiln_ref.py` is a test oracle for Frozen values. It is not used at run time.

This repository is a standalone library.

Documentation: [Why Kiln](https://leo-gan.github.io/gld-kiln-swift/why-kiln/),
[Instructions](https://leo-gan.github.io/gld-kiln-swift/instructions/),
[Examples](https://leo-gan.github.io/gld-kiln-swift/examples/),
[Techniques](https://leo-gan.github.io/gld-kiln-swift/techniques/),
[Test data](https://leo-gan.github.io/gld-kiln-swift/test-data/).

## Install

Swift Package Manager, Swift 6.3. The module is `Kiln`. The generator command is `gld-kilngen-swift`.

```swift
dependencies: [
    .package(url: "https://github.com/leo-gan/gld-kiln-swift", from: "0.1.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "Kiln", package: "gld-kiln-swift"),
    ]),
]
```

```swift
import Kiln

let point = Schema.structure([("x", .i32), ("y", .i32)])
let writer = Writer(capacity: 64)
let raw = try writer.encode(point, .object(["x": .int(9), "y": .int(-4)]))
print(try decode(point, Array(raw)))
```

## License

MIT. Copyright (c) 2026 Leonid Ganeline.
