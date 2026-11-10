//
//  HubView.swift
//  AndroLaunch
//
//  The home window: brand header, three-tab navigation, and one embedded
//  feature surface per tab.
//

import SwiftUI

struct HubView: View {
    @ObservedObject var store: HubStore
    @Environment(\.hubSnapshotMode) private var snapshotMode

    var body: some View {
        ZStack(alignment: .top) {
            HubColor.background
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, HubMetric.pagePadding)
                    .padding(.top, 30)
                    .padding(.bottom, 14)

                HubSegmentedTabs(
                    items: HubStore.Tab.allCases.map {
                        .init(value: $0, title: $0.title, icon: $0.icon)
                    },
                    selection: $store.tab)
                    .padding(.horizontal, HubMetric.pagePadding)
                    .padding(.bottom, 13)

                Rectangle()
                    .fill(HubColor.stroke)
                    .frame(height: 1)

                content
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: snapshotMode ? nil : .infinity,
                        alignment: .top)
            }
        }
        .frame(minWidth: HubMetric.minWindowWidth, minHeight: HubMetric.minWindowHeight)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            HubLogoMark(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("AndroLaunch")
                    .font(.hubWindowTitle)
                    .foregroundStyle(HubColor.textPrimary)
                Text("Seamlessly connect your Mac and Android devices")
                    .font(.hubWindowSubtitle)
                    .foregroundStyle(HubColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)

            Button {
                DeviceDashboardWindowController.shared.show(
                    deviceID: store.selectedDevice?.id, tab: .apps)
            } label: {
                HubPill(text: "Device", tint: HubColor.accent, icon: "iphone.gen3")
            }
            .buttonStyle(.plain)
            .help("Open the compact device dashboard")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.tab {
        case .devices:
            DevicesRootView(store: store)
        case .apps:
            AppsRootView(store: store)
        case .settings:
            SettingsRootView(store: store)
        }
    }
}
