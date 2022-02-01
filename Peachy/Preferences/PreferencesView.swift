import LaunchAtLogin
import SwiftUI

struct PreferencesView: View {
    @State private var triggerKey: String = ":" {
        didSet {
            if triggerKey.count > 1 {
                triggerKey = preferences.triggerKey
            } else {
                preferences.updateTriggerKey(triggerKey)
            }
        }
    }
    @State private var exceptions: AppExceptions = [:]
    @State private var selectedAppBundleID: String?
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    private let preferences: AppPreferences
    
    init(preferences: AppPreferences) {
        self.preferences = preferences
        exceptions = preferences.appExceptions
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .trailing, spacing: 8) {
                Text("Launch: ")
                Text("Trigger Key: ")
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $launchAtLogin.isEnabled) {
                    Text("Launch Peachy at Log In")
                }.toggleStyle(CheckboxToggleStyle())

                TextField("", text: $triggerKey)
                    .multilineTextAlignment(.center)
                    .frame(width: 50, height: 30)
                
                Text("Disable Peachy within these apps:")
                    .padding(.top, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(exceptions.sorted(by: >), id: \.key) { (id, name) in
                            Text(name)
                                .padding(8)
                                .frame(width: 300, alignment: .leading)
                                .background(id == selectedAppBundleID ?
                                            Color(NSColor.selectedTextBackgroundColor) :
                                                Color( NSColor.controlBackgroundColor))
                                .onTapGesture {
                                    selectedAppBundleID = id
                                }
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .frame(width: 300, height: 100, alignment: .leading)

                HStack(spacing: 2) {
                    Button("+") {
                        // TODO: show sheet to select app
                    }

                    Button("-") {
                        // TODO: remove selected app from exceptions
                    }
                }
                .font(.title3)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .frame(width: 500, height: 300)
    }
}
