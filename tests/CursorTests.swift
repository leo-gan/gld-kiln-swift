import XCTest
@testable import Kiln

final class CursorTests: XCTestCase {
    func testByteWriterAndReaderMatchSchemaEncode() throws {
        let schema = Schema.structure([
            ("f_bool", .bool),
            ("f_int32", .i32),
            ("f_int64", .i64),
            ("f_float64", .f64),
            ("f_string", .str),
            ("values", .list(.f64)),
            ("tags", .list(.str)),
        ])
        let value = Value.object([
            "f_bool": .bool(true),
            "f_int32": .int(-42),
            "f_int64": .int(1_234_567_890_123),
            "f_float64": .f64(-0.0),
            "f_string": .string("hello café 🚀 world-longer-than-15-bytes"),
            "values": .f64s([1.5, -2.25, 0.0]),
            "tags": .list([.string("a"), .string("us-east-1"), .string("long-tag-over-sixteen-chars")]),
        ])
        let refBytes = try encode(schema, value)

        let w = ByteWriter(capacity: 32)
        w.writeBool(true)
        w.writeI32(-42)
        w.writeI64(1_234_567_890_123)
        w.writeF64(-0.0)
        try w.writeString("hello café 🚀 world-longer-than-15-bytes")
        try w.writeF64s([1.5, -2.25, 0.0])
        try w.writeCount(3)
        try w.writeString("a")
        try w.writeString("us-east-1")
        try w.writeString("long-tag-over-sixteen-chars")

        let cursorBytes = w.toArray()
        XCTAssertEqual(cursorBytes, refBytes)

        try cursorBytes.withUnsafeBytes { raw in
            var r = ByteReader(raw)
            XCTAssertEqual(try r.readBool(), true)
            XCTAssertEqual(try r.readI32(), -42)
            XCTAssertEqual(try r.readI64(), 1_234_567_890_123)
            let d = try r.readF64()
            XCTAssertEqual(d.bitPattern, (-0.0 as Double).bitPattern)
            XCTAssertEqual(try r.readString(), "hello café 🚀 world-longer-than-15-bytes")
            XCTAssertEqual(try r.readF64s(), [1.5, -2.25, 0.0])
            let n = try r.readCount(each: 4)
            XCTAssertEqual(n, 3)
            XCTAssertEqual(try r.readString(), "a")
            XCTAssertEqual(try r.readString(), "us-east-1")
            XCTAssertEqual(try r.readString(), "long-tag-over-sixteen-chars")
            try r.finish()
        }
    }

    func testByteReaderRejectsInvalidUtf8TrailingBoolAndHostileCount() throws {
        let badUtf8: [UInt8] = [2, 0, 0, 0, 0xff, 0xfe]
        try badUtf8.withUnsafeBytes { raw in
            var r = ByteReader(raw)
            XCTAssertThrowsError(try r.readString()) { err in
                XCTAssertEqual((err as? KilnError)?.code, .UTF8)
            }
        }

        let trailing: [UInt8] = [1, 0]
        try trailing.withUnsafeBytes { raw in
            var r = ByteReader(raw)
            XCTAssertEqual(try? r.readBool(), true)
            XCTAssertThrowsError(try r.finish()) { err in
                XCTAssertEqual((err as? KilnError)?.code, .TRAILING)
            }
        }

        let badBool: [UInt8] = [2]
        try badBool.withUnsafeBytes { raw in
            var r = ByteReader(raw)
            XCTAssertThrowsError(try r.readBool()) { err in
                XCTAssertEqual((err as? KilnError)?.code, .TYPE)
            }
        }

        let hostileEof: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        try hostileEof.withUnsafeBytes { raw in
            var r = ByteReader(raw)
            XCTAssertThrowsError(try r.readCount(each: 8)) { err in
                XCTAssertEqual((err as? KilnError)?.code, .EOF)
            }
        }

        let hostileLimit: [UInt8] = [0x01, 0x00, 0x00, 0x01]
        try hostileLimit.withUnsafeBytes { raw in
            var r = ByteReader(raw)
            XCTAssertThrowsError(try r.readCount(each: 1)) { err in
                XCTAssertEqual((err as? KilnError)?.code, .LIMIT)
            }
        }
    }
}
