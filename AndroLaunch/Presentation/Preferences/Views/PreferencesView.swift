//
//  PreferencesView.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var viewModel: PreferencesViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("ADB Status: \(viewModel.adbStatus)")
                .font(.headline)

            if let error = viewModel.errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }

            Button("Check ADB Status") {
                viewModel.checkAdbStatus()
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
