private let flagLE = ["le"]
private let flagNames = ["names", "le"]

func decodeTensorBlock(
    _ buf: [UInt8],
    start: Int,
    standalone: Bool,
    cap: Int,
    trusted: Bool
) throws -> (TensorDirectory, Int) {
    let viewCount = buf.count - start
    if viewCount < 4 { throw KilnError(.EOF, offset: start) }
    if buf[start] != 0x4B || buf[start + 1] != 0x4C || buf[start + 2] != 0x4E || buf[start + 3] != 0x54 {
        throw KilnError(.FRAME, offset: start)
    }
    if viewCount < tensorHeader { throw KilnError(.EOF, offset: start) }
    let version = buf[start + 4]
    let flags = buf[start + 5]
    let reserved16 = loadU16(buf, start + 6)
    let tensorCount = loadU32(buf, start + 8)
    let nameBytes = loadU32(buf, start + 12)
    let payloadBytes = loadU64(buf, start + 16)
    let directoryBytes = loadU64(buf, start + 24)
    if version != 2 || (flags & ~0x03) != 0 || (flags & 0x02) == 0 {
        throw KilnError(.FRAME, offset: start)
    }
    if reserved16 != 0 || !allZero(buf[(start + 32)..<(start + 64)]) {
        throw KilnError(.FRAME, offset: start)
    }
    if UInt64(tensorCount) > UInt64(cap) || UInt64(nameBytes) > UInt64(cap) {
        throw KilnError(.LIMIT, offset: start)
    }
    let expectDir = try addU(try mulU(UInt64(tensorCount), UInt64(tensorDescriptor)), UInt64(nameBytes))
    if directoryBytes != expectDir { throw KilnError(.TYPE, offset: start) }
    let directoryEnd = try addU(UInt64(tensorHeader), directoryBytes)
    if directoryEnd > UInt64(viewCount) { throw KilnError(.EOF, offset: start) }
    let payloadBase = try align64(directoryEnd)
    let blockEnd = try addU(payloadBase, payloadBytes)
    if blockEnd > UInt64(viewCount) { throw KilnError(.EOF, offset: start) }
    let padStart = start + Int(directoryEnd)
    let padEnd = start + Int(payloadBase)
    if !allZero(buf[padStart..<padEnd]) { throw KilnError(.TYPE, offset: padStart) }

    var raw: [RawTensor] = []
    raw.reserveCapacity(Int(tensorCount))
    for index in 0..<Int(tensorCount) {
        let base = start + tensorHeader + index * tensorDescriptor
        var item = RawTensor()
        item.dtype = loadU16(buf, base)
        item.rank = buf[base + 2]
        item.reserved = buf[base + 3]
        item.nameOff = loadU16(buf, base + 4)
        item.nameLen = loadU16(buf, base + 6)
        item.layoutOff = loadU16(buf, base + 8)
        item.layoutLen = loadU16(buf, base + 10)
        item.blockSize = loadU32(buf, base + 12)
        item.quantScheme = loadU16(buf, base + 16)
        item.quantAxis = loadU16(buf, base + 18)
        item.groupSize = loadU32(buf, base + 20)
        item.scaleIndex = loadU32(buf, base + 24)
        item.outerIndex = loadU32(buf, base + 28)
        item.byteOffset = loadU64(buf, base + 32)
        item.byteLength = loadU64(buf, base + 40)
        for dim in 0..<8 {
            item.shape[dim] = loadU64(buf, base + 48 + dim * 8)
        }
        if !allZero(buf[(base + 112)..<(base + 128)]) { throw KilnError(.FRAME, offset: base) }
        raw.append(item)
    }
    try bindNames(&raw, buf: buf, start: start, nameBytes: nameBytes, flags: flags, trusted: trusted)
    try validatePayloads(raw, buf: buf, start: start, payloadBase: payloadBase, payloadBytes: payloadBytes, trusted: trusted)
    if standalone && blockEnd != UInt64(viewCount) { throw KilnError(.TRAILING, offset: start + Int(blockEnd)) }
    let names = (flags & 0x01) != 0
    let directory = TensorDirectory(
        version: 2,
        flags: names ? flagNames : flagLE,
        tensors: raw.map { makeTensor($0, buf: buf, start: start, payloadBase: payloadBase) },
        blockLength: Int(blockEnd)
    )
    return (directory, Int(blockEnd))
}

