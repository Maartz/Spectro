public enum MigrationStatus: String, CaseIterable {
    case pending
    case completed
    case failed

    public init?(rawValue: String) {
        switch rawValue {
        case "pending": self = .pending
        case "completed": self = .completed
        case "failed": self = .failed
        default: return nil
        }
    }
}
