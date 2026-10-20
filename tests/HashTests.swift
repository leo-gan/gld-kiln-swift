import Foundation
import XCTest

@testable import Kiln

final class HashTests: XCTestCase {
    func testTensorsTokenHash() {
        let schema = Schema.structure([("id", .i64), ("batch", .tensors)])
        XCTAssertEqual(typeHash(schema), 0xE58A_ADC7_552F_0D82)
    }

    func testLoadsCases() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("testdata/kiln-v2-cases.json")
        let data = try Data(contentsOf: url)
        let json = try parseJSON(data)
        guard case .object(let pairs) = json else {
            XCTFail("root")
            return
        }
        let map = Dictionary(uniqueKeysWithValues: pairs)
        guard case .array(let cases) = map["cases"] else {
            XCTFail("cases")
            return
        }
        XCTAssertEqual(cases.count, 46)
    }
}
