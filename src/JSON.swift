/// Ordered JSON subset. Numbers stay decimal text so hashes above 2^53 survive.
indirect enum JSON {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var objectPairs: [(String, JSON)]? {
        if case .object(let pairs) = self { return pairs }
        return nil
    }

    var arrayItems: [JSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    func field(_ name: String) -> JSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.0 == name }?.1
    }
}

func parseJSON(_ data: some Sequence<UInt8>) throws -> JSON {
    var parser = JSONParser(Array(data))
    let value = try parser.parseValue()
    parser.skip()
    if parser.index != parser.bytes.count { throw KilnError(.SCHEMA) }
    return value
}

private struct JSONParser {
    var bytes: [UInt8]
    var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseValue() throws -> JSON {
        skip()
        guard index < bytes.count else { throw KilnError(.SCHEMA) }
        switch bytes[index] {
        case UInt8(ascii: "n"):
            try literal("null")
            return .null
        case UInt8(ascii: "t"):
            try literal("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try literal("false")
            return .bool(false)
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "["):
            return try parseArray()
        case UInt8(ascii: "{"):
            return try parseObject()
        default:
            return .number(try parseNumber())
        }
    }

    mutating func skip() {
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                index += 1
            default:
                return
            }
        }
    }

    mutating func literal(_ text: String) throws {
        for byte in text.utf8 {
            guard index < bytes.count, bytes[index] == byte else { throw KilnError(.SCHEMA) }
            index += 1
        }
    }

    mutating func parseNumber() throws -> String {
        let start = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count, bytes[index].isJSONDigit else { throw KilnError(.SCHEMA) }
        while index < bytes.count, bytes[index].isJSONDigit { index += 1 }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard index < bytes.count, bytes[index].isJSONDigit else { throw KilnError(.SCHEMA) }
            while index < bytes.count, bytes[index].isJSONDigit { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            guard index < bytes.count, bytes[index].isJSONDigit else { throw KilnError(.SCHEMA) }
            while index < bytes.count, bytes[index].isJSONDigit { index += 1 }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    mutating func parseString() throws -> String {
        index += 1
        var out: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == UInt8(ascii: "\"") {
                return String(decoding: out, as: UTF8.self)
            }
            if byte == UInt8(ascii: "\\") {
                guard index < bytes.count else { throw KilnError(.SCHEMA) }
                let esc = bytes[index]
                index += 1
                switch esc {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"):
                    out.append(esc)
                case UInt8(ascii: "b"):
                    out.append(0x08)
                case UInt8(ascii: "f"):
                    out.append(0x0C)
                case UInt8(ascii: "n"):
                    out.append(0x0A)
                case UInt8(ascii: "r"):
                    out.append(0x0D)
                case UInt8(ascii: "t"):
                    out.append(0x09)
                case UInt8(ascii: "u"):
                    let scalar = try parseHex4()
                    UTF8.encode(scalar) { out.append($0) }
                default:
                    throw KilnError(.SCHEMA)
                }
            } else {
                out.append(byte)
            }
        }
        throw KilnError(.SCHEMA)
    }

    mutating func parseHex4() throws -> Unicode.Scalar {
        guard index + 4 <= bytes.count else { throw KilnError(.SCHEMA) }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            value <<= 4
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                value += UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                value += UInt32(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"):
                value += UInt32(byte - UInt8(ascii: "A")) + 10
            default:
                throw KilnError(.SCHEMA)
            }
        }
        guard let scalar = Unicode.Scalar(value) else { throw KilnError(.SCHEMA) }
        return scalar
    }

    mutating func parseArray() throws -> JSON {
        index += 1
        var items: [JSON] = []
        skip()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while true {
            items.append(try parseValue())
            skip()
            guard index < bytes.count else { throw KilnError(.SCHEMA) }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            }
            throw KilnError(.SCHEMA)
        }
    }

    mutating func parseObject() throws -> JSON {
        index += 1
        var pairs: [(String, JSON)] = []
        skip()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(pairs)
        }
        while true {
            skip()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw KilnError(.SCHEMA) }
            let key = try parseString()
            skip()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw KilnError(.SCHEMA) }
            index += 1
            pairs.append((key, try parseValue()))
            skip()
            guard index < bytes.count else { throw KilnError(.SCHEMA) }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(pairs)
            }
            throw KilnError(.SCHEMA)
        }
    }
}

private extension UInt8 {
    var isJSONDigit: Bool { self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9") }
}
