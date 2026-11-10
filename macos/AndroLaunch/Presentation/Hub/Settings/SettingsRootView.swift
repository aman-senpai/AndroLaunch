//
//  SettingsRootView.swift
//  AndroLaunch
//
//  Settings: Fusion mode, Hardware support, AI (Android Use / MCP),
//  Devices, Notifications, Storage and About. Owned by settings-mcp.
//
//  The screen only delegates: each action calls the owning service's contract
//  (MCPController, CameraController, TrackpadController, GlanceBoardController,
//  SpotlightService, NotificationMirror, StorageView, SMAppService).
//  Platform-blocked rows are disabled and say why; there are no dead buttons.
//

import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var store: HubStore
    /// Inline mode for the dashboard Settings tab: renders the sections
    /// directly, without a nested HubPage/ScrollView.
    private let embedded: Bool

    @StateObject private var preferences: AppPreferences
    @ObservedObject private var mcp: MCPController
    @ObservedObject private var camera: CameraController
    @ObservedObject private var trackpad: TrackpadController
    @ObservedObject private var glance: GlanceBoardController
    @ObservedObject private var spotlight: SpotlightService
    @ObservedObject private var mirror: NotificationMirror

    @State private var sheet: SettingsSheet?

    init(store: HubStore, embedded: Bool = false) {
        self.store = store
        self.embedded = embedded
        // Snapshot/preview mode must be deterministic and must not touch the
        // user's real preferences or start services.
        _preferences = StateObject(
            wrappedValue: store.isPreview ? AppPreferences.preview : AppPreferences.shared)
        _mcp = ObservedObject(
            wrappedValue: store.isPreview ? MCPController.preview : MCPController.shared)
        _camera = ObservedObject(wrappedValue: CameraController.shared)
        _trackpad = ObservedObject(wrappedValue: TrackpadController.shared)
        _glance = ObservedObject(wrappedValue: GlanceBoardController.shared)
        _spotlight = ObservedObject(wrappedValue: SpotlightService.shared)
        _mirror = ObservedObject(wrappedValue: NotificationMirror.shared)
    }

    var body: some View {
        Group {
            if embedded {
                sections
                    .transition(.opacity)
            } else {
                HubPage {
                    sections
                }
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .aiActivity:
                SettingsAIActivitySheet(mcp: mcp)
            case .spotlight:
                SettingsSpotlightSheet(
                    spotlight: spotlight,
                    selectedDevice: store.selectedDevice,
                    apps: store.apps)
            case .featureAlerts:
                SettingsFeatureAlertsSheet(preferences: preferences)
            case .camera:
                SettingsCameraSheet(camera: camera)
            case .licenses:
                SettingsLicensesSheet()
            }
        }
        .onAppear {
            guard !store.isPreview else { return }
            camera.refreshExtensionStatus()
            mcp.refreshActivity()
        }
    }

    @ViewBuilder
    private var sections: some View {
        VStack(alignment: .leading, spacing: HubMetric.sectionGap) {
            SettingsFusionSection(
                store: store,
                preferences: preferences,
                spotlight: spotlight,
                showSpotlight: { sheet = .spotlight })

            SettingsHardwareSection(
                store: store,
                camera: camera,
                trackpad: trackpad,
                glance: glance,
                openCameraSettings: { sheet = .camera })

            SettingsAISection(
                store: store,
                mcp: mcp,
                showActivity: { sheet = .aiActivity })

            SettingsDevicesSection(preferences: preferences, isPreview: store.isPreview)

            SettingsNotificationsSection(
                store: store,
                preferences: preferences,
                mirror: mirror,
                showFeatureAlerts: { sheet = .featureAlerts })

            SettingsStorageSection(
                store: store,
                openStorage: { device in
                    guard !store.isPreview else { return }
                    PanelRouter.openStorageAnalytics()
                })

            SettingsAboutSection(showLicenses: { sheet = .licenses })
        }
    }
}

#if DEBUG
    struct SettingsRootView_Previews: PreviewProvider {
        static var previews: some View {
            SettingsRootView(store: HubStore(previewDevices: HubPreviewData.devices))
                .frame(width: 480, height: 1650)
                .environment(\.colorScheme, .dark)
                .environment(\.hubSnapshotMode, true)
        }
    }
#endif
