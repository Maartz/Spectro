import XCTest
@testable import Spectro

final class SpectroTests: XCTestCase {
    var db: Spectro!
    
    override func setUp() async throws {
        db = try Spectro(
            hostname: "localhost",
            username: "postgres",
            password: "postgres",
            database: "postgres"
        )
    }
    
    override func tearDown() async throws {
        db.shutdown()
    }
    
    func testConnection() async throws {
        let version = try await db.test()
        XCTAssertTrue(version.contains("PostgreSQL"))
    }
}
