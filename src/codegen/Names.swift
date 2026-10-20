import Kiln

func swiftType(_ schema: Schema) -> String {
    switch schema {
    case .scalar(.bool): return "Bool"
    case .scalar(.i8): return "Int8"
    case .scalar(.i16): return "Int16"
    case .scalar(.i32): return "Int32"
    case .scalar(.i64), .scalar(.int): return "Int64"
    case .scalar(.u8): return "UInt8"
    case .scalar(.u16): return "UInt16"
    case .scalar(.u32): return "UInt32"
    case .scalar(.u64), .scalar(.uint): return "UInt64"
    case .scalar(.f32): return "Float"
    case .scalar(.f64): return "Double"
    case .str: return "String"
    case .bytes: return "[UInt8]"
    case .tensors: return "TensorDirectory"
    case .list(let inner): return "[\(swiftType(inner))]"
    case .opt(let inner): return "\(swiftType(inner))?"
    case .dict(let inner): return "[String: \(swiftType(inner))]"
    case .structure(let name, _): return ident(name ?? "Root")
    }
}

func defaultExpr(_ schema: Schema) -> String {
    switch schema {
    case .scalar(.bool): return "false"
    case .scalar(.f32), .scalar(.f64): return "0"
    case .str: return "\"\""
    case .bytes, .list: return "[]"
    case .dict: return "[:]"
    case .opt: return "nil"
    case .structure(let name, _): return "\(ident(name ?? "Root"))()"
    case .tensors: return "TensorDirectory(version: 2, flags: [], tensors: [], blockLength: 0)"
    default: return "0"
    }
}

func ident(_ name: String) -> String {
    var out = ""
    for (index, scalar) in name.unicodeScalars.enumerated() {
        let letter = (scalar >= "A" && scalar <= "Z") || (scalar >= "a" && scalar <= "z") || scalar == "_"
        let digit = scalar >= "0" && scalar <= "9"
        if letter || (index > 0 && digit) {
            out.unicodeScalars.append(scalar)
        } else {
            out.append("_")
        }
    }
    if out.isEmpty { out = "Root" }
    if out.first?.isNumber == true { out = "_" + out }
    if swiftKeywords.contains(out) { out += "_" }
    return out
}

func swiftString(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        default: out.unicodeScalars.append(scalar)
        }
    }
    out += "\""
    return out
}

let swiftKeywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
    "init", "inout", "internal", "let", "operator", "private", "protocol", "public", "rethrows",
    "static", "struct", "subscript", "typealias", "var", "break", "case", "continue", "default",
    "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch",
    "where", "while", "as", "Any", "catch", "false", "is", "nil", "super", "self", "Self", "throw",
    "throws", "true", "try", "some", "any", "Type",
]