public func decodeTensors(
    _ buffer: [UInt8],
    standalone: Bool = true,
    cap: Int = defaultCap,
    trusted: Bool = false
) throws -> (TensorDirectory, Int) {
    try decodeTensorBlock(buffer, start: 0, standalone: standalone, cap: cap, trusted: trusted)
}

private func bindNames(
    _ raw: inout [RawTensor],
    buf: [UInt8],
    start: Int,
    nameBytes: UInt32,
    flags: UInt8,
    trusted: Bool
) throws {
    let namesFlag = (flags & 0x01) != 0
    let hasName = raw.contains { $0.nameLen != 0 }
    if namesFlag != hasName || (namesFlag && raw.contains { $0.nameLen == 0 }) {
        throw KilnError(.TYPE)
    }
    let heapStart = start + tensorHeader + raw.count * tensorDescriptor
    var parts: [UInt8] = []
    var layouts: [UInt8] = []
    var seen = Set<[UInt8]>()
    for index in raw.indices {
        if raw[index].reserved != 0 { throw KilnError(.FRAME) }
        if raw[index].nameLen == 0 {
            if raw[index].nameOff != 0xFFFF { throw KilnError(.TYPE) }
        } else {
            if raw[index].nameOff == 0xFFFF { throw KilnError(.TYPE) }
            let name = try heapSlice(buf, heapStart: heapStart, nameBytes: nameBytes, off: raw[index].nameOff, len: raw[index].nameLen)
            if !trusted && !utf8OK(name) { throw KilnError(.UTF8) }
            if seen.contains(name) { throw KilnError(.TYPE) }
            seen.insert(name)
            parts.append(contentsOf: name)
            raw[index].name = name
        }
        if raw[index].layoutLen == 0 {
            if raw[index].layoutOff != 0xFFFF { throw KilnError(.TYPE) }
        } else {
            let layout = try heapSlice(buf, heapStart: heapStart, nameBytes: nameBytes, off: raw[index].layoutOff, len: raw[index].layoutLen)
            if !trusted && !utf8OK(layout) { throw KilnError(.UTF8) }
            layouts.append(contentsOf: layout)
            raw[index].layout = layout
        }
    }
    let heap = Array(buf[heapStart..<(heapStart + Int(nameBytes))])
    if heap != parts + layouts { throw KilnError(.TYPE) }
}

private func heapSlice(
    _ buf: [UInt8],
    heapStart: Int,
    nameBytes: UInt32,
    off: UInt16,
    len: UInt16
) throws -> [UInt8] {
    let end = try addU(UInt64(off), UInt64(len))
    if end > UInt64(nameBytes) { throw KilnError(.TYPE) }
    let begin = heapStart + Int(off)
    return Array(buf[begin..<(begin + Int(len))])
}

private func makeTensor(_ item: RawTensor, buf: [UInt8], start: Int, payloadBase: UInt64) -> Tensor {
    let rank = Int(item.rank)
    let dataAt = start + Int(payloadBase + item.byteOffset)
    var tensor = Tensor(
        name: item.name.isEmpty ? nil : String(decoding: item.name, as: UTF8.self),
        dtype: item.dtype,
        dtypeName: tensorNames[item.dtype],
        shape: [],
        data: [],
        quantScheme: item.quantScheme,
        quantAxis: item.quantAxis,
        groupSize: item.groupSize,
        scaleIndex: item.scaleIndex,
        outerIndex: item.outerIndex,
        layout: item.layout.isEmpty ? nil : String(decoding: item.layout, as: UTF8.self),
        blockSize: item.blockSize
    )
    tensor.rank = rank
    tensor.dims = item.shape
    tensor.borrowed = buf[dataAt..<(dataAt + Int(item.byteLength))]
    return tensor
}
