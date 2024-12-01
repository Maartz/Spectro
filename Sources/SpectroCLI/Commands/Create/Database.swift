import ArgumentParser

struct Database: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "database",
        subcommands: [
            Create.self,
            Drop.self,
        ]
    )
}
