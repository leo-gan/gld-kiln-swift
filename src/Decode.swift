public func decode(
    _ schema: Schema,
    _ buffer: [UInt8],
    cap: Int = defaultCap,
    trusted: Bool = false
) throws -> Value {
    var reader = Reader(buf: buffer, cap: cap, trusted: trusted)
    let value = try reader.readValue(schema, depth: 0)
    if reader.index != buffer.count { throw KilnError(.TRAILING, offset: reader.index) }
    return value
}

public func decodeFramed(
    _ schema: Schema,
    _ buffer: [UInt8],
    cap: Int = defaultCap,
    trusted: Bool = false
) throws -> Value {
    if buffer.count < 16 { throw KilnError(.EOF) }
    if buffer[0] != UInt8(ascii: "K") || buffer[1] != UInt8(ascii: "L")
        || buffer[2] != UInt8(ascii: "N") || buffer[3] != UInt8(ascii: "0")
        || buffer[4] != 0 || buffer[5] != 0 || buffer[6] != 0 || buffer[7] != 0 {
        throw KilnError(.FRAME)
    }
    if loadU64(buffer, 8) != typeHash(schema) { throw KilnError(.SCHEMA) }
    var reader = Reader(buf: buffer, index: 16, cap: cap, trusted: trusted)
    let value = try reader.readValue(schema, depth: 0)
    if reader.index != buffer.count { throw KilnError(.TRAILING, offset: reader.index) }
    return value
}

struct Reader {
    var buf: [UInt8]
    var index: Int
    var cap: Int
    var trusted: Bool

    init(buf: [UInt8], index: Int = 0, cap: Int, trusted: Bool) {
        self.buf = buf
        self.index = index
        self.cap = cap
        self.trusted = trusted
    }

    mutating func need(_ count: Int) throws {
        if index > buf.count || count > buf.count - index { throw KilnError(.EOF, offset: index) }
    }

    mutating func u8() throws -> UInt8 {
        try need(1)
        let value = buf[index]
        index += 1
        return value
    }

    mutating func u16() throws -> UInt16 {
        try need(2)
        let value = loadU16(buf, index)
        index += 2
        return value
    }

    mutating func u32() throws -> UInt32 {
        try need(4)
        let value = loadU32(buf, index)
        index += 4
        return value
    }

    mutating func u64() throws -> UInt64 {
        try need(8)
        let value = loadU64(buf, index)
        index += 8
        return value
    }

    mutating func readSlice() throws -> ArraySlice<UInt8> {
        let length = Int(try u32())
        if length > cap { throw KilnError(.LIMIT, offset: index) }
        try need(length)
        let raw = buf[index..<(index + length)]
        index += length
        return raw
    }

    mutating func readCounted() throws -> [UInt8] {
        Array(try readSlice())
    }

    mutating func readText() throws -> String {
        let raw = try readSlice()
        if !trusted && !utf8OK(raw) { throw KilnError(.UTF8, offset: index) }
        return String(decoding: raw, as: UTF8.self)
    }

    mutating func readValue(_ schema: Schema, depth: Int) throws -> Value {
        if depth > 64 { throw KilnError(.LIMIT, offset: index) }
        switch schema {
        case .scalar(let kind):
            return try readScalar(kind)
        case .str:
            return .string(try readText())
        case .bytes:
            return .bytes(try readCounted())
        case .tensors:
            let (directory, block) = try decodeTensorBlock(buf, start: index, standalone: false, cap: cap, trusted: trusted)
            index += block
            return .tensors(directory)
        case .opt(let inner):
            let tag = try u8()
            if tag == 0 { return .null }
            if tag != 1 { throw KilnError(.TYPE, offset: index - 1) }
            return try readValue(inner, depth: depth + 1)
        case .list(let element):
            return try readList(element, depth: depth)
        case .dict(let inner):
            return try readDict(inner, depth: depth)
        case .structure(_, let fields):
            var map = [String: Value](minimumCapacity: fields.count)
            for field in fields {
                if case .scalar(let kind) = field.schema {
                    map[field.name] = try readScalar(kind)
                } else {
                    map[field.name] = try readValue(field.schema, depth: depth + 1)
                }
            }
            return .object(map)
        }
    }

    mutating func readList(_ element: Schema, depth: Int) throws -> Value {
        let count = Int(try u32())
        let unread = buf.count - index
        try fitCount(count, each: minSize(element), unread: UInt64(unread), cap: cap)
        if case .scalar(.u8) = element {
            let raw = Array(buf[index..<(index + count)])
            index += count
            return .bytes(raw)
        }
        var items: [Value] = []
        items.reserveCapacity(count)
        if case .scalar(let kind) = element {
            for _ in 0..<count { items.append(try readScalar(kind)) }
            return .list(items)
        }
        for _ in 0..<count {
            items.append(try readValue(element, depth: depth + 1))
        }
        return .list(items)
    }

    mutating func readDict(_ inner: Schema, depth: Int) throws -> Value {
        let count = Int(try u32())
        try fitCount(count, each: 4, unread: UInt64(buf.count - index), cap: cap)
        var map = [String: Value](minimumCapacity: count)
        var previous: ArraySlice<UInt8>?
        for _ in 0..<count {
            let rawKey = try readSlice()
            if !trusted && !utf8OK(rawKey) { throw KilnError(.UTF8, offset: index) }
            if let previous, rawKey.lexicographicallyPrecedes(previous) { throw KilnError(.TYPE) }
            previous = rawKey
            map[String(decoding: rawKey, as: UTF8.self)] = try readValue(inner, depth: depth + 1)
        }
        return .object(map)
    }

    mutating func readScalar(_ kind: ScalarKind) throws -> Value {
        switch kind {
        case .bool:
            let byte = try u8()
            if byte > 1 { throw KilnError(.TYPE, offset: index - 1) }
            return .bool(byte == 1)
        case .i8:
            return .int(Int64(Int8(bitPattern: try u8())))
        case .u8:
            return .uint(UInt64(try u8()))
        case .i16:
            return .int(Int64(Int16(bitPattern: try u16())))
        case .u16:
            return .uint(UInt64(try u16()))
        case .i32:
            return .int(Int64(Int32(bitPattern: try u32())))
        case .u32:
            return .uint(UInt64(try u32()))
        case .i64, .int:
            return .int(Int64(bitPattern: try u64()))
        case .u64, .uint:
            return .uint(try u64())
        case .f32:
            return .f32(Float(bitPattern: try u32()))
        case .f64:
            return .f64(Double(bitPattern: try u64()))
        }
    }
}
