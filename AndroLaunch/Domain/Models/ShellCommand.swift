//
//  ShellCommand.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 12/10/25.
//

import Foundation

struct ShellCommand: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var isBackground: Bool
    
    init(id: UUID = UUID(), name: String, command: String, isBackground: Bool) {
        self.id = id
        self.name = name
        self.command = command
        self.isBackground = isBackground
    }
}
