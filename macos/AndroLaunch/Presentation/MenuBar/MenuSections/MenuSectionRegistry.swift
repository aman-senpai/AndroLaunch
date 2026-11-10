//
//  MenuSectionRegistry.swift
//  AndroLaunch
//
//  The single ordered list of menu contributions. Add new sections here.
//

import Foundation

enum MenuSectionRegistry {
    static func makeSections(viewModel: MenuViewModel) -> [MenuSectionProviding] {
        [
            ClipboardMenuSection(viewModel: viewModel),
            TransferMenuSection(viewModel: viewModel),
            ConnectionMenuSection(viewModel: viewModel),
            NotificationMenuSection(viewModel: viewModel),
            CallMenuSection(viewModel: viewModel),
            MediaMenuSection(viewModel: viewModel),
            PhoneToolsMenuSection(viewModel: viewModel),
            PlatformMenuSection(viewModel: viewModel),
        ].sorted { $0.topLevelOrder < $1.topLevelOrder }
    }
}
