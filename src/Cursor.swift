/// Fast 8-byte SWAR ASCII-first UTF-8 validation on contiguous memory.
@inlinable
public func utf8ValidBuffer(_ base: UnsafePointer<UInt8>, count: Int) -> Bool {
    var i = 0
    let raw = UnsafeRawPointer(base)
    while i + 8 <= count {
        let word = raw.loadUnaligned(fromByteOffset: i, as: UInt64.self)
        if (word & 0x8080_8080_8080_8080) != 0 {
            return utf8ValidSlow(base, count: count, from: i)
        }
        i += 8
    }
    while i < count {
        if base[i] >= 0x80 {
            return utf8ValidSlow(base, count: count, from: i)
        }
        i += 1
    }
    return true
}

@usableFromInline
internal func utf8ValidSlow(_ base: UnsafePointer<UInt8>, count: Int, from start: Int) -> Bool {
    var decoder = UTF8()
    var iterator = UnsafeBufferPointer(start: base.advanced(by: start), count: count - start).makeIterator()
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

/// Reusable positional little-endian wire writer with zero intermediate `Value` allocations.
public final class ByteWriter {
    @usableFromInline internal var ptr: UnsafeMutablePointer<UInt8>
    @usableFromInline internal var capacity: Int
    @usableFromInline internal var end: Int

    public init(capacity: Int = 256) {
        let cap = max(capacity, 64)
        self.ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        self.capacity = cap
        self.end = 0
    }

    deinit {
        ptr.deallocate()
    }

    @inlinable
    public var count: Int { end }

    @inlinable
    public func reset() {
        end = 0
    }

    @inlinable
    public func ensure(_ extra: Int) {
        if end + extra <= capacity { return }
        grow(extra)
    }

    @usableFromInline
    internal func grow(_ extra: Int) {
        let need = end + extra
        var nextCap = capacity * 2
        if nextCap < need { nextCap = need }
        let nextPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: nextCap)
        if end > 0 {
            UnsafeMutableRawPointer(nextPtr).copyMemory(from: ptr, byteCount: end)
        }
        ptr.deallocate()
        ptr = nextPtr
        capacity = nextCap
    }

    @inlinable
    public func withBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeRawBufferPointer(start: ptr, count: end))
    }

    @inlinable
    public func toArray() -> [UInt8] {
        let n = end
        if n == 0 { return [] }
        return [UInt8](unsafeUninitializedCapacity: n) { dst, initialized in
            UnsafeMutableRawPointer(dst.baseAddress!).copyMemory(from: ptr, byteCount: n)
            initialized = n
        }
    }

    @inlinable
    public func writeBool(_ value: Bool) {
        ensure(1)
        ptr[end] = value ? 1 : 0
        end += 1
    }

    @inlinable
    public func writeU8(_ value: UInt8) {
        ensure(1)
        ptr[end] = value
        end += 1
    }

    @inlinable
    public func writeI8(_ value: Int8) {
        writeU8(UInt8(bitPattern: value))
    }

    @inlinable
    public func writeU16(_ value: UInt16) {
        ensure(2)
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { src in
            UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src.baseAddress!, byteCount: 2)
        }
        end += 2
    }

    @inlinable
    public func writeI16(_ value: Int16) {
        writeU16(UInt16(bitPattern: value))
    }

    @inlinable
    internal func writeU32Unchecked(_ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { src in
            UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src.baseAddress!, byteCount: 4)
        }
        end += 4
    }

    @inlinable
    public func writeU32(_ value: UInt32) {
        ensure(4)
        writeU32Unchecked(value)
    }

    @inlinable
    public func writeI32(_ value: Int32) {
        writeU32(UInt32(bitPattern: value))
    }

    @inlinable
    public func writeU64(_ value: UInt64) {
        ensure(8)
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { src in
            UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src.baseAddress!, byteCount: 8)
        }
        end += 8
    }

    @inlinable
    public func writeI64(_ value: Int64) {
        writeU64(UInt64(bitPattern: value))
    }

    @inlinable
    public func writeF32(_ value: Float) {
        writeU32(value.bitPattern)
    }

    @inlinable
    public func writeF64(_ value: Double) {
        writeU64(value.bitPattern)
    }

    @inlinable
    public func writeCount(_ count: Int, cap: Int = defaultCap) throws {
        if count < 0 || count > cap || count > Int(UInt32.max) {
            throw KilnError(.LIMIT)
        }
        writeU32(UInt32(count))
    }

    @inlinable
    public func writeString(_ text: String, cap: Int = defaultCap) throws {
        let handled: Bool? = try text.utf8.withContiguousStorageIfAvailable { buf in
            let n = buf.count
            if n > cap || n > Int(UInt32.max) { throw KilnError(.LIMIT) }
            ensure(4 + n)
            writeU32Unchecked(UInt32(n))
            if n > 0, let src = buf.baseAddress {
                UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src, byteCount: n)
                end += n
            }
            return true
        }
        if handled == nil {
            try writeStringSlow(text, cap: cap)
        }
    }

    @usableFromInline
    internal func writeStringSlow(_ text: String, cap: Int) throws {
        let n = text.utf8.count
        if n > cap || n > Int(UInt32.max) { throw KilnError(.LIMIT) }
        ensure(4 + n)
        writeU32Unchecked(UInt32(n))
        var cursor = end
        for byte in text.utf8 {
            ptr[cursor] = byte
            cursor += 1
        }
        end = cursor
    }

    @inlinable
    public func writeBytes(_ raw: [UInt8], cap: Int = defaultCap) throws {
        let n = raw.count
        if n > cap || n > Int(UInt32.max) { throw KilnError(.LIMIT) }
        ensure(4 + n)
        writeU32Unchecked(UInt32(n))
        if n > 0 {
            raw.withUnsafeBytes { src in
                UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src.baseAddress!, byteCount: n)
            }
            end += n
        }
    }

    @inlinable
    public func writeF64s(_ values: [Double], cap: Int = defaultCap) throws {
        let n = values.count
        if n > cap || n > Int(UInt32.max) { throw KilnError(.LIMIT) }
        let byteCount = n * 8
        ensure(4 + byteCount)
        writeU32Unchecked(UInt32(n))
        if n == 0 { return }
        if UInt16(1).littleEndian == 1 {
            values.withUnsafeBytes { src in
                UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src.baseAddress!, byteCount: byteCount)
            }
            end += byteCount
        } else {
            for v in values { writeU64(v.bitPattern) }
        }
    }

    @inlinable
    public func writeF32s(_ values: [Float], cap: Int = defaultCap) throws {
        let n = values.count
        if n > cap || n > Int(UInt32.max) { throw KilnError(.LIMIT) }
        let byteCount = n * 4
        ensure(4 + byteCount)
        writeU32Unchecked(UInt32(n))
        if n == 0 { return }
        if UInt16(1).littleEndian == 1 {
            values.withUnsafeBytes { src in
                UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src.baseAddress!, byteCount: byteCount)
            }
            end += byteCount
        } else {
            for v in values { writeU32(v.bitPattern) }
        }
    }

    @inlinable
    public func writeI64s(_ values: [Int64], cap: Int = defaultCap) throws {
        let n = values.count
        if n > cap || n > Int(UInt32.max) { throw KilnError(.LIMIT) }
        let byteCount = n * 8
        ensure(4 + byteCount)
        writeU32Unchecked(UInt32(n))
        if n == 0 { return }
        if UInt16(1).littleEndian == 1 {
            values.withUnsafeBytes { src in
                UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src.baseAddress!, byteCount: byteCount)
            }
            end += byteCount
        } else {
            for v in values { writeU64(UInt64(bitPattern: v)) }
        }
    }

    @inlinable
    public func writeI32s(_ values: [Int32], cap: Int = defaultCap) throws {
        let n = values.count
        if n > cap || n > Int(UInt32.max) { throw KilnError(.LIMIT) }
        let byteCount = n * 4
        ensure(4 + byteCount)
        writeU32Unchecked(UInt32(n))
        if n == 0 { return }
        if UInt16(1).littleEndian == 1 {
            values.withUnsafeBytes { src in
                UnsafeMutableRawPointer(ptr.advanced(by: end)).copyMemory(from: src.baseAddress!, byteCount: byteCount)
            }
            end += byteCount
        } else {
            for v in values { writeU32(UInt32(bitPattern: v)) }
        }
    }
}

