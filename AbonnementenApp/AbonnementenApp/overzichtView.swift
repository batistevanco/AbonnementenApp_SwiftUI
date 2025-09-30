//
//  overzichtView.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//

import SwiftUI

struct overzichtView: View {
    // MARK: - Local model (keeps this file self‑contained)
    enum Frequentie: String, CaseIterable { case wekelijks, maandelijks, driemaandelijks, jaarlijks }
    struct Abonnement: Identifiable {
        let id = UUID()
        var naam: String
        var prijs: Double
        var frequentie: Frequentie
        var volgendeVervaldatum: Date
        var categorie: String

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
    }

    // MARK: - Settings
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"
    @AppStorage("appTheme") private var appTheme: String = "system"

    // MARK: - State
    @State private var abonnementen: [Abonnement] = Mock.abonnementen
    @State private var categorieen: [String] = CategoriesDefaults.load()
    @State private var gekozenCategorie: String = "Alle"
    @State private var periodeIsJaar: Bool = false // false=maand, true=jaar

    private var preferredScheme: ColorScheme? {
        switch appTheme { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    private var categorieOpties: [String] { ["Alle"] + categorieen.sorted { $0.localizedCompare($1) == .orderedAscending } }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                filterHeader
                if gekozenCategorie == "Alle" {
                    // Toon alle categorieën met subtotaal per categorie
                    ForEach(gesorteerdeCategorieen, id: \.self) { cat in
                        Section(header: sectionHeader(cat)) {
                            ForEach(items(in: cat)) { abo in
                                aboRow(abo)
                            }
                        }
                    }
                } else {
                    // Enkel gekozen categorie + subtotal
                    Section(header: sectionHeader(gekozenCategorie)) {
                        ForEach(items(in: gekozenCategorie)) { abo in
                            aboRow(abo)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Overzicht")
            .preferredColorScheme(preferredScheme)
            .onReceive(NotificationCenter.default.publisher(for: .categoriesUpdated)) { _ in
                categorieen = CategoriesDefaults.load()
            }
        }
    }

    // MARK: - Header (filters)
    private var filterHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Categorie", selection: $gekozenCategorie) {
                    ForEach(categorieOpties, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.navigationLink)

                Toggle(isOn: $periodeIsJaar) {
                    Text(periodeIsJaar ? "Periode: Jaar" : "Periode: Maand")
                }
                .toggleStyle(.switch)

                // KPI voor de huidige selectie
                kpiTile(title: "Totaal \(periodeIsJaar ? "jaar" : "maand")", value: currency(totaalHuidigeSelectie))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sections & Rows
    private func sectionHeader(_ categorie: String) -> some View {
        let subtotal = periodeIsJaar ? somJaar(cat: categorie) : somMaand(cat: categorie)
        return HStack {
            Text(categorie).font(.headline)
            Spacer()
            Text(currency(subtotal)).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func aboRow(_ abo: Abonnement) -> some View {
        HStack {
            Image(systemName: icoonVoorCategorie(abo.categorie)).frame(width: 24)
            VStack(alignment: .leading) {
                Text(abo.naam).font(.body)
                Text(frequentieTekst(abo.frequentie)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(currency(periodeIsJaar ? abo.jaarBedrag : abo.maandBedrag)).font(.body).fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }

    private func kpiTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers (data)
    private var gesorteerdeCategorieen: [String] {
        Set(abonnementen.map { $0.categorie }).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func items(in categorie: String) -> [Abonnement] {
        abonnementen.filter { categorie == "Alle" ? true : $0.categorie == categorie }
            .sorted { $0.naam.localizedCaseInsensitiveCompare($1.naam) == .orderedAscending }
    }

    private func somMaand(cat: String) -> Double {
        let rows = items(in: cat)
        return rows.map { $0.maandBedrag }.reduce(0, +)
    }

    private func somJaar(cat: String) -> Double {
        let rows = items(in: cat)
        return rows.map { $0.jaarBedrag }.reduce(0, +)
    }

    private var totaalHuidigeSelectie: Double {
        if gekozenCategorie == "Alle" {
            return periodeIsJaar ? abonnementen.map { $0.jaarBedrag }.reduce(0, +)
                                 : abonnementen.map { $0.maandBedrag }.reduce(0, +)
        } else {
            return periodeIsJaar ? somJaar(cat: gekozenCategorie) : somMaand(cat: gekozenCategorie)
        }
    }

    // MARK: - Helpers (format)
    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = Locale.current
        return f.string(from: NSNumber(value: value)) ?? "\(currencyCode) " + String(format: "%.2f", value)
    }

    private func icoonVoorCategorie(_ cat: String) -> String {
        switch cat.lowercased() {
        case "video", "tv", "streaming": return "play.rectangle"
        case "muziek", "music": return "music.note"
        case "cloud", "opslag": return "icloud"
        case "software": return "app.badge"
        case "sport", "fitness": return "figure.run"
        case "internet": return "wifi"
        default: return "creditcard"
        }
    }

    private func frequentieTekst(_ f: Frequentie) -> String {
        switch f {
        case .wekelijks: return "Wekelijks"
        case .maandelijks: return "Maandelijks"
        case .driemaandelijks: return "Driemaandelijks"
        case .jaarlijks: return "Jaarlijks"
        }
    }
}

// MARK: - Defaults bridge
private enum CategoriesDefaults {
    static let key = "categories"
    static let fallback = ["Streaming", "Muziek", "Cloud", "Software", "Sport", "Internet", "Overig"]
    static func load() -> [String] {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
            return arr
        }
        return fallback
    }
}

// MARK: - Preview + Mock Data
private enum Mock {
    static var abonnementen: [overzichtView.Abonnement] {
        let cal = Calendar.current
        return [
            .init(naam: "Netflix", prijs: 15.99, frequentie: .maandelijks, volgendeVervaldatum: cal.date(byAdding: .day, value: 5, to: .now)!, categorie: "Streaming"),
            .init(naam: "Spotify", prijs: 10.99, frequentie: .maandelijks, volgendeVervaldatum: cal.date(byAdding: .day, value: 27, to: .now)!, categorie: "Muziek"),
            .init(naam: "iCloud+", prijs: 2.99, frequentie: .maandelijks, volgendeVervaldatum: cal.date(byAdding: .day, value: 1, to: .now)!, categorie: "Cloud"),
            .init(naam: "Amazon Prime", prijs: 89.00, frequentie: .jaarlijks, volgendeVervaldatum: cal.date(byAdding: .day, value: 120, to: .now)!, categorie: "Streaming"),
            .init(naam: "Strava", prijs: 5.99, frequentie: .wekelijks, volgendeVervaldatum: cal.date(byAdding: .day, value: 3, to: .now)!, categorie: "Sport"),
            .init(naam: "Adobe CC", prijs: 24.19, frequentie: .maandelijks, volgendeVervaldatum: cal.date(byAdding: .day, value: 9, to: .now)!, categorie: "Software")
        ]
    }
}

#Preview {
    overzichtView()
}
