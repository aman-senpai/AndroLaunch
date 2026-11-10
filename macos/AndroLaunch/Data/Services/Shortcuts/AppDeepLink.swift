//
//  AppDeepLink.swift
//  AndroLaunch
//
//  The `androlaunch://launch?serial=…&pkg=…` link used by generated desktop
//  shortcuts, Spotlight results and the URL scheme. Foundation-only so the
//  link format can be unit tested without AppKit.
//

import Foundation

/// A parsed request to open one phone app in a Mac window.
struct AppLaunchRequest: Equatable {
    let deviceID: String
    let packageID: String
    let appName: String?
    let mode: AppLaunchMode?

    var displayName: String { appName ?? packageID }
}

enum AppDeepLink {
    static let scheme = "androlaunch"
    static let host = "launch"

    /// Spotlight continuation type. The same string is stored on every
    /// `CSSearchableItem` so `AppDelegate` can route the result back here.
    static let activityType = "com.senpai.AndroLaunch.openApp"

    /// Stable query keys shared by the shortcut builder and the parser.
    enum Key {
        static let serial = "serial"
        static let package = "pkg"
        static let name = "name"
        static let mode = "mode"
    }

    /// Builds the canonical link. Returns `nil` only when the identifiers are
    /// empty, which would produce a shortcut that can never launch anything.
    static func makeURL(
        deviceID: String,
        packageID: String,
        appName: String? = nil,
        mode: AppLaunchMode? = nil
    ) -> URL? {
        let serial = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let package = packageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serial.isEmpty, !package.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var items = [
            URLQueryItem(name: Key.serial, value: serial),
            URLQueryItem(name: Key.package, value: package),
        ]
        if let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            items.append(URLQueryItem(name: Key.name, value: name))
        }
        if let mode {
            items.append(URLQueryItem(name: Key.mode, value: mode.rawValue))
        }
        components.queryItems = items
        return components.url
    }

    /// Parses a link produced by `makeURL` (or typed by hand). Unknown schemes,
    /// hosts and malformed percentages return `nil` rather than guessing.
    static func parse(_ url: URL) -> AppLaunchRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == scheme,
            components.host?.lowercased() == host
        else { return nil }

        let values = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            guard let value = item.value, result[item.name] == nil else { return }
            result[item.name] = value
        }

        guard let serial = values[Key.serial]?.trimmingCharacters(in: .whitespacesAndNewlines),
            let package = values[Key.package]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !serial.isEmpty, !package.isEmpty
        else { return nil }

        let name = values[Key.name]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppLaunchRequest(
            deviceID: serial,
            packageID: package,
            appName: (name?.isEmpty ?? true) ? nil : name,
            mode: AppLaunchMode(queryValue: values[Key.mode]))
    }

    /// Extracts a launch request from a Spotlight/`NSUserActivity` userInfo bag.
    static func parse(userInfo: [String: Any]) -> AppLaunchRequest? {
        guard let serial = stringValue(userInfo[Key.serial]),
            let package = stringValue(userInfo[Key.package]),
            !serial.isEmpty, !package.isEmpty
        else { return nil }
        let name = stringValue(userInfo[Key.name])
        return AppLaunchRequest(
            deviceID: serial,
            packageID: package,
            appName: (name?.isEmpty ?? true) ? nil : name,
            mode: AppLaunchMode(queryValue: stringValue(userInfo[Key.mode])))
    }

    private static func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let value as String:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as NSString:
            return (value as String).trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return nil
        }
    }
}
