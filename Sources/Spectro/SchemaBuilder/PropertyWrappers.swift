import Foundation

/// Property wrapper for database columns
@propertyWrapper
public struct Column<T>: Sendable where T: Sendable {
    public var wrappedValue: T
    
    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for ID fields (UUID primary key)
@propertyWrapper
public struct ID: Sendable {
    public var wrappedValue: UUID
    
    public init(wrappedValue: UUID = UUID()) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for timestamp fields
@propertyWrapper
public struct Timestamp: Sendable {
    public var wrappedValue: Date
    
    public init(wrappedValue: Date = Date()) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for foreign key relationships
@propertyWrapper
public struct ForeignKey: Sendable {
    public var wrappedValue: UUID
    
    public init(wrappedValue: UUID = UUID()) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for has-many relationships (virtual - not stored in database)
@propertyWrapper
public struct HasMany<T: Schema>: Sendable {
    public var wrappedValue: [T]?
    
    public init(wrappedValue: [T]? = nil) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for has-one relationships (virtual - not stored in database)
@propertyWrapper
public struct HasOne<T: Schema>: Sendable {
    public var wrappedValue: T?
    
    public init(wrappedValue: T? = nil) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for belongs-to relationships (virtual - uses foreign key)
@propertyWrapper
public struct BelongsTo<T: Schema>: Sendable {
    public var wrappedValue: T?
    
    public init(wrappedValue: T? = nil) {
        self.wrappedValue = wrappedValue
    }
}