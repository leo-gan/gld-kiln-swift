/// FNV-1a 64 of the canonical type text. Each token is mixed, then a 0x00 step.
public func typeHash(_ schema: Schema) -> UInt64 {
    hashSchema(fnvOffset, schema)
}

private let fnvOffset: UInt64 = 14_695_981_039_346_656_037
private let fnvPrime: UInt64 = 1_099_511_628_211

private func mix(_ hash: UInt64, _ data: some Sequence<UInt8>) -> UInt64 {
    var hash = hash
    for byte in data {
        hash ^= UInt64(byte)
        hash = hash &* fnvPrime
    }
    return hash &* fnvPrime
}

private func mix(_ hash: UInt64, _ text: String) -> UInt64 {
    mix(hash, text.utf8)
}

private func hashSchema(_ hash: UInt64, _ schema: Schema) -> UInt64 {
    switch schema {
    case .scalar(let kind):
        return mix(hash, kind.rawValue)
    case .str:
        return mix(hash, "str")
    case .bytes:
        return mix(hash, "bytes")
    case .tensors:
        return mix(hash, "tensors")
    case .list(let element):
        var hash = mix(hash, "list<")
        hash = hashSchema(hash, element)
        return mix(hash, ">")
    case .opt(let element):
        var hash = mix(hash, "opt<")
        hash = hashSchema(hash, element)
        return mix(hash, ">")
    case .dict(let value):
        var hash = mix(hash, "dict<str,")
        hash = hashSchema(hash, value)
        return mix(hash, ">")
    case .structure(_, let fields):
        var hash = mix(hash, "struct{")
        for field in fields {
            hash = mix(hash, field.name.utf8)
            hash = mix(hash, ":")
            hash = hashSchema(hash, field.schema)
            hash = mix(hash, ",")
        }
        return mix(hash, "}")
    }
}
