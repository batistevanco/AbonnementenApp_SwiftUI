//
//  AbonnementenAppApp.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//

import SwiftUI

@main
struct AbonnementenAppApp: App {
    @State private var accentColor: Color = AccentColorDefaults.currentAccentColor()
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.light.rawValue
    
    init() {
        AppearanceDefaults.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme({
                    let mode = AppearanceMode(rawValue: appearanceMode) ?? .light
                    switch mode {
                    case .system: return nil
                    case .light:  return .light
                    case .dark:   return .dark
                    }
                }())
                .tint(accentColor)
                .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
                    accentColor = AccentColorDefaults.currentAccentColor()
                }
        }
    }
}
