import Kiln

func emitSwift(_ text: String) throws -> (name: String, source: String) {
    let (title, root) = try schemaFromJSON(text)
    guard case .structure = root else {
        throw KilnError(.SCHEMA)
    }
    var seen = Set<String>()
    var structs: [Schema] = []
    collect(root, seen: &seen, into: &structs)
    let emitter = SwiftEmitter()
    var lines = ["import Kiln", ""]
    for schema in structs {
        lines.append(contentsOf: emitter.structLines(schema))
        lines.append("")
    }
    lines.append(generatedSupport)
    let source = lines.joined(separator: "\n")
    return (ident(title), source.hasSuffix("\n") ? source : source + "\n")
}

private func collect(_ schema: Schema, seen: inout Set<String>, into out: inout [Schema]) {
    switch schema {
    case .list(let inner), .opt(let inner), .dict(let inner):
        collect(inner, seen: &seen, into: &out)
    case .structure(let name, let fields):
        let key = name ?? "Root"
        if seen.contains(key) { return }
        seen.insert(key)
        for field in fields {
            collect(field.schema, seen: &seen, into: &out)
        }
        out.append(schema)
    default:
        break
    }
}

private final class SwiftEmitter {
    var fresh = 0

    func structLines(_ schema: Schema) -> [String] {
        guard case .structure(let name, let fields) = schema else { return [] }
        let typeName = ident(name ?? "Root")
        var lines = [
            "public struct \(typeName): Equatable, Sendable {",
        ]
        for field in fields {
            lines.append("    public var \(ident(field.name)): \(swiftType(field.schema))")
        }
        lines.append("")
        if fields.isEmpty {
            lines.append("    public init() {}")
        } else {
            let params = fields.map {
                "\(ident($0.name)): \(swiftType($0.schema)) = \(defaultExpr($0.schema))"
            }
            lines.append("    public init(\(params.joined(separator: ", "))) {")
            for field in fields {
                let prop = ident(field.name)
                lines.append("        self.\(prop) = \(prop)")
            }
            lines.append("    }")
        }
        lines.append("")
        lines.append("    public static func schema() -> Schema {")
        lines.append("        .structure([")
        for field in fields {
            lines.append("            (\(swiftString(field.name)), \(schemaExpr(field.schema))),")
        }
        lines.append("        ], name: \(swiftString(name ?? "Root")))")
        lines.append("    }")
        lines.append("")
        lines.append("    public func encode() throws -> [UInt8] {")
        lines.append("        try Kiln.encode(\(typeName).schema(), toValue())")
        lines.append("    }")
        lines.append("")
        lines.append("    public static func decode(_ bytes: [UInt8]) throws -> \(typeName) {")
        lines.append("        try fromValue(Kiln.decode(\(typeName).schema(), bytes))")
        lines.append("    }")
        lines.append("")
        lines.append("    public func encodedSize() throws -> Int {")
        lines.append("        try encode().count")
        lines.append("    }")
        lines.append("")
        lines.append("    public func toValue() -> Value {")
        lines.append("        .object([")
        for field in fields {
            let access = "self.\(ident(field.name))"
            lines.append("            \(swiftString(field.name)): \(valueExpr(field.schema, access)),")
        }
        lines.append("        ])")
        lines.append("    }")
        lines.append("")
        lines.append("    public static func fromValue(_ value: Value) throws -> \(typeName) {")
        lines.append("        guard case .object(let fields) = value else { throw KilnError(.TYPE) }")
        lines.append("        return \(typeName)(")
        for field in fields {
            let access = "fields[\(swiftString(field.name))]"
            lines.append("            \(ident(field.name)): \(readExpr(field.schema, access)),")
        }
        lines.append("        )")
        lines.append("    }")
        lines.append("}")
        return lines
    }

    func valueExpr(_ schema: Schema, _ access: String) -> String {
        switch schema {
        case .scalar(.bool):
            return ".bool(\(access))"
        case .scalar(.i8), .scalar(.i16), .scalar(.i32), .scalar(.i64), .scalar(.int):
            return ".int(Int64(\(access)))"
        case .scalar(.u8), .scalar(.u16), .scalar(.u32), .scalar(.u64), .scalar(.uint):
            return ".uint(UInt64(\(access)))"
        case .scalar(.f32):
            return ".f32(\(access))"
        case .scalar(.f64):
            return ".f64(\(access))"
        case .str:
            return ".string(\(access))"
        case .bytes:
            return ".bytes(\(access))"
        case .tensors:
            return access
        case .opt(let inner):
            fresh += 1
            let name = "v\(fresh)"
            return "\(access).map { \(name) in \(valueExpr(inner, name)) } ?? .null"
        case .list(let inner):
            fresh += 1
            let name = "v\(fresh)"
            return ".list(\(access).map { \(name) in \(valueExpr(inner, name)) })"
        case .dict(let inner):
            fresh += 1
            let name = "v\(fresh)"
            return ".object(Dictionary(uniqueKeysWithValues: \(access).map { \(name) in (\(name).key, \(valueExpr(inner, "\(name).value"))) }))"
        case .structure:
            return "\(access).toValue()"
        }
    }

    func readExpr(_ schema: Schema, _ access: String) -> String {
        switch schema {
        case .scalar(.bool): return "try boolValue(\(access))"
        case .scalar(.i8): return "try int8Value(\(access))"
        case .scalar(.i16): return "try int16Value(\(access))"
        case .scalar(.i32): return "try int32Value(\(access))"
        case .scalar(.i64), .scalar(.int): return "try int64Value(\(access))"
        case .scalar(.u8): return "try uint8Value(\(access))"
        case .scalar(.u16): return "try uint16Value(\(access))"
        case .scalar(.u32): return "try uint32Value(\(access))"
        case .scalar(.u64), .scalar(.uint): return "try uint64Value(\(access))"
        case .scalar(.f32): return "try f32Value(\(access))"
        case .scalar(.f64): return "try f64Value(\(access))"
        case .str: return "try stringValue(\(access))"
        case .bytes: return "try bytesValue(\(access))"
        case .tensors: return "try tensorsValue(\(access))"
        case .opt(let inner):
            fresh += 1
            let name = "v\(fresh)"
            return "try optionalValue(\(access)) { \(name) in \(readExpr(inner, name)) }"
        case .list(.scalar(.u8)):
            return "try byteList(\(access))"
        case .list(let inner):
            fresh += 1
            let name = "v\(fresh)"
            return "try listValue(\(access)) { \(name) in \(readExpr(inner, name)) }"
        case .dict(let inner):
            fresh += 1
            let name = "v\(fresh)"
            return "try dictValue(\(access)) { \(name) in \(readExpr(inner, name)) }"
        case .structure(let name, _):
            return "try \(ident(name ?? "Root")).fromValue(\(access) ?? .null)"
        }
    }

    func schemaExpr(_ schema: Schema) -> String {
        switch schema {
        case .scalar(.bool): return ".bool"
        case .scalar(let kind): return ".\(kind.rawValue)"
        case .str: return ".str"
        case .bytes: return ".bytes"
        case .tensors: return ".tensors"
        case .list(let inner): return ".list(\(schemaExpr(inner)))"
        case .opt(let inner): return ".opt(\(schemaExpr(inner)))"
        case .dict(let inner): return ".dict(\(schemaExpr(inner)))"
        case .structure(let name, _): return "\(ident(name ?? "Root")).schema()"
        }
    }
}
