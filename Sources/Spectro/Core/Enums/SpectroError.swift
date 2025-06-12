import Foundation

/// Comprehensive error system for Spectro ORM
public enum SpectroError: Error, Sendable {
    // MARK: - Connection Errors
    case connectionFailed(underlying: Error)
    case connectionPoolExhausted
    case connectionTimeout
    case invalidConnectionConfiguration(String)
    
    // MARK: - Query Errors
    case invalidQuery(String)
    case invalidSql(sql: String, error: Error)
    case invalidParameter(name: String, value: Any?, reason: String? = nil)
    case queryExecutionFailed(sql: String, error: Error)
    case resultDecodingFailed(column: String, expectedType: String)
    
    // MARK: - Data Errors
    case notFound(schema: String, id: UUID)
    case unexpectedResultCount(expected: Int, actual: Int)
    case invalidData(field: String, value: Any?, reason: String)
    case validationError(field: String, errors: [String])
    case constraintViolation(String)
    case databaseError(reason: String)
    
    // MARK: - Schema Errors
    case invalidSchema(reason: String)
    case invalidField(schema: String, field: String)
    case relationshipError(from: String, to: String, reason: String)
    case relationshipNotFound(relationship: String, schema: String)
    case missingRequiredField(String)
    
    // MARK: - Transaction Errors
    case transactionFailed(underlying: Error)
    case transactionAlreadyStarted
    case noActiveTransaction
    case transactionDeadlock
    
    // MARK: - Migration Errors
    case migrationFailed(version: String, error: Error)
    case migrationNotFound(version: String)
    case invalidMigrationFile(path: String, reason: String)
    case migrationVersionConflict(String)
    
    // MARK: - Configuration Errors
    case configurationError(String)
    case missingEnvironmentVariable(String)
    case invalidCredentials
    
    // MARK: - Internal Errors
    case internalError(String)
    case notImplemented(String)
}

extension SpectroError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let error):
            return "Database connection failed: \(error.localizedDescription)"
        case .connectionPoolExhausted:
            return "Database connection pool exhausted"
        case .connectionTimeout:
            return "Database connection timeout"
        case .invalidConnectionConfiguration(let message):
            return "Invalid connection configuration: \(message)"
            
        case .invalidQuery(let message):
            return "Invalid query: \(message)"
        case .invalidSql(let sql, let error):
            return "SQL execution failed for '\(sql)': \(error.localizedDescription)"
        case .invalidParameter(let name, let value, let reason):
            let baseMessage = "Invalid parameter '\(name)' with value '\(String(describing: value))'"
            if let reason = reason {
                return "\(baseMessage): \(reason)"
            }
            return baseMessage
        case .queryExecutionFailed(let sql, let error):
            return "Query execution failed for '\(sql)': \(error.localizedDescription)"
        case .resultDecodingFailed(let column, let type):
            return "Failed to decode column '\(column)' as \(type)"
            
        case .notFound(let schema, let id):
            return "\(schema) with ID '\(id)' not found"
        case .unexpectedResultCount(let expected, let actual):
            return "Expected \(expected) results but got \(actual)"
        case .invalidData(let field, let value, let reason):
            return "Invalid data for field '\(field)' with value '\(String(describing: value))': \(reason)"
        case .validationError(let field, let errors):
            return "Validation failed for field '\(field)': \(errors.joined(separator: ", "))"
        case .constraintViolation(let message):
            return "Database constraint violation: \(message)"
        case .databaseError(let reason):
            return "Database error: \(reason)"
            
        case .invalidSchema(let reason):
            return "Invalid schema: \(reason)"
        case .invalidField(let schema, let field):
            return "Invalid field '\(field)' in schema '\(schema)'"
        case .relationshipError(let from, let to, let reason):
            return "Relationship error from '\(from)' to '\(to)': \(reason)"
        case .relationshipNotFound(let relationship, let schema):
            return "Relationship '\(relationship)' not found on schema '\(schema)'"
        case .missingRequiredField(let field):
            return "Required field '\(field)' missing"
            
        case .transactionFailed(let error):
            return "Transaction failed: \(error.localizedDescription)"
        case .transactionAlreadyStarted:
            return "Transaction already started"
        case .noActiveTransaction:
            return "No active transaction"
        case .transactionDeadlock:
            return "Transaction deadlock detected"
            
        case .migrationFailed(let version, let error):
            return "Migration '\(version)' failed: \(error.localizedDescription)"
        case .migrationNotFound(let version):
            return "Migration '\(version)' not found"
        case .invalidMigrationFile(let path, let reason):
            return "Invalid migration file at '\(path)': \(reason)"
        case .migrationVersionConflict(let message):
            return "Migration version conflict: \(message)"
            
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .missingEnvironmentVariable(let name):
            return "Missing required environment variable: \(name)"
        case .invalidCredentials:
            return "Invalid database credentials"
            
        case .internalError(let message):
            return "Internal error: \(message)"
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .connectionFailed, .connectionTimeout:
            return "Check database server status and connection parameters"
        case .connectionPoolExhausted:
            return "Increase connection pool size or reduce concurrent operations"
        case .invalidConnectionConfiguration:
            return "Verify hostname, port, username, password, and database name"
        case .notFound:
            return "Verify the ID exists in the database"
        case .validationError:
            return "Check field requirements and constraints"
        case .transactionDeadlock:
            return "Retry the operation after a brief delay"
        case .missingEnvironmentVariable(let name):
            return "Set the \(name) environment variable"
        default:
            return nil
        }
    }
}

extension SpectroError: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .invalidSql(let sql, let error):
            return "SpectroError.invalidSql(sql: \"\(sql)\", error: \(error))"
        case .queryExecutionFailed(let sql, let error):
            return "SpectroError.queryExecutionFailed(sql: \"\(sql)\", error: \(error))"
        default:
            return "SpectroError.\(self)"
        }
    }
}