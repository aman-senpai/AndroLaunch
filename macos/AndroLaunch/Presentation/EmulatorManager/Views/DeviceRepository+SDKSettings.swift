import Foundation

extension DeviceRepository {
    var androidSdkRootPath: String? {
        UserDefaults.standard.string(forKey: "android_sdk_root_path")
    }

    func setAndroidSdkRoot(_ path: String?) {
        if let path = path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: "android_sdk_root_path")
        } else {
            UserDefaults.standard.removeObject(forKey: "android_sdk_root_path")
        }
        objectWillChange.send()
    }
}
