//
//  SharedDefaults.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 01/10/2025.
//

import Foundation
import SwiftUI

// MARK: - Shared Models

// MARK: - Theme
struct Theme {
    /// Primary accent used across the app (buttons, icons, highlights)
    static let primary: Color = .accentColor
    
    /// Optional semantic colors if needed later
    static let success: Color = .green
    static let warning: Color = .orange
    static let destructive: Color = .red
}

// MARK: - Accent Color Defaults
enum AccentColorDefaults {
    private struct RGBA: Codable { let r: Double; let g: Double; let b: Double; let a: Double }

    static func currentAccentColor(fallback: Color = .accentColor) -> Color {
        let ud = UserDefaults.standard
        let mode = ud.string(forKey: "accentMode") ?? "default"
        guard mode == "custom",
              let data = ud.data(forKey: "accentCustomColor"),
              let rgba = try? JSONDecoder().decode(RGBA.self, from: data) else {
            return fallback
        }
        return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}
enum Frequentie: String, CaseIterable, Codable {
    case wekelijks, maandelijks, driemaandelijks, jaarlijks
}

struct CategoryIconOptions {
    static let options: [(name: String, symbol: String)] = [
        ("Other", "square.grid.2x2.fill"),
        ("Streaming", "play.tv.fill"),
        ("Video", "play.rectangle.fill"),
        ("Music", "music.note.list"),
        ("Podcast", "headphones"),
        ("Cloud", "icloud.fill"),
        ("Storage", "externaldrive.fill"),
        ("Hosting", "server.rack"),
        ("Software", "app.badge.fill"),
        ("Productivity", "hammer"),
        ("Gaming", "gamecontroller.fill"),
        ("News", "newspaper.fill"),
        ("Books", "book.fill"),
        ("Library", "books.vertical.fill"),
        ("Sport", "sportscourt.fill"),
        ("Fitness", "figure.run"),
        ("Health", "heart.fill"),
        ("Medical", "cross.case.fill"),
        ("Energy", "bolt.fill"),
        ("Gas", "flame.fill"),
        ("Water", "drop.fill"),
        ("Internet", "globe"),
        ("Netwerk", "network"),
        ("Security", "lock.fill"),
        ("VPN", "shield.fill"),
        ("Phone", "phone.fill"),
        ("Data", "simcard.fill"),
        ("E-mail", "envelope.fill"),
        ("social", "person.2.fill"),
        ("Travel", "airplane"),
        ("Car", "car.fill"),
        ("Public transport", "tram.fill"),
        ("Fuel", "fuelpump.fill"),
        ("House", "house.fill"),
        ("Finance", "creditcard.fill"),
        ("Subscription", "banknote.fill"),
        ("Food & Drinks", "fork.knife"),
        ("Groceries", "cart.fill"),
        ("Delivery", "shippingbox.fill"),
        ("Photo/Media", "photo.stack"),
        ("Education", "graduationcap.fill")
    ]
}

// Default icon resolver for categories (fallbacks)
struct CategoryIcon {
    static func symbol(for category: String) -> String {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "Other", "misc": return "square.grid.2x2.fill"
        case "streaming", "tv": return "play.tv.fill"
        case "video": return "play.rectangle.fill"
        case "muziek", "music": return "music.note.list"
        case "podcast": return "headphones"
        case "cloud": return "icloud.fill"
        case "opslag", "storage": return "externaldrive.fill"
        case "hosting", "server": return "server.rack"
        case "software", "apps": return "app.badge.fill"
        case "productivity": return "hammer"
        case "games": return "gamecontroller.fill"
        case "news": return "newspaper.fill"
        case "books": return "book.fill"
        case "library": return "books.vertical.fill"
        case "sport": return "sportscourt.fill"
        case "fitness": return "figure.run"
        case "health": return "heart.fill"
        case "medical": return "cross.case.fill"
        case "energy", "electricity", "stroom": return "bolt.fill"
        case "gas": return "flame.fill"
        case "water": return "drop.fill"
        case "internet": return "globe"
        case "network": return "network"
        case "security": return "lock.fill"
        case "vpn": return "shield.fill"
        case "phone": return "phone.fill"
        case "data", "sim": return "simcard.fill"
        case "e-mail", "email", "mail": return "envelope.fill"
        case "social": return "person.2.fill"
        case "reizen", "travel": return "airplane"
        case "auto", "car": return "car.fill"
        case "public transport", "ov", "tram": return "tram.fill"
        case "brandstof", "fuel": return "fuelpump.fill"
        case "woning", "huis", "home": return "house.fill"
        case "financiën", "finance", "bank": return "creditcard.fill"
        case "subscription", "factuur", "billing", "invoice": return "banknote.fill"
        case "food & drinks", "drinken", "food": return "fork.knife"
        case "boodschappen", "groceries": return "cart.fill"
        case "levering", "delivery", "pakket": return "shippingbox.fill"
        case "photo", "media", "photos": return "photo.stack"
        case "onderwijs", "education", "school": return "graduationcap.fill"
        default: return "square.grid.2x2.fill"
        }
    }
}

