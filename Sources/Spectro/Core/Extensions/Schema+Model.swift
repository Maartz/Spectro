import Foundation

extension Schema {
  public typealias Model = SchemaModel<Self>
}

public struct SchemaModel<S: Schema>: Identifiable {
  public let id: UUID
  public let data: [String: Any]

  public init(from row: DataRow) throws {
    guard let idString = row.values["id"],
      let id = UUID(uuidString: idString) else {
      throw RepositoryError.invalidData("Missing or invalid ID")
    }

    self.id = id
    self.data = row.values.mapValues { $0 as Any }
  }

  public subscript(dynamicMember keyPath: String) -> Any? {
    data[keyPath]
  }
}
