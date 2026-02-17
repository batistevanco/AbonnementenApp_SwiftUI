//
//  dagboekView.swift
//  AbonnementenApp
//
//  Created by Codex on 17/02/2026.
//

import SwiftUI

struct dagboekView: View {
    @AppStorage("abonnementenData") private var abonnementenData: Data = Data()
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"

    @State private var abonnementen: [Abonnement] = []
    @State private var zoektekst: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if gefilterdeAbonnementen.isEmpty {
                        ContentUnavailableView("Geen abonnementen", systemImage: "book.closed")
                    } else {
                        ForEach(gefilterdeAbonnementen) { abo in
                            NavigationLink(value: abo.id) {
                                dagboekRij(abo)
                            }
                        }
                    }
                } header: {
                    Text("Abonnementen Dagboek")
                } footer: {
                    Text("Beheer hier je account- en betalingsgegevens per abonnement.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dagboek")
            .searchable(text: $zoektekst, prompt: "Zoek op naam of categorie")
            .onAppear { loadAbonnementen() }
            .onChange(of: abonnementenData, initial: false) { _, _ in loadAbonnementen() }
            .onReceive(NotificationCenter.default.publisher(for: .abboDataDidChange)) { _ in
                loadAbonnementen()
            }
            .navigationDestination(for: UUID.self) { id in
                if let binding = bindingVoorAbonnement(id) {
                    DagboekDetailView(abonnement: binding, currencyCode: currencyCode) {
                        saveAbonnementen()
                    }
                } else {
                    ContentUnavailableView("Abonnement niet gevonden", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .tint(Theme.primary)
    }

    private func loadAbonnementen() {
        if let arr = try? JSONDecoder().decode([Abonnement].self, from: abonnementenData) {
            abonnementen = arr
        } else {
            abonnementen = []
        }
    }

    private func saveAbonnementen() {
        guard let data = try? JSONEncoder().encode(abonnementen) else { return }
        abonnementenData = data
        NotificationCenter.default.post(name: .abboDataDidChange, object: nil)
    }

    private var gefilterdeAbonnementen: [Abonnement] {
        let sorted = abonnementen.sorted { $0.naam.localizedCaseInsensitiveCompare($1.naam) == .orderedAscending }
        guard !zoektekst.isEmpty else { return sorted }
        return sorted.filter {
            $0.naam.localizedCaseInsensitiveContains(zoektekst) ||
            $0.categorie.localizedCaseInsensitiveContains(zoektekst)
        }
    }

    private func bindingVoorAbonnement(_ id: UUID) -> Binding<Abonnement>? {
        guard let index = abonnementen.firstIndex(where: { $0.id == id }) else { return nil }
        return $abonnementen[index]
    }

    private func dagboekRij(_ abo: Abonnement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: abo.iconSymbol)
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(abo.naam)
                        .font(.headline)
                    Text(abo.categorie)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(currency(abo.prijs))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primary)
            }

            HStack(spacing: 8) {
                Label(abo.heeftLoginData ? "Login ok" : "Login leeg", systemImage: abo.heeftLoginData ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark")
                Label(abo.heeftBetaalData ? "Betaling ok" : "Betaling leeg", systemImage: abo.heeftBetaalData ? "creditcard.fill" : "creditcard.trianglebadge.exclamationmark")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: value)) ?? "\(currencyCode) " + String(format: "%.2f", value)
    }
}

private struct DagboekDetailView: View {
    @Binding var abonnement: Abonnement
    let currencyCode: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Abonnement") {
                HStack {
                    Text("Naam")
                    Spacer()
                    Text(abonnement.naam)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Categorie")
                    Spacer()
                    Text(abonnement.categorie)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Prijs")
                    Spacer()
                    Text(currency(abonnement.prijs))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Login gegevens") {
                TextField("Gebruikersnaam", text: $abonnement.loginGebruikersnaam.orEmpty())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                TextField("E-mail", text: $abonnement.loginEmail.orEmpty())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                SecureField("Wachtwoord", text: $abonnement.loginWachtwoord.orEmpty())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            Section("Betaling") {
                TextField("Betaalmethode (bv. Visa, PayPal, Bancontact)", text: $abonnement.betalingsMethode.orEmpty())
                TextField("Facturatie notitie", text: $abonnement.facturatieNotitie.orEmpty())
            }

            Section("Extra") {
                TextField("Website of portaal", text: $abonnement.accountWebsite.orEmpty())
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled(true)
                TextField("Extra notitie", text: $abonnement.notitie.orEmpty())
            }
        }
        .navigationTitle(abonnement.naam)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bewaar") {
                    onSave()
                    dismiss()
                }
            }
        }
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: value)) ?? "\(currencyCode) " + String(format: "%.2f", value)
    }
}

private extension Abonnement {
    var heeftLoginData: Bool {
        !(loginGebruikersnaam?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(loginEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(loginWachtwoord?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var heeftBetaalData: Bool {
        !(betalingsMethode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(facturatieNotitie?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

private extension Binding where Value == String? {
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
    dagboekView()
}
