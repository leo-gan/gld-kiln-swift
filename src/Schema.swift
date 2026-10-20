/// Runtime description of a Frozen value. Field order is declaration order.
public enum Schema: Sendable, Equatable {
    case scalar(ScalarKind)
    case str
    case bytes
    case tensors
    indirect case list(Schema)
    indirect case opt(Schema)
    indirect case dict(Schema)
    case structure(name: String?, fields: [Field])

    public struct Field: Sendable, Equatable {
        public var name: String
        public var schema: Schema

        public init(name: String, schema: Schema) {
            self.name = name
            self.schema = schema
        }
    }

    public static func structure(_ fields: [(String, Schema)], name: String? = nil) -> Schema {
        .structure(name: name, fields: fields.map { Field(name: $0.0, schema: $0.1) })
    }
}

public enum ScalarKind: String, Sendable, Equatable {
    case bool
    case i8, i16, i32, i64, int
    case u8, u16, u32, u64, uint
    case f32, f64
}

extension Schema {
    public static var bool: Schema { .scalar(.bool) }
    public static var i8: Schema { .scalar(.i8) }
    public static var i16: Schema { .scalar(.i16) }
    public static var i32: Schema { .scalar(.i32) }
    public static var i64: Schema { .scalar(.i64) }
    public static var int: Schema { .scalar(.int) }
    public static var u8: Schema { .scalar(.u8) }
    public static var u16: Schema { .scalar(.u16) }
    public static var u32: Schema { .scalar(.u32) }
    public static var u64: Schema { .scalar(.u64) }
    public static var uint: Schema { .scalar(.uint) }
    public static var f32: Schema { .scalar(.f32) }
    public static var f64: Schema { .scalar(.f64) }
}

/// Default cap: 16,777,216 counts and 16 MiB for one string or byte run.
public let defaultCap = 16_777_216

public func minSize(_ schema: Schema) -> Int {
    switch schema {
    case .scalar(let kind):
        switch kind {
        case .bool, .i8, .u8:
            return 1
        case .i16, .u16:
            return 2
        case .i32, .u32, .f32:
            return 4
        case .i64, .u64, .int, .uint, .f64:
            return 8
        }
    case .str, .bytes, .list, .dict:
        return 4
    case .tensors:
        return 64
    case .opt:
        return 1
    case .structure(_, let fields):
        return fields.reduce(0) { $0 + minSize($1.schema) }
    }
}

func parseTypeText(_ text: String) throws -> Schema {
    let text = trimASCII(text)
    if text.hasPrefix("struct{"), text.hasSuffix("}") {
        let body = text.dropFirst("struct{".count).dropLast()
        var fields: [(String, Schema)] = []
        if !body.isEmpty {
            for part in body.split(separator: ",", omittingEmptySubsequences: false) {
                if part.isEmpty { continue }
                let bits = part.split(separator: ":", maxSplits: 1)
                if bits.count != 2 { throw KilnError(.SCHEMA) }
                fields.append((String(bits[0]), try parseTypeText(String(bits[1]))))
            }
        }
        return .structure(fields)
    }
    if text.hasPrefix("list<"), text.hasSuffix(">") {
        return .list(try parseTypeText(String(text.dropFirst("list<".count).dropLast())))
    }
    if text.hasPrefix("opt<"), text.hasSuffix(">") {
        return .opt(try parseTypeText(String(text.dropFirst("opt<".count).dropLast())))
    }
    if text == "str" { return .str }
    if text == "bytes" { return .bytes }
    if text == "tensors" { return .tensors }
    if let kind = ScalarKind(rawValue: text) { return .scalar(kind) }
    throw KilnError(.SCHEMA)
}

private func trimASCII(_ text: String) -> String {
    var bytes = Array(text.utf8)
    while let first = bytes.first, first == 32 || first == 9 || first == 10 || first == 13 {
        bytes.removeFirst()
    }
    while let last = bytes.last, last == 32 || last == 9 || last == 10 || last == 13 {
        bytes.removeLast()
    }
    return String(decoding: bytes, as: UTF8.self)
}

func schemaFromCase(_ json: JSON) throws -> Schema {
    switch json {
    case .string(let text):
        if text == "tensor-v2" { return .tensors }
        if text == "frame" {
            return .structure([("id", .i64), ("batch", .tensors)])
        }
        throw KilnError(.SCHEMA)
    case .object(let pairs):
        let map = Dictionary(uniqueKeysWithValues: pairs)
        guard case .string(let kind) = map["type"] else { throw KilnError(.SCHEMA) }
        if kind == "list" {
            guard case .string(let element) = map["element"] else { throw KilnError(.SCHEMA) }
            return .list(try parseTypeText(element))
        }
        if kind == "struct" {
            guard case .array(let fields) = map["fields"] else { throw KilnError(.SCHEMA) }
            var out: [(String, Schema)] = []
            for field in fields {
                guard case .string(let item) = field else { throw KilnError(.SCHEMA) }
                let bits = item.split(separator: ":", maxSplits: 1)
                if bits.count != 2 { throw KilnError(.SCHEMA) }
                out.append((String(bits[0]), try parseTypeText(String(bits[1]))))
            }
            return .structure(out)
        }
        throw KilnError(.SCHEMA)
    default:
        throw KilnError(.SCHEMA)
    }
}
