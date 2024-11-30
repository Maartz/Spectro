import Foundation

public enum DatabaseError: LocalizedError {
    case alreadyExists(String)
    case insuficientPrivileges(String)
    case createdFailed(String)
    case doesNotExist(String)
    case dropFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let database):
            return "Database \(database) already exists"
        case .insuficientPrivileges(let user):
            return "User \(user) does not have enough privileges"
        case .createdFailed(let reason):
            return "Failed to create database: \(reason)"
        case .doesNotExist(let database):
            return "Database \(database) does not exist"
        case .dropFailed(let reason):
            return "Failed to drop database: \(reason)"
        }
    }
}
