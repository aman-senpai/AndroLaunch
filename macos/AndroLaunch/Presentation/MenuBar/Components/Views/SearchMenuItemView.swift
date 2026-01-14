//
//  SearchMenuItemView.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 11/29/25.
//

import AppKit

class DeviceSearchField: NSSearchField {
    var deviceID: String?
}

class SearchMenuItemView: NSView {
    let searchField: DeviceSearchField
    
    init(deviceID: String, delegate: NSSearchFieldDelegate) {
        searchField = DeviceSearchField(frame: .zero)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        
        searchField.deviceID = deviceID
        searchField.delegate = delegate
        searchField.placeholderString = "Search apps..."
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(searchField)
        
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 22)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
}
