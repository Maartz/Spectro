import Foundation
import XCTest

@testable import Spectro
@testable import SpectroCore

final class SQLStatementParserTests: XCTestCase {
    func testSimpleSQLParsing() throws {
        let sql = """
        CREATE TABLE users (id SERIAL);
        INSERT INTO users DEFAULT VALUES;
        """
        
        let statements = try SQLStatementParser.parse(sql)
        XCTAssertEqual(statements.count, 2)
        XCTAssertTrue(statements[0].contains("CREATE TABLE"))
        XCTAssertTrue(statements[1].contains("INSERT INTO"))
    }
    
    func testComplexFunctionParsing() throws {
        let sql = """
        CREATE OR REPLACE FUNCTION update_timestamp()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $$ language 'plpgsql';
        """
        
        let statements = try SQLStatementParser.parse(sql)
        XCTAssertEqual(statements.count, 1)
        XCTAssertTrue(statements[0].contains("CREATE OR REPLACE FUNCTION"))
        XCTAssertTrue(statements[0].contains("RETURN NEW;"))
    }
    
    func testMixedStatements() throws {
        let sql = """
        CREATE TABLE test (id SERIAL);
        CREATE OR REPLACE FUNCTION test_func()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $$ language 'plpgsql';
        CREATE TRIGGER update_trigger BEFORE UPDATE ON test FOR EACH ROW EXECUTE FUNCTION test_func();
        """
        
        let statements = try SQLStatementParser.parse(sql)
        XCTAssertEqual(statements.count, 3)
    }
}
