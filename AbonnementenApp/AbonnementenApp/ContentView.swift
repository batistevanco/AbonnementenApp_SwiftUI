//
//  ContentView.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//

import SwiftUI

struct ContentView: View {
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
    }
}

#Preview {
    ContentView()
}
