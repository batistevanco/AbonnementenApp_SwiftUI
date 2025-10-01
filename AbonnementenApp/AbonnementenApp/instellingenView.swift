//
//  instellingenView.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//


import SwiftUI
import UserNotifications


// MARK: - Keys & Defaults
private enum SettingsKeys {
    static let notifLeadDays = "notifLeadDays"
    static let currencyCode   = "currencyCode"
    static let appTheme       = "appTheme"
}

extension Notification.Name { static let categoriesUpdated = Notification.Name("categoriesUpdated") }

// MARK: - Settings View
struct instellingenView: View {
    // Meldingen lead time (dagen)
    @AppStorage(SettingsKeys.notifLeadDays) private var notifLeadDays: Int = 2

    // Valuta (ISO-4217)
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"

    // Thema: system / light / dark
    @AppStorage(SettingsKeys.appTheme) private var appTheme: String = "system"

    @AppStorage(CategoriesDefaults.key) private var categoriesRaw: Data = Data()
    @State private var categories: [String] = []
    @State private var newCategory: String = ""
    @State private var isShowingInfo: Bool = false

    @AppStorage("categoryIconMap") private var categoryIconMapRaw: Data = Data()
    @State private var categoryIconMap: [String:String] = [:]
    @State private var showIconPicker: Bool = false
    @State private var categoryToEditIcon: String? = nil

    private let leadTimeOptions: [(label: String, days: Int)] = [
        ("Op de dag zelf", 0), ("1 dag voordien", 1), ("2 dagen voordien", 2),
        ("3 dagen voordien", 3), ("1 week voordien", 7), ("2 weken voordien", 14)
    ]

    private let currencyOptions: [String] = ["EUR", "USD", "GBP", "CHF", "JPY"]
    private let themeOptions: [(label: String, key: String)] = [("Systeem", "system"), ("Licht", "light"), ("Donker", "dark")]

