//
//  HomescreenView.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//
import SwiftUI


struct HomescreenView: View {
    // MARK: - Types
    enum Periode: String, CaseIterable, Identifiable { case maand = "Maand", jaar = "Jaar"; var id: String { rawValue } }

    // MARK: - State
    @AppStorage("periodeRaw") private var periodeRaw: String = Periode.maand.rawValue
    @State private var periode: Periode = .maand
    @State private var zoektekst: String = ""
    @State private var isSearchActive: Bool = false
    @AppStorage("abonnementenData") private var abonnementenData: Data = Data()
    @State private var abonnementen: [Abonnement] = []
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("dismissedSwipeHint") private var dismissedSwipeHint: Bool = false
    @AppStorage("dismissedInfoHint") private var dismissedInfoHint: Bool = false

    // Add/Edit state
    @State private var isPresentingAddEdit = false
    @State private var editingID: UUID? = nil
    // Delete confirmation state
    @State private var pendingDelete: Abonnement? = nil
    @State private var showDeleteAlert: Bool = false

    // Draft model used in the Add/Edit sheet
    private struct Draft {
        var naam: String = ""
        var prijs: Double = 0
        var frequentie: Frequentie = .maandelijks
        var volgendeVervaldatum: Date = Date()
        var categorie: String = "Overig"
        var categorieIcon: String? = nil
        var opzegbaar: Bool = true
        var notitie: String? = nil
    }
    @State private var draft = Draft()
    // Tekstveld voor prijs met placeholder (voorkomt standaard "0")
    @State private var prijsText: String = ""

    // Wordt beheerd in Instellingen en geladen uit UserDefaults
    @AppStorage(CategoriesDefaults.key) private var categoriesRaw: Data = Data()
    @State private var categorieen: [String] = []

    private var isEditing: Bool { editingID != nil }
    
