import Foundation
import XCTest

@testable import Kiln

final class WireTests: XCTestCase {
    func testAllFortySixCases() throws {
        let root = try parseJSON(Data(contentsOf: casesURL()))
        let cases = root.field("cases")?.arrayItems ?? []
        XCTAssertEqual(cases.count, 46)
        var failures: [String] = []
        for item in cases {
            guard let id = item.field("id")?.string else {
                failures.append("missing id")
                continue
            }
            do {
                try check(item)
            } catch {
                failures.append("\(id) threw \(error)")
            }
        }
        if !failures.isEmpty {
            XCTFail(failures.joined(separator: "\n"))
        }
    }

    func testListCapDoesNotAllocate() {
        let raw = [UInt8(0x01), 0x00, 0x00, 0x01]
        XCTAssertThrowsError(try decode(.list(.i8), raw)) { error in
            XCTAssertEqual((error as? KilnError)?.code, .LIMIT)
        }
    }

    private func check(_ item: JSON) throws {
        let id = item.field("id")?.string ?? "?"
        let raw = hexDecode(item.field("input")?.string ?? "")
        let schemaJSON = item.field("schema") ?? .null
        let schema = try schemaFromCase(schemaJSON)
        let framed = item.field("schema")?.string == "frame"
        let expect = item.field("expect")?.string
        do {
            let value = try framed ? decodeFramed(schema, raw) : decode(schema, raw)
            if expect == "reject" {
                XCTFail("\(id) accepted")
                return
            }
            if let decoded = item.field("decoded") {
                if framed {
                    let hashText: String
                    if case .number(let text)? = decoded.field("hash") {
                        hashText = text
                    } else {
                        hashText = ""
                    }
                    XCTAssertEqual(typeHash(schema), UInt64(hashText), id)
                    let kept = (decoded.objectPairs ?? []).filter { $0.0 == "id" || $0.0 == "batch" }
                    XCTAssertTrue(matches(value, .object(kept)), "\(id) value")
                } else {
                    XCTAssertTrue(matches(value, decoded), "\(id) value")
                }
            }
            let again = try framed ? encodeFramed(schema, value) : encode(schema, value)
            if again != raw {
                XCTFail("\(id) re-encode \(again.count) != \(raw.count)")
            }
        } catch let error as KilnError {
            XCTAssertEqual(expect, "reject", id)
            XCTAssertEqual(error.code.rawValue, item.field("error")?.string, id)
        }
    }

    private func casesURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("testdata/kiln-v2-cases.json")
    }
}

private func boxedList(_ value: Value) -> [Value]? {
    switch value {
    case .list(let items):
        return items
    case .f32s(let raw):
        return raw.map { .f32($0) }
    case .f64s(let raw):
        return raw.map { .f64($0) }
    case .i32s(let raw):
        return raw.map { .int(Int64($0)) }
    case .i64s(let raw):
        return raw.map { .int($0) }
    default:
        return nil
    }
}

func matches(_ value: Value, _ want: JSON) -> Bool {
    switch want {
    case .object:
        if case .tensors(let directory) = value { return matchDirectory(directory, want) }
        guard case .object(let map) = value, let pairs = want.objectPairs else { return false }
        for (key, item) in pairs {
            guard let got = map[key], matches(got, item) else { return false }
        }
        return true
    case .array(let items):
        guard let got = boxedList(value), got.count == items.count else { return false }
        return zip(got, items).allSatisfy(matches)
    case .string(let text):
        if case .string(let got) = value { return got == text }
        return false
    case .bool(let flag):
        if case .bool(let got) = value { return got == flag }
        return false
    case .null:
        if case .null = value { return true }
        return false
    case .number(let text):
        return numberEquals(value, text)
    }
}

private func matchDirectory(_ directory: TensorDirectory, _ want: JSON) -> Bool {
    guard let pairs = want.objectPairs else { return false }
    for (key, item) in pairs {
        switch key {
        case "version":
            guard case .number(let text) = item, Int(text) == directory.version else { return false }
        case "block_length":
            guard case .number(let text) = item, Int(text) == directory.blockLength else { return false }
        case "flags":
            guard let items = item.arrayItems else { return false }
            if items.compactMap(\.string) != directory.flags { return false }
        case "tensors":
            guard let items = item.arrayItems, items.count == directory.tensors.count else { return false }
            for (tensor, wantTensor) in zip(directory.tensors, items) {
                if !matchTensor(tensor, wantTensor) { return false }
            }
        default:
            return false
        }
    }
    return true
}

private func matchTensor(_ tensor: Tensor, _ want: JSON) -> Bool {
    guard let pairs = want.objectPairs else { return false }
    for (key, item) in pairs {
        switch key {
        case "name":
            if case .null = item {
                if tensor.name != nil { return false }
            } else if case .string(let text) = item, tensor.name == text {
            } else {
                return false
            }
        case "dtype":
            if case .string(let text) = item {
                if tensor.dtypeName != text { return false }
            } else if case .number(let text) = item, tensor.dtypeName == nil, UInt16(text) == tensor.dtype {
            } else {
                return false
            }
        case "shape":
            guard let items = item.arrayItems, items.count == tensor.shape.count else { return false }
            for (got, wantDim) in zip(tensor.shape, items) {
                guard case .number(let text) = wantDim, UInt64(text) == got else { return false }
            }
        case "quant_scheme":
            guard case .number(let text) = item, UInt16(text) == tensor.quantScheme else { return false }
        case "data_hex":
            guard case .string(let text) = item, hexEncode(tensor.data) == text else { return false }
        default:
            return false
        }
    }
    return true
}

private func numberEquals(_ value: Value, _ text: String) -> Bool {
    if text.contains(".") || text.contains("e") || text.contains("E") {
        guard let want = Double(text) else { return false }
        switch value {
        case .f32(let number):
            return number.isNaN ? want.isNaN : Double(number) == want
        case .f64(let number):
            return number.isNaN ? want.isNaN : number == want
        case .int(let number):
            return Double(number) == want
        case .uint(let number):
            return Double(number) == want
        default:
            return false
        }
    }
    if let want = Int64(text), case .int(let got) = value { return got == want }
    if let want = UInt64(text) {
        if case .uint(let got) = value { return got == want }
        if case .int(let got) = value, got >= 0 { return UInt64(got) == want }
    }
    return false
}

func hexDecode(_ text: String) -> [UInt8] {
    var out: [UInt8] = []
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        out.append(UInt8(text[index..<next], radix: 16) ?? 0)
        index = next
    }
    return out
}

func hexEncode(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}
