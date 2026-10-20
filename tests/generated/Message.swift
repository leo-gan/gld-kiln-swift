import Kiln

public struct Meta: Equatable, Sendable {
    public var region: String
    public var flag: Bool

    public init(region: String = "", flag: Bool = false) {
        self.region = region
        self.flag = flag
    }

    public static func schema() -> Schema {
        .structure([
            ("region", .str),
            ("flag", .bool),
        ], name: "Meta")
    }

    public func encode() throws -> [UInt8] {
        try Kiln.encode(Meta.schema(), toValue())
    }

    public static func decode(_ bytes: [UInt8]) throws -> Meta {
        try fromValue(Kiln.decode(Meta.schema(), bytes))
    }

    public func encodedSize() throws -> Int {
        try encode().count
    }

    public func toValue() -> Value {
        .object([
            "region": .string(self.region),
            "flag": .bool(self.flag),
        ])
    }

    public static func fromValue(_ value: Value) throws -> Meta {
        guard case .object(let fields) = value else { throw KilnError(.TYPE) }
        return Meta(
            region: try stringValue(fields["region"]),
            flag: try boolValue(fields["flag"]),
        )
    }
}

public struct Message: Equatable, Sendable {
    public var f_bool: Bool
    public var f_int32: Int32
    public var f_int64: Int64
    public var f_float64: Double
    public var f_string: String
    public var f_bool_2: Bool
    public var f_int32_2: Int32
    public var f_string_2: String
    public var meta: Meta

    public init(f_bool: Bool = false, f_int32: Int32 = 0, f_int64: Int64 = 0, f_float64: Double = 0, f_string: String = "", f_bool_2: Bool = false, f_int32_2: Int32 = 0, f_string_2: String = "", meta: Meta = Meta()) {
        self.f_bool = f_bool
        self.f_int32 = f_int32
        self.f_int64 = f_int64
        self.f_float64 = f_float64
        self.f_string = f_string
        self.f_bool_2 = f_bool_2
        self.f_int32_2 = f_int32_2
        self.f_string_2 = f_string_2
        self.meta = meta
    }

    public static func schema() -> Schema {
        .structure([
            ("f_bool", .bool),
            ("f_int32", .i32),
            ("f_int64", .i64),
            ("f_float64", .f64),
            ("f_string", .str),
            ("f_bool_2", .bool),
            ("f_int32_2", .i32),
            ("f_string_2", .str),
            ("meta", Meta.schema()),
        ], name: "Message")
    }

    public func encode() throws -> [UInt8] {
        try Kiln.encode(Message.schema(), toValue())
    }

    public static func decode(_ bytes: [UInt8]) throws -> Message {
        try fromValue(Kiln.decode(Message.schema(), bytes))
    }

    public func encodedSize() throws -> Int {
        try encode().count
    }

    public func toValue() -> Value {
        .object([
            "f_bool": .bool(self.f_bool),
            "f_int32": .int(Int64(self.f_int32)),
            "f_int64": .int(Int64(self.f_int64)),
            "f_float64": .f64(self.f_float64),
            "f_string": .string(self.f_string),
            "f_bool_2": .bool(self.f_bool_2),
            "f_int32_2": .int(Int64(self.f_int32_2)),
            "f_string_2": .string(self.f_string_2),
            "meta": self.meta.toValue(),
        ])
    }

    public static func fromValue(_ value: Value) throws -> Message {
        guard case .object(let fields) = value else { throw KilnError(.TYPE) }
        return Message(
            f_bool: try boolValue(fields["f_bool"]),
            f_int32: try int32Value(fields["f_int32"]),
            f_int64: try int64Value(fields["f_int64"]),
            f_float64: try f64Value(fields["f_float64"]),
            f_string: try stringValue(fields["f_string"]),
            f_bool_2: try boolValue(fields["f_bool_2"]),
            f_int32_2: try int32Value(fields["f_int32_2"]),
            f_string_2: try stringValue(fields["f_string_2"]),
            meta: try Meta.fromValue(fields["meta"] ?? .null),
        )
    }
}

