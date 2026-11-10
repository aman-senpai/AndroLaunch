//
//  HubPreviewData.swift
//  AndroLaunch
//
//  Deterministic fixtures for SwiftUI previews and the DEBUG snapshot renderer.
//  Never used by the shipping UI for real data.
//

import Foundation

enum HubPreviewData {
    static let pixel = AndroidDevice(
        id: "R58M12ABCDE",
        name: "Pixel 9 Pro",
        model: "Pixel 9 Pro",
        isConnected: true,
        serialNumber: "R58M12ABCDE",
        androidVersion: "16",
        apiLevel: "36",
        batteryLevel: 82,
        isCharging: false)

    static let galaxy = AndroidDevice(
        id: "192.168.1.23:5555",
        name: "Galaxy S25 Ultra",
        model: "SM-S938B",
        isConnected: true,
        serialNumber: "SM-S938B",
        androidVersion: "15",
        apiLevel: "35",
        batteryLevel: 41,
        isCharging: true)

    static let devices = [pixel, galaxy]

    static let apps: [AndroidApp] = [
        AndroidApp(id: "com.whatsapp", name: "WhatsApp", iconName: "message.fill", packageName: "com.whatsapp"),
        AndroidApp(id: "com.spotify.music", name: "Spotify", iconName: "music.note", packageName: "com.spotify.music"),
        AndroidApp(id: "com.google.android.youtube", name: "YouTube", iconName: "play.rectangle.fill", packageName: "com.google.android.youtube"),
        AndroidApp(id: "com.google.android.apps.photos", name: "Photos", iconName: "photo.fill", packageName: "com.google.android.apps.photos"),
        AndroidApp(id: "com.google.android.gm", name: "Gmail", iconName: "envelope.fill", packageName: "com.google.android.gm"),
        AndroidApp(id: "com.google.android.apps.maps", name: "Maps", iconName: "map.fill", packageName: "com.google.android.apps.maps"),
        AndroidApp(id: "com.android.chrome", name: "Chrome", iconName: "globe", packageName: "com.android.chrome"),
        AndroidApp(id: "com.google.android.deskclock", name: "Clock", iconName: "clock.fill", packageName: "com.google.android.deskclock"),
        AndroidApp(id: "com.google.android.apps.messaging", name: "Messages", iconName: "message.fill", packageName: "com.google.android.apps.messaging"),
        AndroidApp(id: "com.google.android.apps.camera", name: "Camera", iconName: "camera.fill", packageName: "com.google.android.apps.camera"),
        AndroidApp(id: "com.google.android.calendar", name: "Calendar", iconName: "calendar", packageName: "com.google.android.calendar"),
        AndroidApp(id: "com.google.android.keep", name: "Keep Notes", iconName: "note.text", packageName: "com.google.android.keep"),
    ]
}
