//
//  MainWatchView.swift
//  AbonnementenApp Watch App
//
//  Created by Batiste Vancoillie on 06/11/2025.
//

import SwiftUI

// Je gedeelde UserDefaults-container (zelfde als iOS)
private let sharedStore = UserDefaults(suiteName: "group.be.vancoilliestudio.abbobuddy.shared")

struct ContentView: View {
    @State private var abonnementen: [Abonnement] = []
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Titel
                Text("AbboBuddy")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Eventuele foutmelding
                if let loadError {
                    Text(loadError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                // 📊 Overzicht kaart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overzicht")
                        .font(.footnote)
                        .bold()
                        .foregroundStyle(.black)

                    HStack {
                        Text("Totaal maand:")
                        Spacer()
                        Text(formattedCurrency(totalPerMaand))
                            .bold()
                    }

                    HStack {
                        Text("Totaal jaar:")
                        Spacer()
                        Text(formattedCurrency(totalPerJaar))
                            .bold()
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.25))
                )

                // 💳 Binnenkort te betalen kaart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Binnenkort te betalen:")
                        .font(.footnote)
                        .bold()
                        .foregroundStyle(.black)

                    ForEach(upcomingAbonnementen) { abbo in
                        HStack {
                            Image(systemName: abbo.iconSymbol)
                                .font(.caption)
                            Text(abbo.naam)
                                .bold()
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(formattedCurrency(abbo.prijs))
                                .bold()
                            Text("\(abbo.dagenTotVervaldatum)d")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.1))
                        )
                    }

                    if upcomingAbonnementen.isEmpty {
                        Text("Geen betalingen 🤙")
                            .foregroundStyle(.gray)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.25))
                )
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
        .background(Color(red: 0.85, green: 0.95, blue: 0.85))
        .onAppear {
            loadFromSharedDefaults()
        }
    }

    // MARK: - Helpers

    private var totalPerMaand: Double {
        abonnementen.map { $0.maandBedrag }.reduce(0, +)
    }

    private var totalPerJaar: Double {
        abonnementen.map { $0.jaarBedrag }.reduce(0, +)
    }

    private var upcomingAbonnementen: [Abonnement] {
        abonnementen
            .filter { $0.isBinnen30Dagen }
            .sorted { $0.dagenTotVervaldatum < $1.dagenTotVervaldatum }
    }

    private func formattedCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        return f.string(from: NSNumber(value: value)) ?? "€0,00"
    }

    // MARK: - Data ophalen uit App Group
    private func loadFromSharedDefaults() {
        guard let store = sharedStore else {
            loadError = "Geen shared store – check App Group"
            return
        }
        guard let data = store.data(forKey: "abonnementenData") else {
            loadError = "Geen data gevonden (key 'abonnementenData')"
            return
        }

        let decoder = JSONDecoder()
        if let arr = try? decoder.decode([Abonnement].self, from: data) {
            abonnementen = arr
            loadError = nil
        } else {
            loadError = "Kon abonnementen niet decoderen – zelfde model op iOS & watch?"
        }
    }
}
