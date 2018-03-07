import XCTest
@testable import thrift_swift_nio

class thrift_swift_nioTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(thrift_swift_nio().text, "Hello, World!")
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
