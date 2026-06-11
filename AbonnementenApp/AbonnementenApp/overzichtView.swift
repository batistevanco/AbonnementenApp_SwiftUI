//
//  overzichtView.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//

import SwiftUI
import Charts

struct overzichtView: View {

    // MARK: - Settings
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"
    @AppStorage("appTheme") private var appTheme: String = "system"

    // MARK: - State
    @AppStorage("abonnementenData") private var abonnementenData: Data = Data()
    @State private var abonnementen: [Abonnement] = []
    @AppStorage(CategoriesDefaults.key) private var categoriesRaw: Data = Data()
    @State private var categorieen: [String] = []
    @State private var gekozenCategorie: String = "All"
    @AppStorage("overviewPeriodIsYear") private var periodeIsJaar: Bool = false // false=maand, true=jaar (persisted)

    private var preferredScheme: ColorScheme? {
        switch appTheme { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    private var categorieOpties: [String] { ["All"] + categorieen.sorted { $0.localizedCompare($1) == .orderedAscending } }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                if gekozenCategorie == "All" && !abonnementen.isEmpty {
                    inzichtenSection
                }
                filterHeader
                if gekozenCategorie == "All" {
                    // Toon All categorieën met subtotaal per categorie
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
            .onAppear { loadAbonnementen(); loadCategorieen() }
            .onReceive(NotificationCenter.default.publisher(for: .categoriesUpdated)) { _ in loadCategorieen() }
            .onChange(of: abonnementenData, initial: false) { _, _ in loadAbonnementen() }
            .onChange(of: categoriesRaw, initial: false) { _, _ in loadCategorieen() }
        }
        .tint(Theme.primary)
    }

    // MARK: - Persistence helpers
    private func loadAbonnementen() {
        if let arr = try? JSONDecoder().decode([Abonnement].self, from: abonnementenData), !arr.isEmpty {
            abonnementen = arr
        } else {
            abonnementen = []
        }
    }

    private func loadCategorieen() {
        if let arr = try? JSONDecoder().decode([String].self, from: categoriesRaw), !arr.isEmpty {
            categorieen = arr
        } else {
            categorieen = CategoriesDefaults.fallback
        }
    }

    // MARK: - Inzichten

    private struct CategorieSpending: Identifiable {
        var id: String { categorie }
        let categorie: String
        let bedrag: Double
    }

    private var categorieSpending: [CategorieSpending] {
        let cats = Set(abonnementen.map { $0.categorie })
        return cats.map { cat in
            let total = abonnementen.filter { $0.categorie == cat }
                .map { periodeIsJaar ? $0.jaarBedrag : $0.maandBedrag }
                .reduce(0, +)
            return CategorieSpending(categorie: cat, bedrag: total)
        }
        .filter { $0.bedrag > 0 }
        .sorted { $0.bedrag > $1.bedrag }
    }

    private var duursteAbonnement: Abonnement? {
        abonnementen.max { $0.maandBedrag < $1.maandBedrag }
    }

    private var inzichtenSection: some View {
        Section(header: Text("Inzichten")) {
            // Bar chart per categorie
            if !categorieSpending.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(periodeIsJaar ? "Verdeling per categorie (jaar)" : "Verdeling per categorie (maand)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                    
                    let maxSpending = categorieSpending.map { $0.bedrag }.max() ?? 1.0
                    
                    ForEach(categorieSpending) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(item.categorie, systemImage: CategoryIcon.symbol(for: item.categorie))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(currency(item.bedrag))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.primary)
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Theme.primary.opacity(0.1))
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Theme.primary.gradient)
                                        .frame(width: geo.size.width * CGFloat(item.bedrag / maxSpending), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(.vertical, 6)
            }

            // Duurste abonnement
            if let top = duursteAbonnement {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.primary.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: top.iconSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DUURSTE ABONNEMENT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(top.naam)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(currency(top.maandBedrag))
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.primary)
                        Text("p/m")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
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
                kpiTile(title: NSLocalizedString(periodeIsJaar ? "KPI_TOTAL_YEAR" : "KPI_TOTAL_MONTH",
                                                 comment: "KPI title: Total for the selected period (month/year)"),
                        value: currency(totaalHuidigeSelectie))
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
        let aboBedrag = periodeIsJaar ? abo.jaarBedrag : abo.maandBedrag
        let totaal = totaalHuidigeSelectie
        let progress = totaal > 0 ? aboBedrag / totaal : 0
        let bedragTekst = currency(aboBedrag)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.primary.opacity(0.13))
                        .frame(width: 36, height: 36)
                    Image(systemName: abo.iconSymbol)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(abo.naam).font(.body)
                    Text(frequentieTekst(abo.frequentie)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(periodeIsJaar
                     ? String(format: NSLocalizedString("LABEL_YEARLY_AMOUNT",
                                                        comment: "Label prefix for yearly amount"),
                              bedragTekst)
                     : bedragTekst)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.primary.opacity(0.1))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.primary.opacity(0.6))
                        .frame(width: geo.size.width * min(progress, 1), height: 5)
                }
            }
            .frame(height: 5)
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
        abonnementen.filter { categorie == "All" ? true : $0.categorie == categorie }
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
        if gekozenCategorie == "All" {
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

    private func frequentieTekst(_ f: Frequentie) -> String {
        switch f {
        case .wekelijks:
            return NSLocalizedString("FREQ_WEEKLY", comment: "Frequency label: Weekly")
        case .maandelijks:
            return NSLocalizedString("FREQ_MONTHLY", comment: "Frequency label: Monthly")
        case .driemaandelijks:
            return NSLocalizedString("FREQ_QUARTERLY", comment: "Frequency label: Quarterly (every three months)")
        case .jaarlijks:
            return NSLocalizedString("FREQ_YEARLY", comment: "Frequency label: Yearly")
        }
    }
}




#Preview {
    overzichtView()
}
