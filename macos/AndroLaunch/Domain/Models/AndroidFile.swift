//
//  AndroidFile.swift
//  AndroLaunch
//
//  Created by Aman Raj on 12/4/26.
//

import Foundation

struct AndroidFile: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let size: Int64
    let modificationDate: String?
    let isDirectory: Bool
    let permissions: String
    
    var extensionName: String {
        return (name as NSString).pathExtension.lowercased()
    }
    
    var formattedSize: String {
        if isDirectory { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    init(name: String, path: String, size: Int64, modificationDate: String?, isDirectory: Bool, permissions: String) {
        self.name = name
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.permissions = permissions
    }
}
