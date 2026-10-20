struct ByteSink {
    var storage: [UInt8]
    var end: Int

    init(capacity: Int = 64) {
        storage = []
        storage.reserveCapacity(max(capacity, 0))
        end = 0
    }

    mutating func ensure(_ extra: Int) {
        let need = end + extra
        if storage.count >= need { return }
        storage.reserveCapacity(max(need, max(storage.count, 1) * 2))
        storage.append(contentsOf: repeatElement(0, count: need - storage.count))
    }

    mutating func writeU8(_ value: UInt8) {
        ensure(1)
        storage[end] = value
        end += 1
    }

    mutating func writeU16(_ value: UInt16) {
        ensure(2)
        storage[end] = UInt8(truncatingIfNeeded: value)
        storage[end + 1] = UInt8(truncatingIfNeeded: value >> 8)
        end += 2
    }

    mutating func writeU32(_ value: UInt32) {
        ensure(4)
        storage[end] = UInt8(truncatingIfNeeded: value)
        storage[end + 1] = UInt8(truncatingIfNeeded: value >> 8)
        storage[end + 2] = UInt8(truncatingIfNeeded: value >> 16)
        storage[end + 3] = UInt8(truncatingIfNeeded: value >> 24)
        end += 4
    }

    mutating func writeU64(_ value: UInt64) {
        ensure(8)
        var bits = value.littleEndian
        withUnsafeBytes(of: &bits) { raw in
            for offset in 0..<8 {
                storage[end + offset] = raw[offset]
            }
        }
        end += 8
    }

    mutating func writeBytes(_ bytes: [UInt8]) {
        if bytes.isEmpty { return }
        ensure(bytes.count)
        bytes.withUnsafeBytes { src in
            storage.withUnsafeMutableBytes { dst in
                dst.baseAddress!.advanced(by: end).copyMemory(from: src.baseAddress!, byteCount: bytes.count)
            }
        }
        end += bytes.count
    }
}

func storeU16(_ value: UInt16, _ buf: inout [UInt8], _ index: Int) {
    buf[index] = UInt8(truncatingIfNeeded: value)
    buf[index + 1] = UInt8(truncatingIfNeeded: value >> 8)
}

func storeU32(_ value: UInt32, _ buf: inout [UInt8], _ index: Int) {
    buf[index] = UInt8(truncatingIfNeeded: value)
    buf[index + 1] = UInt8(truncatingIfNeeded: value >> 8)
    buf[index + 2] = UInt8(truncatingIfNeeded: value >> 16)
    buf[index + 3] = UInt8(truncatingIfNeeded: value >> 24)
}

func storeU64(_ value: UInt64, _ buf: inout [UInt8], _ index: Int) {
    var bits = value.littleEndian
    withUnsafeBytes(of: &bits) { raw in
        for offset in 0..<8 { buf[index + offset] = raw[offset] }
    }
}

func loadU16(_ buf: [UInt8], _ index: Int) -> UInt16 {
    UInt16(buf[index]) | (UInt16(buf[index + 1]) << 8)
}

func loadU32(_ buf: [UInt8], _ index: Int) -> UInt32 {
    UInt32(buf[index])
        | (UInt32(buf[index + 1]) << 8)
        | (UInt32(buf[index + 2]) << 16)
        | (UInt32(buf[index + 3]) << 24)
}

func loadU64(_ buf: [UInt8], _ index: Int) -> UInt64 {
    var bits: UInt64 = 0
    for offset in 0..<8 {
        bits |= UInt64(buf[index + offset]) << (UInt64(offset) * 8)
    }
    return bits
}

func allZero(_ bytes: ArraySlice<UInt8>) -> Bool {
    for byte in bytes where byte != 0 { return false }
    return true
}

func utf8OK(_ bytes: some Collection<UInt8>) -> Bool {
    for byte in bytes where byte >= 0x80 {
        return utf8OKFull(bytes)
    }
    return true
}

private func utf8OKFull(_ bytes: some Collection<UInt8>) -> Bool {
    var decoder = UTF8()
    var iterator = bytes.makeIterator()
    while true {
        switch decoder.decode(&iterator) {
        case .scalarValue:
            continue
        case .emptyInput:
            return true
        case .error:
            return false
        }
    }
}

func addU(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow { throw KilnError(.LIMIT) }
    return sum
}

func mulU(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
    let (product, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    if overflow { throw KilnError(.LIMIT) }
    return product
}

func align64(_ value: UInt64) throws -> UInt64 {
    let (sum, overflow) = value.addingReportingOverflow(63)
    if overflow { throw KilnError(.LIMIT) }
    return sum & ~UInt64(63)
}

func fitCount(_ count: Int, each: Int, unread: UInt64, cap: Int) throws {
    if count > cap { throw KilnError(.LIMIT) }
    if each <= 0 { return }
    let wide = UInt64(count)
    let step = UInt64(each)
    if wide > UInt64.max / step { throw KilnError(.LIMIT) }
    if wide * step > unread { throw KilnError(.EOF) }
}
