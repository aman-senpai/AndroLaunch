//
//  ShellCommandWrapper.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 12/10/25.
//

import Foundation

class ShellCommandWrapper {
    let command: ShellCommand
    let deviceID: String
    
    init(command: ShellCommand, deviceID: String) {
        self.command = command
        self.deviceID = deviceID
    }
}
