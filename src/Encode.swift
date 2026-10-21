public final class Writer {
    var sink: ByteSink

    public init(capacity: Int = 64) {
        sink = ByteSink(capacity: capacity)
    }

    public var end: Int { sink.end }

    public func encode(_ schema: Schema, _ value: Value, cap: Int = defaultCap) throws -> ArraySlice<UInt8> {
        sink.end = 0
        try sink.writeValue(schema, value, cap: cap, depth: 0)
        return sink.storage[0..<sink.end]
    }

    public func encodeFramed(_ schema: Schema, _ value: Value, cap: Int = defaultCap) throws -> ArraySlice<UInt8> {
        sink.end = 0
        sink.writeBytes(Array("KLN0".utf8))
        sink.writeU32(0)
        sink.writeU64(typeHash(schema))
        try sink.writeValue(schema, value, cap: cap, depth: 0)
        return sink.storage[0..<sink.end]
    }
}

public func encode(_ schema: Schema, _ value: Value, cap: Int = defaultCap) throws -> [UInt8] {
    Array(try Writer().encode(schema, value, cap: cap))
}

public func encodeFramed(_ schema: Schema, _ value: Value, cap: Int = defaultCap) throws -> [UInt8] {
    Array(try Writer().encodeFramed(schema, value, cap: cap))
}

extension ByteSink {
    mutating func writeValue(_ schema: Schema, _ value: Value, cap: Int, depth: Int) throws {
        if depth > 64 { throw KilnError(.LIMIT) }
        switch schema {
        case .scalar(let kind):
            try writeScalar(kind, value)
        case .str:
            guard case .string(let text) = value else { throw KilnError(.TYPE) }
            try writeText(text, cap: cap)
        case .bytes:
            guard case .bytes(let raw) = value else { throw KilnError(.TYPE) }
            try writeCounted(raw, cap: cap)
        case .tensors:
            guard case .tensors(let directory) = value else { throw KilnError(.TYPE) }
            writeBytes(try encodeTensors(directory.tensors))
        case .opt(let inner):
            if case .null = value {
                writeU8(0)
                return
            }
            writeU8(1)
            try writeValue(inner, value, cap: cap, depth: depth + 1)
        case .list(let element):
            try writeList(element, value, cap: cap, depth: depth)
        case .dict(let inner):
            try writeDict(inner, value, cap: cap, depth: depth)
        case .structure(_, let fields):
            guard case .object(let map) = value else { throw KilnError(.TYPE) }
            for field in fields {
                guard let item = map[field.name] else { throw KilnError(.TYPE) }
                if case .scalar(let kind) = field.schema {
                    try writeScalar(kind, item)
                } else {
                    try writeValue(field.schema, item, cap: cap, depth: depth + 1)
                }
            }
        }
    }

    mutating func writeList(_ element: Schema, _ value: Value, cap: Int, depth: Int) throws {
        if case .scalar(.u8) = element, case .bytes(let raw) = value {
            try fitCount(raw.count, each: 1, unread: .max, cap: cap)
            try writeCounted(raw, cap: cap)
            return
        }
        if case .scalar(.f32) = element, case .f32s(let nums) = value {
            try writeF32s(nums, cap: cap)
            return
        }
        if case .scalar(.f64) = element, case .f64s(let nums) = value {
            try writeF64s(nums, cap: cap)
            return
        }
        if case .scalar(.i32) = element, case .i32s(let nums) = value {
            try writeI32s(nums, cap: cap)
            return
        }
        if case .scalar(.i64) = element, case .i64s(let nums) = value {
            try writeI64s(nums, cap: cap)
            return
        }
        if case .scalar(.int) = element, case .i64s(let nums) = value {
            try writeI64s(nums, cap: cap)
            return
        }
        guard case .list(let items) = value else { throw KilnError(.TYPE) }
        try fitCount(items.count, each: minSize(element), unread: .max, cap: cap)
        guard items.count <= Int(UInt32.max) else { throw KilnError(.LIMIT) }
        writeU32(UInt32(items.count))
        if case .scalar(let kind) = element {
            for item in items { try writeScalar(kind, item) }
            return
        }
        for item in items {
            try writeValue(element, item, cap: cap, depth: depth + 1)
        }
    }

