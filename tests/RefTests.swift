import Foundation
import XCTest

@testable import Kiln

final class RefTests: XCTestCase {
    func testReferenceBytes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let ref = root.appendingPathComponent("testdata/reference").path
        let script = """
        import sys, struct
        sys.path.insert(0, sys.argv[1])
        import kiln_ref
        point = {"x": 9, "y": -4}
        message = {"f_bool": True, "f_int32": -2, "f_int64": 99, "f_float64": 1.5,
            "f_string": "hello", "f_bool_2": False, "f_int32_2": 7, "f_string_2": "world"}
        nan = struct.unpack("<d", bytes.fromhex("010000000000f87f"))[0]
        rows = [
            ("point", kiln_ref.encode(kiln_ref.POINT, point)),
            ("pointf", kiln_ref.encode_framed(kiln_ref.POINT, point)),
            ("message", kiln_ref.encode(kiln_ref.MESSAGE, message)),
            ("messagef", kiln_ref.encode_framed(kiln_ref.MESSAGE, message)),
            ("list", kiln_ref.encode(("list", ("i32",)), [1, -2, 3])),
            ("dict", kiln_ref.encode(("dict", ("i32",)), {"b": 2, "a": 1})),
            ("opt0", kiln_ref.encode(("opt", ("str",)), None)),
            ("opt1", kiln_ref.encode(("opt", ("str",)), "z")),
            ("u8", kiln_ref.encode(("list", ("u8",)), bytes([1, 2, 255]))),
            ("i8", kiln_ref.encode(("list", ("i8",)), [-1, 2])),
            ("f64", kiln_ref.encode(("list", ("f64",)), [-0.0, nan])),
            ("bytes", kiln_ref.encode(("bytes",), b"ab")),
        ]
        for name, raw in rows:
            print(name)
            print(raw.hex())
        """
        let output = try runPython(script, arguments: [ref])
        var hexes: [String: [UInt8]] = [:]
        var name = ""
        var expectName = true
        for line in output.split(separator: "\n") where !line.isEmpty {
            if expectName {
                name = String(line)
                expectName = false
            } else {
                hexes[name] = hexDecode(String(line))
                expectName = true
            }
        }
        let point = Schema.structure([("x", .i32), ("y", .i32)])
        let pointValue = Value.object(["x": .int(9), "y": .int(-4)])
        XCTAssertEqual(try encode(point, pointValue), hexes["point"])
        XCTAssertEqual(try decode(point, hexes["point"] ?? []), pointValue)
        XCTAssertEqual(try encodeFramed(point, pointValue), hexes["pointf"])
        XCTAssertEqual(try decodeFramed(point, hexes["pointf"] ?? []), pointValue)

        let message = Schema.structure([
            ("f_bool", .bool), ("f_int32", .i32), ("f_int64", .i64), ("f_float64", .f64),
            ("f_string", .str), ("f_bool_2", .bool), ("f_int32_2", .i32), ("f_string_2", .str),
        ])
        let messageValue = Value.object([
            "f_bool": .bool(true), "f_int32": .int(-2), "f_int64": .int(99), "f_float64": .f64(1.5),
            "f_string": .string("hello"), "f_bool_2": .bool(false), "f_int32_2": .int(7),
            "f_string_2": .string("world"),
        ])
        XCTAssertEqual(try encode(message, messageValue), hexes["message"])
        XCTAssertEqual(try decode(message, hexes["message"] ?? []), messageValue)
        XCTAssertEqual(try encodeFramed(message, messageValue), hexes["messagef"])
        XCTAssertEqual(try decodeFramed(message, hexes["messagef"] ?? []), messageValue)

        let list = try decode(.list(.i32), hexes["list"] ?? [])
        XCTAssertEqual(list, .list([.int(1), .int(-2), .int(3)]))
        XCTAssertEqual(try encode(.list(.i32), list), hexes["list"])
        let dict = try decode(.dict(.i32), hexes["dict"] ?? [])
        XCTAssertEqual(dict, .object(["a": .int(1), "b": .int(2)]))
        XCTAssertEqual(try encode(.dict(.i32), .object(["b": .int(2), "a": .int(1)])), hexes["dict"])
        XCTAssertEqual(try decode(.opt(.str), hexes["opt0"] ?? []), .null)
        XCTAssertEqual(try decode(.opt(.str), hexes["opt1"] ?? []), .string("z"))
        XCTAssertEqual(try encode(.opt(.str), .null), hexes["opt0"])
        XCTAssertEqual(try encode(.opt(.str), .string("z")), hexes["opt1"])
        XCTAssertEqual(try decode(.list(.u8), hexes["u8"] ?? []), .bytes([1, 2, 255]))
        XCTAssertEqual(try encode(.list(.u8), .bytes([1, 2, 255])), hexes["u8"])
        XCTAssertEqual(try decode(.list(.i8), hexes["i8"] ?? []), .list([.int(-1), .int(2)]))
        XCTAssertEqual(try encode(.bytes, .bytes(Array("ab".utf8))), hexes["bytes"])

        let floats = try decode(.list(.f64), hexes["f64"] ?? [])
        guard case .list(let items) = floats, items.count == 2,
            case .f64(let first) = items[0], case .f64(let second) = items[1] else {
            return XCTFail("f64 list")
        }
        XCTAssertTrue(first.sign == .minus && first == 0)
        XCTAssertTrue(second.isNaN)
        XCTAssertEqual(second.bitPattern, 0x7FF8_0000_0000_0001)
        XCTAssertEqual(try encode(.list(.f64), floats), hexes["f64"])
    }

    func testTrustedSkipsUTF8ButNotPastTheBuffer() throws {
        let bad: [UInt8] = [1, 0, 0, 0, 0xFF]
        XCTAssertThrowsError(try decode(.str, bad)) { error in
            XCTAssertEqual((error as? KilnError)?.code, .UTF8)
        }
        _ = try decode(.str, bad, trusted: true)
        let short: [UInt8] = [5, 0, 0, 0]
        XCTAssertThrowsError(try decode(.str, short, trusted: true)) { error in
            XCTAssertEqual((error as? KilnError)?.code, .EOF)
        }
    }
}

private func runPython(_ source: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-c", source] + arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    if process.terminationStatus != 0 {
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTFail(err)
    }
    return text
}
