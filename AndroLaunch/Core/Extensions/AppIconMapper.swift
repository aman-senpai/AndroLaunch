import Foundation

/// A utility class for mapping app names and package IDs to appropriate SF Symbols
struct AppIconMapper {
    // MARK: - Icon Categories
    private static let googleApps: [String: String] = [
        "keep": "note.text",
        "meet": "video.fill",
        "drive": "externaldrive.fill",
        "docs": "doc.fill",
        "sheets": "tablecells.fill",
        "slides": "rectangle.stack.fill",
        "maps": "map.fill",
        "gmail": "envelope.fill",
        "calendar": "calendar",
        "photos": "photo.fill",
        "youtube": "play.rectangle.fill",
        "play": "play.circle.fill",
        "chrome": "globe",
        "translate": "character.bubble.fill",
        "duo": "video.fill",
        "hangouts": "bubble.left.fill",
        "classroom": "book.fill",
        "pay": "creditcard.fill",
        "authenticator": "key.fill",
        "assistant": "waveform",
        "lens": "camera.viewfinder",
        "news": "newspaper.fill",
        "podcasts": "headphones",
        "books": "book.closed.fill",
        "tasks": "checklist",
        "contacts": "person.2.fill",
        "messages": "message.fill",
        "phone": "phone.fill",
        "files": "folder.fill",
        "clock": "clock.fill",
        "calculator": "function",
        "browser": "globe",
        "default": "g.circle.fill"
    ]
    
    private static let socialMedia: [String: String] = [
        "facebook": "bubble.left.and.bubble.right.fill",
        "fb": "bubble.left.and.bubble.right.fill",
        "twitter": "bird.fill",
        "x": "bird.fill",
        "instagram": "camera.fill",
        "whatsapp": "message.fill",
        "telegram": "paperplane.fill",
        "discord": "bubble.left.fill",
        "linkedin": "person.2.fill",
        "reddit": "circle.grid.2x2.fill",
        "pinterest": "pin.fill",
        "tiktok": "music.note",
        "snapchat": "camera.fill",
        "wechat": "message.fill",
        "line": "bubble.left.fill",
        "viber": "phone.fill",
        "skype": "video.fill",
        "zoom": "video.fill",
        "teams": "person.3.fill",
        "slack": "bubble.left.fill",
        "default": "bubble.left.and.bubble.right.fill"
    ]
    
    private static let messaging: [String: String] = [
        "message": "message.fill",
        "sms": "message.fill",
        "chat": "bubble.left.fill",
        "messenger": "bubble.left.fill",
        "mail": "envelope.fill",
        "email": "envelope.fill",
        "call": "phone.fill",
        "phone": "phone.fill",
        "default": "message.fill"
    ]
    
    private static let media: [String: String] = [
        "camera": "camera.fill",
        "photo": "photo.fill",
        "gallery": "photo.fill",
        "music": "music.note",
        "spotify": "music.note",
        "player": "play.fill",
        "video": "play.fill",
        "netflix": "play.tv.fill",
        "prime": "play.square.fill",
        "disney": "play.tv.fill",
        "hbo": "play.tv.fill",
        "youtube": "play.rectangle.fill",
        "twitch": "play.tv.fill",
        "default": "play.fill"
    ]
    
    private static let productivity: [String: String] = [
        "browser": "globe",
        "firefox": "globe",
        "opera": "globe",
        "edge": "globe",
        "safari": "globe",
        "settings": "gear",
        "system": "gear",
        "calculator": "function",
        "clock": "clock.fill",
        "alarm": "alarm.fill",
        "notes": "note.text",
        "notepad": "note.text",
        "calendar": "calendar",
        "files": "folder.fill",
        "file": "folder.fill",
        "download": "arrow.down.circle.fill",
        "upload": "arrow.up.circle.fill",
        "share": "square.and.arrow.up.fill",
        "print": "printer.fill",
        "scan": "doc.viewfinder.fill",
        "default": "app.fill"
    ]
    
    private static let games: [String: String] = [
        "game": "gamecontroller.fill",
        "play": "gamecontroller.fill",
        "minecraft": "cube.fill",
        "roblox": "cube.fill",
        "fortnite": "gamecontroller.fill",
        "pubg": "gamecontroller.fill",
        "cod": "gamecontroller.fill",
        "call of duty": "gamecontroller.fill",
        "battlefield": "gamecontroller.fill",
        "fifa": "sportscourt.fill",
        "pes": "sportscourt.fill",
        "asphalt": "car.fill",
        "nfs": "car.fill",
        "need for speed": "car.fill",
        "default": "gamecontroller.fill"
    ]
    
    private static let shopping: [String: String] = [
        "shop": "cart.fill",
        "store": "cart.fill",
        "amazon": "bag.fill",
        "pay": "creditcard.fill",
        "bank": "creditcard.fill",
        "wallet": "creditcard.fill",
        "default": "cart.fill"
    ]
    
    private static let weather: [String: String] = [
        "weather": "cloud.sun.fill",
        "news": "newspaper.fill",
        "default": "cloud.sun.fill"
    ]
    
    private static let system: [String: String] = [
        "settings": "gear",
        "launcher": "square.grid.2x2.fill",
        "contacts": "person.fill",
        "phone": "phone.fill",
        "messages": "message.fill",
        "camera": "camera.fill",
        "gallery": "photo.fill",
        "files": "folder.fill",
        "clock": "clock.fill",
        "calculator": "function",
        "calendar": "calendar",
        "browser": "globe",
        "default": "gear"
    ]
    
    // MARK: - Icon Mapping Logic
    static func getIconName(for app: AndroidApp) -> String {
        let name = app.name.lowercased()
        let packageId = app.id.lowercased()
        
        // Check for exact matches first (these should take precedence)
        let exactMatches: [(String, String)] = [
            // Games
            ("call of duty", "gamecontroller.fill"),
            ("cod", "gamecontroller.fill"),
            ("need for speed", "car.fill"),
            ("nfs", "car.fill"),
            // Add more exact matches here
        ]
        
        for (exactName, icon) in exactMatches {
            if name == exactName {
                return icon
            }
        }
        
        // Check Google Apps first
        if packageId.contains("com.google.android") {
            for (key, icon) in googleApps {
                if name.contains(key) {
                    return icon
                }
            }
            return googleApps["default"] ?? "app.fill"
        }
        
        // Check System Apps
        if packageId.contains("com.android") {
            for (key, icon) in system {
                if name.contains(key) {
                    return icon
                }
            }
            return system["default"] ?? "app.fill"
        }
        
        // Check other categories in priority order
        let categories: [[String: String]] = [
            games,      // Check games before messaging to avoid "call" conflict
            socialMedia,
            messaging,
            media,
            productivity,
            shopping,
            weather
        ]
        
        for category in categories {
            for (key, icon) in category {
                if name.contains(key) {
                    return icon
                }
            }
        }
        
        // Default icon
        return "app.fill"
    }
} 