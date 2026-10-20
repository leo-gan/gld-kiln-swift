private let intFormats: [String: ScalarKind] = [
    "int8": .i8,
    "int16": .i16,
    "int32": .i32,
    "int64": .i64,
    "uint8": .u8,
    "uint16": .u16,
    "uint32": .u32,
    "uint64": .u64,
]

/// JSON Schema subset from the wire spec. The name is the document title.
public func schemaFromJSON(_ text: String) throws -> (name: String, schema: Schema) {
    let doc: JSON
    do {
        doc = try parseJSON(Array(text.utf8))
    } catch let error as KilnError {
        throw error
    } catch {
        throw KilnError(.SCHEMA)
    }
    guard case .object = doc else { throw KilnError(.SCHEMA) }
    var title = "Root"
    if let text = doc.field("title")?.string, !text.isEmpty {
        title = text
    }
    var converter = SchemaConverter(defs: doc.field("$defs"))
    let root = try converter.convert(doc, label: title)
    return (title, root)
}

private struct SchemaConverter {
    var defs: JSON?
    var cache: [String: Schema] = [:]
    var building = Set<String>()

    mutating func convert(_ node: JSON, label: String) throws -> Schema {
        guard case .object = node else { throw KilnError(.SCHEMA) }
        if let ref = node.field("$ref") {
            guard case .string(let text) = ref else { throw KilnError(.SCHEMA) }
            let prefix = "#/$defs/"
            guard text.hasPrefix(prefix) else { throw KilnError(.SCHEMA) }
            return try resolve(String(text.dropFirst(prefix.count)))
        }
        guard case .string(let kind) = node.field("type") else { throw KilnError(.SCHEMA) }
        switch kind {
        case "boolean":
            return .bool
        case "string":
            if case .string("binary") = node.field("format") { return .bytes }
            return .str
        case "integer":
            let format = node.field("format")?.string ?? ""
            return .scalar(intFormats[format] ?? .i64)
        case "number":
            if case .string("float") = node.field("format") { return .f32 }
            return .f64
        case "array":
            guard let items = node.field("items") else { throw KilnError(.SCHEMA) }
            return .list(try convert(items, label: label + "Item"))
        case "object":
            let propCount = node.field("properties")?.objectPairs?.count ?? 0
            if let extra = node.field("additionalProperties"), case .object = extra, propCount == 0 {
                return .dict(try convert(extra, label: label + "Value"))
            }
            return try objectSchema(node, label: label)
        default:
            throw KilnError(.SCHEMA)
        }
    }

    mutating func resolve(_ name: String) throws -> Schema {
        if let hit = cache[name] { return hit }
        if building.contains(name) { throw KilnError(.SCHEMA) }
        guard let body = defs?.field(name) else { throw KilnError(.SCHEMA) }
        building.insert(name)
        let built = try convert(body, label: name)
        building.remove(name)
        cache[name] = built
        return built
    }

    mutating func objectSchema(_ node: JSON, label: String) throws -> Schema {
        var fields: [(String, Schema)] = []
        if let pairs = node.field("properties")?.objectPairs {
            let requiredNames = node.field("required")?.arrayItems?.compactMap(\.string)
            for (fname, body) in pairs {
                var field = try convert(body, label: label + "_" + fname)
                if let requiredNames, !requiredNames.contains(fname) {
                    field = .opt(field)
                }
                fields.append((fname, field))
            }
        }
        return .structure(fields, name: label)
    }
}
