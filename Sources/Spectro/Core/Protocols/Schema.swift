public protocol Schema: Sendable {
    static var tableName: String { get }
    init()
}
