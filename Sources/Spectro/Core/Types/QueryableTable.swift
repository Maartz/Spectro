import Foundation

public struct QueryableTable<S: Schema> {
    let alias: String

    @dynamicMemberLookup
    struct Fields {
        let table: QueryableTable

        subscript(dynamicMemberLookup field: String) -> SelectableField {
            SelectableField(table: table.alias, name: field)
        }
    }

    var fields: Fields { Fields(table: self )}
}