import Foundation
import XCTest

@testable import Kiln

final class GeneratedTests: XCTestCase {
    func testPointRoundTrip() throws {
        let point = Point(x: 3, y: -1, label: "n")
        let raw = try point.encode()
        XCTAssertEqual(try Point.decode(raw), point)
        XCTAssertEqual(try point.encodedSize(), raw.count)
        let bare = Point(x: 9, y: -4)
        XCTAssertEqual(try Point.decode(try bare.encode()), bare)
        let text = try String(contentsOf: schemaURL("point.json"), encoding: .utf8)
        XCTAssertEqual(Point.schema(), try schemaFromJSON(text).schema)
    }

    func testMessageRoundTrip() throws {
        let message = Message(
            f_bool: true,
            f_int32: -2,
            f_int64: 99,
            f_float64: 1.5,
            f_string: "hello",
            f_bool_2: false,
            f_int32_2: 7,
            f_string_2: "world",
            meta: Meta(region: "us", flag: true)
        )
        XCTAssertEqual(try Message.decode(try message.encode()), message)
        let text = try String(contentsOf: schemaURL("message.json"), encoding: .utf8)
        XCTAssertEqual(Message.schema(), try schemaFromJSON(text).schema)
    }

    private func schemaURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("testdata/schema/\(name)")
    }
}
