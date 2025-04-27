import Foundation

extension String {
    /// Returns nil if the string is empty, otherwise returns self
    var nilIfEmpty: String? {
        return isEmpty ? nil : self
    }
    
    /// Returns nil if the string is empty or consists only of whitespace characters, otherwise returns self
    var nilIfBlank: String? {
        return trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
} 