private func boolValue(_ value: Value?) throws -> Bool {
    guard case .bool(let item)? = value else { throw KilnError(.TYPE) }
    return item
}
private func intValue(_ value: Value?) throws -> Int64 {
    switch value {
    case .some(.int(let item)): return item
    case .some(.uint(let item)) where item <= UInt64(Int64.max): return Int64(item)
    default: throw KilnError(.TYPE)
    }
}
private func uintValue(_ value: Value?) throws -> UInt64 {
    switch value {
    case .some(.uint(let item)): return item
    case .some(.int(let item)) where item >= 0: return UInt64(item)
    default: throw KilnError(.TYPE)
    }
}
private func narrowSigned(_ value: Value?, min: Int64, max: Int64) throws -> Int64 {
    let raw = try intValue(value)
    if raw < min || raw > max { throw KilnError(.TYPE) }
    return raw
}
private func narrowUnsigned(_ value: Value?, bits: Int) throws -> UInt64 {
    let raw = try uintValue(value)
    if bits < 64 && raw >= (UInt64(1) << UInt64(bits)) { throw KilnError(.TYPE) }
    return raw
}
private func int8Value(_ value: Value?) throws -> Int8 {
    Int8(try narrowSigned(value, min: Int64(Int8.min), max: Int64(Int8.max)))
}
private func int16Value(_ value: Value?) throws -> Int16 {
    Int16(try narrowSigned(value, min: Int64(Int16.min), max: Int64(Int16.max)))
}
private func int32Value(_ value: Value?) throws -> Int32 {
    Int32(try narrowSigned(value, min: Int64(Int32.min), max: Int64(Int32.max)))
}
private func int64Value(_ value: Value?) throws -> Int64 { try intValue(value) }
private func uint8Value(_ value: Value?) throws -> UInt8 { UInt8(try narrowUnsigned(value, bits: 8)) }
private func uint16Value(_ value: Value?) throws -> UInt16 { UInt16(try narrowUnsigned(value, bits: 16)) }
private func uint32Value(_ value: Value?) throws -> UInt32 { UInt32(try narrowUnsigned(value, bits: 32)) }
private func uint64Value(_ value: Value?) throws -> UInt64 { try uintValue(value) }
private func f32Value(_ value: Value?) throws -> Float {
    guard case .f32(let item)? = value else { throw KilnError(.TYPE) }
    return item
}
private func f64Value(_ value: Value?) throws -> Double {
    guard case .f64(let item)? = value else { throw KilnError(.TYPE) }
    return item
}
private func stringValue(_ value: Value?) throws -> String {
    guard case .string(let item)? = value else { throw KilnError(.TYPE) }
    return item
}
private func bytesValue(_ value: Value?) throws -> [UInt8] {
    guard case .bytes(let item)? = value else { throw KilnError(.TYPE) }
    return item
}
private func tensorsValue(_ value: Value?) throws -> TensorDirectory {
    guard case .tensors(let item)? = value else { throw KilnError(.TYPE) }
    return item
}
private func optionalValue<T>(_ value: Value?, _ body: (Value) throws -> T) throws -> T? {
    guard let value else { return nil }
    if case .null = value { return nil }
    return try body(value)
}
private func listValue<T>(_ value: Value?, _ body: (Value) throws -> T) throws -> [T] {
    guard case .list(let items)? = value else { throw KilnError(.TYPE) }
    return try items.map(body)
}
private func dictValue<T>(_ value: Value?, _ body: (Value) throws -> T) throws -> [String: T] {
    guard case .object(let map)? = value else { throw KilnError(.TYPE) }
    var out: [String: T] = [:]
    for (key, item) in map { out[key] = try body(item) }
    return out
}
private func byteList(_ value: Value?) throws -> [UInt8] {
    if case .bytes(let raw)? = value { return raw }
    return try listValue(value) { UInt8(try narrowUnsigned($0, bits: 8)) }
}