    var body: some View {
        Form {
            Section {
                Picker("Herinnering", selection: $notifLeadDays) {
                    ForEach(leadTimeOptions, id: \.days) { opt in
                        Text(opt.label).tag(opt.days)
                    }
                }
                .pickerStyle(.navigationLink)

                Text("Je krijgt een push/herinnering \(labelForLeadDays(notifLeadDays)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    sendTestNotification()
                } label: {
                    Label("Stuur testmelding", systemImage: "paperplane.circle.fill")
                }
            } header: {
                Text("Meldingen")
            }

            Section {
                Picker("Thema", selection: $appTheme) {
                    ForEach(themeOptions, id: \.key) { opt in
                        Text(opt.label).tag(opt.key)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Valuta", selection: $currencyCode) {
                    ForEach(currencyOptions, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Weergave")
            } footer: {
                Text("De thema-instelling wordt app-breed toegepast. Valuta wordt gebruikt bij het tonen en opslaan van bedragen.")
            }

            Section {
                if categories.isEmpty {
                    Text("Nog geen categorieën. Voeg er hieronder één toe.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categories, id: \.self) { cat in
                        HStack {
                            Image(systemName: symbolForCategory(cat))
                            Text(cat)
                            Spacer()
                            Button {
                                categoryToEditIcon = cat
                                showIconPicker = true
                            } label: {
                                Label("Icoon", systemImage: "paintpalette")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .onDelete(perform: deleteCategories)
                    .onMove(perform: moveCategories)
                }

                HStack {
                    TextField("Nieuwe categorie…", text: $newCategory)
                        .onSubmit { addCategory() }
                    Button {
                        dismissKeyboard()
                        addCategory()
                    } label: {
                        Label("Voeg toe", systemImage: "plus.circle.fill")
                    }
                    .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Categorieën")
            } footer: {
                Text("Standaardcategorieën zijn: \(CategoriesDefaults.fallback.joined(separator: ", ")). Je kunt deze lijst vrij aanpassen.")
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
        .navigationTitle("Instellingen")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingInfo = true
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
            }
        }
        .onAppear { loadCategories(); loadIconMap() }
        .onChange(of: categories, initial: false) { _,_  in saveCategories() }
        .onChange(of: categoryIconMapRaw, initial: false) { _, _ in loadIconMap() }
        .sheet(isPresented: $isShowingInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            Text("Welkom bij Abonnementen")
                                .font(.title2).bold()
                            Text("Met deze app beheer je al je abonnementen op één plek. Hieronder een korte uitleg:")
                        }
                        Divider()
                        Group {
                            Text("📥 Abonnement toevoegen")
                                .font(.headline)
                            Text("Ga naar **Home** → tik op **Toevoegen**. Vul naam, prijs, frequentie, vervaldatum en categorie in. Je kunt ook een notitie en of het opzegbaar is aangeven.")
                        }
                        Group {
                            Text("🧭 Overzicht & totalen")
                                .font(.headline)
                            Text("Bovenaan zie je totalen per **maand/jaar**. In **Overzicht** kun je filteren per categorie en de som per categorie zien.")
                        }
                        Group {
                            Text("➡️ Swipen voor acties")
                                .font(.headline)
                            Text("Veeg een rij naar **links** om **Bewerk/Betaald** en **Verwijder** te tonen.")
                        }
                        Group {
                            Text("🗂️ Categorieën beheren")
                                .font(.headline)
                            Text("Hier in **Instellingen** kun je categorieën toevoegen, verwijderen en herschikken. Wijzigingen worden overal toegepast.")
                        }
                        Group {
                            Text("🔔 Herinneringen")
                                .font(.headline)
                            Text("Stel in wanneer je een melding wil krijgen vóór de vervaldatum. Je kunt ook een testmelding sturen.")
                        }
                        Group {
                            Text("💱 Valuta & 🎨 Thema")
                                .font(.headline)
                            Text("Kies je **valuta** en stel het **thema** in (Systeem/Licht/Donker). Deze instellingen gelden app-breed.")
                        }
                        Group {
                            Text("💾 Opslag")
                                .font(.headline)
                            Text("Alles wordt lokaal bewaard via **AppStorage** (UserDefaults). Je data blijft bewaard tussen app-sessies.")
                        }
                    }
                    .padding()
                }
                .navigationTitle("Hoe werkt de app?")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluit") { isShowingInfo = false } } }
            }
        }
        .sheet(isPresented: $showIconPicker) {
            let cat = categoryToEditIcon ?? ""
            NavigationStack {
                List {
                    ForEach(CategoryIconOptions.options, id: \.symbol) { opt in
                        Button {
                            setIcon(opt.symbol, for: cat)
                            showIconPicker = false
                        } label: {
                            HStack {
                                Label(opt.name, systemImage: opt.symbol)
                                Spacer()
                                if symbolForCategory(cat) == opt.symbol { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                .navigationTitle("Kies icoon")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluit") { showIconPicker = false } } }
            }
        }
    }

    // MARK: - Keyboard
    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    // MARK: - Category Icon Map
    private func loadIconMap() {
        if let map = try? JSONDecoder().decode([String:String].self, from: categoryIconMapRaw) {
            categoryIconMap = map
        } else {
            categoryIconMap = CategoryIconMapDefaults.load()
        }
    }

    private func saveIconMap() {
        if let data = try? JSONEncoder().encode(categoryIconMap) {
            categoryIconMapRaw = data
            CategoryIconMapDefaults.save(categoryIconMap)
        }
    }

    private func setIcon(_ symbol: String, for category: String) {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        categoryIconMap[key] = symbol
        saveIconMap()
    }

    private func symbolForCategory(_ category: String) -> String {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return categoryIconMap[key] ?? CategoryIcon.symbol(for: category)
    }

    // MARK: - Permissions & Test Notification
    private func ensureNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .denied:
                completion(false)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    completion(granted)
                }
            @unknown default:
                completion(false)
            }
        }
    }

    private func sendTestNotification() {
        ensureNotificationPermission { granted in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Testmelding"
            content.body = "Dit is een test van je herinneringsinstelling (\(labelForLeadDays(notifLeadDays)))."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    // MARK: - Persistence (Categories via AppStorage)
    private func loadCategories() {
        if let arr = try? JSONDecoder().decode([String].self, from: categoriesRaw), !arr.isEmpty {
            categories = arr
        } else {
            categories = CategoriesDefaults.fallback
            saveCategories() // seed storage
        }
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            categoriesRaw = data
            NotificationCenter.default.post(name: .categoriesUpdated, object: nil)
        }
    }

    private func addCategory() {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !categories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            categories.append(trimmed)
            categories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        newCategory = ""
        saveCategories()
    }

    private func deleteCategories(at offsets: IndexSet) {
        categories.remove(atOffsets: offsets)
        // remove any icon assignments for deleted categories
        let lowered = Set(categories.map { $0.lowercased() })
        categoryIconMap = categoryIconMap.filter { lowered.contains($0.key) }
        saveIconMap()
        saveCategories()
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        saveCategories()
    }

    // MARK: - Helpers
    private func labelForLeadDays(_ days: Int) -> String {
        switch days {
        case 0: return "op de vervaldag"
        case 1: return "1 dag op voorhand"
        case 7: return "1 week op voorhand"
        case 14: return "2 weken op voorhand"
        default: return "\(days) dagen op voorhand"
        }
    }
}

#Preview { NavigationStack { instellingenView() } }
