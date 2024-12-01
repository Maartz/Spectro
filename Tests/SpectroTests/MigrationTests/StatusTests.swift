import XCTest

@testable import Spectro
@testable import SpectroCLI
@testable import SpectroCore

final class StatusTests: XCTestCase {
    var sut: Status!
    var mockMigrationManager: MockMigrationManager!
    var outputStrings: [String]!

    override func setUp() {
        super.setUp()
        mockMigrationManager = MockMigrationManager()
        outputStrings = []

        sut = Status(migrationManager: mockMigrationManager)
    }

    override func tearDown() {
        sut = nil
        mockMigrationManager = nil
        outputStrings = nil
        super.tearDown()
    }

    func testStatusDisplaysCorrectInformation() async throws {
        // Given
        let migrations = [
            MigrationFile(
                version: "20240116120000_test1",
                name: "test1",
                filePath: URL(fileURLWithPath: "test1")
            ),
            MigrationFile(
                version: "20240116120001_test2",
                name: "test2",
                filePath: URL(fileURLWithPath: "test2")
            ),
        ]

        let statuses: [String: MigrationStatus] = [
            "20240116120000_test1": .completed,
            "20240116120001_test2": .pending,
        ]

        mockMigrationManager.migrationStatusesResult = (migrations, statuses)

        class TestStatus: Status {
            var capturedOutput: [String] = []
            override func printToStandardOutput(_ string: String) {
                capturedOutput.append(string)
            }
        }

        let testStatus = TestStatus(migrationManager: mockMigrationManager)

        try await testStatus.run()

        XCTAssertTrue(testStatus.capturedOutput.contains { $0.contains("20240116120000_test1") })
        XCTAssertTrue(testStatus.capturedOutput.contains { $0.contains("test1") })
        XCTAssertTrue(testStatus.capturedOutput.contains { $0.contains("Completed") })
        XCTAssertTrue(testStatus.capturedOutput.contains { $0.contains("20240116120001_test2") })
        XCTAssertTrue(testStatus.capturedOutput.contains { $0.contains("test2") })
        XCTAssertTrue(testStatus.capturedOutput.contains { $0.contains("Pending") })
        XCTAssertTrue(testStatus.capturedOutput.contains { $0.contains("Total migrations: 2") })
    }
}

class MockMigrationManager: MigrationManaging {
    var migrationStatusesResult: ([MigrationManager.MigrationFile], [String: MigrationStatus])!

    func getMigrationStatuses() async throws -> (
        [MigrationManager.MigrationFile], [String: MigrationStatus]
    ) {
        return migrationStatusesResult
    }
}

