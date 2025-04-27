import SwiftUI

struct SettingsView: View {
    @State private var name: String = "Aman Raj"

    var body: some View {
        VStack(spacing: 20) {
            // Profile Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Profile")
                    .font(.headline)

                HStack {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading) {
                        TextField("Your Name", text: $name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("Developer")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(10)

            // About Section
            VStack(alignment: .leading, spacing: 10) {
                Text("About AndroLaunch")
                    .font(.headline)

                Text("A professional macOS menu bar application for managing Android devices through ADB and Scrcpy, built with modern Swift architecture patterns.")
                    .font(.body)
                    .padding()
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(10)

            Spacer()
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}