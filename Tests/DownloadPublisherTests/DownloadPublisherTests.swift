import XCTest
@testable import DownloadPublisher

final class DownloadPublisherTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(DownloadPublisher().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
