let generatedSupport = """
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
private func f32List(_ value: Value?) throws -> [Float] {
    if case .f32s(let items)? = value { return items }
    return try listValue(value) { try f32Value($0) }
}
private func f64List(_ value: Value?) throws -> [Double] {
    if case .f64s(let items)? = value { return items }
    return try listValue(value) { try f64Value($0) }
}
private func i32List(_ value: Value?) throws -> [Int32] {
    if case .i32s(let items)? = value { return items }
    return try listValue(value) { try int32Value($0) }
}
private func i64List(_ value: Value?) throws -> [Int64] {
    if case .i64s(let items)? = value { return items }
    return try listValue(value) { try int64Value($0) }
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
"""
