import Foundation

typealias AppExceptions = [String: String]

final class AppPreferences {
    private let userDefaults: UserDefaults

    var triggerKey: String {
        userDefaults.triggerKey ?? Constants.defaultTriggerKey
    }

    var appExceptions: AppExceptions {
        userDefaults.appExceptions ?? Constants.defaultAppExceptions
    }

    var appExceptionIDs: [String] {
        userDefaults.appExceptionIDs ?? Constants.defaultAppExceptions.keys.sorted()
    }

    init(userDefaults: UserDefaults = .peachyDefaults) {
        self.userDefaults = userDefaults
    }

    func updateTriggerKey(_ key: String) {
        userDefaults.triggerKey = key
    }

    func updateAppExceptions(bundleID: String, name: String?) {
        var updatedExceptions = appExceptions
        var updatedIDs = appExceptionIDs
        if let name = name {
            guard !updatedIDs.contains(bundleID) else {
                return
            }
            updatedExceptions[bundleID] = name
            updatedIDs.append(bundleID)
        } else {
            updatedExceptions.removeValue(forKey: bundleID)
            updatedIDs.removeAll(where: { $0 == bundleID })
        }
        userDefaults.appExceptions = updatedExceptions
        userDefaults.appExceptionIDs = updatedIDs
    }
}

private extension AppPreferences {
    enum Constants {
        static let defaultTriggerKey = ":"
        static let defaultAppExceptions = [
            "com.apple.dt.Xcode": "Xcode"
        ]
    }
}
