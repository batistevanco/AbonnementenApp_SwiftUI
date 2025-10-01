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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(accentColor)
                .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
                    accentColor = AccentColorDefaults.currentAccentColor()
                }
        }
    }
}
