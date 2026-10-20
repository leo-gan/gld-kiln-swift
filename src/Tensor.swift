let tensorHeader = 64
let tensorDescriptor = 128
let tensorDTypes: [String: UInt16] = [
    "f64": 1, "f32": 2, "f16": 3, "bf16": 4,
    "f8e4m3": 5, "f8e5m2": 6, "bool": 7,
    "i8": 8, "u8": 9, "i16": 10, "u16": 11,
    "i32": 12, "u32": 13, "i64": 14, "u64": 15,
    "i4": 16, "u4": 17, "e2m1": 18, "e8m0": 19,
]
let tensorNames: [UInt16: String] = Dictionary(uniqueKeysWithValues: tensorDTypes.map { ($1, $0) })
let wholeBytes: [UInt16: UInt64] = [
    1: 8, 2: 4, 3: 2, 4: 2, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1,
    10: 2, 11: 2, 12: 4, 13: 4, 14: 8, 15: 8, 19: 1,
]
let packedDTypes: Set<UInt16> = [16, 17, 18]

struct Dims: Sendable, Equatable {
    var v0: UInt64 = 0
    var v1: UInt64 = 0
    var v2: UInt64 = 0
    var v3: UInt64 = 0
    var v4: UInt64 = 0
    var v5: UInt64 = 0
    var v6: UInt64 = 0
    var v7: UInt64 = 0

    subscript(_ index: Int) -> UInt64 {
        get {
            switch index {
            case 0: return v0
            case 1: return v1
            case 2: return v2
            case 3: return v3
            case 4: return v4
            case 5: return v5
            case 6: return v6
            default: return v7
            }
        }
        set {
            switch index {
            case 0: v0 = newValue
            case 1: v1 = newValue
            case 2: v2 = newValue
            case 3: v3 = newValue
            case 4: v4 = newValue
            case 5: v5 = newValue
            case 6: v6 = newValue
            default: v7 = newValue
            }
        }
    }
}

public struct Tensor: Sendable, Equatable {
    public var name: String?
    public var dtype: UInt16
    public var dtypeName: String?
    var rank = 0
    var dims = Dims()
    var ownedData: [UInt8]
    var borrowed: ArraySlice<UInt8>?
    public var quantScheme: UInt16
    public var quantAxis: UInt16
    public var groupSize: UInt32
    public var scaleIndex: UInt32
    public var outerIndex: UInt32
    public var layout: String?
    public var blockSize: UInt32

    public var data: [UInt8] {
        if let borrowed { return Array(borrowed) }
        return ownedData
    }

    var dataCount: Int { borrowed?.count ?? ownedData.count }

    public var shape: [UInt64] {
        var out: [UInt64] = []
        out.reserveCapacity(rank)
        for index in 0..<rank { out.append(dims[index]) }
        return out
    }

    public init(
        name: String? = nil,
        dtype: UInt16,
        dtypeName: String? = nil,
        shape: [UInt64],
        data: [UInt8],
        quantScheme: UInt16 = 0,
        quantAxis: UInt16 = 0xFFFF,
        groupSize: UInt32 = 0,
        scaleIndex: UInt32 = 0xFFFF_FFFF,
        outerIndex: UInt32 = 0xFFFF_FFFF,
        layout: String? = nil,
        blockSize: UInt32 = 0
    ) {
        self.name = name
        self.dtype = dtype
        self.dtypeName = dtypeName ?? tensorNames[dtype]
        self.ownedData = data
        self.rank = shape.count
        let limit = min(shape.count, 8)
        for index in 0..<limit { self.dims[index] = shape[index] }
        self.quantScheme = quantScheme
        self.quantAxis = quantAxis
        self.groupSize = groupSize
        self.scaleIndex = scaleIndex
        self.outerIndex = outerIndex
        self.layout = layout
        self.blockSize = blockSize
    }

    func withPayload<T>(_ body: (ArraySlice<UInt8>) -> T) -> T {
        if let borrowed { return body(borrowed) }
        return body(ownedData[0..<ownedData.count])
    }

    public static func == (lhs: Tensor, rhs: Tensor) -> Bool {
        lhs.name == rhs.name && lhs.dtype == rhs.dtype && lhs.dtypeName == rhs.dtypeName
            && lhs.rank == rhs.rank && lhs.dims == rhs.dims && lhs.quantScheme == rhs.quantScheme
            && lhs.quantAxis == rhs.quantAxis && lhs.groupSize == rhs.groupSize
            && lhs.scaleIndex == rhs.scaleIndex && lhs.outerIndex == rhs.outerIndex
            && lhs.layout == rhs.layout && lhs.blockSize == rhs.blockSize
            && lhs.dataCount == rhs.dataCount
            && lhs.withPayload { left in rhs.withPayload { left.elementsEqual($0) } }
    }
}

public struct TensorDirectory: Sendable, Equatable {
    public var version: Int
    public var flags: [String]
    public var tensors: [Tensor]
    public var blockLength: Int

    public init(version: Int, flags: [String], tensors: [Tensor], blockLength: Int) {
        self.version = version
        self.flags = flags
        self.tensors = tensors
        self.blockLength = blockLength
    }
}

struct RawTensor {
    var dtype: UInt16 = 0
    var rank: UInt8 = 0
    var reserved: UInt8 = 0
    var nameOff: UInt16 = 0
    var nameLen: UInt16 = 0
    var layoutOff: UInt16 = 0
    var layoutLen: UInt16 = 0
    var blockSize: UInt32 = 0
    var quantScheme: UInt16 = 0
    var quantAxis: UInt16 = 0
    var groupSize: UInt32 = 0
    var scaleIndex: UInt32 = 0
    var outerIndex: UInt32 = 0
    var byteOffset: UInt64 = 0
    var byteLength: UInt64 = 0
    var shape = Dims()
    var name: [UInt8] = []
    var layout: [UInt8] = []
}

public func tensor(
    _ dtype: String,
    shape: [UInt64],
    data: [UInt8],
    name: String? = nil
) throws -> Tensor {
    guard let code = tensorDTypes[dtype] else { throw KilnError(.TYPE) }
    return Tensor(name: name, dtype: code, dtypeName: dtype, shape: shape, data: data)
}

func elementCount(rank: Int, shape: Dims) throws -> UInt64 {
    if rank == 0 { return 1 }
    var count: UInt64 = 1
    for dim in 0..<rank {
        count = try mulU(count, shape[dim])
    }
    return count
}

func expectedBytes(dtype: UInt16, count: UInt64) throws -> UInt64 {
    if let width = wholeBytes[dtype] { return try mulU(count, width) }
    if packedDTypes.contains(dtype) { return (count + 1) / 2 }
    throw KilnError(.TYPE)
}
