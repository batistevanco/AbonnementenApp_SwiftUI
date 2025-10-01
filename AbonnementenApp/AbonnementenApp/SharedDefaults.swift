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
enum Frequentie: String, CaseIterable, Codable {
    case wekelijks, maandelijks, driemaandelijks, jaarlijks
}

struct CategoryIconOptions {
    static let options: [(name: String, symbol: String)] = [
        ("Streaming", "play.tv.fill"),
        ("Muziek", "music.note.list"),
        ("Cloud", "icloud.fill"),
        ("Software", "app.badge.fill"),
        ("Sport", "sportscourt.fill"),
        ("Internet", "globe"),
        ("Overig", "square.grid.2x2.fill")
    ]
}

// Default icon resolver for categories (fallbacks)
struct CategoryIcon {
    static func symbol(for category: String) -> String {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "streaming": return "play.tv.fill"
        case "muziek":    return "music.note.list"
        case "cloud":     return "icloud.fill"
        case "software":  return "app.badge.fill"
        case "sport":     return "sportscourt.fill"
        case "internet":  return "globe"
        case "video":     return "play.rectangle.fill"
        case "overig", "overige", "other", "misc": return "square.grid.2x2.fill"
        default:            return "square.grid.2x2.fill" // default = overig
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


// MARK: - Shared Defaults

struct CategoriesDefaults {
    static let key = "categories"
    static let fallback: [String] = [
        "Streaming", "Muziek", "Cloud", "Software", "Sport", "Internet", "Overig"
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