    private var preferredScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil // system
        }
    }

    // Binding for icon picker ("__auto__" sentinel = follow category)
    private var iconSelection: Binding<String> {
        Binding<String>(
            get: { draft.categorieIcon ?? "__auto__" },
            set: { draft.categorieIcon = ($0 == "__auto__") ? nil : $0 }
        )
    }

    // MARK: - Persistence helpers (AppStorage <-> in-memory)
    private func loadAbonnementen() {
        if let arr = try? JSONDecoder().decode([Abonnement].self, from: abonnementenData), !arr.isEmpty {
            abonnementen = arr
        } else {
            // Fresh start: no seed data for real users
            abonnementen = []
        }
    }
    
    private func saveAbonnementen() {
        if let data = try? JSONEncoder().encode(abonnementen) {
            abonnementenData = data
        }
    }
    
    private func loadCategorieen() {
        if let arr = try? JSONDecoder().decode([String].self, from: categoriesRaw), !arr.isEmpty {
            categorieen = arr
        } else {
            categorieen = CategoriesDefaults.fallback
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            // App-wide tint on this screen
            List {
                if !dismissedSwipeHint { swipeHintSection }
                if !dismissedInfoHint { infoHintSection }
                headerKPISection
                if !binnenkortLeeg {
                    upcomingSection
                }
                volledigeLijstSection
            }
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard(); if isSearchActive { isSearchActive = false; zoektekst = "" } })
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("AbboBuddy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { instellingenView() } label: { Image(systemName: "gearshape").foregroundStyle(Theme.primary) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openAdd() } label: {
                        Image(systemName: "plus")
                            .imageScale(.large)
                            .font(.headline)
                            .symbolRenderingMode(.monochrome)
                    }
                }
            }
            .searchable(text: $zoektekst, isPresented: $isSearchActive, placement: .navigationBarDrawer(displayMode: .always), prompt: "Zoek abonnement…")
            .onAppear { periode = Periode(rawValue: periodeRaw) ?? .maand; loadAbonnementen(); loadCategorieen() }
            .onReceive(NotificationCenter.default.publisher(for: .categoriesUpdated)) { _ in loadCategorieen() }
            .onChange(of: categoriesRaw, initial: false) { _, _ in loadCategorieen() }
            .onChange(of: periode, initial: false) { oldValue, newValue in periodeRaw = newValue.rawValue }
            .preferredColorScheme(preferredScheme)
            .tint(Theme.primary)
            .sheet(isPresented: $isPresentingAddEdit) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("Naam", text: $draft.naam, prompt: Text("Naam van abonnement (bv. Netflix)"))

                            Picker("Categorie", selection: $draft.categorie) {
                                ForEach(categorieen, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            .pickerStyle(.navigationLink)
                            
                            Picker("Icoon", selection: iconSelection) {
                                HStack { Image(systemName: CategoryIcon.symbol(for: draft.categorie)); Text("Volg categorie (automatisch)") }
                                    .tag("__auto__")
                                ForEach(CategoryIconOptions.options, id: \.symbol) { opt in
                                    HStack { Image(systemName: opt.symbol); Text(opt.name) }
                                        .tag(opt.symbol)
                                }
                            }
                            .pickerStyle(.navigationLink)

                            TextField("Prijs", text: $prijsText, prompt: Text("Prijs (bv. 12,99)"))
                                .keyboardType(.decimalPad)

                            Picker("Frequentie", selection: $draft.frequentie) {
                                Text("Wekelijks").tag(Frequentie.wekelijks)
                                Text("Maandelijks").tag(Frequentie.maandelijks)
                                Text("Driemaandelijks").tag(Frequentie.driemaandelijks)
                                Text("Jaarlijks").tag(Frequentie.jaarlijks)
                            }

                            DatePicker("Volgende vervaldatum", selection: $draft.volgendeVervaldatum, displayedComponents: .date)
                            Toggle("Opzegbaar", isOn: $draft.opzegbaar)
                            TextField("Notitie (optioneel)", text: $draft.notitie.orEmpty(), prompt: Text("Extra info (bv. plan, kortingscode)…"))
                        } header: {
                            Text("Details").foregroundStyle(Theme.primary)
                        } footer: {
                            Text("Categorie is een lijst die je later in Instellingen kunt beheren.")
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .navigationTitle(isEditing ? "Bewerk" : "Toevoegen")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annuleer") { isPresentingAddEdit = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Bewaar") { saveDraft() }
                                .disabled(draft.naam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (parseLocalizedDouble(prijsText) ?? -1) < 0)
                        }
                    }
                }
            }
            .alert("Abonnement verwijderen?", isPresented: $showDeleteAlert, presenting: pendingDelete) { abo in
                Button("Verwijder", role: .destructive) {
                    verwijder(abo)
                }
                Button("Annuleer", role: .cancel) { }
            } message: { abo in
                Text("\(abo.naam) wordt verwijderd en kan niet ongedaan gemaakt worden.")
            }
        }
    }

    // MARK: - Sections
    private var swipeHintSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.point.left.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tip")
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                    Text("Veeg een abonnement naar links om **Verwijder** of **Bewerk/Betaald** te tonen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("OK") { withAnimation { dismissedSwipeHint = true } }
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }

    private var infoHintSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wist je dit?")
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                    Text("Uitleg over hoe de app werkt vind je in **Instellingen → Info** (tandwiel linksboven).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("OK") { withAnimation { dismissedInfoHint = true } }
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }
    private var headerKPISection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Periode", selection: $periode) {
                        ForEach(Periode.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.primary)
                }

                HStack(spacing: 12) {
                    kpiTile(title: "Totaal", value: totaalGeformatteerd)
                    kpiTile(title: "Abonnementen", value: "\(gefilterdeAbos.count)")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var upcomingSection: some View {
        Section("Binnenkort te betalen") {
            ForEach(binnenkortAbos) { abo in
                aboRow(abo)
                    .badge(abo.isVandaag ? "Vandaag" : "over \(abo.dagenTotVervaldatum) d")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { verwijder(abo) } label: { Label("Verwijder", systemImage: "trash") }
                        Button { markeerBetaald(abo) } label: { Label("Betaald", systemImage: "checkmark.circle") }
                    }
            }
        }
    }

    private var volledigeLijstSection: some View {
        Section("Alle abonnementen") {
            ForEach(gefilterdeAbos) { abo in
                aboRow(abo)
                    .contentShape(Rectangle())
                    .onTapGesture { openEdit(abo) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = abo
                            showDeleteAlert = true
                        } label: { Label("Verwijder", systemImage: "trash") }
                        Button { openEdit(abo) } label: { Label("Bewerk", systemImage: "pencil") }
                    }
            }
            .onDelete { offsets in
                let idsToDelete = offsets.map { gefilterdeAbos[$0].id }
                withAnimation { abonnementen.removeAll { idsToDelete.contains($0.id) } }
            }
        }
    }

    // MARK: - Rows & Tiles
    private func aboRow(_ abo: Abonnement) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: abo.iconSymbol)
                .font(.title3)
                .foregroundStyle(Theme.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(abo.naam).font(.headline)
                    if abo.opzegbaar {
                        Text("Opzegbaar")
                            .font(.caption2)
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.primary.opacity(0.12), in: Capsule())
                    }
                }
                Text(abo.categorie.capitalized).font(.subheadline).foregroundStyle(.secondary)
                Text(vervaldatumTekst(abo.volgendeVervaldatum)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(bedragTekst(abo)).font(.headline).foregroundStyle(Theme.primary)
                Text(frequentieTekst(abo.frequentie)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func kpiTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2).fontWeight(.semibold).foregroundStyle(Theme.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(colors: [Theme.primary.opacity(0.12), Theme.primary.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.primary.opacity(0.15))
        )
    }

    // MARK: - Helpers
    private var gefilterdeAbos: [Abonnement] {
        guard !zoektekst.isEmpty else { return abonnementen.sorted { $0.naam.localizedCaseInsensitiveCompare($1.naam) == .orderedAscending } }
        return abonnementen.filter { $0.naam.localizedCaseInsensitiveContains(zoektekst) || $0.categorie.localizedCaseInsensitiveContains(zoektekst) }
            .sorted { $0.naam.localizedCaseInsensitiveCompare($1.naam) == .orderedAscending }
    }

    private var binnenkortAbos: [Abonnement] {
        gefilterdeAbos.filter { $0.isBinnen30Dagen }
            .sorted { $0.volgendeVervaldatum < $1.volgendeVervaldatum }
    }

    private var binnenkortLeeg: Bool { binnenkortAbos.isEmpty }

    private var totaal: Double {
        switch periode {
        case .maand: return gefilterdeAbos.map { $0.maandBedrag }.reduce(0, +)
        case .jaar: return gefilterdeAbos.map { $0.jaarBedrag }.reduce(0, +)
        }
    }

    private var totaalGeformatteerd: String { currency(totaal) }

    private func bedragTekst(_ abo: Abonnement) -> String {
        switch periode {
        case .maand: return currency(abo.maandBedrag)
        case .jaar: return currency(abo.jaarBedrag)
        }
    }

    private func frequentieTekst(_ f: Frequentie) -> String {
        switch f {
        case .wekelijks:       return "Wekelijks"
        case .maandelijks:     return "Maandelijks"
        case .driemaandelijks: return "Driemaandelijks"
        case .jaarlijks:       return "Jaarlijks"
        }
    }


    private func vervaldatumTekst(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Locale.preferredLanguages.first ?? "nl_BE")
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = Locale.current
        return f.string(from: NSNumber(value: value)) ?? "\(currencyCode) " + String(format: "%.2f", value)
    }
    
    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    // MARK: - Actions (mock)
    private func openAdd() {
        editingID = nil
        draft = Draft()
        prijsText = ""
        isPresentingAddEdit = true
    }

    private func openEdit(_ abo: Abonnement) {
        editingID = abo.id
        draft = Draft(
            naam: abo.naam,
            prijs: abo.prijs,
            frequentie: abo.frequentie,
            volgendeVervaldatum: abo.volgendeVervaldatum,
            categorie: abo.categorie,
            categorieIcon: abo.categorieIcon,
            opzegbaar: abo.opzegbaar,
            notitie: abo.notitie
        )
        prijsText = plainNumberString(abo.prijs)
        isPresentingAddEdit = true
    }

    private func saveDraft() {
        let parsedPrijs = parseLocalizedDouble(prijsText) ?? 0
        let newOrUpdated = Abonnement(
            naam: draft.naam.trimmingCharacters(in: .whitespacesAndNewlines),
            prijs: parsedPrijs,
            frequentie: draft.frequentie,
            volgendeVervaldatum: draft.volgendeVervaldatum,
            categorie: draft.categorie.trimmingCharacters(in: .whitespacesAndNewlines),
            categorieIcon: draft.categorieIcon,
            opzegbaar: draft.opzegbaar,
            notitie: draft.notitie
        )

        if let id = editingID, let idx = abonnementen.firstIndex(where: { $0.id == id }) {
            // Preserve the original ID when editing
            var updated = newOrUpdated
            // overwrite generated id with original
            let originalID = abonnementen[idx].id
            // rebuild with same id
            updated = Abonnement(
                id: originalID,
                naam: updated.naam,
                prijs: updated.prijs,
                frequentie: updated.frequentie,
                volgendeVervaldatum: updated.volgendeVervaldatum,
                categorie: updated.categorie,
                categorieIcon: updated.categorieIcon,
                opzegbaar: updated.opzegbaar,
                notitie: updated.notitie
            )
            // replace in place while keeping array order
            abonnementen.remove(at: idx)
            abonnementen.insert(updated, at: idx)
            // NOTE: The synthesized id will change; if you want to preserve UUID, promote `id` to var.
        } else {
            abonnementen.append(newOrUpdated)
        }
        saveAbonnementen()
        isPresentingAddEdit = false
    }

    private func parseLocalizedDouble(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        // Sta zowel komma als punt toe
        let cleaned = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: formatter.decimalSeparator ?? ",").replacingOccurrences(of: ".", with: formatter.decimalSeparator ?? ",")
        return formatter.number(from: cleaned)?.doubleValue
    }

    private func plainNumberString(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale.current
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func verwijder(_ abo: Abonnement) {
        withAnimation { abonnementen.removeAll { $0.id == abo.id } }
        saveAbonnementen()
    }

    private func markeerBetaald(_ abo: Abonnement) {
        // Voor nu simuleren we: schuif de vervaldatum door naar de volgende periode.
        if let idx = abonnementen.firstIndex(where: { $0.id == abo.id }) {
            withAnimation {
                abonnementen[idx].volgendeVervaldatum = abonnementen[idx].volgendeVervaldatumNaHuidige()
                saveAbonnementen()
            }
        }
    }
}



private extension Binding where Value == String? {
    /// Provides a non-optional Binding<String> for use in TextField, while writing back nil when empty.
    func orEmpty(_ defaultValue: String = "") -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? defaultValue },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.wrappedValue = trimmed.isEmpty ? nil : newValue
            }
        )
    }
}



#Preview {
    HomescreenView()
}
