import Foundation
import PostgresNIO

/// Protocol for types that can be built from database row values
public protocol TupleBuildable {
    static func build(from values: [Any?]) -> Self
}

/// Tuple mapper that handles converting database rows to Swift tuples
public struct TupleMapper {
    
    /// Map a database row to a tuple type
    public static func mapRow<T: TupleBuildable>(
        _ row: PostgresRow,
        selectedFields: [String],
        to type: T.Type
    ) throws -> T {
        let randomAccess = row.makeRandomAccess()
        var values: [Any?] = []
        
        for fieldName in selectedFields {
            let dbValue = randomAccess[data: fieldName]
            // Check if the value exists - PostgresData always exists but may be null
            // For now, we'll try to extract and if it fails, treat as null
            let extractedValue = extractValue(from: dbValue)
            if extractedValue == nil {
                values.append(nil)
                continue
            }
            
            values.append(extractedValue)
        }
        
        return T.build(from: values)
    }
    
    private static func extractValue(from postgresData: PostgresData) -> Any? {
        if let string = postgresData.string {
            return string
        } else if let int = postgresData.int {
            return int
        } else if let bool = postgresData.bool {
            return bool
        } else if let uuid = postgresData.uuid {
            return uuid
        } else if let date = postgresData.date {
            return date
        } else if let double = postgresData.double {
            return double
        } else if let float = postgresData.float {
            return float
        } else if let bytes = postgresData.bytes {
            return Data(bytes)
        } else {
            return nil
        }
    }
}

// MARK: - Common Tuple Type Extensions

/// Make standard tuples conform to TupleBuildable
extension String: TupleBuildable {
    public static func build(from values: [Any?]) -> String {
        return values.first as? String ?? ""
    }
}

extension Int: TupleBuildable {
    public static func build(from values: [Any?]) -> Int {
        return values.first as? Int ?? 0
    }
}

extension UUID: TupleBuildable {
    public static func build(from values: [Any?]) -> UUID {
        return values.first as? UUID ?? UUID()
    }
}

extension Bool: TupleBuildable {
    public static func build(from values: [Any?]) -> Bool {
        return values.first as? Bool ?? false
    }
}

extension Date: TupleBuildable {
    public static func build(from values: [Any?]) -> Date {
        return values.first as? Date ?? Date()
    }
}

extension Double: TupleBuildable {
    public static func build(from values: [Any?]) -> Double {
        return values.first as? Double ?? 0.0
    }
}

// MARK: - Tuple2 through Tuple6 for common use cases

/// Two-element tuple
public struct Tuple2<T1, T2>: TupleBuildable, Sendable where T1: Sendable, T2: Sendable {
    public let _0: T1
    public let _1: T2
    
    public init(_ _0: T1, _ _1: T2) {
        self._0 = _0
        self._1 = _1
    }
    
    public static func build(from values: [Any?]) -> Tuple2<T1, T2> {
        let v0 = values.count > 0 ? values[0] as? T1 : nil
        let v1 = values.count > 1 ? values[1] as? T2 : nil
        
        return Tuple2(
            v0 ?? defaultValue(for: T1.self),
            v1 ?? defaultValue(for: T2.self)
        )
    }
}

/// Three-element tuple
public struct Tuple3<T1, T2, T3>: TupleBuildable, Sendable where T1: Sendable, T2: Sendable, T3: Sendable {
    public let _0: T1
    public let _1: T2
    public let _2: T3
    
    public init(_ _0: T1, _ _1: T2, _ _2: T3) {
        self._0 = _0
        self._1 = _1
        self._2 = _2
    }
    
    public static func build(from values: [Any?]) -> Tuple3<T1, T2, T3> {
        let v0 = values.count > 0 ? values[0] as? T1 : nil
        let v1 = values.count > 1 ? values[1] as? T2 : nil
        let v2 = values.count > 2 ? values[2] as? T3 : nil
        
        return Tuple3(
            v0 ?? defaultValue(for: T1.self),
            v1 ?? defaultValue(for: T2.self),
            v2 ?? defaultValue(for: T3.self)
        )
    }
}

/// Four-element tuple
public struct Tuple4<T1, T2, T3, T4>: TupleBuildable, Sendable where T1: Sendable, T2: Sendable, T3: Sendable, T4: Sendable {
    public let _0: T1
    public let _1: T2
    public let _2: T3
    public let _3: T4
    
    public init(_ _0: T1, _ _1: T2, _ _2: T3, _ _3: T4) {
        self._0 = _0
        self._1 = _1
        self._2 = _2
        self._3 = _3
    }
    
    public static func build(from values: [Any?]) -> Tuple4<T1, T2, T3, T4> {
        let v0 = values.count > 0 ? values[0] as? T1 : nil
        let v1 = values.count > 1 ? values[1] as? T2 : nil
        let v2 = values.count > 2 ? values[2] as? T3 : nil
        let v3 = values.count > 3 ? values[3] as? T4 : nil
        
        return Tuple4(
            v0 ?? defaultValue(for: T1.self),
            v1 ?? defaultValue(for: T2.self),
            v2 ?? defaultValue(for: T3.self),
            v3 ?? defaultValue(for: T4.self)
        )
    }
}

// MARK: - Helper Functions

private func defaultValue<T>(for type: T.Type) -> T {
    switch type {
    case is String.Type:
        return "" as! T
    case is Int.Type:
        return 0 as! T
    case is Bool.Type:
        return false as! T
    case is UUID.Type:
        return UUID() as! T
    case is Date.Type:
        return Date() as! T
    case is Double.Type:
        return 0.0 as! T
    case is Float.Type:
        return Float(0.0) as! T
    default:
        // For optional types or other complex types
        // This is a fallback - in production we'd need more sophisticated handling
        fatalError("Cannot create default value for type \(type). Consider making the field optional.")
    }
}