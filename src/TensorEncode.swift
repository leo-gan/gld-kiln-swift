struct TensorPlan {
    var nameOff: UInt16 = 0xFFFF
    var nameLen: UInt16 = 0
    var layoutOff: UInt16 = 0xFFFF
    var layoutLen: UInt16 = 0
    var byteOffset: UInt64 = 0
    var byteLength: UInt64 = 0
    var hasName = false
    var hasLayout = false
}

public func encodeTensors(_ tensors: [Tensor]) throws -> [UInt8] {
    var plans = [TensorPlan](repeating: TensorPlan(), count: tensors.count)
    var heap = 0
    var anyName = false
    for index in tensors.indices {
        if tensors[index].rank > 8 { throw KilnError(.TYPE) }
        let nameCount = tensors[index].name?.utf8.count ?? 0
        if nameCount > 0 {
            if heap > 0xFFFF || nameCount > 0xFFFF { throw KilnError(.LIMIT) }
            plans[index].nameOff = UInt16(heap)
            plans[index].nameLen = UInt16(nameCount)
            plans[index].hasName = true
            anyName = true
            heap += nameCount
        }
    }
    for index in tensors.indices {
        let layoutCount = tensors[index].layout?.utf8.count ?? 0
        if layoutCount > 0 {
            if heap > 0xFFFF || layoutCount > 0xFFFF { throw KilnError(.LIMIT) }
            plans[index].layoutOff = UInt16(heap)
            plans[index].layoutLen = UInt16(layoutCount)
            plans[index].hasLayout = true
            heap += layoutCount
        }
        plans[index].byteLength = UInt64(tensors[index].dataCount)
    }
    var payloadEnd: UInt64 = 0
    for index in plans.indices {
        let offset = try align64(payloadEnd)
        plans[index].byteOffset = offset
        payloadEnd = try addU(offset, plans[index].byteLength)
    }
    let directoryBytes = tensors.count * tensorDescriptor + heap
    let payloadBase = try align64(UInt64(tensorHeader + directoryBytes))
    let blockLength = try addU(payloadBase, payloadEnd)
    guard blockLength <= UInt64(Int.max) else { throw KilnError(.LIMIT) }
    let prefix = Int(payloadBase)
    let total = Int(blockLength)
    var block = [UInt8](unsafeUninitializedCapacity: total) { raw, initialized in
        guard let base = raw.baseAddress else {
            initialized = 0
            return
        }
        base.initialize(repeating: 0, count: prefix)
        var filled = prefix
        for index in tensors.indices {
            let at = prefix + Int(plans[index].byteOffset)
            if at > filled {
                (base + filled).initialize(repeating: 0, count: at - filled)
            }
            tensors[index].withPayload { slice in
                if slice.isEmpty { return }
                slice.withUnsafeBytes { src in
                    (base + at).initialize(
                        from: src.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        count: slice.count
                    )
                }
            }
            filled = at + Int(plans[index].byteLength)
        }
        if filled < total {
            (base + filled).initialize(repeating: 0, count: total - filled)
        }
        initialized = total
    }
    block[0] = UInt8(ascii: "K")
    block[1] = UInt8(ascii: "L")
    block[2] = UInt8(ascii: "N")
    block[3] = UInt8(ascii: "T")
    block[4] = 2
    block[5] = anyName ? 0x03 : 0x02
    storeU32(UInt32(tensors.count), &block, 8)
    storeU32(UInt32(heap), &block, 12)
    storeU64(payloadEnd, &block, 16)
    storeU64(UInt64(directoryBytes), &block, 24)
    var cursor = tensorHeader + tensors.count * tensorDescriptor
    for index in tensors.indices where plans[index].hasName {
        cursor = writeUTF8(tensors[index].name ?? "", into: &block, at: cursor)
    }
    for index in tensors.indices where plans[index].hasLayout {
        cursor = writeUTF8(tensors[index].layout ?? "", into: &block, at: cursor)
    }
    for (index, tensor) in tensors.enumerated() {
        let plan = plans[index]
        let base = tensorHeader + index * tensorDescriptor
        storeU16(tensor.dtype, &block, base)
        block[base + 2] = UInt8(tensor.rank)
        storeU16(plan.nameOff, &block, base + 4)
        storeU16(plan.nameLen, &block, base + 6)
        storeU16(plan.layoutOff, &block, base + 8)
        storeU16(plan.layoutLen, &block, base + 10)
        storeU32(tensor.blockSize, &block, base + 12)
        storeU16(tensor.quantScheme, &block, base + 16)
        storeU16(tensor.quantAxis, &block, base + 18)
        storeU32(tensor.groupSize, &block, base + 20)
        storeU32(tensor.scaleIndex, &block, base + 24)
        storeU32(tensor.outerIndex, &block, base + 28)
        storeU64(plan.byteOffset, &block, base + 32)
        storeU64(plan.byteLength, &block, base + 40)
        for dim in 0..<8 {
            storeU64(tensor.dims[dim], &block, base + 48 + dim * 8)
        }
    }
    return block
}

private func writeUTF8(_ text: String, into block: inout [UInt8], at index: Int) -> Int {
    var cursor = index
    for byte in text.utf8 {
        block[cursor] = byte
        cursor += 1
    }
    return cursor
}