// Persisted user-selected icons per category
struct CategoryIconMapDefaults {
    static let key = "categoryIconMap"

    static func load() -> [String:String] {
        if let data = UserDefaults.standard.data(forKey: key),
           let map = try? JSONDecoder().decode([String:String].self, from: data) {
            return map
        }
        return [:]
    }

    static func save(_ map: [String:String]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func symbol(for category: String) -> String? {
        let keyLower = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return load()[keyLower]
    }
}

// Resolve the icon with priority: user map → explicit field → default mapping
extension Abonnement {
    var iconSymbol: String {
        if let mapped = CategoryIconMapDefaults.symbol(for: categorie) { return mapped }
        if let explicit = categorieIcon { return explicit }
        return CategoryIcon.symbol(for: categorie)
    }
}

struct Abonnement: Identifiable, Codable {
    var id = UUID()
    var naam: String
    var prijs: Double
    var frequentie: Frequentie
    var volgendeVervaldatum: Date
    var categorie: String
    var categorieIcon: String? = nil// SF Symbol naam, optioneel
    var opzegbaar: Bool
    var notitie: String?

    // MARK: - Computed amounts per period
    var maandBedrag: Double {
        switch frequentie {
        case .wekelijks: return prijs * 52.0 / 12.0
        case .maandelijks: return prijs
        case .driemaandelijks: return prijs / 3.0
        case .jaarlijks: return prijs / 12.0
        }
    }

    var jaarBedrag: Double {
        switch frequentie {
        case .wekelijks: return prijs * 52.0
        case .maandelijks: return prijs * 12.0
        case .driemaandelijks: return prijs * 4.0
        case .jaarlijks: return prijs
        }
    }

    var dagenTotVervaldatum: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: volgendeVervaldatum).day ?? 0
    }

    var isBinnen30Dagen: Bool { dagenTotVervaldatum >= 0 && dagenTotVervaldatum <= 30 }
    var isVandaag: Bool { Calendar.current.isDateInToday(volgendeVervaldatum) }
}
extension Abonnement {
    /// Berekent de eerstvolgende vervaldatum na de huidige `volgendeVervaldatum` op basis van de frequentie.
    func volgendeVervaldatumNaHuidige() -> Date {
        let calendar = Calendar.current
        switch frequentie {
        case .wekelijks:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: volgendeVervaldatum) ?? volgendeVervaldatum
        case .maandelijks:
            return calendar.date(byAdding: .month, value: 1, to: volgendeVervaldatum) ?? volgendeVervaldatum
        case .driemaandelijks:
            return calendar.date(byAdding: .month, value: 3, to: volgendeVervaldatum) ?? volgendeVervaldatum
        case .jaarlijks:
            return calendar.date(byAdding: .year, value: 1, to: volgendeVervaldatum) ?? volgendeVervaldatum
        }
    }
}


// MARK: - Appearance Defaults
enum AppearanceMode: String, CaseIterable, Codable { case system, light, dark }

struct AppearanceDefaults {
    static let key = "appearanceMode"
    /// Register a default appearance for first install without overwriting user changes later
    static func register() {
        UserDefaults.standard.register(defaults: [key: AppearanceMode.light.rawValue])
    }
}

// MARK: - Shared Defaults

struct CategoriesDefaults {
    static let key = "categories"
    static let fallback: [String] = [
        "Streaming", "Muziek", "Cloud", "Software", "Sport", "Internet", "Other"
    ]
    static func load() -> [String] {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
            return arr
        }
        return fallback
    }
}

struct AbonnementenDefaults {
    static let key = "abonnementenData"
    
    static func load() -> [Abonnement] {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([Abonnement].self, from: data) {
            return arr
        }
        return []
    }
}
