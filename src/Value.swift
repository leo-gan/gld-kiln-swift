public enum Value: Sendable, Equatable {
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case f32(Float)
    case f64(Double)
    case string(String)
    case bytes([UInt8])
    case list([Value])
    case object([String: Value])
    case null
    case tensors(TensorDirectory)

    public static func == (lhs: Value, rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case (.bool(let lhs), .bool(let rhs)):
            return lhs == rhs
        case (.int(let lhs), .int(let rhs)):
            return lhs == rhs
        case (.uint(let lhs), .uint(let rhs)):
            return lhs == rhs
        case (.f32(let lhs), .f32(let rhs)):
            return lhs.bitPattern == rhs.bitPattern
        case (.f64(let lhs), .f64(let rhs)):
            return lhs.bitPattern == rhs.bitPattern
        case (.string(let lhs), .string(let rhs)):
            return lhs == rhs
        case (.bytes(let lhs), .bytes(let rhs)):
            return lhs == rhs
        case (.list(let lhs), .list(let rhs)):
            return lhs == rhs
        case (.object(let lhs), .object(let rhs)):
            return lhs == rhs
        case (.null, .null):
            return true
        case (.tensors(let lhs), .tensors(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

func fitSigned(_ value: Value, bits: Int) throws -> Int64 {
    let raw: Int64
    switch value {
    case .int(let number):
        raw = number
    case .uint(let number):
        guard number <= UInt64(Int64.max) else { throw KilnError(.TYPE) }
        raw = Int64(number)
    default:
        throw KilnError(.TYPE)
    }
    if bits >= 64 { return raw }
    let limit = Int64(1) << Int64(bits - 1)
    if raw < -limit || raw >= limit { throw KilnError(.TYPE) }
    return raw
}

func fitUnsigned(_ value: Value, bits: Int) throws -> UInt64 {
    let raw: UInt64
    switch value {
    case .uint(let number):
        raw = number
    case .int(let number):
        guard number >= 0 else { throw KilnError(.TYPE) }
        raw = UInt64(number)
    default:
        throw KilnError(.TYPE)
    }
    if bits < 64, raw >= (UInt64(1) << UInt64(bits)) { throw KilnError(.TYPE) }
    return raw
}
