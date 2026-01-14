import Foundation

extension String {
    var nilIfEmpty: String? {
        return isEmpty ? nil : self
    }
    var nilIfBlank: String? {
        return trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}