    mutating func writeDict(_ inner: Schema, _ value: Value, cap: Int, depth: Int) throws {
        guard case .object(let map) = value else { throw KilnError(.TYPE) }
        let items = map.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
        try fitCount(items.count, each: 4, unread: .max, cap: cap)
        guard items.count <= Int(UInt32.max) else { throw KilnError(.LIMIT) }
        writeU32(UInt32(items.count))
        for (key, item) in items {
            try writeText(key, cap: cap)
            try writeValue(inner, item, cap: cap, depth: depth + 1)
        }
    }

    mutating func writeF32s(_ values: [Float], cap: Int) throws {
        try beginPod(values.count, width: 4, cap: cap)
        if hostIsLittleEndian {
            writeContiguous(values)
        } else {
            for value in values { writeU32(value.bitPattern) }
        }
    }

    mutating func writeF64s(_ values: [Double], cap: Int) throws {
        try beginPod(values.count, width: 8, cap: cap)
        if hostIsLittleEndian {
            writeContiguous(values)
        } else {
            for value in values { writeU64(value.bitPattern) }
        }
    }

    mutating func writeI32s(_ values: [Int32], cap: Int) throws {
        try beginPod(values.count, width: 4, cap: cap)
        if hostIsLittleEndian {
            writeContiguous(values)
        } else {
            for value in values { writeU32(UInt32(bitPattern: value)) }
        }
    }

    mutating func writeI64s(_ values: [Int64], cap: Int) throws {
        try beginPod(values.count, width: 8, cap: cap)
        if hostIsLittleEndian {
            writeContiguous(values)
        } else {
            for value in values { writeU64(UInt64(bitPattern: value)) }
        }
    }

    private mutating func beginPod(_ count: Int, width: Int, cap: Int) throws {
        try fitCount(count, each: width, unread: .max, cap: cap)
        guard count <= Int(UInt32.max) else { throw KilnError(.LIMIT) }
        writeU32(UInt32(count))
    }

    mutating func writeCounted(_ raw: [UInt8], cap: Int) throws {
        if raw.count > cap || raw.count > Int(UInt32.max) { throw KilnError(.LIMIT) }
        writeU32(UInt32(raw.count))
        writeBytes(raw)
    }

    mutating func writeText(_ text: String, cap: Int) throws {
        let count = text.utf8.count
        if count > cap || count > Int(UInt32.max) { throw KilnError(.LIMIT) }
        writeU32(UInt32(count))
        if count == 0 { return }
        ensure(count)
        var cursor = end
        for byte in text.utf8 {
            storage[cursor] = byte
            cursor += 1
        }
        end = cursor
    }

    mutating func writeScalar(_ kind: ScalarKind, _ value: Value) throws {
        switch kind {
        case .bool:
            guard case .bool(let flag) = value else { throw KilnError(.TYPE) }
            writeU8(flag ? 1 : 0)
        case .i8:
            writeU8(UInt8(bitPattern: Int8(try fitSigned(value, bits: 8))))
        case .i16:
            writeU16(UInt16(bitPattern: Int16(try fitSigned(value, bits: 16))))
        case .i32:
            writeU32(UInt32(bitPattern: Int32(try fitSigned(value, bits: 32))))
        case .i64, .int:
            writeU64(UInt64(bitPattern: try fitSigned(value, bits: 64)))
        case .u8:
            writeU8(UInt8(try fitUnsigned(value, bits: 8)))
        case .u16:
            writeU16(UInt16(try fitUnsigned(value, bits: 16)))
        case .u32:
            writeU32(UInt32(try fitUnsigned(value, bits: 32)))
        case .u64, .uint:
            writeU64(try fitUnsigned(value, bits: 64))
        case .f32:
            guard case .f32(let number) = value else { throw KilnError(.TYPE) }
            writeU32(number.bitPattern)
        case .f64:
            guard case .f64(let number) = value else { throw KilnError(.TYPE) }
            writeU64(number.bitPattern)
        }
    }
}
