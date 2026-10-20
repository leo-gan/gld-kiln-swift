# Instructions

Swift 6.3.

```swift
dependencies: [
    .package(url: "https://github.com/leo-gan/gld-kiln-swift", from: "0.2.0"),
],
```

The import name is `Kiln`. From a git checkout:

```bash
bash scripts/run-tests.sh
swift run gld-kilngen-swift --schema testdata/schema/point.json --out tests/generated
```

`encode` and `decode` take a `Schema` and a `Value`. `Writer` reuses one buffer across calls. `schemaFromJSON` reads the JSON Schema subset: booleans, integers with an optional `format`, numbers, strings, binary strings, arrays, objects, `$ref` of the form `#/$defs/Name`, and `additionalProperties` as a dict. A property omitted from `required` is optional. `gld-kilngen-swift` writes Swift structs with `encode`, `decode`, and `encodedSize`. A `tensors` field is not produced from that JSON subset. Build a tensor directory with `encodeTensors` and read it with `decodeTensors`.

Pass `cap:` to raise the default of 16,777,216 counts and 16 MiB for one string or byte run. Pass `trusted: true` to skip UTF-8 checks and quant-shape checks on a buffer this process just wrote. A length past the buffer is still `EOF`.
