public enum Value: Sendable, Equatable {
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case f32(Float)
    case f64(Double)
    case string(String)
    case bytes([UInt8])
    case list([Value])
    /// Contiguous numeric lists. The wire is one little-endian copy of these bits.
    case f32s([Float])
    case f64s([Double])
    case i32s([Int32])
    case i64s([Int64])
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
        case (.f32s(let lhs), .f32s(let rhs)):
            return sameBits(lhs, rhs)
        case (.f64s(let lhs), .f64s(let rhs)):
            return sameBits(lhs, rhs)
        case (.i32s(let lhs), .i32s(let rhs)):
            return lhs == rhs
        case (.i64s(let lhs), .i64s(let rhs)):
            return lhs == rhs
        case (.f32s(let raw), .list(let items)), (.list(let items), .f32s(let raw)):
            return raw.count == items.count && zip(raw, items).allSatisfy { number, item in
                guard case .f32(let value) = item else { return false }
                return value.bitPattern == number.bitPattern
            }
        case (.f64s(let raw), .list(let items)), (.list(let items), .f64s(let raw)):
            return raw.count == items.count && zip(raw, items).allSatisfy { number, item in
                guard case .f64(let value) = item else { return false }
                return value.bitPattern == number.bitPattern
            }
        case (.i32s(let raw), .list(let items)), (.list(let items), .i32s(let raw)):
            return raw.count == items.count && zip(raw, items).allSatisfy { number, item in
                guard case .int(let value) = item else { return false }
                return value == Int64(number)
            }
        case (.i64s(let raw), .list(let items)), (.list(let items), .i64s(let raw)):
            return raw.count == items.count && zip(raw, items).allSatisfy { number, item in
                guard case .int(let value) = item else { return false }
                return value == number
            }
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

private func sameBits(_ lhs: [Float], _ rhs: [Float]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.bitPattern == $1.bitPattern }
}

private func sameBits(_ lhs: [Double], _ rhs: [Double]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.bitPattern == $1.bitPattern }
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
