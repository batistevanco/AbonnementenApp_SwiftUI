import SwiftUI

// gedeelde defaults uit je app group
private let sharedStore = UserDefaults(
    suiteName: "group.be.vancoilliestudio.abbobuddy.shared"
)

struct MainWatchView: View {
    @State private var abonnementen: [Abonnement] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // titel
                Text("AbboBuddy")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(Color.black)


                // kaart 1: totals
                VStack(alignment: .leading, spacing: 6) {
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
                .foregroundStyle(Color.black)


                // kaart 2: upcoming
                VStack(alignment: .leading, spacing: 8) {
                    Text("Binnenkort te betalen:")
                        .font(.footnote)
                        .bold()
                        .foregroundStyle(Color.black)


                    ForEach(upcomingAbonnementen) { abbo in
                        HStack {
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
                                .fill(Color.white.opacity(0.03))
                        )
                    }

                    if upcomingAbonnementen.isEmpty {
                        Text("Geen betalingen 🤙")
                            .foregroundStyle(Color.gray)
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
        .background(Color(red: 0.85, green: 0.95, blue: 0.85)) // lichtgroene achtergrond
        .onAppear {
            loadFromSharedDefaults()
        }
    }

    // MARK: - Helpers

    private var totalPerMaand: Double {
        abonnementen.reduce(0) { $0 + $1.prijs }
    }

    private var totalPerJaar: Double {
        totalPerMaand * 12
    }

    // voor nu gewoon dezelfde volgorde; hier kan je straks sorteren op vervaldatum
    private var upcomingAbonnementen: [Abonnement] {
        abonnementen
            .filter { $0.isBinnen30Dagen }
            .sorted { $0.dagenTotVervaldatum < $1.dagenTotVervaldatum }
    }

    private func formattedCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR" // of in watch ook uit shared defaults lezen
        return f.string(from: NSNumber(value: value)) ?? "€\(value)"
    }

    private func loadFromSharedDefaults() {
        guard let data = sharedStore?.data(forKey: "abonnementenData") else {
            print("⌚️ Watch: geen data gevonden in app group")
            return
        }

        let decoder = JSONDecoder()
        // als jouw Abonnement dates gebruikt, kan je hier ook dateDecodingStrategy zetten
        if let arr = try? decoder.decode([Abonnement].self, from: data) {
            abonnementen = arr
        } else {
            print("⚠️ Watch: kon abonnementen niet decoden – mogelijk andere versie van Abonnement op iPhone")
        }
    }
}
