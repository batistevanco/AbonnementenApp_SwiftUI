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
