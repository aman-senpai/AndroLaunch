//
//  AppIconView.swift
//  AndroLaunch
//
//  One app icon: the real Android launcher icon when `AppIconStore` has it,
//  otherwise the existing AppIconMapper SF Symbol on the same rounded tile the
//  Hub already used.
//
//  The fallback is deliberately identical to the old tile so adding real icons
//  never causes a layout jump on the first paint, and a phone without the
//  companion (or with a pre-v4 APK) simply keeps the symbols.
//
//  Snapshot rendering (`hubSnapshotMode`) never starts network work: the renderer
//  gets deterministic symbol tiles instead of racing asynchronous loads.
//

import AppKit
import SwiftUI

struct AppIconView: View {
    let packageName: String
    var fallbackSymbol: String = "square.grid.2x2.fill"
    var size: CGFloat = 42
    /// Device whose icon cache to use. When nil the view always shows the symbol.
    var deviceID: String? = nil
    /// Dim the tile when the phone is offline (matches the old tinted symbols).
    var dimmed: Bool = false

    @ObservedObject private var store = AppIconStore.shared
    @Environment(\.hubSnapshotMode) private var snapshotMode
    @Environment(\.hubGlassMode) private var glassMode

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(HubColor.stroke, lineWidth: 1))
                    .opacity(dimmed ? 0.5 : 1)
            } else {
                Group {
                    if glassMode {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [HubColor.cardElevated, HubColor.card],
                                    startPoint: .top, endPoint: .bottom))
                    }
                }
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(
                            dimmed ? HubColor.textTertiary : HubColor.accent))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(HubColor.stroke, lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
        .onAppear(perform: requestIconIfNeeded)
        .accessibilityHidden(true)
    }

    private var cornerRadius: CGFloat {
        // Android adaptive icons are rounded squares; matching that keeps the
        // grid recognisable at every size (28 pt row … 48 pt tile).
        max(6, size * 0.235)
    }

    private var resolvedImage: NSImage? {
        guard let deviceID else { return nil }
        return store.cachedImage(deviceID: deviceID, packageName: packageName)
    }

    private func requestIconIfNeeded() {
        guard !snapshotMode, let deviceID else { return }
        store.ensureIcons(packages: [packageName], deviceID: deviceID)
    }
}
