public struct SelectableField {
    let table: String
    let name: String

    var qualified: String {
        "\(table).\(name)"
    }

    func `as`(_ alias: String) -> String {
        "\(qualified) AS \(alias)"
    }
}