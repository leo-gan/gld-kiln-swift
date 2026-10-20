func checkTensor(_ item: RawTensor) throws {
    if item.rank > 8 { throw KilnError(.TYPE) }
    for dim in Int(item.rank)..<8 where item.shape[dim] != 0 {
        throw KilnError(.TYPE)
    }
    let dtype = item.dtype
    if dtype == 0 || (dtype >= 20 && dtype < 4096) || dtype > 32767 {
        throw KilnError(.TYPE)
    }
    let count = try elementCount(rank: Int(item.rank), shape: item.shape)
    if dtype >= 4096 {
        if item.layout.isEmpty || item.blockSize == 0 { throw KilnError(.TYPE) }
        if item.byteLength % UInt64(item.blockSize) != 0 { throw KilnError(.TYPE) }
        return
    }
    if !item.layout.isEmpty || item.blockSize != 0 { throw KilnError(.TYPE) }
    if item.byteLength != (try expectedBytes(dtype: dtype, count: count)) {
        throw KilnError(.TYPE)
    }
}

func validatePayloads(
    _ raw: [RawTensor],
    buf: [UInt8],
    start: Int,
    payloadBase: UInt64,
    payloadBytes: UInt64,
    trusted: Bool
) throws {
    var ranges: [(UInt64, UInt64)] = []
    ranges.reserveCapacity(raw.count)
    for item in raw {
        let itemEnd = try addU(item.byteOffset, item.byteLength)
        if itemEnd > payloadBytes { throw KilnError(.TYPE) }
        ranges.append((item.byteOffset, itemEnd))
        try checkTensor(item)
    }
    for left in ranges.indices {
        let (startA, endA) = ranges[left]
        for right in (left + 1)..<ranges.count {
            let (startB, endB) = ranges[right]
            if startA == endA || startB == endB { continue }
            if startA < endB && startB < endA { throw KilnError(.TYPE) }
        }
    }
    var cursor: UInt64 = 0
    for item in raw {
        guard let aligned = try? align64(cursor), item.byteOffset == aligned else {
            throw KilnError(.TYPE)
        }
        cursor = try addU(item.byteOffset, item.byteLength)
    }
    if cursor != payloadBytes { throw KilnError(.TYPE) }
    let payloadStart = start + Int(payloadBase)
    for item in raw {
        let count = try elementCount(rank: Int(item.rank), shape: item.shape)
        let region = buf[(payloadStart + Int(item.byteOffset))..<(payloadStart + Int(item.byteOffset + item.byteLength))]
        if packedDTypes.contains(item.dtype), count % 2 == 1, let last = region.last, last >> 4 != 0 {
            throw KilnError(.TYPE)
        }
        if item.dtype == 7 {
            for byte in region where byte > 1 { throw KilnError(.TYPE) }
        }
    }
    var covered: UInt64 = 0
    for item in raw {
        let gapStart = payloadStart + Int(covered)
        let gapEnd = payloadStart + Int(item.byteOffset)
        if gapEnd > gapStart, !allZero(buf[gapStart..<gapEnd]) { throw KilnError(.TYPE) }
        covered = try addU(item.byteOffset, item.byteLength)
    }
    let tail = payloadStart + Int(covered)
    let payloadEnd = payloadStart + Int(payloadBytes)
    if payloadEnd > tail, !allZero(buf[tail..<payloadEnd]) { throw KilnError(.TYPE) }
    if !trusted { try checkQuant(raw) }
}

func checkQuant(_ tensors: [RawTensor]) throws {
    for index in tensors.indices {
        let item = tensors[index]
        if item.quantScheme == 0 {
            if item.groupSize != 0 || item.quantAxis != 0xFFFF
                || item.scaleIndex != 0xFFFF_FFFF || item.outerIndex != 0xFFFF_FFFF {
                throw KilnError(.TYPE)
            }
            continue
        }
        if item.quantScheme != 1 && item.quantScheme != 2 { throw KilnError(.TYPE) }
        if item.rank == 0 || item.quantAxis >= UInt16(item.rank) || item.groupSize == 0 {
            throw KilnError(.TYPE)
        }
        if item.scaleIndex >= UInt32(tensors.count) || Int(item.scaleIndex) == index {
            throw KilnError(.TYPE)
        }
        let scale = Int(item.scaleIndex)
        if tensors[scale].quantScheme != 0 { throw KilnError(.TYPE) }
        let axis = Int(item.quantAxis)
        let group = UInt64(item.groupSize)
        let (sum, overflow) = item.shape[axis].addingReportingOverflow(group - 1)
        if overflow { throw KilnError(.LIMIT) }
        let groups = sum / group
        var otherDims: UInt64 = 1
        for dim in 0..<Int(item.rank) where dim != axis {
            otherDims = try mulU(otherDims, item.shape[dim])
        }
        let need = try mulU(groups, otherDims)
        let scaleCount = try elementCount(rank: Int(tensors[scale].rank), shape: tensors[scale].shape)
        if scaleCount != need { throw KilnError(.TYPE) }
        if item.quantScheme == 1 {
            if item.outerIndex != 0xFFFF_FFFF { throw KilnError(.TYPE) }
            continue
        }
        if item.outerIndex >= UInt32(tensors.count) { throw KilnError(.TYPE) }
        let outer = Int(item.outerIndex)
        if outer == index || outer == scale { throw KilnError(.TYPE) }
        let outerItem = tensors[outer]
        if outerItem.quantScheme != 0 || outerItem.dtype != tensorDTypes["f32"] {
            throw KilnError(.TYPE)
        }
        if try elementCount(rank: Int(outerItem.rank), shape: outerItem.shape) != 1 {
            throw KilnError(.TYPE)
        }
    }
}
