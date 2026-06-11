//
//  iCloudSync.swift
//  AbonnementenApp
//

import Foundation

extension Notification.Name {
    static let iCloudDataDidChange = Notification.Name("iCloudDataDidChange")
}

// Mirrors AppStorage keys to NSUbiquitousKeyValueStore for basic iCloud sync.
// Requires iCloud capability + com.apple.developer.ubiquity-kvstore-identifier entitlement.
final class iCloudSyncManager {
    static let shared = iCloudSyncManager()
    private let store = NSUbiquitousKeyValueStore.default

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    @objc private func storeDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .iCloudDataDidChange, object: nil)
        }
    }

    func save(_ data: Data, forKey key: String) {
        store.set(data, forKey: key)
        let ts = Date().timeIntervalSince1970
        store.set(ts, forKey: "\(key)__ts")
        UserDefaults.standard.set(ts, forKey: "\(key)__ts")
        store.synchronize()
    }

    /// Returns cloud data if it's strictly newer than local, otherwise nil.
    func newerCloudData(forKey key: String) -> Data? {
        let cloudTs = store.double(forKey: "\(key)__ts")
        let localTs = UserDefaults.standard.double(forKey: "\(key)__ts")
        guard cloudTs > localTs, let data = store.data(forKey: key) else { return nil }
        return data
    }
}
