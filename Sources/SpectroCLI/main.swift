//
//  main.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser
import Dispatch

@available(macOS 10.15, *)
struct SpectroCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spectro",
        subcommands: [
            Generate.self,
            Database.self,
            Migration.self,
        ]
    )
}

@available(macOS 10.15, *)
func main() {
    let group = DispatchGroup()
    group.enter()
    Task {
        do {
            await SpectroCLI.main()
        } catch {
            print("Error: \(error)")
        }
        group.leave()
    }
    group.wait()
}

main()
