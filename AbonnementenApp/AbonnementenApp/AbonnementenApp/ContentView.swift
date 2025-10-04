//
//  ContentView.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("abonnementenData") private var abonnementenData: Data = Data()
    @AppStorage("categories") private var categoriesRaw: Data = Data()

    var body: some View {
        TabView {
            HomescreenView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
            
            overzichtView()
                .tabItem {
                    Image(systemName: "info.circle.fill")
                    Text("Overzicht")
                }
        }
        .preferredColorScheme(preferredScheme)
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if granted {
                    print("Notificaties toegestaan")
                } else {
                    print("Notificaties geweigerd: \(String(describing: error))")
                }
            }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

#Preview {
    ContentView()
}
