import ISSInternalTestSupport
import XCTest

final class EventSerializationTests: XCTestCase {
    func testFixedPointBoundaries() { XCTAssertEqual(iss_test_fixed_point(), 0) }
    func testPayloadLayoutAndReplacement() { XCTAssertEqual(iss_test_serialized_payload(), 0) }
    func testMalformedInput() { XCTAssertEqual(iss_test_serialized_validation(), 0) }
    func testSyntheticIdentity() { XCTAssertEqual(iss_test_synthetic_identity(), 0) }
}
