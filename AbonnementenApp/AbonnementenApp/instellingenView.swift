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
    static let categories     = "categories"
}

private enum SettingsDefaults {
    static let fallbackCategories: [String] = ["Streaming", "Muziek", "Cloud", "Software", "Sport", "Internet", "Overig"]

    static func loadCategories() -> [String] {
        if let data = UserDefaults.standard.data(forKey: SettingsKeys.categories),
           let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
            return arr
        }
        return fallbackCategories
    }

    static func saveCategories(_ arr: [String]) {
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: SettingsKeys.categories)
            NotificationCenter.default.post(name: .categoriesUpdated, object: nil)
        }
    }
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

    // Categorieën
    @State private var categories: [String] = SettingsDefaults.loadCategories()
    @State private var newCategory: String = ""

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
                        Text(cat)
                    }
                    .onDelete(perform: deleteCategories)
                    .onMove(perform: moveCategories)
                }

                HStack {
                    TextField("Nieuwe categorie…", text: $newCategory)
                    Button {
                        addCategory()
                    } label: {
                        Label("Voeg toe", systemImage: "plus.circle.fill")
                    }
                    .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Categorieën")
            } footer: {
                Text("Standaardcategorieën zijn: \(SettingsDefaults.fallbackCategories.joined(separator: ", ")). Je kunt deze lijst vrij aanpassen.")
            }
        }
        .navigationTitle("Instellingen")
        .toolbar { EditButton() }
        .onDisappear { SettingsDefaults.saveCategories(categories) }
    }

    // MARK: - Permissions & Test Notification
    private func ensureNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional: completion(true)
            case .denied: completion(false)
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

    private func addCategory() {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !categories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            categories.append(trimmed)
            categories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        newCategory = ""
        SettingsDefaults.saveCategories(categories)
    }

    private func deleteCategories(at offsets: IndexSet) {
        categories.remove(atOffsets: offsets)
        SettingsDefaults.saveCategories(categories)
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        SettingsDefaults.saveCategories(categories)
    }
}

#Preview { NavigationStack { instellingenView() } }
