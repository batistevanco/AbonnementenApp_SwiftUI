//
//  SharedDefaults.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 01/10/2025.
//

import Foundation

// MARK: - Shared Models
enum Frequentie: String, CaseIterable, Codable {
    case wekelijks, maandelijks, driemaandelijks, jaarlijks
}

struct Abonnement: Identifiable, Codable {
    var id = UUID()
    var naam: String
    var prijs: Double
    var frequentie: Frequentie
    var volgendeVervaldatum: Date
    var categorie: String
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