/// Zero-copy stack cursor over raw little-endian Kiln bytes.
public struct ByteReader {
    @usableFromInline internal let base: UnsafePointer<UInt8>?
    @usableFromInline internal let count: Int
    @usableFromInline internal var pos: Int
    @usableFromInline internal let cap: Int
    @usableFromInline internal let trusted: Bool

    @inlinable
    public init(_ raw: UnsafeRawBufferPointer, cap: Int = defaultCap, trusted: Bool = false) {
        self.base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
        self.count = raw.count
        self.pos = 0
        self.cap = cap
        self.trusted = trusted
    }

    @inlinable
    public var offset: Int { pos }

    @inlinable
    public var remaining: Int { count - pos }

    @inlinable
    public mutating func readU8() throws -> UInt8 {
        if pos >= count { throw KilnError(.EOF, offset: pos) }
        let v = base![pos]
        pos += 1
        return v
    }

    @inlinable
    public mutating func readI8() throws -> Int8 {
        Int8(bitPattern: try readU8())
    }

    @inlinable
    public mutating func readBool() throws -> Bool {
        let b = try readU8()
        if b > 1 { throw KilnError(.TYPE, offset: pos - 1) }
        return b == 1
    }

    @inlinable
    public mutating func readU16() throws -> UInt16 {
        if count - pos < 2 { throw KilnError(.EOF, offset: pos) }
        let v = UInt16(littleEndian: UnsafeRawPointer(base!).loadUnaligned(fromByteOffset: pos, as: UInt16.self))
        pos += 2
        return v
    }

    @inlinable
    public mutating func readI16() throws -> Int16 {
        Int16(bitPattern: try readU16())
    }

