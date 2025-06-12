import Foundation

/// Example schema showing how to implement SchemaBuilder for generic mapping
public struct Product: Schema, SchemaBuilder {
    public static let tableName = "products"
    
    @ID public var id: UUID
    @Column public var name: String = ""
    @Column public var description: String = ""
    @Column public var price: Double = 0.0
    @Column public var stock: Int = 0
    @Column public var active: Bool = true
    @Timestamp public var createdAt: Date = Date()
    @Timestamp public var updatedAt: Date = Date()
    
    public init() {}
    
    public init(name: String, description: String, price: Double, stock: Int = 0) {
        self.name = name
        self.description = description
        self.price = price
        self.stock = stock
    }
    
    // MARK: - SchemaBuilder Implementation
    
    public static func build(from values: [String: Any]) -> Product {
        var product = Product()
        
        // Map values to properties
        if let id = values["id"] as? UUID {
            product.id = id
        }
        if let name = values["name"] as? String {
            product.name = name
        }
        if let description = values["description"] as? String {
            product.description = description
        }
        if let price = values["price"] as? Double {
            product.price = price
        }
        if let stock = values["stock"] as? Int {
            product.stock = stock
        }
        if let active = values["active"] as? Bool {
            product.active = active
        }
        if let createdAt = values["createdAt"] as? Date {
            product.createdAt = createdAt
        }
        if let updatedAt = values["updatedAt"] as? Date {
            product.updatedAt = updatedAt
        }
        
        return product
    }
}