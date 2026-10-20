import Foundation
import XCTest

@testable import Kiln

final class SchemaTests: XCTestCase {
    func testPointAndMessage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pointText = try String(contentsOf: root.appendingPathComponent("testdata/schema/point.json"), encoding: .utf8)
        let messageText = try String(contentsOf: root.appendingPathComponent("testdata/schema/message.json"), encoding: .utf8)
        let point = try schemaFromJSON(pointText)
        XCTAssertEqual(point.name, "Point")
        guard case .structure(let name, let fields) = point.schema else {
            return XCTFail("point")
        }
        XCTAssertEqual(name, "Point")
        XCTAssertEqual(fields.map(\.name), ["x", "y", "label"])
        XCTAssertEqual(fields[0].schema, .i32)
        XCTAssertEqual(fields[2].schema, .opt(.str))
        XCTAssertEqual(minSize(point.schema), 9)

        let message = try schemaFromJSON(messageText)
        guard case .structure(_, let messageFields) = message.schema else {
            return XCTFail("message")
        }
        XCTAssertEqual(messageFields.map(\.name), [
            "f_bool", "f_int32", "f_int64", "f_float64", "f_string",
            "f_bool_2", "f_int32_2", "f_string_2", "meta",
        ])
        guard case .structure(let metaName, let metaFields) = messageFields[8].schema else {
            return XCTFail("meta")
        }
        XCTAssertEqual(metaName, "Meta")
        XCTAssertEqual(metaFields.map(\.name), ["region", "flag"])
    }

    func testDictAndBadSchema() throws {
        let text = """
        {"title":"Bag","type":"object","additionalProperties":{"type":"integer","format":"uint8"}}
        """
        let bag = try schemaFromJSON(text)
        XCTAssertEqual(bag.schema, .dict(.u8))
        XCTAssertThrowsError(try schemaFromJSON("[]")) { error in
            XCTAssertEqual((error as? KilnError)?.code, .SCHEMA)
        }
    }
}
