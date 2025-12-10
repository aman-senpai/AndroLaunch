//
//  ShellCommandManager.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 12/10/25.
//

import Foundation
import Combine

final class ShellCommandManager: ObservableObject {
    static let shared = ShellCommandManager()
    
    private let userDefaults = UserDefaults.standard
    private let globalKey = "shell_commands_global"
    
    // Publish changes so ViewModel can react
    let objectWillChange = PassthroughSubject<Void, Never>()
    
    private init() {}
    
    func getAllCommands() -> [ShellCommand] {
        guard let data = userDefaults.data(forKey: globalKey) else { return [] }
        do {
            let commands = try JSONDecoder().decode([ShellCommand].self, from: data)
            return commands
        } catch {
            print("Error decoding shell commands: \(error)")
            return []
        }
    }
    
    func saveCommand(_ command: ShellCommand) {
        var commands = getAllCommands()
        
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
        } else {
            commands.append(command)
        }
        
        save(commands)
    }
    
    func deleteCommand(id: UUID) {
        var commands = getAllCommands()
        commands.removeAll { $0.id == id }
        save(commands)
    }
    
    private func save(_ commands: [ShellCommand]) {
        do {
            let data = try JSONEncoder().encode(commands)
            userDefaults.set(data, forKey: globalKey)
            objectWillChange.send()
        } catch {
            print("Error encoding shell commands: \(error)")
        }
    }
}