    @inlinable
    public mutating func readU32() throws -> UInt32 {
        if count - pos < 4 { throw KilnError(.EOF, offset: pos) }
        let v = UInt32(littleEndian: UnsafeRawPointer(base!).loadUnaligned(fromByteOffset: pos, as: UInt32.self))
        pos += 4
        return v
    }

    @inlinable
    public mutating func readI32() throws -> Int32 {
        Int32(bitPattern: try readU32())
    }

    @inlinable
    public mutating func readU64() throws -> UInt64 {
        if count - pos < 8 { throw KilnError(.EOF, offset: pos) }
        let v = UInt64(littleEndian: UnsafeRawPointer(base!).loadUnaligned(fromByteOffset: pos, as: UInt64.self))
        pos += 8
        return v
    }

    @inlinable
    public mutating func readI64() throws -> Int64 {
        Int64(bitPattern: try readU64())
    }

    @inlinable
    public mutating func readF32() throws -> Float {
        Float(bitPattern: try readU32())
    }

    @inlinable
    public mutating func readF64() throws -> Double {
        Double(bitPattern: try readU64())
    }

    @inlinable
    public mutating func readCount(each: Int = 1) throws -> Int {
        let n = Int(try readU32())
        if n > cap { throw KilnError(.LIMIT, offset: pos) }
        if each > 0 {
            let unread = UInt64(count - pos)
            let (prod, overflow) = UInt64(n).multipliedReportingOverflow(by: UInt64(each))
            if overflow { throw KilnError(.LIMIT, offset: pos) }
            if prod > unread { throw KilnError(.EOF, offset: pos) }
        }
        return n
    }

    @inlinable
    public mutating func readString() throws -> String {
        let n = Int(try readU32())
        if n > cap { throw KilnError(.LIMIT, offset: pos) }
        if n > count - pos { throw KilnError(.EOF, offset: pos) }
        if n == 0 { return "" }
        let start = base!.advanced(by: pos)
        pos += n
        if trusted {
            return String(decoding: UnsafeBufferPointer(start: start, count: n), as: UTF8.self)
        }
        if !utf8ValidBuffer(start, count: n) {
            throw KilnError(.UTF8, offset: pos)
        }
        return String(unsafeUninitializedCapacity: n) { dst in
            UnsafeMutableRawPointer(dst.baseAddress!).copyMemory(from: start, byteCount: n)
            return n
        }
    }

    @inlinable
    public mutating func readBytes() throws -> [UInt8] {
        let n = try readCount(each: 1)
        if n == 0 { return [] }
        let start = base!.advanced(by: pos)
        pos += n
        return [UInt8](unsafeUninitializedCapacity: n) { dst, initialized in
            UnsafeMutableRawPointer(dst.baseAddress!).copyMemory(from: start, byteCount: n)
            initialized = n
        }
    }

    @inlinable
    public mutating func readF64s() throws -> [Double] {
        let n = try readCount(each: 8)
        if n == 0 { return [] }
        if UInt16(1).littleEndian == 1 {
            let byteCount = n * 8
            let start = base!.advanced(by: pos)
            pos += byteCount
            return [Double](unsafeUninitializedCapacity: n) { dst, initialized in
                UnsafeMutableRawPointer(dst.baseAddress!).copyMemory(from: start, byteCount: byteCount)
                initialized = n
            }
        }
        var out: [Double] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try readF64()) }
        return out
    }

    @inlinable
    public mutating func readF32s() throws -> [Float] {
        let n = try readCount(each: 4)
        if n == 0 { return [] }
        if UInt16(1).littleEndian == 1 {
            let byteCount = n * 4
            let start = base!.advanced(by: pos)
            pos += byteCount
            return [Float](unsafeUninitializedCapacity: n) { dst, initialized in
                UnsafeMutableRawPointer(dst.baseAddress!).copyMemory(from: start, byteCount: byteCount)
                initialized = n
            }
        }
        var out: [Float] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try readF32()) }
        return out
    }

    @inlinable
    public mutating func readI64s() throws -> [Int64] {
        let n = try readCount(each: 8)
        if n == 0 { return [] }
        if UInt16(1).littleEndian == 1 {
            let byteCount = n * 8
            let start = base!.advanced(by: pos)
            pos += byteCount
            return [Int64](unsafeUninitializedCapacity: n) { dst, initialized in
                UnsafeMutableRawPointer(dst.baseAddress!).copyMemory(from: start, byteCount: byteCount)
                initialized = n
            }
        }
        var out: [Int64] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try readI64()) }
        return out
    }

    @inlinable
    public mutating func readI32s() throws -> [Int32] {
        let n = try readCount(each: 4)
        if n == 0 { return [] }
        if UInt16(1).littleEndian == 1 {
            let byteCount = n * 4
            let start = base!.advanced(by: pos)
            pos += byteCount
            return [Int32](unsafeUninitializedCapacity: n) { dst, initialized in
                UnsafeMutableRawPointer(dst.baseAddress!).copyMemory(from: start, byteCount: byteCount)
                initialized = n
            }
        }
        var out: [Int32] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try readI32()) }
        return out
    }

    @inlinable
    public func finish() throws {
        if pos != count { throw KilnError(.TRAILING, offset: pos) }
    }
}
