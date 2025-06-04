import Foundation

extension Schema {
  public typealias Model = SchemaModel<Self>
}

public struct SchemaModel<S: Schema>: Identifiable {
  public let id: UUID
  public let data: [String: Any]

  public init(from row: DataRow) throws {
    let idValue = row.values["id"]
    
    let id: UUID
    if let uuidValue = idValue as? UUID {
      id = uuidValue
    } else if let stringValue = idValue as? String,
              let parsedUuid = UUID(uuidString: stringValue) {
      id = parsedUuid
    } else {
      throw RepositoryError.invalidData("Missing or invalid ID")
    }

    self.id = id
    self.data = row.values
  }

  public subscript(dynamicMember keyPath: String) -> Any? {
    data[keyPath]
  }
}
