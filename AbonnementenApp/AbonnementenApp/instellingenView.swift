//
//  instellingenView.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//


import SwiftUI
import UserNotifications
import UIKit
import MessageUI

private let sharedDefaults = UserDefaults(
    suiteName: "group.be.vancoilliestudio.abbobuddy.shared"
)!


// MARK: - Keys & Defaults
private enum SettingsKeys {
    static let notifLeadDays = "notifLeadDays"
    static let currencyCode   = "currencyCode"
    static let appTheme       = "appearanceMode"
    static let accentMode     = "accentMode"       // "default" | "custom"
    static let accentCustomColor = "accentCustomColor" // Data (JSON-encoded RGBA)
    static let notifHour      = "notifHour"
    static let notifMinute    = "notifMinute"
    static let upcomingWeeksWindow = "upcomingWeeksWindow"
    static let autoMarkPaidOnDue = "autoMarkPaidOnDue"
}

extension Notification.Name { static let categoriesUpdated = Notification.Name("categoriesUpdated") }
extension Notification.Name { static let accentColorChanged = Notification.Name("accentColorChanged") }

// MARK: - Settings View
struct instellingenView: View {
    // Meldingen lead time (dagen)
    @AppStorage(SettingsKeys.notifLeadDays) private var notifLeadDays: Int = 2
    @AppStorage(SettingsKeys.notifHour) private var notifHour: Int = 9
    @AppStorage(SettingsKeys.notifMinute) private var notifMinute: Int = 0
    @AppStorage(SettingsKeys.upcomingWeeksWindow) private var upcomingWeeksWindow: Int = 1 // in weken (1-4)
    @AppStorage(SettingsKeys.autoMarkPaidOnDue) private var autoMarkPaidOnDue: Bool = false
    @State private var notifTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    // Testmelding status
    @State private var notifStatus: String = ""

    // Valuta (ISO-4217)
    @AppStorage(SettingsKeys.currencyCode, store: sharedDefaults) private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"

    // Thema: system / light / dark
    @AppStorage(SettingsKeys.appTheme) private var appTheme: String = "system"
    
    // Accentkleur: default/custom + opgeslagen kleur
    @AppStorage(SettingsKeys.accentMode) private var accentMode: String = "default"
    @AppStorage(SettingsKeys.accentCustomColor) private var accentCustomColorRaw: Data = Data()
    @State private var customAccentColor: Color = .accentColor

    @AppStorage(CategoriesDefaults.key) private var categoriesRaw: Data = Data()
    @State private var categories: [String] = []
    @State private var newCategory: String = ""
    @State private var isShowingInfo: Bool = false

    @AppStorage("categoryIconMap") private var categoryIconMapRaw: Data = Data()
    @State private var categoryIconMap: [String:String] = [:]
    @State private var showIconPicker: Bool = false
    @State private var categoryToEditIcon: String? = nil

    @State private var showingMailSheet: Bool = false
    @State private var mailFallbackFailed: Bool = false
    @Environment(\.openURL) private var openURL

    private let leadTimeOptions: [(label: String, days: Int)] = [
        (NSLocalizedString("LEADTIME_SAME_DAY", comment: "Same day"), 0),
        (NSLocalizedString("LEADTIME_1_DAY", comment: "1 day before"), 1),
        (NSLocalizedString("LEADTIME_2_DAYS", comment: "2 days before"), 2),
        (NSLocalizedString("LEADTIME_3_DAYS", comment: "3 days before"), 3),
        (NSLocalizedString("LEADTIME_1_WEEK", comment: "1 week before"), 7),
        (NSLocalizedString("LEADTIME_2_WEEKS", comment: "2 weeks before"), 14)
    ]

    private let currencyOptions: [String] = ["EUR", "USD", "GBP", "CHF", "JPY"]
    private let themeOptions: [(label: String, key: String)] = [
        (NSLocalizedString("SYSTEMMODE", comment: "Theme option: follow system"), "system"),
        (NSLocalizedString("LIGHTMODE", comment: "Theme option: light"), "light"),
        (NSLocalizedString("DARKMODE", comment: "Theme option: dark"), "dark")
    ]

