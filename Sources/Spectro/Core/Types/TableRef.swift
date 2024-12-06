public struct TableRef<S: Schema> {
    let schema: S.Type
    let alias: String

    func column(_ name: String) -> String {
        "\(alias).\(name)"
    }
}