    private var isPreview: Bool { ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" }

    private func defaultProblemReportBody() -> String {
        #if canImport(UIKit)
        let device = UIDevice.current
        let system = "iOS \(device.systemVersion)"
        let model = device.model
        #else
        let system = "iOS"
        let model = "Unknown"
        #endif
        let currency = currencyCode
        return "Write your issue here...\n\n— App info —\nThema: \(appTheme)\nValuta: \(currency)\n— Device —\nModel: \(model)\nSysteem: \(system)\n"
    }
    
    /// Localized sentence for the upcoming window description.
    /// Expects a .stringsdict entry for key `UPCOMING_WINDOW_SENTENCE` that pluralizes on the week count
    /// and can adjust the verb as needed per language.
    private func upcomingWindowSentence(_ n: Int) -> String {
        if n == 1 {
            return NSLocalizedString("UPCOMING_WINDOW_1WEEK", comment: "")
        } else {
            return String(format: NSLocalizedString("UPCOMING_WINDOW_NWEEKS", comment: ""), n)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Herinnering", selection: $notifLeadDays) {
                    ForEach(leadTimeOptions, id: \.days) { opt in
                        Text(opt.label).tag(opt.days)
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: notifLeadDays) { _, _ in
                    // Wijziging in lead time -> alle reminders herplannen
                    rescheduleAllSubscriptionReminders()
                }

                Text("Je krijgt een push/herinnering \(labelForLeadDays(notifLeadDays)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                DatePicker("Tijdstip van melding", selection: $notifTime, displayedComponents: .hourAndMinute)
                    .onChange(of: notifTime) { _, newValue in
                        let cal = Calendar.current
                        notifHour = cal.component(.hour, from: newValue)
                        notifMinute = cal.component(.minute, from: newValue)
                        // Tijdstip veranderd -> alle reminders herplannen
                        rescheduleAllSubscriptionReminders()
                    }

                Text("Meldingen worden verstuurd rond \(String(format: "%02d:%02d", notifHour, notifMinute)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Toon in \"Binnenkort te betalen\"", selection: $upcomingWeeksWindow) {
                    Text("1 week").tag(1)
                    Text("2 weken").tag(2)
                    Text("3 weken").tag(3)
                    Text("4 weken").tag(4)
                }
                .pickerStyle(.segmented)
                
                

                Text(upcomingWindowSentence(upcomingWeeksWindow))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                // Testmelding UI verwijderd
            } header: {
                Text("Meldingen")
            }
            
            Section{
                Toggle("Automatisch op betaaldag markeren", isOn: $autoMarkPaidOnDue)
                Text("Wanneer dit aan staat, worden abonnementen automatisch als **Betaald** gemarkeerd zodra de vervaldag aanbreekt (of zodra je de app opent als je de betaaldag gemist hebt).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            } header: {
                Text("Automatisch betaald markeren")
            }

            Section {
                Picker("Thema", selection: $appTheme) {
                    ForEach(themeOptions, id: \.key) { opt in
                        Text(opt.label).tag(opt.key)
                    }
                }
                .pickerStyle(.segmented)
                Text("Kies kleur")

                
                Picker("Accentkleur", selection: $accentMode) {
                    Text("Standaard").tag("default")
                    Text("Aangepast").tag("custom")
                }
                .pickerStyle(.segmented)
                if accentMode == "custom" {
                    ColorPicker("Kies kleur", selection: $customAccentColor, supportsOpacity: false)
                        .onChange(of: customAccentColor) { _, _ in
                            saveCustomAccentColor()
                        }
                }

                Picker("Valuta", selection: $currencyCode) {
                    ForEach(currencyOptions, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .pickerStyle(.navigationLink)
                
               

               
            } header: {
                Text("Weergave")
            } footer: {
                Text("De thema-instelling wordt app-breed toegepast. Valuta wordt gebruikt bij het tonen en opslaan van bedragen. Je kunt ook de **accentkleur** kiezen: **Standaard** gebruikt de app-kleur, **Aangepast** gebruikt je gekozen kleur.")
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
            
            Section {
                HStack {
                    Text("App naam")
                    Spacer()
                    Text(appDisplayName())
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("about_app_name")

                HStack {
                    Text("Versie")
                    Spacer()
                    Text(appVersionString())
                        .monospaced()
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("about_app_version")
                HStack {
                    Text("Gemaakt door Vancoillie Studio")
                }
            } header: {
                Text("Versie")
            }

            Section {
                Button(
                    action: {
                        #if canImport(UIKit)
                        if MFMailComposeViewController.canSendMail() {
                            showingMailSheet = true
                        } else {
                            let subject = "Abonnementen – Probleemrapport"
                            let body = defaultProblemReportBody().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            let to = "support@vancoilliestudio.be"
                            if let url = URL(string: "mailto:\(to)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body)") {
                                if UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                } else {
                                    mailFallbackFailed = true
                                }
                            } else {
                                mailFallbackFailed = true
                            }
                        }
                        #endif
                    }
                ) {
                    Text("Meld een probleem")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                        .multilineTextAlignment(.center)
                }
            } header: {
                Text("Support")
            } footer: {
                Text("Lukt e-mail niet? Mail ons dan rechtstreeks op support@vancoilliestudio.be.")
            }
        }
        .scrollDismissesKeyboard(.immediately)
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
        .onAppear { if !isPreview { loadCategories(); loadIconMap() } }
        .onChange(of: categories, initial: false) { _,_  in if !isPreview { saveCategories() } }
        .onChange(of: categoryIconMapRaw, initial: false) { _, _ in if !isPreview { loadIconMap() } }
        .onAppear { if !isPreview { loadCustomAccentColor() } }
        .onChange(of: accentMode, initial: false) { _, newValue in
            if !isPreview {
                if newValue == "default" {
                    NotificationCenter.default.post(name: .accentColorChanged, object: nil)
                } else {
                    saveCustomAccentColor()
                }
            }
        }
        .onAppear {
            if !isPreview {
                if let d = Calendar.current.date(bySettingHour: notifHour, minute: notifMinute, second: 0, of: Date()) {
                    notifTime = d
                }
            }
        }
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
                            Text("📅 Maand/Jaar weergave")
                                .font(.headline)
                            Text("Kies bovenaan **Maand** of **Jaar**. Alleen het **Totaal** past zich aan; de bedragen in de lijst blijven het originele bedrag van elk abonnement. Staat **Jaar** aan, dan zie je bij elk item de prefix **‘Jaarlijks:’** voor extra duidelijkheid. Je laatste keuze wordt onthouden.")
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
                            Text("Stel in wanneer je een melding wil krijgen vóór de vervaldatum.")
                        }
                        Group {
                            Text("🔜 Binnenkort‑venster")
                                .font(.headline)
                            Text("Bepaal zelf wanneer items in **Binnenkort te betalen** verschijnen. In **Instellingen → Meldingen** kies je **1, 2, 3 of 4 weken**. De app toont dan alle abonnementen waarvan de vervaldatum binnen dat venster valt.")
                        }
                        Group {
                            Text("⚠️ Betaal‑herinnering banner")
                                .font(.headline)
                            Text("Als er abonnementen zijn met vervaldatum **vandaag** of **voorbij**, verschijnt bovenaan een banner **‘Vergeet niet te betalen’**. Deze blijft zichtbaar zolang er zulke items zijn en kan niet worden weggeklikt. Markeer een item als **Betaald** via een **veeg naar links** om de banner te laten verdwijnen.")
                        }
                        Group {
                            Text("💱 Valuta & 🎨 Thema")
                                .font(.headline)
                            Text("Kies je **valuta** en stel het **thema** in (Systeem/Licht/Donker). Deze instellingen gelden app-breed.")
                        }
                        Group {
                            Text("💾 Opslag")
                                .font(.headline)
                            Text("Alles wordt lokaal bewaard via **AppStorage** (SharedDefaults). Je data blijft bewaard tussen app-sessies.")
                        }
                        // ...

                        Group {
                            Text("Privacy Policy")
                                .font(.headline)

                            Button {
                                if let url = URL(string: "https://www.vancoillieithulp.be/privacyPolicyAbboBuddy.html") {
                                    openURL(url)
                                }
                            } label: {
                                Label("Bekijk privacy policy", systemImage: "lock.doc")
                                    .font(.body)
                            }
                            .buttonStyle(.bordered)      // of .borderedProminent als je ‘m opvallend wil
                            .tint(.accentColor)          // volgt je accentkleur
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
        .sheet(isPresented: $showingMailSheet) {
            MailView(
                to: ["support@vancoilliestudio.be"],
                subject: "Abonnementen – Probleemrapport",
                body: defaultProblemReportBody()
            )
        }
        .alert("E-mail kon niet geopend worden", isPresented: $mailFallbackFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Kopieer en mail ons op support@vancoilliestudio.be.")
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

    // MARK: - Accent Color Persistence
    private struct RGBAColor: Codable { let r: Double; let g: Double; let b: Double; let a: Double }

    private func colorToRGBA(_ color: Color) -> RGBAColor {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBAColor(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
        #else
        return RGBAColor(r: 0, g: 0, b: 0, a: 1)
        #endif
    }

    private func rgbaToColor(_ rgba: RGBAColor) -> Color {
        #if canImport(UIKit)
        return Color(UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
        #else
        return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
        #endif
    }

    private func loadCustomAccentColor() {
        if accentCustomAccentIsSaved() == false { return }
        if let raw = try? JSONDecoder().decode(RGBAColor.self, from: accentCustomColorRaw) {
            customAccentColor = rgbaToColor(raw)
        }
    }

    private func saveCustomAccentColor() {
        let rgba = colorToRGBA(customAccentColor)
        if let data = try? JSONEncoder().encode(rgba) {
            accentCustomColorRaw = data
            NotificationCenter.default.post(name: .accentColorChanged, object: nil)
        }
    }

    private func accentCustomAccentIsSaved() -> Bool {
        !accentCustomColorRaw.isEmpty
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

    private func appDisplayName() -> String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
            return name
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return "Abonnementen"
    }

    private func appVersionString() -> String {
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, build.isEmpty == false {
            return "\(ver) (\(build))"
        }
        return ver
    }


    /// Bouwt de gewenste trigger-datum op basis van vervaldatum, leadDays en het ingestelde tijdstip.
    private func preferredTriggerDate(for dueDate: Date, leadDays: Int, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        let day = calendar.date(byAdding: .day, value: -leadDays, to: dueDate)
        guard let base = day else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: base)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    /// Publieke helper die je elders in de app kan oproepen om een echte abonnements-herinnering in te plannen.
    /// - Parameters:
    ///   - name: Titel (bv. naam van het abonnement)
    ///   - dueDate: Vervaldatum van het abonnement
    ///   - amountText: Optioneel bedragstekst voor in de body (bv. "€9,99")
    func scheduleSubscriptionReminder(name: String, dueDate: Date, amountText: String? = nil) {
        ensureNotificationPermission { granted in
            guard granted else {
                DispatchQueue.main.async {
                    self.notifStatus = NSLocalizedString("NOTIF_STATUS_NO_PERMISSION",
                                                         comment: "Shown when notification permissions are missing")
                }
                return
            }

            guard let triggerDate = preferredTriggerDate(for: dueDate, leadDays: self.notifLeadDays, hour: self.notifHour, minute: self.notifMinute) else {
                DispatchQueue.main.async {
                    self.notifStatus = NSLocalizedString("NOTIF_STATUS_CANNOT_COMPUTE_DATE",
                                                         comment: "Shown when trigger date could not be computed")
                }
                return
            }

            // --- Begin: auto-correct trigger date if in past ---
            var finalDate = triggerDate
            let now = Date()
            if finalDate <= now {
                if let adjusted = Calendar.current.date(byAdding: .minute, value: 1, to: now) {
                    finalDate = adjusted
                }
            }
            // --- End: auto-correct trigger date if in past ---

            let content = UNMutableNotificationContent()
            content.title = appDisplayName()
            content.subtitle = name
            if let amountText = amountText, !amountText.isEmpty {
                // Localized: "Your subscription is due soon. Amount: %@."
                content.body = String(format: NSLocalizedString("NOTIFICATION_BODY_WITH_AMOUNT",
                                                                comment: "Notification body shown when an amount is available"),
                                      amountText)
            } else {
                // Localized: "Your subscription is due soon."
                content.body = NSLocalizedString("NOTIFICATION_BODY_NO_AMOUNT",
                                                 comment: "Notification body shown when no amount is provided")
            }
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: finalDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let identifier = "sub-\(name)-\(Int(dueDate.timeIntervalSince1970))"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.notifStatus = String(format: NSLocalizedString("NOTIF_STATUS_SCHEDULE_FAILED",
                                                                            comment: "Shown when scheduling the reminder failed with an error"),
                                                  error.localizedDescription)
                    } else {
                        let hm = String(format: "%02d:%02d", self.notifHour, self.notifMinute)
                        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
                        self.notifStatus = String(format: NSLocalizedString("NOTIF_STATUS_SCHEDULED_AT",
                                                                            comment: "Shown when a reminder was scheduled; placeholders are date and time"),
                                                  df.string(from: finalDate), hm)
                    }
                }
            }
        }
    }

    // MARK: - (Re)Schedule helpers

    /// Verwijder alle nog niet afgeleverde 'subscription' reminders.
    private func cancelAllSubscriptionReminders(completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let ids = reqs
                .map(\.identifier)
                .filter { $0.hasPrefix("sub-") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            completion?()
        }
    }

    /// Eenvoudige currency formatter voor de body-tekst.
    private func currencyText(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = .current
        return f.string(from: NSNumber(value: value)) ?? "\(currencyCode) " + String(format: "%.2f", value)
    }

    /// Plant alle reminders opnieuw volgens de actuele instellingen.
    private func rescheduleAllSubscriptionReminders() {
        // Laad alle abonnementen uit de opslag
        let abos = AbonnementenDefaults.load()

        cancelAllSubscriptionReminders {
            for abo in abos {
                let amount = currencyText(abo.prijs)
                self.scheduleSubscriptionReminder(name: abo.naam,
                                                  dueDate: abo.volgendeVervaldatum,
                                                  amountText: amount)
            }
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
        case 0:
            return NSLocalizedString("LEADDAYS_SAME_DAY",
                                     comment: "Notification lead time: on due date")
        case 1:
            return NSLocalizedString("LEADDAYS_1_DAY",
                                     comment: "Notification lead time: 1 day in advance")
        case 7:
            return NSLocalizedString("LEADDAYS_1_WEEK",
                                     comment: "Notification lead time: 1 week in advance")
        case 14:
            return NSLocalizedString("LEADDAYS_2_WEEKS",
                                     comment: "Notification lead time: 2 weeks in advance")
        default:
            return String(format: NSLocalizedString("LEADDAYS_N_DAYS",
                                                    comment: "Notification lead time: N days in advance"),
                          days)
        }
    }
}

#Preview { NavigationStack { instellingenView() } }

struct MailView: UIViewControllerRepresentable {
    var to: [String]
    var subject: String
    var body: String

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(to)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) { }
}

